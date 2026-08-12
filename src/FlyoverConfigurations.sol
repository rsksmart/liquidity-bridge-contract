// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {
    AccessControlDefaultAdminRulesUpgradeable
} from "@openzeppelin/contracts-upgradeable/access/extensions/AccessControlDefaultAdminRulesUpgradeable.sol";
import {IFlyoverConfigurations} from "./interfaces/IFlyoverConfigurations.sol";
import {Flyover} from "./libraries/Flyover.sol";

/// @title FlyoverConfigurations
/// @notice On-chain source of commit-first peg-in and peg-out parameters, exposed via the
/// frozen {IFlyoverConfigurations}. Peg-out storage uses a separate ERC-7201 namespace so
/// peg-in layout / tests stay unchanged. Admin changes are time-locked (queue then apply)
/// and re-validated against immutable bounds.
/// @author Rootstock Labs
contract FlyoverConfigurations is
    AccessControlDefaultAdminRulesUpgradeable,
    IFlyoverConfigurations
{
    /// @notice Identifies the scalar field an out-of-bounds revert refers to.
    enum Field {
        FixedFee,
        PercentageFee,
        MinAmount,
        MaxAmount,
        PenaltyFee,
        ClaimWindow,
        ClaimWindowBlocks,
        CallTime,
        ExpireTime,
        ExpireBlocks,
        MaxMinerFee,
        GasFee,
        DepositConfirmations
    }

    /// @custom:storage-location erc7201:rsk.flyover.FlyoverConfigurations
    struct FlyoverConfigurationsStorage {
        PegConfiguration activePegIn;
        PegConfiguration pending;
        uint256 pendingEta;
    }

    /// @custom:storage-location erc7201:rsk.flyover.FlyoverConfigurations.bounds
    /// @dev Held in a separate namespace from the mutable config. Written once in `initialize`
    /// and never again; these are the immutable deployment bounds every queued change is
    /// re-validated against.
    struct FlyoverConfigurationsBounds {
        uint256 timelockDelay;
        PegConfiguration min;
        PegConfiguration max;
    }

    /// @custom:storage-location erc7201:rsk.flyover.FlyoverConfigurations.pegOut
    /// @dev Separate namespace so peg-out never shifts peg-in storage (Timelock slot tests, etc.).
    struct PegOutConfigurationsStorage {
        PegOutConfiguration active;
        PegOutConfiguration pending;
        uint256 pendingEta;
        PegOutConfiguration minBound;
        PegOutConfiguration maxBound;
        bool initialized;
    }

    /// @notice The version of the contract
    string public constant VERSION = "1.0.0";

    /// @notice Percentage fee denominator: 10_000 == 100%.
    uint256 public constant FEE_PERCENTAGE_DENOMINATOR = 10_000;

    /// @notice 1 satoshi expressed in wei; fees are rounded down to a satoshi boundary so on-chain
    /// fees agree with the bridge. Mirrors `Quotes.SAT_TO_WEI_CONVERSION`.
    uint256 public constant SAT_TO_WEI_CONVERSION = 10 ** 10;

    // ERC-7201: keccak256(abi.encode(uint256(keccak256("rsk.flyover.FlyoverConfigurations")) - 1)) &
    // ~bytes32(uint256(0xff))
    bytes32 private constant _FLYOVER_CONFIGURATIONS_STORAGE =
        0x13aa2a37a5354fe7c5dcced2a6c33933ec66091f98f22792660cd2862f158700;

    // ERC-7201: keccak256(abi.encode(uint256(keccak256("rsk.flyover.FlyoverConfigurations.bounds")) - 1)) &
    // ~bytes32(uint256(0xff))
    bytes32 private constant _FLYOVER_CONFIGURATIONS_BOUNDS =
        0x62f8e0a1022a246e45081dab13f708870be3f38423627ed9d784f6bc5369e500;

    // ERC-7201: keccak256(abi.encode(uint256(keccak256("rsk.flyover.FlyoverConfigurations.pegOut")) - 1)) &
    // ~bytes32(uint256(0xff))
    bytes32 private constant _FLYOVER_CONFIGURATIONS_PEGOUT =
        0x15978da28ad46e9b891b8591ece2c0413e91c9a5c9c768c642316e015001be00;

    /// @notice Emitted when a configuration change is queued by the admin.
    /// @param newConfiguration The configuration that will activate once the time lock elapses
    /// @param eta The earliest timestamp `applyChange` may activate the queued configuration
    event ChangeQueued(PegConfiguration newConfiguration, uint256 eta);

    /// @notice Emitted when a queued configuration change is applied and becomes active.
    /// @param newConfiguration The now-active configuration
    event ChangeApplied(PegConfiguration newConfiguration);

    event PegOutChangeQueued(PegOutConfiguration newConfiguration, uint256 eta);
    event PegOutChangeApplied(PegOutConfiguration newConfiguration);

    /// @notice Raised when a scalar field falls outside its immutable deployment bound.
    error ConfigValueOutOfBounds(Field field, uint256 value, uint256 min, uint256 max);
    /// @notice Raised when minAmount exceeds maxAmount.
    error InvalidAmountLimits(uint256 minAmount, uint256 maxAmount);
    /// @notice Raised when percentageFee exceeds the 10_000 denominator (100%).
    error InvalidPercentageFee(uint256 percentageFee);
    /// @notice Raised when the confirmation-tier list is empty.
    error EmptyTiers();
    /// @notice Raised when the confirmation-tier list is not strictly ascending by maxAmount.
    error TiersNotAscending();
    /// @notice Raised when applying a change before its time lock elapses.
    error TimelockNotElapsed(uint256 eta, uint256 nowTime);
    /// @notice Raised when applying while no change is queued.
    error NoQueuedChange();
    /// @notice Raised when peg-out seed/bounds were already written via {initializePegOut}.
    error PegOutAlreadyInitialized();
    /// @notice Raised when peg-out has not been seeded yet.
    error PegOutNotInitialized();
    /// @notice Raised when peg-out claim/expire windows are zero.
    error InvalidPegOutDeadlines();

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @notice This contract does not accept value
    // solhint-disable-next-line comprehensive-interface
    receive() external payable {
        revert Flyover.PaymentNotAllowed();
    }

    /// @notice Initializes the contract with the seed peg-in configuration and immutable bounds.
    /// @dev Writes the bounds and time-lock delay once, then validates and stores the seed config
    /// against those bounds. Must be called only once (proxy initializer).
    /// @param defaultAdmin The default admin and initial owner address
    /// @param initialDelay The initial admin delay for `AccessControlDefaultAdminRules`
    /// @param timelockDelay The delay (seconds) every queued configuration change must wait
    /// @param pegInConfig The initial peg-in configuration
    /// @param pegInMin Lower bound for every peg-in scalar field
    /// @param pegInMax Upper bound for every peg-in scalar field
    // solhint-disable-next-line comprehensive-interface
    function initialize(
        address defaultAdmin,
        uint48 initialDelay,
        uint256 timelockDelay,
        PegConfiguration calldata pegInConfig,
        PegConfiguration calldata pegInMin,
        PegConfiguration calldata pegInMax
    ) external initializer {
        __AccessControlDefaultAdminRules_init(initialDelay, defaultAdmin);

        FlyoverConfigurationsBounds storage bounds = _getBounds();
        bounds.timelockDelay = timelockDelay;
        bounds.min = pegInMin;
        bounds.max = pegInMax;

        // The seed config must itself respect the bounds it will be measured against.
        _validateConfig(pegInConfig);
        _getStorage().activePegIn = pegInConfig;
    }

    /// @notice One-time seed of peg-out active config + immutable bounds (call after {initialize}).
    /// @dev Kept separate from {initialize} so the peg-in ABI and existing deploy/tests stay unchanged.
    // solhint-disable-next-line comprehensive-interface
    function initializePegOut(
        PegOutConfiguration calldata pegOutConfig,
        PegOutConfiguration calldata pegOutMin,
        PegOutConfiguration calldata pegOutMax
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        PegOutConfigurationsStorage storage pegOut = _getPegOutStorage();
        if (pegOut.initialized) revert PegOutAlreadyInitialized();

        pegOut.minBound = pegOutMin;
        pegOut.maxBound = pegOutMax;
        _validatePegOutConfig(pegOutConfig);
        pegOut.active = pegOutConfig;
        pegOut.initialized = true;
    }

    /// @inheritdoc IFlyoverConfigurations
    function queueChange(PegConfiguration calldata newConfiguration) external override onlyRole(DEFAULT_ADMIN_ROLE) {
        _validateConfig(newConfiguration);
        FlyoverConfigurationsStorage storage $ = _getStorage();
        uint256 eta = block.timestamp + _getBounds().timelockDelay;
        $.pending = newConfiguration;
        $.pendingEta = eta;
        emit ChangeQueued(newConfiguration, eta);
    }

    /// @inheritdoc IFlyoverConfigurations
    function applyChange() external override onlyRole(DEFAULT_ADMIN_ROLE) {
        FlyoverConfigurationsStorage storage $ = _getStorage();
        uint256 eta = $.pendingEta;
        if (eta == 0) revert NoQueuedChange();
        if (block.timestamp < eta) revert TimelockNotElapsed(eta, block.timestamp);

        PegConfiguration memory pending = $.pending;
        // Re-validate at apply time: bounds are immutable, but this closes the window where a
        // value queued as valid could be applied after any invariant assumption changed.
        _validateConfig(pending);

        // Storage-to-storage deep copy (the memory-to-storage form is not supported for the
        // nested ConfirmationTier[] array).
        $.activePegIn = $.pending;
        delete $.pending;
        $.pendingEta = 0;
        emit ChangeApplied(pending);
    }

    /// @inheritdoc IFlyoverConfigurations
    function queuePegOutChange(PegOutConfiguration calldata newConfiguration)
        external
        override
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        _requirePegOutInitialized();
        _validatePegOutConfig(newConfiguration);
        PegOutConfigurationsStorage storage pegOut = _getPegOutStorage();
        uint256 eta = block.timestamp + _getBounds().timelockDelay;
        pegOut.pending = newConfiguration;
        pegOut.pendingEta = eta;
        emit PegOutChangeQueued(newConfiguration, eta);
    }

    /// @inheritdoc IFlyoverConfigurations
    function applyPegOutChange() external override onlyRole(DEFAULT_ADMIN_ROLE) {
        _requirePegOutInitialized();
        PegOutConfigurationsStorage storage pegOut = _getPegOutStorage();
        uint256 eta = pegOut.pendingEta;
        if (eta == 0) revert NoQueuedChange();
        if (block.timestamp < eta) revert TimelockNotElapsed(eta, block.timestamp);

        PegOutConfiguration memory pending = pegOut.pending;
        _validatePegOutConfig(pending);

        pegOut.active = pegOut.pending;
        delete pegOut.pending;
        pegOut.pendingEta = 0;
        emit PegOutChangeApplied(pending);
    }

    /// @inheritdoc IFlyoverConfigurations
    function getPegInConfiguration() external view override returns (PegConfiguration memory configuration) {
        return _getStorage().activePegIn;
    }

    /// @inheritdoc IFlyoverConfigurations
    function calculatePegInFee(uint256 amount) external view override returns (uint256 fee) {
        return _calculateFee(_getStorage().activePegIn, amount);
    }

    /// @inheritdoc IFlyoverConfigurations
    function getRequiredPegInBtcConfirmations(uint256 amount)
        external
        view
        override
        returns (uint256 confirmations)
    {
        return _requiredConfirmations(_getStorage().activePegIn, amount);
    }

    /// @notice Returns the immutable deployment bounds every queued change is validated against.
    /// @return min The lower bound for every peg-in scalar field
    /// @return max The upper bound for every peg-in scalar field
    // solhint-disable-next-line comprehensive-interface
    function getPegInConfigurationBounds()
        external
        view
        returns (PegConfiguration memory min, PegConfiguration memory max)
    {
        FlyoverConfigurationsBounds storage bounds = _getBounds();
        return (bounds.min, bounds.max);
    }

    /// @notice Returns the queued configuration change and its activation time.
    /// @return pending The queued configuration (zeroed when nothing is queued)
    /// @return eta The earliest activation timestamp; `0` means no change is queued
    // solhint-disable-next-line comprehensive-interface
    function getPendingChange() external view returns (PegConfiguration memory pending, uint256 eta) {
        FlyoverConfigurationsStorage storage $ = _getStorage();
        return ($.pending, $.pendingEta);
    }

    /// @notice Returns the time-lock delay (seconds) applied to every queued change.
    // solhint-disable-next-line comprehensive-interface
    function getTimelockDelay() external view returns (uint256) {
        return _getBounds().timelockDelay;
    }

    /// @inheritdoc IFlyoverConfigurations
    function getPegOutConfiguration() external view override returns (PegOutConfiguration memory configuration) {
        _requirePegOutInitialized();
        return _getPegOutStorage().active;
    }

    /// @inheritdoc IFlyoverConfigurations
    function calculatePegOutFee(uint256 amount) external view override returns (uint256 fee) {
        _requirePegOutInitialized();
        return _calculatePegOutFee(_getPegOutStorage().active, amount);
    }

    /// @inheritdoc IFlyoverConfigurations
    function getRequiredPegOutBtcConfirmations(uint256 amount)
        external
        view
        override
        returns (uint256 confirmations)
    {
        _requirePegOutInitialized();
        return _requiredPegOutConfirmations(_getPegOutStorage().active, amount);
    }

    /// @notice Returns the immutable peg-out deployment bounds.
    // solhint-disable-next-line comprehensive-interface
    function getPegOutConfigurationBounds()
        external
        view
        returns (PegOutConfiguration memory min, PegOutConfiguration memory max)
    {
        _requirePegOutInitialized();
        PegOutConfigurationsStorage storage pegOut = _getPegOutStorage();
        return (pegOut.minBound, pegOut.maxBound);
    }

    /// @notice Returns the queued peg-out configuration change and its activation time.
    // solhint-disable-next-line comprehensive-interface
    function getPendingPegOutChange()
        external
        view
        returns (PegOutConfiguration memory pending, uint256 eta)
    {
        PegOutConfigurationsStorage storage pegOut = _getPegOutStorage();
        return (pegOut.pending, pegOut.pendingEta);
    }

    /// @dev fee = fixedFee + amount * percentageFee / 10_000, then rounded DOWN to a satoshi
    /// boundary (mirrors `Quotes.checkAgreedAmount`), so on-chain fees agree with the bridge.
    function _calculateFee(PegConfiguration storage config, uint256 amount) private view returns (uint256) {
        uint256 fee = config.fixedFee + (amount * config.percentageFee) / FEE_PERCENTAGE_DENOMINATOR;
        if (fee > SAT_TO_WEI_CONVERSION && (fee % SAT_TO_WEI_CONVERSION) != 0) {
            fee -= (fee % SAT_TO_WEI_CONVERSION);
        }
        return fee;
    }

    function _calculatePegOutFee(PegOutConfiguration storage config, uint256 amount)
        private
        view
        returns (uint256)
    {
        uint256 fee = config.fixedFee + (amount * config.percentageFee) / FEE_PERCENTAGE_DENOMINATOR;
        if (fee > SAT_TO_WEI_CONVERSION && (fee % SAT_TO_WEI_CONVERSION) != 0) {
            fee -= (fee % SAT_TO_WEI_CONVERSION);
        }
        return fee;
    }

    /// @dev Returns the confirmations of the first tier whose maxAmount covers the amount. If the
    /// amount exceeds every tier, returns the highest (last) tier's confirmations, the most
    /// conservative answer. Tiers are kept strictly ascending, so the first match is the tightest.
    function _requiredConfirmations(PegConfiguration storage config, uint256 amount)
        private
        view
        returns (uint256)
    {
        ConfirmationTier[] storage tiers = config.confirmationTiers;
        uint256 length = tiers.length;
        for (uint256 i = 0; i < length; ++i) {
            if (amount <= tiers[i].maxAmount) {
                return tiers[i].confirmations;
            }
        }
        return tiers[length - 1].confirmations;
    }

    function _requiredPegOutConfirmations(PegOutConfiguration storage config, uint256 amount)
        private
        view
        returns (uint256)
    {
        ConfirmationTier[] storage tiers = config.confirmationTiers;
        uint256 length = tiers.length;
        for (uint256 i = 0; i < length; ++i) {
            if (amount <= tiers[i].maxAmount) {
                return tiers[i].confirmations;
            }
        }
        return tiers[length - 1].confirmations;
    }

    /// @dev Validates a full config against the immutable bounds and the structural invariants:
    /// every scalar within [min, max], minAmount <= maxAmount, percentageFee <= 10_000, and the
    /// confirmation tiers non-empty and strictly ascending by maxAmount. The tier array itself is
    /// only ordering/non-emptiness checked; it is not min/max-bounded.
    function _validateConfig(PegConfiguration memory config) private view {
        FlyoverConfigurationsBounds storage bounds = _getBounds();
        PegConfiguration storage minConfigBoundary = bounds.min;
        PegConfiguration storage maxConfigBoundary = bounds.max;

        _checkBound(Field.FixedFee, config.fixedFee, minConfigBoundary.fixedFee, maxConfigBoundary.fixedFee);
        _checkBound(
            Field.PercentageFee,
            config.percentageFee,
            minConfigBoundary.percentageFee,
            maxConfigBoundary.percentageFee
        );
        _checkBound(Field.MinAmount, config.minAmount, minConfigBoundary.minAmount, maxConfigBoundary.minAmount);
        _checkBound(Field.MaxAmount, config.maxAmount, minConfigBoundary.maxAmount, maxConfigBoundary.maxAmount);

        if (config.percentageFee > FEE_PERCENTAGE_DENOMINATOR) {
            revert InvalidPercentageFee(config.percentageFee);
        }
        if (config.minAmount > config.maxAmount) {
            revert InvalidAmountLimits(config.minAmount, config.maxAmount);
        }
        _validateTiers(config.confirmationTiers);
    }

    function _checkBound(Field field, uint256 value, uint256 minV, uint256 maxV) private pure {
        if (value < minV || value > maxV) {
            revert ConfigValueOutOfBounds(field, value, minV, maxV);
        }
    }

    function _validateTiers(ConfirmationTier[] memory tiers) private pure {
        uint256 length = tiers.length;
        if (length == 0) revert EmptyTiers();
        for (uint256 i = 1; i < length; ++i) {
            if (tiers[i].maxAmount <= tiers[i - 1].maxAmount) revert TiersNotAscending();
        }
    }

    function _validatePegOutConfig(PegOutConfiguration memory config) private view {
        PegOutConfigurationsStorage storage pegOut = _getPegOutStorage();
        PegOutConfiguration storage minB = pegOut.minBound;
        PegOutConfiguration storage maxB = pegOut.maxBound;

        _checkBound(Field.FixedFee, config.fixedFee, minB.fixedFee, maxB.fixedFee);
        _checkBound(Field.PercentageFee, config.percentageFee, minB.percentageFee, maxB.percentageFee);
        _checkBound(Field.MinAmount, config.minAmount, minB.minAmount, maxB.minAmount);
        _checkBound(Field.MaxAmount, config.maxAmount, minB.maxAmount, maxB.maxAmount);
        _checkBound(Field.PenaltyFee, config.penaltyFee, minB.penaltyFee, maxB.penaltyFee);
        _checkBound(Field.ClaimWindow, config.claimWindow, minB.claimWindow, maxB.claimWindow);
        _checkBound(
            Field.ClaimWindowBlocks, config.claimWindowBlocks, minB.claimWindowBlocks, maxB.claimWindowBlocks
        );
        _checkBound(Field.CallTime, config.callTime, minB.callTime, maxB.callTime);
        _checkBound(Field.ExpireTime, config.expireTime, minB.expireTime, maxB.expireTime);
        _checkBound(Field.ExpireBlocks, config.expireBlocks, minB.expireBlocks, maxB.expireBlocks);
        _checkBound(Field.MaxMinerFee, config.maxMinerFee, minB.maxMinerFee, maxB.maxMinerFee);
        _checkBound(Field.GasFee, config.gasFee, minB.gasFee, maxB.gasFee);
        _checkBound(
            Field.DepositConfirmations,
            config.depositConfirmations,
            minB.depositConfirmations,
            maxB.depositConfirmations
        );

        if (config.percentageFee > FEE_PERCENTAGE_DENOMINATOR) {
            revert InvalidPercentageFee(config.percentageFee);
        }
        if (config.minAmount > config.maxAmount) {
            revert InvalidAmountLimits(config.minAmount, config.maxAmount);
        }
        if (config.claimWindow == 0 || config.callTime == 0 || config.expireTime == 0) {
            revert InvalidPegOutDeadlines();
        }
        _validateTiers(config.confirmationTiers);
    }

    function _requirePegOutInitialized() private view {
        if (!_getPegOutStorage().initialized) revert PegOutNotInitialized();
    }

    function _getStorage() private pure returns (FlyoverConfigurationsStorage storage $) {
        assembly {
            $.slot := _FLYOVER_CONFIGURATIONS_STORAGE
        }
    }

    function _getBounds() private pure returns (FlyoverConfigurationsBounds storage $) {
        assembly {
            $.slot := _FLYOVER_CONFIGURATIONS_BOUNDS
        }
    }

    function _getPegOutStorage() private pure returns (PegOutConfigurationsStorage storage $) {
        assembly {
            $.slot := _FLYOVER_CONFIGURATIONS_PEGOUT
        }
    }
}
