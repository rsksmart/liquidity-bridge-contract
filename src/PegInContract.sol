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
import {Flyover} from "./libraries/Flyover.sol";
import {Quotes} from "./libraries/Quotes.sol";
import {SignatureValidator} from "./libraries/SignatureValidator.sol";

/// @title PegIn
/// @notice This contract is used to handle the peg in of the Bitcoin network to the Rootstock network
/// @dev All non pure/view functions in this contract should be marked as nonReentrant
/// @author Rootstock Labs
contract PegInContract is
    AccessControlDefaultAdminRulesUpgradeable,
    EmergencyPause,
    ReentrancyGuard,
    EIP712Upgradeable,
    IPegIn
{
    /// @notice This struct is used to store the information of a call on behalf of the user
    /// @param timestamp The timestamp of the call
    /// @param success Whether the call was successful or not
    struct Registry {
        uint256 timestamp;
        bool success;
    }

    /// @notice State of a commit-first (E4) peg-in claim, keyed by `_pegInId(rskAddr, btcTxHash)`.
    /// @param claimer The LP that fronted the RBTC by calling requestPegIn (0 if unclaimed).
    /// @param amount The full peg-in amount the claim is for.
    /// @param fee The config-sourced fee for this amount, returned to the claimer at settlement.
    /// @param requestBlock The block at which requestPegIn was called.
    /// @param resolved True once resolvePegIn settled the claim with the Bridge.
    struct PegInClaim {
        address claimer;
        uint256 amount;
        uint256 fee;
        uint256 requestBlock;
        bool resolved;
    }

    /// @notice The version of the contract
    string constant public VERSION = "1.0.0";
    /// @notice The name of the contract (used for EIP712)
    string constant public NAME = "PegInContract";
    Flyover.ProviderType constant private _PEG_TYPE = Flyover.ProviderType.PegIn;
    uint256 constant private _REFUND_ADDRESS_LENGTH = 21;

    uint256 constant private _MAX_CALL_GAS_COST = 35000;
    uint256 constant private _MAX_REFUND_GAS_LIMIT = 2300;

    /// @notice OP_RETURN SC-call header length: destContract(20) + maxGasFee(32).
    uint256 constant private _OP_RETURN_HEADER_LENGTH = 52;
    /// @notice OP_RETURN payload cap for an SC-call. The standard Bitcoin budget is ~80 bytes; this
    /// admits the header (52) plus a small selector+single-arg callData (header + 4 + 32 = 88) while
    /// rejecting clearly oversized payloads, which are treated as a plain peg-in (constraints.md).
    uint256 constant private _OP_RETURN_MAX_LENGTH = 100;
    /// @notice E2 derivation scheme tag, mirrored from PegInAddressRegistry.DERIVATION_DOMAIN.
    bytes constant private _DERIVATION_DOMAIN = "FLYOVER_PEGIN_V1";

    int256 constant private _BRIDGE_UNPROCESSABLE_TX_VALIDATIONS_ERROR = -303;
    int256 constant private _BRIDGE_REFUNDED_USER_ERROR_CODE = -100;
    int256 constant private _BRIDGE_REFUNDED_LP_ERROR_CODE = -200;
    /// @dev A Bridge result below this value is an error code, not a deposited amount.
    int256 constant private _MIN_VALID_BRIDGE_RESULT = 1;

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

    // --- E4 commit-first claim flow: APPENDED storage (never reorder the fields above). ---------

    /// @notice The peg-in address registry (E2): source of truth for registration + deposit address.
    IPegInAddressRegistry private _registry;
    /// @notice The fee/confirmation configuration (E1): replaces quote-sourced fees.
    IFlyoverConfigurations private _configurations;
    /// @notice Blocks after the registration block within which a registered peg-in must be claimed
    /// before it becomes globally slashable. Anchored to the registration block (E4.4), not deposit.
    uint256 private _claimDeadlineBlocks;
    /// @notice Registrant (Watchtower) fee paid once, from callFee, on the first peg-in of an address.
    uint256 private _registrantFee;
    /// @notice Claim state per peg-in id (rskAddr + btcTxHash).
    mapping(bytes32 => PegInClaim) private _claims;
    /// @notice True once the registrant fee has been paid for an RSK address (first peg-in only).
    mapping(address => bool) private _registrantPaid;

    /// @notice Emitted when the dust threshold is set
    /// @param oldThreshold The old dust threshold
    /// @param newThreshold The new dust threshold
    event DustThresholdSet(uint256 indexed oldThreshold, uint256 indexed newThreshold);

    /// @notice Emitted when the minimum peg in amount is set
    /// @param oldMinPegIn The old minimum peg in amount
    /// @param newMinPegIn The new minimum peg in amount
    event MinPegInSet(uint256 indexed oldMinPegIn, uint256 indexed newMinPegIn);

    /// @notice Emitted when the E4 dependencies (registry, configurations) are wired.
    event PegInClaimDependenciesSet(address indexed registry, address indexed configurations);
    /// @notice Emitted when an LP claims a peg-in by fronting RBTC.
    /// @param pegInId The claim id (rskAddr + btcTxHash)
    /// @param claimer The LP that fronted the RBTC
    /// @param rskAddr The registered RSK address being served
    /// @param amount The full peg-in amount
    /// @param netToUser The amount delivered to the user / destination (amount - fee)
    /// @param callSuccess Whether the destination call (if any) succeeded
    event PegInRequested(
        bytes32 indexed pegInId,
        address indexed claimer,
        address indexed rskAddr,
        uint256 amount,
        uint256 netToUser,
        bool callSuccess
    );
    /// @notice Emitted when a claim is settled with the Bridge and the claimer is paid back.
    /// @param pegInId The claim id
    /// @param claimer The LP that is reimbursed
    /// @param fronted The RBTC the LP fronted (amount - fee)
    /// @param fee The fee returned to the LP (net of any registrant fee)
    event PegInResolved(bytes32 indexed pegInId, address indexed claimer, uint256 fronted, uint256 fee);
    /// @notice Emitted when an unclaimed, valid, registered peg-in past its deadline triggers a global slash.
    /// @param rskAddr The registered RSK address whose peg-in went unserved
    /// @param amount The peg-in amount
    event UnclaimedPegInSlashed(address indexed rskAddr, uint256 indexed amount);

    /// @notice Raised when a peg-in has already been claimed or resolved.
    error PegInAlreadyProcessed(bytes32 pegInId);
    /// @notice Raised when the RSK address is not registered in the address registry.
    error AddressNotRegistered(address rskAddr);
    /// @notice Raised when an E4 dependency has not been wired.
    error DependencyNotSet();
    /// @notice Raised when the claim's required confirmations are not yet met.
    error InsufficientConfirmations(uint256 have, uint256 required);
    /// @notice Raised when the RBTC fronted by the LP does not match amount - fee.
    error IncorrectFronting(uint256 expected, uint256 provided);
    /// @notice Raised when resolvePegIn is called for a peg-in that was never claimed.
    error PegInNotClaimed(bytes32 pegInId);
    /// @notice Raised when the Bridge rejects the settlement (e.g. not enough confirmations).
    error BridgeSettlementFailed(int256 bridgeResult);
    /// @notice Raised when a slash is attempted before the claim deadline has passed.
    error ClaimDeadlineNotReached(uint256 deadlineBlock);

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

    /// @notice Wires the E4 claim-flow dependencies (registry + configurations) and the claim deadline.
    /// @dev Append-only setter for the commit-first peg-in path; callable by the admin so the existing
    /// storage layout is preserved across the upgrade. The legacy quote-based path is unaffected.
    /// @param registry The PegInAddressRegistry (E2)
    /// @param configurations The FlyoverConfigurations (E1)
    /// @param claimDeadlineBlocks Blocks after the registration block before an unclaimed peg-in is slashable
    /// @param registrantFee The registrant (Watchtower) fee paid from callFee on the first peg-in of an address
    // solhint-disable-next-line comprehensive-interface
    function setPegInClaimDependencies(
        address registry,
        address configurations,
        uint256 claimDeadlineBlocks,
        uint256 registrantFee
    ) external onlyRole(DEFAULT_ADMIN_ROLE) nonReentrant {
        if (registry.code.length == 0) revert Flyover.NoContract(registry);
        if (configurations.code.length == 0) revert Flyover.NoContract(configurations);
        _registry = IPegInAddressRegistry(registry);
        _configurations = IFlyoverConfigurations(configurations);
        _claimDeadlineBlocks = claimDeadlineBlocks;
        _registrantFee = registrantFee;
        emit PegInClaimDependenciesSet(registry, configurations);
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

    // =====================================================================================
    // E4 commit-first peg-in claim flow
    // =====================================================================================

    /// @notice E4.1/E4.2 — an LP claims a confirmed, registered peg-in by fronting RBTC from its OWN
    /// wallet (msg.value), delivering `amount - fee` to the user or an OP_RETURN-described destination.
    /// The fee and the required confirmations come from FlyoverConfigurations, not a quote. The claim is
    /// later settled by resolvePegIn, which returns the fronted RBTC plus the fee to the claimer.
    /// @dev Reverts on the FIRST line if the peg-in id is already processed (cheap double-claim guard).
    /// @param rskAddr The registered RSK address whose deposit address received the BTC
    /// @param amount The full peg-in amount (LP fronts amount - fee; fee is config-sourced)
    /// @param btcTxHash The BTC transaction id of the deposit (identifies the peg-in)
    /// @param opReturn The OP_RETURN script bytes for an SC-call peg-in, or empty for a plain peg-in
    /// @return callSuccess Whether the destination call (if any) succeeded
    function requestPegIn(
        address rskAddr,
        uint256 amount,
        bytes32 btcTxHash,
        bytes calldata opReturn
    ) external payable nonReentrant whenNotHardPaused returns (bool callSuccess) {
        bytes32 id = _pegInId(rskAddr, btcTxHash);
        // First line: cheap revert on a double claim.
        if (_claims[id].claimer != address(0)) revert PegInAlreadyProcessed(id);

        if (address(_registry) == address(0) || address(_configurations) == address(0)) {
            revert DependencyNotSet();
        }
        if (!_registry.isRegistered(rskAddr)) revert AddressNotRegistered(rskAddr);

        uint256 required = _configurations.getRequiredPegInConfirmations(amount);
        uint256 confirmations = _confirmationsFor(btcTxHash);
        if (confirmations < required) revert InsufficientConfirmations(confirmations, required);

        uint256 fee = _configurations.calculatePegInFee(amount);
        uint256 netToUser = amount - fee;
        // The LP fronts the net amount from its own wallet, NOT from contract _balances.
        if (msg.value != netToUser) revert IncorrectFronting(netToUser, msg.value);

        _claims[id] = PegInClaim({
            claimer: msg.sender,
            amount: amount,
            fee: fee,
            requestBlock: block.number,
            resolved: false
        });

        callSuccess = _deliver(rskAddr, netToUser, opReturn);
        emit PegInRequested(id, msg.sender, rskAddr, amount, netToUser, callSuccess);
    }

    /// @notice E4.3 — settles a claimed peg-in with the Bridge and reimburses the claiming LP its fronted
    /// RBTC plus the full callFee. On the first peg-in for an address, the registrant (Watchtower) fee is
    /// subtracted from the fee and credited to the registrant.
    /// @param rskAddr The registered RSK address the claim served
    /// @param btcTxHash The BTC transaction id of the deposit
    /// @param btcRawTransaction The raw BTC transaction (without witness data)
    /// @param partialMerkleTree The partial merkle tree proving inclusion
    /// @param height The BTC block height of the transaction
    /// @param registrant The address that registered the RSK address (credited the registrant fee once)
    /// @return bridgeResult The amount released by the Bridge
    function resolvePegIn(
        address rskAddr,
        bytes32 btcTxHash,
        bytes calldata btcRawTransaction,
        bytes calldata partialMerkleTree,
        uint256 height,
        address payable registrant
    ) external nonReentrant whenNotHardPaused returns (int256 bridgeResult) {
        bytes32 id = _pegInId(rskAddr, btcTxHash);
        if (_claims[id].claimer == address(0)) revert PegInNotClaimed(id);
        if (_claims[id].resolved) revert PegInAlreadyProcessed(id);

        // Settle with the Bridge: release the deposited RBTC to this contract.
        bridgeResult = _settleWithBridge(rskAddr, btcRawTransaction, partialMerkleTree, height);
        if (bridgeResult < _MIN_VALID_BRIDGE_RESULT) revert BridgeSettlementFailed(bridgeResult);

        _claims[id].resolved = true;
        _reimburseClaim(id, rskAddr, registrant);
    }

    /// @notice Calls the Bridge to settle a claimed peg-in, releasing the deposited RBTC to this contract.
    /// Split out of resolvePegIn to bound stack use. Uses the E2 derivation value for the RSK address.
    /// @param rskAddr The registered RSK address
    /// @param btcRawTransaction The raw BTC transaction (without witness data)
    /// @param partialMerkleTree The partial merkle tree proving inclusion
    /// @param height The BTC block height of the transaction
    /// @return The Bridge result (the released amount, or a negative error code)
    function _settleWithBridge(
        address rskAddr,
        bytes calldata btcRawTransaction,
        bytes calldata partialMerkleTree,
        uint256 height
    ) private returns (int256) {
        return _bridge.registerFastBridgeBtcTransaction(
            btcRawTransaction,
            height,
            partialMerkleTree,
            _derivationValue(rskAddr),
            new bytes(0),
            payable(this),
            new bytes(0),
            true
        );
    }

    /// @notice Reimburses the claiming LP its fronted RBTC plus the fee, paying the registrant (Watchtower)
    /// fee once from the fee on the first peg-in for the address. Split out of resolvePegIn to bound stack use.
    /// @param id The claim id
    /// @param rskAddr The registered RSK address
    /// @param registrant The address credited the registrant fee once (ignored if zero)
    function _reimburseClaim(bytes32 id, address rskAddr, address payable registrant) private {
        PegInClaim memory claim = _claims[id];
        uint256 fronted = claim.amount - claim.fee;
        uint256 feeToClaimer = claim.fee;

        // Registrant (Watchtower) fee: paid once, from the fee, on the first peg-in for the address.
        if (!_registrantPaid[rskAddr] && _registrantFee > 0 && registrant != address(0)) {
            _registrantPaid[rskAddr] = true;
            uint256 registrantFee = _registrantFee < feeToClaimer ? _registrantFee : feeToClaimer;
            feeToClaimer -= registrantFee;
            if (registrantFee > 0) {
                _increaseBalance(registrant, registrantFee);
            }
        }

        // Reimburse the claiming LP: its fronted RBTC plus the (remaining) fee.
        _increaseBalance(claim.claimer, fronted + feeToClaimer);

        emit PegInResolved(id, claim.claimer, fronted, feeToClaimer);
    }

    /// @notice E4.4 — slashes the network when a valid, registered peg-in is left unclaimed past its
    /// deadline (anchored to the registration block). No single LP is at fault, so the whole network is
    /// slashed via CollateralManagement.globalSlash. Unregistered addresses and below-minimum amounts are
    /// NOT penalizable.
    /// @param rskAddr The registered RSK address whose peg-in went unserved
    /// @param amount The peg-in amount (used to source the penalty and check the minimum)
    /// @param btcTxHash The BTC transaction id of the unserved deposit
    function slashUnclaimedPegIn(
        address rskAddr,
        uint256 amount,
        bytes32 btcTxHash
    ) external nonReentrant whenNotHardPaused {
        if (address(_registry) == address(0) || address(_configurations) == address(0)) {
            revert DependencyNotSet();
        }
        // Non-penalizable: unregistered address.
        if (!_registry.isRegistered(rskAddr)) revert AddressNotRegistered(rskAddr);

        bytes32 id = _pegInId(rskAddr, btcTxHash);
        // Already claimed/served: nothing to slash.
        if (_claims[id].claimer != address(0)) revert PegInAlreadyProcessed(id);

        // Non-penalizable: below the Flyover minimum amount.
        uint256 minAmount = _configurations.getPegInConfiguration().minAmount;
        if (amount < minAmount) revert AmountUnderMinimum(minAmount);

        // Deadline anchored to the registration block, not the deposit.
        uint256 deadlineBlock = _registry.getRegistrationBlock(rskAddr) + _claimDeadlineBlocks;
        if (block.number <= deadlineBlock) revert ClaimDeadlineNotReached(deadlineBlock);

        // Mark processed so the slash cannot be repeated for this peg-in.
        _claims[id] = PegInClaim({
            claimer: address(this),
            amount: amount,
            fee: 0,
            requestBlock: block.number,
            resolved: true
        });

        uint256 penalty = _configurations.getPegInConfiguration().penaltyFee;
        _collateralManagement.globalSlash(penalty);
        emit UnclaimedPegInSlashed(rskAddr, amount);
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

    /// @notice Returns the E4 claim id for an (rskAddr, btcTxHash) pair.
    /// @param rskAddr The registered RSK address
    /// @param btcTxHash The BTC transaction id
    /// @return The claim id
    // solhint-disable-next-line comprehensive-interface
    function pegInId(address rskAddr, bytes32 btcTxHash) external pure returns (bytes32) {
        return _pegInId(rskAddr, btcTxHash);
    }

    /// @notice Returns the claim record for an E4 peg-in.
    /// @param rskAddr The registered RSK address
    /// @param btcTxHash The BTC transaction id
    /// @return The claim record
    // solhint-disable-next-line comprehensive-interface
    function getPegInClaim(address rskAddr, bytes32 btcTxHash) external view returns (PegInClaim memory) {
        return _claims[_pegInId(rskAddr, btcTxHash)];
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

    /// @notice Delivers the net peg-in amount to the user (plain peg-in) or an OP_RETURN-described
    /// destination contract (SC-call peg-in). A reverting destination does NOT revert the peg-in: the
    /// funds are refunded to the RSK (refund) address and the call is marked failed (E4.2 / constraints).
    /// @param rskAddr The RSK address; also the refund address for a failed SC-call
    /// @param netAmount The amount to deliver (amount - fee)
    /// @param opReturn The OP_RETURN script bytes (empty => plain peg-in)
    /// @return callSuccess Whether the destination call succeeded (true for a plain peg-in)
    function _deliver(
        address rskAddr,
        uint256 netAmount,
        bytes calldata opReturn
    ) private returns (bool callSuccess) {
        (bool isCall, address destination, uint256 maxGasFee, bytes memory callData) = _parseOpReturn(opReturn);

        if (!isCall) {
            // Plain peg-in: send the net amount to the RSK address.
            (bool ok,) = payable(rskAddr).call{value: netAmount}("");
            if (!ok) revert Flyover.PaymentFailed(rskAddr, netAmount, "");
            return true;
        }

        // SC-call peg-in: call the destination with callData and the net amount, capped at maxGasFee gas.
        uint256 gasCap = maxGasFee == 0 ? gasleft() : maxGasFee;
        (callSuccess,) = destination.call{value: netAmount, gas: gasCap}(callData);

        if (!callSuccess) {
            // Reverting destination: refund the RSK address and mark a failed call; do NOT revert the peg-in.
            (bool refunded,) = payable(rskAddr).call{value: netAmount}("");
            if (!refunded) revert Flyover.PaymentFailed(rskAddr, netAmount, "");
        }
    }

    /// @notice Parses an OP_RETURN script per the locked layout: OP_RETURN <destContract:20> <maxGasFee:32>
    /// <callData>. An empty payload is a plain peg-in. A malformed or oversized payload is treated as a plain
    /// peg-in (no SC-call), per constraints.md.
    /// @param opReturn The OP_RETURN script bytes (with or without a leading OP_RETURN opcode)
    /// @return isCall True if a well-formed SC-call payload was parsed
    /// @return destination The destination contract address
    /// @return maxGasFee The maximum gas budget for the call
    /// @return callData The bounded calldata
    function _parseOpReturn(
        bytes calldata opReturn
    ) private pure returns (bool isCall, address destination, uint256 maxGasFee, bytes memory callData) {
        if (opReturn.length == 0) {
            return (false, address(0), 0, new bytes(0));
        }
        // Oversized: beyond the standard OP_RETURN budget -> treat as plain (rejected as an SC-call).
        if (opReturn.length > _OP_RETURN_MAX_LENGTH) {
            return (false, address(0), 0, new bytes(0));
        }
        // Strip a leading OP_RETURN opcode if present so callers can pass either the script or the payload.
        bytes calldata payload = opReturn;
        if (opReturn[0] == OpCodes.OP_RETURN) {
            payload = opReturn[1:];
        }
        // Malformed: must hold at least the destContract(20) + maxGasFee(32) header.
        if (payload.length < _OP_RETURN_HEADER_LENGTH) {
            return (false, address(0), 0, new bytes(0));
        }

        destination = address(bytes20(payload[0:20]));
        maxGasFee = uint256(bytes32(payload[20:52]));
        callData = payload[52:];
        // A zero destination is not a valid SC-call target.
        if (destination == address(0)) {
            return (false, address(0), 0, new bytes(0));
        }
        isCall = true;
    }

    /// @notice Reads the confirmations for a BTC transaction from the Bridge.
    /// @dev Canonical confirmations count is read by tx hash; PoC/mock scope does not need block/merkle inputs.
    /// @param btcTxHash The BTC transaction id
    /// @return The number of confirmations (0 if the Bridge returns a negative error code)
    function _confirmationsFor(bytes32 btcTxHash) private view returns (uint256) {
        bytes32[] memory empty;
        int256 result = _bridge.getBtcTransactionConfirmations(btcTxHash, bytes32(0), 0, empty);
        return result < 0 ? 0 : uint256(result);
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
        if (address(_bridge) == quote.contractAddress) {
            revert Flyover.NoContract(quote.contractAddress);
        }
        if (quote.btcRefundAddress.length != _REFUND_ADDRESS_LENGTH) {
            revert InvalidRefundAddress(quote.btcRefundAddress);
        }
        if (quote.liquidityProviderBtcAddress.length != _REFUND_ADDRESS_LENGTH) {
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

    /// @notice Computes the Bridge fast-bridge derivation value for an RSK address (E2 scheme),
    /// mirroring PegInAddressRegistry: keccak256(abi.encodePacked(DERIVATION_DOMAIN, rskAddr)).
    /// @param rskAddr The RSK address
    /// @return The derivation value used by the Bridge to reconstruct the flyover redeem script
    function _derivationValue(address rskAddr) private pure returns (bytes32) {
        return keccak256(abi.encodePacked(_DERIVATION_DOMAIN, rskAddr));
    }

    /// @notice Computes the E4 claim id for an (rskAddr, btcTxHash) pair.
    /// @param rskAddr The registered RSK address
    /// @param btcTxHash The BTC transaction id
    /// @return The claim id
    function _pegInId(address rskAddr, bytes32 btcTxHash) private pure returns (bytes32) {
        return keccak256(abi.encodePacked(rskAddr, btcTxHash));
    }
}
