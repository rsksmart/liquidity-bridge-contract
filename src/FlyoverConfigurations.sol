// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {
    AccessControlDefaultAdminRulesUpgradeable
} from "@openzeppelin/contracts-upgradeable/access/extensions/AccessControlDefaultAdminRulesUpgradeable.sol";
import {IFlyoverConfigurations} from "./interfaces/IFlyoverConfigurations.sol";
import {Flyover} from "./libraries/Flyover.sol";

/// @title FlyoverConfigurations
/// @notice The single on-chain source of the commit-first peg-in parameters (fee, confirmation
/// tiers, amount limits) that every party reads: the SDK for its estimate, every LPS for its
/// serve decision, and the settlement path for its amount validation. Admin changes are
/// time-locked in two steps (queue then apply) and re-validated at both steps against the active
/// bounds, so an admin mistake cannot set absurd values even with the role. The bounds themselves
/// are seeded at deployment and are editable by the admin only through the same two-step time
/// lock ({queueBoundsChange} / {applyBoundsChange}), so widening or tightening them is observable
/// for a full delay before it can take effect and never needs a contract upgrade.
/// @dev Implements the frozen {IFlyoverConfigurations}. Peg-out uses a separate ERC-7201 namespace.
/// Upgradeable, ERC-7201 namespaced storage, deployed behind a TransparentUpgradeableProxy per
/// repo pattern.
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
        RegistrantFee,
        PenaltyFee,
        ClaimWindow,
        ClaimWindowBlocks,
        CallTime,
        ExpireTime,
        ExpireBlocks,
        MaxMinerFee
    }

    /// @custom:storage-location erc7201:rsk.flyover.FlyoverConfigurations
    struct FlyoverConfigurationsStorage {
        PegConfiguration activePegIn;
        PegConfiguration pending;
        uint256 pendingEta;
    }

    /// @custom:storage-location erc7201:rsk.flyover.FlyoverConfigurations.bounds
    /// @dev Held in a separate namespace from the mutable config: a bounds change and a
    /// configuration change are independent pending slots, so queueing one never clobbers the
    /// other. `min`/`max` are seeded in `initialize` and thereafter only ever written by
    /// `applyBoundsChange`, which the same time lock as a configuration change guards.
    /// `timelockDelay` is not editable; it is the review window itself.
    struct FlyoverConfigurationsBounds {
        uint256 timelockDelay;
        PegConfiguration min;
        PegConfiguration max;
        PegConfiguration pendingMin;
        PegConfiguration pendingMax;
        uint256 pendingEta;
    }

    /// @custom:storage-location erc7201:rsk.flyover.FlyoverConfigurations.pegOut
    /// @dev Separate namespace so peg-out never shifts peg-in storage.
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

    /// @notice Rejects registrantFee values at or above this cap (0.001 ether).
    uint256 public constant MAX_REGISTRANT_FEE_EXCLUSIVE = 0.001 ether;

    /// @notice LP claim-gas headroom required between fixedFee and registrantFee at queue/apply.
    uint256 private constant _REGISTRANT_FEE_LP_GAS_CUSHION = 0;

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

    /// @notice Emitted when a bounds change is queued by the admin.
    /// @param newMin The lower bounds that will take effect once the time lock elapses
    /// @param newMax The upper bounds that will take effect once the time lock elapses
    /// @param eta The earliest timestamp `applyBoundsChange` may activate the queued bounds
    event BoundsChangeQueued(PegConfiguration newMin, PegConfiguration newMax, uint256 eta);

    /// @notice Emitted when a queued bounds change is applied and becomes active.
    /// @param newMin The now-active lower bounds
    /// @param newMax The now-active upper bounds
    event BoundsChangeApplied(PegConfiguration newMin, PegConfiguration newMax);

    event PegOutChangeQueued(PegOutConfiguration newConfiguration, uint256 eta);
    event PegOutChangeApplied(PegOutConfiguration newConfiguration);

    /// @notice Raised when a scalar field falls outside its active bound.
    error ConfigValueOutOfBounds(Field field, uint256 value, uint256 min, uint256 max);
    /// @notice Raised when a bounds pair inverts a field, i.e. its min exceeds its max.
    error InvalidBounds(Field field, uint256 min, uint256 max);
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
    /// @notice Raised when applying while no bounds change is queued.
    error NoQueuedBoundsChange();
    /// @notice Raised when applying bounds that would leave the active configuration outside them.
    error ActiveConfigOutsideNewBounds(Field field, uint256 value, uint256 min, uint256 max);
    error PegOutAlreadyInitialized();
    error PegOutNotInitialized();
    error InvalidPegOutDeadlines();
    /// @notice Raised when registrantFee is at or above {MAX_REGISTRANT_FEE_EXCLUSIVE}.
    error RegistrantFeeTooHigh(uint256 registrantFee, uint256 maxExclusive);
    /// @notice Raised when fixedFee cannot cover registrantFee plus the LP gas cushion.
    error InsufficientFixedFeeForRegistrant(uint256 fixedFee, uint256 registrantFee, uint256 cushion);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @notice This contract does not accept value
    // solhint-disable-next-line comprehensive-interface
    receive() external payable {
        revert Flyover.PaymentNotAllowed();
    }

    /// @notice Initializes the contract with the seed peg-in configuration and the seed bounds.
    /// @dev Writes the time-lock delay and the seed bounds, then validates and stores the seed
    /// config against those bounds. The bounds are checked for well-formedness here for the same
    /// reason `queueBoundsChange` checks them: no code path may install an inverted pair. Must be
    /// called only once (proxy initializer).
    /// @param defaultAdmin The default admin and initial owner address
    /// @param initialDelay The initial admin delay for `AccessControlDefaultAdminRules`
    /// @param timelockDelay The delay (seconds) every queued change must wait, configuration and
    /// bounds alike
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

        _validateBoundsPair(pegInMin, pegInMax);

        FlyoverConfigurationsBounds storage bounds = _getBounds();
        bounds.timelockDelay = timelockDelay;
        bounds.min = pegInMin;
        bounds.max = pegInMax;

        // The seed config must itself respect the bounds it will be measured against.
        _validateConfig(pegInConfig);
        _getStorage().activePegIn = pegInConfig;
    }

    /// @notice One-time peg-out seed; call after {initialize}.
    /// @dev TODO: consider folding peg-out seed/bounds into {initialize} on a greenfield deploy.
    /// Kept separate so the existing peg-in initializer ABI, deploy calldata, and tests stay
    /// unchanged, and so an already-initialized proxy can seed the peg-out ERC-7201 namespace
    /// without re-running `initialize`.
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
        // Re-validate at apply time: the bounds may themselves have moved during the delay, so a
        // value that was in range when queued is not guaranteed to be in range when it lands.
        _validateConfig(pending);

        // Storage-to-storage deep copy (the memory-to-storage form is not supported for the
        // nested ConfirmationTier[] array).
        $.activePegIn = $.pending;
        delete $.pending;
        $.pendingEta = 0;
        emit ChangeApplied(pending);
    }

    /// @notice Queues a change to the configuration bounds, the first step of the time-locked
    /// admin change. Admin-only.
    /// @dev Deliberately no plain setter. A bound and a configuration value that could move in a
    /// single transaction would make the bounds useless: catching an admin mistake is their only
    /// job, and they cannot catch a mistake the same actor is free to redefine on the spot. The
    /// delay is the review window, so a queued widening is observable before it can take effect.
    ///
    /// Only well-formedness (`min <= max` per field) is checked here. Whether the *active*
    /// configuration still fits the new bounds is deliberately checked at apply time only: the
    /// active configuration may legitimately change during the delay, so a queue-time verdict
    /// would be advisory at best and would block the legitimate sequence of queueing a
    /// tightening now and moving the active configuration into the new range during the wait.
    ///
    /// Follows the single-pending-change pattern: queueing again overwrites the pending bounds
    /// and refreshes the eta. Independent of the configuration slot used by {queueChange}.
    ///
    /// The `confirmationTiers` field of a bounds pair is ignored, as it is at initialization: the
    /// tier array is validated structurally (non-empty, strictly ascending), never min/max
    /// bounded, so there is nothing for a bound to constrain.
    /// @param newMin Lower bound for every peg-in scalar field
    /// @param newMax Upper bound for every peg-in scalar field
    // solhint-disable-next-line comprehensive-interface
    function queueBoundsChange(PegConfiguration calldata newMin, PegConfiguration calldata newMax)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        _validateBoundsPair(newMin, newMax);

        FlyoverConfigurationsBounds storage bounds = _getBounds();
        uint256 eta = block.timestamp + bounds.timelockDelay;
        bounds.pendingMin = newMin;
        bounds.pendingMax = newMax;
        bounds.pendingEta = eta;
        emit BoundsChangeQueued(newMin, newMax, eta);
    }

    /// @notice Activates the queued bounds change, the second step of the time-locked admin
    /// change. Admin-only.
    /// @dev Reverts before the delay has elapsed, and reverts when nothing is queued.
    ///
    /// Bounds that the active configuration does not satisfy are rejected rather than accepted
    /// as forward-only constraints. The alternative would leave `getPegInConfiguration` returning
    /// values `getPegInConfigurationBounds` declares illegal, and no reader could tell whether
    /// the pair it just read was consistent. Rejecting keeps one invariant that holds at every
    /// block and needs no qualification: the active configuration is always within the active
    /// bounds. The admin's remedy for a tightening that excludes the active configuration is to
    /// move the configuration into the new range first (itself time-locked, and runnable during
    /// this change's delay), then apply the bounds. Widening — the case this feature exists for —
    /// is never blocked by this rule.
    // solhint-disable-next-line comprehensive-interface
    function applyBoundsChange() external onlyRole(DEFAULT_ADMIN_ROLE) {
        FlyoverConfigurationsBounds storage bounds = _getBounds();
        uint256 eta = bounds.pendingEta;
        if (eta == 0) revert NoQueuedBoundsChange();
        if (block.timestamp < eta) revert TimelockNotElapsed(eta, block.timestamp);

        // Re-validate at apply time for the same reason applyChange does: the queued pair must
        // still be well-formed when it lands, not only when it was queued.
        _validateBoundsPair(bounds.pendingMin, bounds.pendingMax);
        _checkActiveConfigFits(bounds.pendingMin, bounds.pendingMax);

        // Storage-to-storage deep copies (the memory-to-storage form is not supported for the
        // nested ConfirmationTier[] array).
        bounds.min = bounds.pendingMin;
        bounds.max = bounds.pendingMax;
        PegConfiguration memory newMin = bounds.min;
        PegConfiguration memory newMax = bounds.max;
        delete bounds.pendingMin;
        delete bounds.pendingMax;
        bounds.pendingEta = 0;
        emit BoundsChangeApplied(newMin, newMax);
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

    // TODO(nit): drop unused named returns on all view getters below (`configuration`, `fee`,
    // `confirmations`, `min`/`max`, `pending`/`eta`) — peg-in and peg-out. Names mirror NatSpec
    // but are unused when the body uses an explicit `return`.
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

    /// @notice Returns the active bounds every queued configuration change is validated against.
    /// @dev Seeded at deployment; changed only through {queueBoundsChange} / {applyBoundsChange}.
    /// The active configuration is always within the pair returned here.
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

    /// @notice Returns the queued bounds change and its activation time.
    /// @return min The queued lower bounds (zeroed when nothing is queued)
    /// @return max The queued upper bounds (zeroed when nothing is queued)
    /// @return eta The earliest activation timestamp; `0` means no bounds change is queued
    // solhint-disable-next-line comprehensive-interface
    function getPendingBoundsChange()
        external
        view
        returns (PegConfiguration memory min, PegConfiguration memory max, uint256 eta)
    {
        FlyoverConfigurationsBounds storage bounds = _getBounds();
        return (bounds.pendingMin, bounds.pendingMax, bounds.pendingEta);
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

    /// @notice Immutable peg-out deployment bounds.
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

    /// @notice Queued peg-out change and eta (`0` if none).
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
    /// boundary (mirrors `Quotes.checkAgreedAmount`), so on-chain fees agree with the bridge. The
    /// scale is read from {Flyover}, which declares it once; `Quotes.SAT_TO_WEI_CONVERSION` is the
    /// legacy quote path's own copy, left alone because that path's ABI is frozen, and
    /// `test/configurations/Fee.t.sol` asserts the two agree so they cannot drift.
    /// `PegOutContract` holds a third, private copy.
    function _calculateFee(PegConfiguration storage config, uint256 amount) private view returns (uint256) {
        uint256 fee = config.fixedFee + (amount * config.percentageFee) / FEE_PERCENTAGE_DENOMINATOR;
        if (fee > Flyover.SAT_TO_WEI_CONVERSION && (fee % Flyover.SAT_TO_WEI_CONVERSION) != 0) {
            fee -= (fee % Flyover.SAT_TO_WEI_CONVERSION);
        }
        return fee;
    }

    function _calculatePegOutFee(PegOutConfiguration storage config, uint256 amount)
        private
        view
        returns (uint256)
    {
        uint256 fee = config.fixedFee + (amount * config.percentageFee) / FEE_PERCENTAGE_DENOMINATOR;
        if (fee > Flyover.SAT_TO_WEI_CONVERSION && (fee % Flyover.SAT_TO_WEI_CONVERSION) != 0) {
            fee -= (fee % Flyover.SAT_TO_WEI_CONVERSION);
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

    /// @dev Validates a full config against the active bounds and the structural invariants:
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
        _checkBound(
            Field.RegistrantFee,
            config.registrantFee,
            minConfigBoundary.registrantFee,
            maxConfigBoundary.registrantFee
        );

        if (config.registrantFee >= MAX_REGISTRANT_FEE_EXCLUSIVE) {
            revert RegistrantFeeTooHigh(config.registrantFee, MAX_REGISTRANT_FEE_EXCLUSIVE);
        }
        if (config.fixedFee < config.registrantFee + _REGISTRANT_FEE_LP_GAS_CUSHION) {
            revert InsufficientFixedFeeForRegistrant(
                config.fixedFee, config.registrantFee, _REGISTRANT_FEE_LP_GAS_CUSHION
            );
        }

        if (config.percentageFee > FEE_PERCENTAGE_DENOMINATOR) {
            revert InvalidPercentageFee(config.percentageFee);
        }
        if (config.minAmount > config.maxAmount) {
            revert InvalidAmountLimits(config.minAmount, config.maxAmount);
        }
        _validateTiers(config.confirmationTiers);
    }

    /// @dev Enforces the invariant that makes the bounds readable at all: the active
    /// configuration lies within the active bounds. Called before a bounds change lands, so a
    /// pair that would strand the live configuration outside it is rejected instead of applied.
    /// See {applyBoundsChange} for why rejecting beats accepting it as a forward-only constraint.
    function _checkActiveConfigFits(PegConfiguration memory min, PegConfiguration memory max)
        private
        view
    {
        PegConfiguration storage active = _getStorage().activePegIn;
        _checkActiveField(Field.FixedFee, active.fixedFee, min.fixedFee, max.fixedFee);
        _checkActiveField(
            Field.PercentageFee,
            active.percentageFee,
            min.percentageFee,
            max.percentageFee
        );
        _checkActiveField(Field.MinAmount, active.minAmount, min.minAmount, max.minAmount);
        _checkActiveField(Field.MaxAmount, active.maxAmount, min.maxAmount, max.maxAmount);
        _checkActiveField(Field.RegistrantFee, active.registrantFee, min.registrantFee, max.registrantFee);
    }

    function _checkBound(Field field, uint256 value, uint256 minV, uint256 maxV) private pure {
        if (value < minV || value > maxV) {
            revert ConfigValueOutOfBounds(field, value, minV, maxV);
        }
    }

    /// @dev A bounds pair is well-formed when no field inverts, i.e. `min <= max` on all five
    /// scalars. An inverted field admits no value at all, which would wedge every future
    /// configuration change. `confirmationTiers` carries no bound and is not inspected.
    function _validateBoundsPair(PegConfiguration memory min, PegConfiguration memory max)
        private
        pure
    {
        _checkPairOrdered(Field.FixedFee, min.fixedFee, max.fixedFee);
        _checkPairOrdered(Field.PercentageFee, min.percentageFee, max.percentageFee);
        _checkPairOrdered(Field.MinAmount, min.minAmount, max.minAmount);
        _checkPairOrdered(Field.MaxAmount, min.maxAmount, max.maxAmount);
        _checkPairOrdered(Field.RegistrantFee, min.registrantFee, max.registrantFee);
    }

    function _checkPairOrdered(Field field, uint256 minV, uint256 maxV) private pure {
        if (minV > maxV) revert InvalidBounds(field, minV, maxV);
    }

    function _checkActiveField(Field field, uint256 value, uint256 minV, uint256 maxV)
        private
        pure
    {
        if (value < minV || value > maxV) {
            revert ActiveConfigOutsideNewBounds(field, value, minV, maxV);
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
