// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {
    AccessControlDefaultAdminRulesUpgradeable
} from "@openzeppelin/contracts-upgradeable/access/extensions/AccessControlDefaultAdminRulesUpgradeable.sol";
import {EIP712Upgradeable} from "@openzeppelin/contracts-upgradeable/utils/cryptography/EIP712Upgradeable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {BtcUtils} from "@rsksmart/btc-transaction-solidity-helper/contracts/BtcUtils.sol";
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
    /// @param feeAtClaim The service fee snapshot at claim time
    /// @param gasFeeAtClaim The gas fee snapshot at claim time
    /// @param requestBlock The RSK block number of the claim
    struct PegInClaim {
        address claimer;
        uint256 frontedAmount;
        uint256 feeAtClaim;
        uint256 gasFeeAtClaim;
        uint256 requestBlock;
    }

    /// @notice The version of the contract
    string constant public VERSION = "1.0.0";
    /// @notice The name of the contract (used for EIP712)
    string constant public NAME = "PegInContract";
    Flyover.ProviderType constant private _PEG_TYPE = Flyover.ProviderType.PegIn;
    uint256 constant private _MAX_REFUND_GAS_LIMIT = 2300;

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
    /// @notice Whether the registrant fee was already paid for a destination address
    mapping(address => bool) private _registrantPaid;
    /// @notice Whether a peg-in id was already settled on the claimed path
    mapping(bytes32 => bool) private _pegInSettled;

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

    /// @inheritdoc IPegInCommitFirst
    function requestPegIn(
        address rskAddr,
        bytes calldata btcTxSerialized,
        bytes32 btcBlockHash,
        uint256 merkleBranchPath,
        bytes32[] calldata merkleBranchHashes
    ) external payable nonReentrant whenNotSoftPaused override returns (bytes32 pegInId) {
        if(!_collateralManagement.isRegistered(_PEG_TYPE, msg.sender)) {
            revert Flyover.ProviderNotRegistered(msg.sender);
        }
        // Before the hash, never after: hashBtcTx would return a wtxid for the witness form, and
        // pegInId is derived from it. See {BtcTransactionReader-WitnessSerializedTxNotAccepted}.
        BtcTransactionReader.requireWitnessStripped(btcTxSerialized);
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
        IFlyoverConfigurations.PegConfiguration memory configuration = _configurations.getPegInConfiguration();
        if (amount < configuration.minAmount) {
            revert PegInBelowMinimum(amount, configuration.minAmount);
        }
        _requirePegInConfirmations(amount, btcTxHash, btcBlockHash, merkleBranchPath, merkleBranchHashes);

        uint256 fee = _configurations.calculatePegInFee(amount);
        uint256 expected = _requireCorrectFronting(amount, fee + configuration.claimGasFee);

        _pegInClaims[pegInId] = PegInClaim({
            claimer: msg.sender,
            frontedAmount: msg.value,
            feeAtClaim: fee,
            gasFeeAtClaim: configuration.claimGasFee,
            requestBlock: block.number
        });
        _payPegInUser(rskAddr, expected);
        emit PegInRequested(pegInId, msg.sender, rskAddr, amount, expected, true);
    }

    /// @inheritdoc IPegInCommitFirst
    function resolvePegIn(
        address rskAddr,
        bytes calldata btcRawTransaction,
        bytes calldata partialMerkleTree,
        uint256 height
    ) external override nonReentrant whenNotHardPaused returns (int256 registerResult) {
        bytes32 pegInId = _resolvePegInId(rskAddr, btcRawTransaction);
        PegInClaim memory claim = _requireClaimedUnsettled(pegInId);
        _requirePegInDepsSet();

        registerResult = _registerCommitFirstBridge(
            rskAddr, btcRawTransaction, partialMerkleTree, height
        );

        if (registerResult <= 0) {
            return registerResult;
        }

        _creditResolvedPegIn(pegInId, rskAddr, claim, uint256(registerResult));
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
    function getMinPegIn() external view override returns (uint256) {
        return _minPegIn;
    }

    /// @inheritdoc IPegIn
    function getBalance(address addr) external view override returns (uint256) {
        if (_reentrancyGuardEntered()) revert ReentrancyGuardReentrantCall();
        return _balances[addr];
    }

    /// @dev Bridge fast-register with per-network BTC placeholder addresses.
    function _registerCommitFirstBridge(
        address rskAddr,
        bytes calldata btcRawTransaction,
        bytes calldata partialMerkleTree,
        uint256 height
    ) private returns (int256) {
        return _bridge.registerFastBridgeBtcTransaction(
            btcRawTransaction,
            height,
            partialMerkleTree,
            PegInDerivation.derivationArgumentsHash(rskAddr),
            PegInDerivation.getRefundPlaceholderBtcAddress(_mainnet),
            payable(address(this)),
            PegInDerivation.getLpPlaceholderBtcAddress(_mainnet),
            true
        );
    }

    /// @dev released is the cap. If the bridge releases less than the claimer is owed, the
    /// claimer loses the difference, and other balances lose nothing. Dust goes to the claimer,
    /// so no RBTC stays in the contract with no owner. A remainder the user does not accept is
    /// credited to the user's balance, so the user can withdraw it.
    function _creditResolvedPegIn(
        bytes32 pegInId,
        address rskAddr,
        PegInClaim memory claim,
        uint256 released
    ) private {
        _pegInSettled[pegInId] = true;
        uint256 providerPot = _min(released, claim.frontedAmount + claim.feeAtClaim + claim.gasFeeAtClaim);

        (address registrant, uint256 registrantFeePaid) =
            _payRegistrantOnce(rskAddr, claim.feeAtClaim, providerPot);

        uint256 claimerPayout = providerPot - registrantFeePaid;
        _increaseBalance(claim.claimer, claimerPayout);

        uint256 remaining = released - providerPot;
        uint256 userPayout = 0;
        if (remaining > dustThreshold) {
            (bool success,) = rskAddr.call{gas: _MAX_REFUND_GAS_LIMIT, value: remaining}("");
            emit UserRemainderRefunded(pegInId, rskAddr, remaining, success);
            if (success) {
                userPayout = remaining;
            } else {
                _increaseBalance(rskAddr, remaining);
            }
        } else {
            _increaseBalance(claim.claimer, remaining);
            claimerPayout += remaining;
        }

        emit PegInResolved(
            pegInId, claim.claimer, registrant, released, claimerPayout, registrantFeePaid, userPayout
        );
    }

    /// @dev The registrant is paid once per registered address, on the first peg-in that settles
    /// to it.
    function _payRegistrantOnce(
        address rskAddr,
        uint256 feeAtClaim,
        uint256 providerPot
    ) private returns (address registrant, uint256 paid) {
        if (_registrantPaid[rskAddr]) {
            return (address(0), 0);
        }
        _registrantPaid[rskAddr] = true;
        registrant = _pegInAddressRegistry.getRegistrant(rskAddr);
        uint256 feeDue = _min(
            _min(_configurations.getPegInConfiguration().registrantFee, feeAtClaim),
            providerPot
        );
        if (feeDue > 0 && registrant != address(0)) {
            paid = feeDue;
            _increaseBalance(registrant, paid);
        }
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

    /// @dev Loads a claimed, not-yet-settled peg-in or reverts.
    function _requireClaimedUnsettled(bytes32 pegInId) private view returns (PegInClaim memory claim) {
        if (_pegInSettled[pegInId]) {
            revert PegInAlreadyProcessed(pegInId);
        }
        claim = _pegInClaims[pegInId];
        if (claim.claimer == address(0)) {
            revert PegInNotClaimed(pegInId);
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
    ///
    /// The network flag comes from this contract's own `_mainnet`, set at initialization. It must
    /// agree with the flag the registry was initialized with: the BTC placeholders mixed into the
    /// derivation are per-network, so a disagreement derives a script no deposit pays and every
    /// claim reverts DepositOutputNotFound.
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
            rskAddr, address(this), _bridge.getActivePowpegRedeemScript(), _mainnet
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

    /// @dev Derives pegInId from witness-stripped raw tx bytes.
    function _resolvePegInId(
        address rskAddr,
        bytes calldata btcRawTransaction
    ) private pure returns (bytes32 pegInId) {
        BtcTransactionReader.requireWitnessStripped(btcRawTransaction);
        pegInId = keccak256(abi.encodePacked(rskAddr, BtcUtils.hashBtcTx(btcRawTransaction)));
    }

    /// @dev Utility function to return the minimum of two uint256 values
    function _min(uint a, uint b) private pure returns (uint) {
        return a < b ? a : b;
    }
}
