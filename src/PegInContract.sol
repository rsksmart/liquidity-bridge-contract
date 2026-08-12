// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {
    AccessControlDefaultAdminRulesUpgradeable
} from "@openzeppelin/contracts-upgradeable/access/extensions/AccessControlDefaultAdminRulesUpgradeable.sol";
import {EIP712Upgradeable} from "@openzeppelin/contracts-upgradeable/utils/cryptography/EIP712Upgradeable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {BtcUtils} from "@rsksmart/btc-transaction-solidity-helper/contracts/BtcUtils.sol";
import {OpCodes} from "@rsksmart/btc-transaction-solidity-helper/contracts/OpCodes.sol";
import {EmergencyPause} from "./EmergencyPause/EmergencyPause.sol";
import {IBridge} from "./interfaces/IBridge.sol";
import {ICollateralManagement, CollateralManagementSet} from "./interfaces/ICollateralManagement.sol";
import {IFlyoverConfigurations} from "./interfaces/IFlyoverConfigurations.sol";
import {IPauseRegistry} from "./interfaces/IPauseRegistry.sol";
import {IPegIn} from "./interfaces/IPegIn.sol";
import {IPegInAddressRegistry} from "./interfaces/IPegInAddressRegistry.sol";
import {IPegInCommitFirst} from "./interfaces/IPegInCommitFirst.sol";
import {BtcTransactionReader} from "./libraries/BtcTransactionReader.sol";
import {Flyover} from "./libraries/Flyover.sol";
import {PegInDerivation} from "./libraries/PegInDerivation.sol";
import {Quotes} from "./libraries/Quotes.sol";
import {SignatureValidator} from "./libraries/SignatureValidator.sol";

/// @title PegIn
/// @notice This contract is used to handle the peg in of the Bitcoin network to the Rootstock network
/// @dev All non pure/view functions in this contract should be marked as nonReentrant
/// @author Rootstock Labs
// solhint-disable-next-line max-states-count
contract PegInContract is
    AccessControlDefaultAdminRulesUpgradeable,
    EmergencyPause,
    ReentrancyGuard,
    EIP712Upgradeable,
    IPegIn,
    IPegInCommitFirst
{
    /// @notice This struct is used to store the information of a call on behalf of the user
    /// @param timestamp The timestamp of the call
    /// @param success Whether the call was successful or not
    struct Registry {
        uint256 timestamp;
        bool success;
    }

    /// @notice Claim record written by requestPegIn for later settlement
    /// @param claimer The account that fronted RBTC; address(0) means unset
    /// @param frontedAmount The net amount delivered to the user (msg.value at claim)
    /// @param feeAtClaim The fee snapshot at claim time
    /// @param requestBlock The RSK block number of the claim
    struct PegInClaim {
        address claimer;
        uint256 frontedAmount;
        uint256 feeAtClaim;
        uint256 requestBlock;
    }

    /// @notice The version of the contract
    string constant public VERSION = "1.0.0";
    /// @notice The name of the contract (used for EIP712)
    string constant public NAME = "PegInContract";
    Flyover.ProviderType constant private _PEG_TYPE = Flyover.ProviderType.PegIn;
    uint256 constant private _REFUND_ADDRESS_LENGTH = 21;

    uint256 constant private _MAX_CALL_GAS_COST = 35000;
    uint256 constant private _MAX_REFUND_GAS_LIMIT = 2300;

    int256 constant private _BRIDGE_UNPROCESSABLE_TX_VALIDATIONS_ERROR = -303;
    int256 constant private _BRIDGE_REFUNDED_USER_ERROR_CODE = -100;
    int256 constant private _BRIDGE_REFUNDED_LP_ERROR_CODE = -200;

    IBridge private _bridge;
    ICollateralManagement private _collateralManagement;

    mapping(address => uint256) private _balances;
    mapping(bytes32 => PegInStates) private _processedQuotes;
    mapping(bytes32 => Registry) private _callRegistry;

    uint256 private _minPegIn;
    bool private _mainnet;
    /// @notice The dust threshold for the peg in. If the difference between the amount paid and the amount required
    /// is more than this value, the difference goes back to the user's wallet
    uint256 public dustThreshold;

    /// @notice Commit-first address registry (appended after dustThreshold for proxy safety)
    IPegInAddressRegistry private _pegInAddressRegistry;
    /// @notice Shared peg-in fee and confirmation configuration
    IFlyoverConfigurations private _configurations;
    /// @notice Commit-first claims keyed by keccak256(rskAddr ++ btcTxHash)
    mapping(bytes32 => PegInClaim) private _pegInClaims;

    /// @notice Emitted when the dust threshold is set
    /// @param oldThreshold The old dust threshold
    /// @param newThreshold The new dust threshold
    event DustThresholdSet(uint256 indexed oldThreshold, uint256 indexed newThreshold);

    /// @notice Emitted when the minimum peg in amount is set
    /// @param oldMinPegIn The old minimum peg in amount
    /// @param newMinPegIn The new minimum peg in amount
    event MinPegInSet(uint256 indexed oldMinPegIn, uint256 indexed newMinPegIn);

    /// @notice Emitted when commit-first dependency contracts are set
    /// @param oldRegistry The previous PegInAddressRegistry address
    /// @param newRegistry The new PegInAddressRegistry address
    /// @param oldConfigurations The previous FlyoverConfigurations address
    /// @param newConfigurations The new FlyoverConfigurations address
    event PegInDependenciesSet(
        address indexed oldRegistry,
        address indexed newRegistry,
        address oldConfigurations,
        address newConfigurations
    );

    /// @notice Reverts when the PegInAddressRegistry dependency has not been set
    error PegInAddressRegistryNotSet();
    /// @notice Reverts when the FlyoverConfigurations dependency has not been set
    error FlyoverConfigurationsNotSet();
    /// @notice Reverts resolvePegIn until settlement is implemented
    error ResolvePegInNotImplemented();

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    // solhint-disable-next-line comprehensive-interface
    receive() external payable {
        if (msg.sender != address(_bridge)) {
            revert Flyover.PaymentNotAllowed();
        }
    }

    /// @notice This function is used to initialize the contract
    /// @param defaultAdmin the default admin of the contract
    /// @param bridge the address of the Rootstock bridge
    /// @param dustThreshold_ the dust threshold for the peg in
    /// @param minPegIn the minimum peg in amount supported by the bridge
    /// @param collateralManagement the address of the Collateral Management contract
    /// @param mainnet whether the contract is on the mainnet or not
    /// @param pauseRegistry the central PauseRegistry for pause state
    // solhint-disable-next-line comprehensive-interface
    function initialize(
        address defaultAdmin,
        address payable bridge,
        uint256 dustThreshold_,
        uint256 minPegIn,
        address collateralManagement,
        bool mainnet,
        IPauseRegistry pauseRegistry
    ) external initializer {
        if (collateralManagement.code.length == 0) revert Flyover.NoContract(collateralManagement);
        if (address(pauseRegistry).code.length == 0) revert Flyover.NoContract(address(pauseRegistry));
        __AccessControlDefaultAdminRules_init(0, defaultAdmin);
        __EIP712_init(NAME, VERSION);
        __EmergencyPause_init(pauseRegistry);
        _bridge = IBridge(bridge);
        _collateralManagement = ICollateralManagement(collateralManagement);
        _mainnet = mainnet;
        dustThreshold = dustThreshold_;
        _minPegIn = minPegIn;
    }

    /// @notice This function is used to set the collateral management contract
    /// @param collateralManagement the address of the Collateral Management contract
    /// @dev This function is only callable by the owner of the contract
    // solhint-disable-next-line comprehensive-interface
    function setCollateralManagement(address collateralManagement) external onlyRole(DEFAULT_ADMIN_ROLE) nonReentrant {
        if (collateralManagement.code.length == 0) revert Flyover.NoContract(collateralManagement);
        emit CollateralManagementSet(address(_collateralManagement), collateralManagement);
        _collateralManagement = ICollateralManagement(collateralManagement);
    }

    /// @notice This function is used to set the dust threshold
    /// @param threshold the new dust threshold
    /// @dev This function is only callable by the owner of the contract
    // solhint-disable-next-line comprehensive-interface
    function setDustThreshold(uint256 threshold) external onlyRole(DEFAULT_ADMIN_ROLE) nonReentrant {
        emit DustThresholdSet(dustThreshold, threshold);
        dustThreshold = threshold;
    }

    /// @notice This function is used to set the minimum peg in amount
    /// @param minPegIn the new minimum peg in amount
    /// @dev This function is only callable by the owner of the contract
    // solhint-disable-next-line comprehensive-interface
    function setMinPegIn(uint256 minPegIn) external onlyRole(DEFAULT_ADMIN_ROLE) nonReentrant {
        emit MinPegInSet(_minPegIn, minPegIn);
        _minPegIn = minPegIn;
    }

    /// @notice Wires the commit-first PegInAddressRegistry and FlyoverConfigurations dependencies
    /// @param registry The PegInAddressRegistry contract address
    /// @param configurations The FlyoverConfigurations contract address
    /// @dev Only callable by DEFAULT_ADMIN_ROLE. Both addresses must have code.
    // solhint-disable-next-line comprehensive-interface
    function setPegInDependencies(address registry, address configurations)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
        nonReentrant
    {
        if (registry.code.length == 0) revert Flyover.NoContract(registry);
        if (configurations.code.length == 0) revert Flyover.NoContract(configurations);
        address oldRegistry = address(_pegInAddressRegistry);
        address oldConfigurations = address(_configurations);
        _pegInAddressRegistry = IPegInAddressRegistry(registry);
        _configurations = IFlyoverConfigurations(configurations);
        emit PegInDependenciesSet(oldRegistry, registry, oldConfigurations, configurations);
    }

    /// @inheritdoc IPegIn
    function deposit() external payable nonReentrant whenNotSoftPaused override {
        if(!_collateralManagement.isRegistered(_PEG_TYPE, msg.sender)) {
            revert Flyover.ProviderNotRegistered(msg.sender);
        }
        _increaseBalance(msg.sender, msg.value);
    }

    /// @inheritdoc IPegIn
    function withdraw(uint256 amount) external nonReentrant whenNotHardPaused override {
        uint256 balance = _balances[msg.sender];
        if (balance < amount) {
            revert Flyover.NoBalance(amount, balance);
        }
        _decreaseBalance(msg.sender, amount);
        emit Withdrawal(msg.sender, amount);
        (bool success, bytes memory reason) = msg.sender.call{value: amount}("");
        if (!success) {
            revert Flyover.PaymentFailed(msg.sender, amount, reason);
        }
    }

    /// @inheritdoc IPegIn
    function callForUser(
        Quotes.PegInQuote calldata quote
    ) external payable nonReentrant whenNotHardPaused override returns (bool) {
        if(!_collateralManagement.isRegistered(_PEG_TYPE, msg.sender)) {
            revert Flyover.ProviderNotRegistered(msg.sender);
        }
        if (quote.liquidityProviderRskAddress != msg.sender) {
            revert Flyover.InvalidSender(quote.liquidityProviderRskAddress, msg.sender);
        }
        uint256 newBalance = _balances[quote.liquidityProviderRskAddress] + msg.value;
        if (newBalance < quote.value) {
            revert Flyover.InsufficientAmount(newBalance, quote.value);
        }

        bytes32 quoteHash = _hashPegInQuote(quote);
        if (_processedQuotes[quoteHash] != PegInStates.UNPROCESSED_QUOTE) {
            revert QuoteAlreadyProcessed(quoteHash);
        }

        _increaseBalance(quote.liquidityProviderRskAddress, msg.value);

        // This check ensures that the call cannot be performed with less gas than the agreed amount
        if (gasleft() < quote.gasLimit + _MAX_CALL_GAS_COST) {
            revert InsufficientGas(gasleft(), quote.gasLimit + _MAX_CALL_GAS_COST);
        }
        (bool success,) = quote.contractAddress.call{
            gas: quote.gasLimit,
            value: quote.value
        }(quote.data);

        _callRegistry[quoteHash].timestamp = block.timestamp;
        _processedQuotes[quoteHash] = PegInStates.CALL_DONE;

        if (success) {
            _callRegistry[quoteHash].success = true;
            _decreaseBalance(quote.liquidityProviderRskAddress, quote.value);
        }

        emit CallForUser(
            msg.sender,
            quote.contractAddress,
            quoteHash,
            quote.gasLimit,
            quote.value,
            quote.data,
            success
        );
        return success;
    }

    /// @inheritdoc IPegIn
    function registerPegIn(
        Quotes.PegInQuote calldata quote,
        bytes calldata signature,
        bytes calldata btcRawTransaction,
        bytes calldata partialMerkleTree,
        uint256 height
    ) external nonReentrant whenNotHardPaused override returns (int256) {
        bytes32 quoteHash = _hashPegInQuote(quote);
        _validateRegisterParams(quote, quoteHash, height, signature);
        int256 registerResult = _registerBridge(quote, btcRawTransaction, partialMerkleTree, height, quoteHash);

        bool btcRefunded = registerResult == _BRIDGE_REFUNDED_USER_ERROR_CODE ||
            registerResult == _BRIDGE_REFUNDED_LP_ERROR_CODE;
        if (registerResult == _BRIDGE_UNPROCESSABLE_TX_VALIDATIONS_ERROR) {
            revert NotEnoughConfirmations();
        } else if (!btcRefunded && registerResult < 1) {
            revert UnexpectedBridgeError(registerResult);
        }

        Registry memory callRegistry = _callRegistry[quoteHash];
        delete _callRegistry[quoteHash];
        if (_shouldPenalize(quote, registerResult, callRegistry.timestamp, height)) {
            _collateralManagement.slashPegInCollateral(msg.sender, quote, quoteHash);
        }
        if (btcRefunded) {
            _processedQuotes[quoteHash] = PegInStates.PROCESSED_QUOTE;
            emit BridgeCapExceeded(quoteHash, registerResult);
            return registerResult;
        }

        // the amount is safely assumed positive because it's already been validated there's
        // no (negative) error code being returned by the bridge.
        uint256 transferredAmount = uint256(registerResult);
        Quotes.checkAgreedAmount(quote, transferredAmount);

        _processedQuotes[quoteHash] = PegInStates.PROCESSED_QUOTE;
        emit PegInRegistered(quoteHash, transferredAmount);
        if (callRegistry.timestamp > 0) {
            _registerCallDone(quote, quoteHash, callRegistry.success, transferredAmount);
        } else {
            _registerCallNotDone(quote, quoteHash, transferredAmount);
        }
        return registerResult;
    }

    /// @inheritdoc IPegInCommitFirst
    function requestPegIn(
        address rskAddr,
        bytes calldata btcTxSerialized,
        bytes calldata opReturn,
        bytes32 btcBlockHash,
        uint256 merkleBranchPath,
        bytes32[] calldata merkleBranchHashes
    ) external payable nonReentrant whenNotHardPaused override returns (bytes32 pegInId) {
        bytes32 btcTxHash = BtcUtils.hashBtcTx(btcTxSerialized);
        pegInId = keccak256(abi.encodePacked(rskAddr, btcTxHash));
        if (_pegInClaims[pegInId].claimer != address(0)) {
            revert PegInAlreadyProcessed(pegInId);
        }

        _requirePegInDepsSet();
        if (!_pegInAddressRegistry.isRegistered(rskAddr)) {
            revert AddressNotRegistered(rskAddr);
        }
        uint256 amount = _readPegInAmount(rskAddr, btcTxSerialized, btcTxHash);
        _requirePegInConfirmations(amount, btcTxHash, btcBlockHash, merkleBranchPath, merkleBranchHashes);

        uint256 fee = _configurations.calculatePegInFee(amount);
        uint256 expected = _requireCorrectFronting(amount, fee);

        _pegInClaims[pegInId] = PegInClaim({
            claimer: msg.sender,
            frontedAmount: msg.value,
            feeAtClaim: fee,
            requestBlock: block.number
        });
        _payPegInUser(rskAddr, expected);
        emit PegInRequested(pegInId, msg.sender, rskAddr, amount, expected, true);
    }

    /// @inheritdoc IPegInCommitFirst
    function resolvePegIn(
        address rskAddr,
        bytes32 btcTxHash,
        bytes calldata btcRawTransaction,
        bytes calldata partialMerkleTree,
        uint256 height
    ) external pure override returns (int256) {
        revert ResolvePegInNotImplemented();
    }

    /// @notice Returns the wired PegInAddressRegistry address
    // solhint-disable-next-line comprehensive-interface
    function getPegInAddressRegistry() external view returns (address) {
        return address(_pegInAddressRegistry);
    }

    /// @notice Returns the wired FlyoverConfigurations address
    // solhint-disable-next-line comprehensive-interface
    function getFlyoverConfigurations() external view returns (address) {
        return address(_configurations);
    }

    /// @inheritdoc IPegIn
    function validatePegInDepositAddress(
        Quotes.PegInQuote calldata quote,
        bytes calldata depositAddress
    ) external view override returns (bool) {
        bytes32 derivationValue = keccak256(
            bytes.concat(
                _hashPegInQuote(quote),
                quote.btcRefundAddress,
                bytes20(quote.lbcAddress),
                quote.liquidityProviderBtcAddress
            )
        );
        bytes memory flyoverRedeemScript = bytes.concat(
            OpCodes.OP_PUSHBYTES_32,
            derivationValue,
            OpCodes.OP_DROP,
            _bridge.getActivePowpegRedeemScript()
        );
        bytes memory segwitScript = bytes.concat(OpCodes.OP_0, OpCodes.OP_PUSHBYTES_32, sha256(flyoverRedeemScript));
        return BtcUtils.validateP2SHAdress(depositAddress, segwitScript, _mainnet);
    }

    /// @inheritdoc IPegIn
    function getMinPegIn() external view override returns (uint256) {
        return _minPegIn;
    }

    /// @inheritdoc IPegIn
    function getBalance(address addr) external view override returns (uint256) {
        if (_reentrancyGuardEntered()) revert ReentrancyGuardReentrantCall();
        return _balances[addr];
    }

    /// @inheritdoc IPegIn
    function hashPegInQuote(Quotes.PegInQuote calldata quote) external view override returns (bytes32) {
        return _hashPegInQuote(quote);
    }

    /// @inheritdoc IPegIn
    function hashPegInQuoteEIP712(Quotes.PegInQuote calldata quote) external view override returns (bytes32) {
        return _hashPegInQuoteEIP712(quote);
    }

    /// @inheritdoc IPegIn
    function getQuoteStatus(bytes32 quoteHash) external view override returns (PegInStates) {
        if (_reentrancyGuardEntered()) revert ReentrancyGuardReentrantCall();
        return _processedQuotes[quoteHash];
    }

    /// @notice This function is used to increase the balance of an account
    /// @dev This function must remain private. Any exposure can lead to a loss of funds.
    /// It is responsibility of the caller to ensure that the account is a liquidity provider
    /// @param dest The address of account
    /// @param amount The amount of balance to increase
    function _increaseBalance(address dest, uint256 amount) private {
        if (amount > 0) {
            _balances[dest] += amount;
            emit BalanceIncrease(dest, amount);
        }
    }

    /// @notice Reverts unless commit-first registry and configurations are wired
    function _requirePegInDepsSet() private view {
        if (address(_pegInAddressRegistry) == address(0)) revert PegInAddressRegistryNotSet();
        if (address(_configurations) == address(0)) revert FlyoverConfigurationsNotSet();
    }

    /// @notice Reads the peg-in amount out of the deposit transaction
    /// @dev Two different operations, and only the first is a derivation: the deposit
    /// scriptPubkey for rskAddr is DERIVED (a formula over this proxy's address and the live
    /// powpeg script), and the amount is then READ from the FIRST output paying that script.
    /// Both go through the same helpers the registry uses at registration —
    /// {PegInDerivation-depositPkScript} for the script, {BtcTransactionReader} for the lookup. See
    /// {BtcTransactionReader-findFirstOutputPaying} for why first-match and not the sum, and why
    /// that is the open question here rather than in the registry.
    /// The derivation inputs come from state and the matched output from the SPV-proven bytes,
    /// so there is no argument a caller can move to change the answer.
    ///
    /// The powpeg script is read fresh from the bridge on every call, so a federation change
    /// rotates the expected script here exactly as it rotates the issued address. In-flight
    /// deposits to a pre-rotation address stop matching, which is the drain-then-rotate cost
    /// PegInDerivation documents, not a new failure mode.
    /// @param rskAddr The RSK destination address of the peg-in
    /// @param btcTxSerialized The witness-stripped raw deposit transaction
    /// @param btcTxHash The txid hashed from btcTxSerialized, for the revert reason
    /// @return The gross peg-in amount in wei
    function _readPegInAmount(address rskAddr, bytes calldata btcTxSerialized, bytes32 btcTxHash)
        private
        view
        returns (uint256)
    {
        bytes memory pkScript = PegInDerivation.depositPkScript(
            rskAddr, address(this), _bridge.getActivePowpegRedeemScript()
        );
        (uint64 depositSats, bool found) =
            BtcTransactionReader.findFirstOutputPaying(btcTxSerialized, pkScript);
        if (!found) {
            revert DepositOutputNotFound(rskAddr, btcTxHash);
        }
        return uint256(depositSats) * Flyover.SAT_TO_WEI_CONVERSION;
    }

    /// @notice Reverts unless Bridge confirmations meet the configured tier for amount
    function _requirePegInConfirmations(
        uint256 amount,
        bytes32 btcTxHash,
        bytes32 btcBlockHash,
        uint256 merkleBranchPath,
        bytes32[] calldata merkleBranchHashes
    ) private view {
        int256 reportedConfirmations = _bridge.getBtcTransactionConfirmations(
            btcTxHash, btcBlockHash, merkleBranchPath, merkleBranchHashes
        );
        uint256 requiredConfirmations = _configurations.getRequiredPegInBtcConfirmations(amount);
        if (reportedConfirmations < 0 || uint256(reportedConfirmations) < requiredConfirmations) {
            revert InsufficientConfirmations(
                reportedConfirmations < 0 ? 0 : uint256(reportedConfirmations),
                requiredConfirmations
            );
        }
    }

    /// @notice Validates msg.value equals amount minus fee; returns the expected net
    function _requireCorrectFronting(uint256 amount, uint256 fee) private view returns (uint256 expected) {
        if (amount < fee) {
            revert IncorrectFronting(0, msg.value);
        }
        expected = amount - fee;
        if (msg.value != expected) {
            revert IncorrectFronting(expected, msg.value);
        }
    }

    /// @notice Delivers net RBTC to the peg-in destination address
    // slither-disable-next-line arbitrary-send-eth,low-level-calls
    function _payPegInUser(address rskAddr, uint256 expected) private {
        (bool success, bytes memory reason) = rskAddr.call{value: expected}("");
        if (!success) {
            revert Flyover.PaymentFailed(rskAddr, expected, reason);
        }
    }

    /// @notice This function is used to decrease the balance of an account
    /// @dev This function must remain private. Any exposure can lead to a loss of funds.
    /// It is responsibility of the caller to ensure that the account is a liquidity provider
    /// @param dest The address of account
    /// @param amount The amount of balance to decrease
    function _decreaseBalance(address dest, uint256 amount) private {
        if (amount > 0) {
            _balances[dest] -= amount;
            emit BalanceDecrease(dest, amount);
        }
    }

    /// @notice This function is used to register the peg in into the bridge
    /// @param quote The quote of the peg in
    /// @param btcRawTransaction The raw transaction of the peg in in the Bitcoin network,
    /// without the witness data
    /// @param partialMerkleTree The partial merkle tree proving the inclusion of the peg
    /// in transaction
    /// @param height The height of the peg in transaction
    /// @param derivationHash The hash of the quote used to derive the deposit address
    /// @return registerResult The result of the registration. It can be:
    /// - A negative value: An error code returned by the bridge
    /// - A positive value: The amount of the peg in transaction
    function _registerBridge(
        Quotes.PegInQuote memory quote,
        bytes memory btcRawTransaction,
        bytes memory partialMerkleTree,
        uint256 height,
        bytes32 derivationHash
    ) private returns (int256) {
        Registry memory callRegistry = _callRegistry[derivationHash];
        return _bridge.registerFastBridgeBtcTransaction(
            btcRawTransaction,
            height,
            partialMerkleTree,
            derivationHash,
            quote.btcRefundAddress,
            payable(this),
            quote.liquidityProviderBtcAddress,
            callRegistry.timestamp > 0 && callRegistry.success
        );
    }

    /// @notice This function is used by the registerPegIn function to handle the scenarios
    /// where the liquidity provider has already called the callForUser function
    /// @dev This function makes an external call, therefore it might be exposed to a reentrancy attack,
    /// the caller must have the nonReentrant modifier or any kind of reentrancy protection. Not all the
    /// modifications to the state can be done before the call as some of them depend on the result of the
    /// call itself
    /// @param quote The quote of the peg in
    /// @param quoteHash The hash of the quote
    /// @param callSuccessful Whether the call on behalf of the user was successful or not
    /// @param transferredAmount The amount of the peg in transaction
    function _registerCallDone(
        Quotes.PegInQuote calldata quote,
        bytes32 quoteHash,
        bool callSuccessful,
        uint256 transferredAmount
    ) private {
        uint refundAmount;
        if (callSuccessful) {
            refundAmount = _min(transferredAmount, quote.value + quote.callFee + quote.gasFee);
        } else {
            refundAmount = _min(transferredAmount, quote.callFee + quote.gasFee);
        }
        _increaseBalance(quote.liquidityProviderRskAddress, refundAmount);

        uint remainingAmount = transferredAmount - refundAmount;
        if (remainingAmount > dustThreshold) {
            // refund rskRefundAddress, if remaining amount greater than dust
            (bool success,) = quote.rskRefundAddress.call{
                gas: _MAX_REFUND_GAS_LIMIT,
                value: remainingAmount
            }("");

            emit Refund(
                quote.rskRefundAddress,
                quoteHash,
                remainingAmount,
                success
            );

            if (!success) {
                // transfer funds to LP instead, if for some reason transfer to rskRefundAddress was unsuccessful
                _increaseBalance(quote.liquidityProviderRskAddress, remainingAmount);
            }
        }
    }

    /// @notice This function is used by the registerPegIn function to handle the scenarios
    /// where the liquidity provider has not called the callForUser function
    /// @dev This function makes an external call, therefore it might be exposed to a reentrancy attack,
    /// the caller must have the nonReentrant modifier or any kind of reentrancy protection. Not all the
    /// modifications to the state can be done before the call as some of them depend on the result of the
    /// call itself
    /// @param quote The quote of the peg in
    /// @param quoteHash The hash of the quote
    /// @param transferredAmount The amount of the peg in transaction
    function _registerCallNotDone(
        Quotes.PegInQuote calldata quote,
        bytes32 quoteHash,
        uint256 transferredAmount
    ) private {
        uint refundAmount = transferredAmount;

        if (quote.callOnRegister && refundAmount >= quote.value) { // solhint-disable-line gas-strict-inequalities
            (bool callSuccess,) = quote.contractAddress.call{
                gas: quote.gasLimit,
                value: quote.value
            }(quote.data);

            emit CallForUser(
                msg.sender,
                quote.contractAddress,
                quoteHash,
                quote.gasLimit,
                quote.value,
                quote.data,
                callSuccess
            );

            if (callSuccess) {
                refundAmount -= quote.value;
            }
        }
        if (refundAmount > dustThreshold) {
            // refund rskRefundAddress, if refund amount greater than dust
            (bool success,) = quote.rskRefundAddress.call{
                gas: _MAX_REFUND_GAS_LIMIT,
                value: refundAmount
            }("");
            emit Refund(
                quote.rskRefundAddress,
                quoteHash,
                refundAmount,
                success
            );
            if (!success) {
                // transfer funds to user instead, if for some reason transfer to rskRefundAddress was unsuccessful
                _increaseBalance(quote.rskRefundAddress, refundAmount);
            }
        }
    }

    /// @notice This function is used to validate the parameters of the registerPegIn function
    /// @dev The validations include:
    /// - If the quote was already registered
    /// - If the signature provided by the liquidity provider is valid
    /// - If the height is supported by the Rootstock bridge
    /// @param quote The quote of the peg in
    /// @param quoteHash The hash of the quote
    /// @param height The height of the peg in transaction
    /// @param signature The signature of the quoteHash by the liquidity provider
    function _validateRegisterParams(
        Quotes.PegInQuote calldata quote,
        bytes32 quoteHash,
        uint256 height,
        bytes calldata signature
    ) private view {
        if (_processedQuotes[quoteHash] == PegInStates.PROCESSED_QUOTE) {
            revert QuoteAlreadyProcessed(quoteHash);
        }
        bytes32 eip712hash = _hashPegInQuoteEIP712(quote);
        if (!SignatureValidator.verify(quote.liquidityProviderRskAddress, eip712hash, signature)) {
            revert SignatureValidator.IncorrectSignature(quote.liquidityProviderRskAddress, eip712hash, signature);
        }
        // the actual type in the RSKj node source code is a java int which is equivalent to int32
        if (height > uint256(int(type(int32).max)) - 1) {
            revert Flyover.Overflow(uint256(int(type(int32).max)));
        }
    }

    /// @notice This function is used to hash a peg in quote
    /// @dev The function also validates the following:
    /// - The quote belongs to this contract
    /// - The quote destination is not the bridge contract
    /// - The quote BTC refund address is valid
    /// - The quote liquidity provider BTC address is valid
    /// - The quote total amount is greater than the bridge minimum peg in amount
    /// - The sum of the timestamp values is not greater than the maximum uint32 value
    /// @param quote The peg in quote
    /// @return quoteHash The hash of the quote
    function _hashPegInQuote(Quotes.PegInQuote calldata quote) private view returns (bytes32) {
        _validatePegInQuote(quote);
        return keccak256(Quotes.encodeQuote(quote));
    }

    /// @notice This function is used to hash a peg in quote using EIP712 specification
    /// @dev The function also validates the following:
    /// - The quote belongs to this contract
    /// - The quote destination is not the bridge contract
    /// - The quote BTC refund address is valid
    /// - The quote liquidity provider BTC address is valid
    /// - The quote total amount is greater than the bridge minimum peg in amount
    /// - The sum of the timestamp values is not greater than the maximum uint32 value
    /// @param quote The peg in quote
    /// @return quoteHash The hash struct to be combined with the domain separator
    function _hashPegInQuoteEIP712(Quotes.PegInQuote calldata quote) private view returns (bytes32) {
        _validatePegInQuote(quote);
        return _hashTypedDataV4(Quotes.hashPegInQuoteEIP712(quote));
    }

    function _validatePegInQuote(Quotes.PegInQuote calldata quote) private view {
        if (quote.chainId != block.chainid) {
            revert Flyover.InvalidChainId(block.chainid, quote.chainId);
        }
        if (address(this) != quote.lbcAddress) {
            revert Flyover.IncorrectContract(address(this), quote.lbcAddress);
        }
        if (
            address(_bridge) == quote.contractAddress ||
            address(this) == quote.contractAddress ||
            address(0) == quote.contractAddress ||
            address(_collateralManagement) == quote.contractAddress
        ) {
            revert Flyover.NoContract(quote.contractAddress);
        }
        if (
            quote.btcRefundAddress.length != _REFUND_ADDRESS_LENGTH ||
            !_isValidBtcPrefix(quote.btcRefundAddress[0])
        ) {
            revert InvalidRefundAddress(quote.btcRefundAddress);
        }
        if (
            quote.liquidityProviderBtcAddress.length != _REFUND_ADDRESS_LENGTH ||
            !_isValidBtcPrefix(quote.liquidityProviderBtcAddress[0])
        ) {
            revert InvalidRefundAddress(quote.liquidityProviderBtcAddress);
        }
        uint256 total = quote.value + quote.callFee + quote.gasFee;
        if (total < _minPegIn) {
            revert AmountUnderMinimum(_minPegIn);
        }
        if (type(uint32).max < uint64(quote.agreementTimestamp) + uint64(quote.timeForDeposit)) {
            revert Flyover.Overflow(type(uint32).max);
        }
    }

    /// @notice This function is used to check if the prefix of a btc address is valid
    /// @param prefix The prefix of the address
    /// @return isValid Whether the prefix is valid or not
    function _isValidBtcPrefix(bytes1 prefix) private view returns (bool) {
        return _mainnet ?
            prefix == 0x00 || prefix == 0x05 : // p2pkh and p2sh mainnet
            prefix == 0x6f || prefix == 0xc4; // p2pkh and p2sh testnet
    }

    /// @notice This function is used to determine if the liquidity provider should be penalized
    /// @param quote The peg in quote
    /// @param amount The amount of the peg in transaction
    /// @param callTimestamp The timestamp of the call on behalf of the user
    /// @param height The height of the peg in transaction
    /// @return shouldPenalize Whether the liquidity provider should be penalized or not
    function _shouldPenalize(
        Quotes.PegInQuote calldata quote,
        int256 amount,
        uint256 callTimestamp,
        uint256 height
    ) private view returns (bool) {
        // do not penalize if deposit amount is insufficient
        uint256 quoteTotal = quote.value + quote.callFee + quote.gasFee;
        if (amount > 0 && uint256(amount) < quoteTotal) {
            return false;
        }

        bytes memory firstConfirmationHeader = _bridge.getBtcBlockchainBlockHeaderByHeight(height);
        if (firstConfirmationHeader.length < 1) revert Flyover.EmptyBlockHeader(bytes32(height));

        uint256 firstConfirmationTimestamp = BtcUtils.getBtcBlockTimestamp(
            firstConfirmationHeader
        );

        // do not penalize if deposit was not made on time (BTC-side, no pause adjustment)
        uint256 timeLimit = quote.agreementTimestamp + quote.timeForDeposit;
        if (firstConfirmationTimestamp > timeLimit) {
            return false;
        }

        bytes memory nConfirmationsHeader = _bridge.getBtcBlockchainBlockHeaderByHeight(
            height + quote.depositConfirmations - 1
        );
        if (nConfirmationsHeader.length < 1) revert Flyover.EmptyBlockHeader(bytes32(height));
        uint256 nConfirmationsTimestamp = BtcUtils.getBtcBlockTimestamp(
            nConfirmationsHeader
        );

        uint256 pauseOverlap = pauseRegistry().computePauseOverlap(
            nConfirmationsTimestamp,
            block.timestamp
        );
        uint256 adjustedDeadline = nConfirmationsTimestamp + quote.callTime + pauseOverlap;

        // if LP never called: penalize only if adjusted deadline has passed
        if (callTimestamp == 0) {
            return block.timestamp > adjustedDeadline;
        }

        // penalize if the call was not made on time (adjusted for hard pause)
        if (callTimestamp > adjustedDeadline) {
            return true;
        }

        return false;
    }

    /// @dev Utility function to return the minimum of two uint256 values
    function _min(uint a, uint b) private pure returns (uint) {
        return a < b ? a : b;
    }
}
