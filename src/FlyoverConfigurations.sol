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
/// time-locked in two steps (queue then apply) and re-validated at both steps against immutable
/// bounds fixed at deployment, so an admin mistake cannot set absurd values even with the role.
/// @dev Implements the frozen {IFlyoverConfigurations} (peg-in only); its function signatures and
/// structs are the shared ABI every consumer depends on, so they must not be changed here.
/// Upgradeable, ERC-7201 namespaced storage, deployed behind a TransparentUpgradeableProxy per
/// repo pattern.
/// @author Rootstock Labs
contract FlyoverConfigurations is
    AccessControlDefaultAdminRulesUpgradeable,
    IFlyoverConfigurations
{
    /// @notice Identifies the scalar field an out-of-bounds revert refers to.
    enum Field { FixedFee, PercentageFee, MinAmount, MaxAmount }

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

    /// @notice The version of the contract
    string public constant VERSION = "1.0.0";

    /// @notice Percentage fee denominator: 10_000 == 100%.
    uint256 public constant FEE_PERCENTAGE_DENOMINATOR = 10_000;

    // ERC-7201: keccak256(abi.encode(uint256(keccak256("rsk.flyover.FlyoverConfigurations")) - 1)) &
    // ~bytes32(uint256(0xff))
    bytes32 private constant _FLYOVER_CONFIGURATIONS_STORAGE =
        0x13aa2a37a5354fe7c5dcced2a6c33933ec66091f98f22792660cd2862f158700;

    // ERC-7201: keccak256(abi.encode(uint256(keccak256("rsk.flyover.FlyoverConfigurations.bounds")) - 1)) &
    // ~bytes32(uint256(0xff))
    bytes32 private constant _FLYOVER_CONFIGURATIONS_BOUNDS =
        0x62f8e0a1022a246e45081dab13f708870be3f38423627ed9d784f6bc5369e500;

    /// @notice Emitted when a configuration change is queued by the admin.
    /// @param newConfiguration The configuration that will activate once the time lock elapses
    /// @param eta The earliest timestamp `applyChange` may activate the queued configuration
    event ChangeQueued(PegConfiguration newConfiguration, uint256 eta);

    /// @notice Emitted when a queued configuration change is applied and becomes active.
    /// @param newConfiguration The now-active configuration
    event ChangeApplied(PegConfiguration newConfiguration);

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
}
