// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {
    AccessControlDefaultAdminRulesUpgradeable
} from "@openzeppelin/contracts-upgradeable/access/extensions/AccessControlDefaultAdminRulesUpgradeable.sol";
import {IFlyoverConfigurations} from "./interfaces/IFlyoverConfigurations.sol";
import {Flyover} from "./libraries/Flyover.sol";

/// @title FlyoverConfigurations
/// @notice Upgradeable contract holding both peg-in and peg-out configuration (fees, confirmation
/// tiers, deadlines and limits). Every scalar setter is time-locked: a change is queued by the
/// admin and only applied after a fixed delay, and is validated against immutable deployment-time
/// bounds both when queued and when applied. The confirmation-tier list has its own queue.
/// @dev SAT/WEI rounding in `calculatePegInFee`/`calculatePegOutFee` mirrors
/// `Quotes.checkAgreedAmount`: the fee is rounded down to the nearest satoshi so peg-in and
/// peg-out agree with the bridge.
/// @author Rootstock Labs
contract FlyoverConfigurations is
    AccessControlDefaultAdminRulesUpgradeable,
    IFlyoverConfigurations
{
    /// @notice The version of the contract
    string public constant VERSION = "1.0.0";

    /// @notice Percentage fee denominator: 10_000 == 100%.
    uint256 public constant FEE_PERCENTAGE_DENOMINATOR = 10_000;

    /// @notice 1 satoshi expressed in wei; fees are rounded down to a satoshi boundary.
    uint256 public constant SAT_TO_WEI_CONVERSION = 10 ** 10;

    /// @notice Identifies the flow a queued change targets.
    enum Flow { PegIn, PegOut }

    /// @notice Identifies the scalar field a queued change targets.
    enum Field {
        FixedFee,
        PercentageFee,
        PenaltyFee,
        CallTime,
        ExpireTime,
        ExpireBlocks,
        DeliveryGrace,
        MinAmount,
        MaxAmount
    }

    /// @notice A queued scalar change. `eta == 0` means no change is queued.
    struct PendingChange {
        uint256 value;
        uint256 eta;
    }

    /// @notice A queued confirmation-tier change. `eta == 0` means no change is queued.
    struct PendingTiers {
        ConfirmationTier[] tiers;
        uint256 eta;
    }

    /// @custom:storage-location erc7201:rsk.flyover.FlyoverConfigurations
    struct FlyoverConfigurationsStorage {
        PegConfiguration pegIn;
        PegConfiguration pegOut;
        // Queued scalar changes, keyed by flow then field.
        mapping(Flow => mapping(Field => PendingChange)) pendingScalar;
        // Queued confirmation-tier changes, keyed by flow.
        mapping(Flow => PendingTiers) pendingTiers;
    }

    /// @custom:storage-location erc7201:rsk.flyover.FlyoverConfigurations.immutables
    /// @dev Held in a separate namespace from the mutable config. Written once in `initialize`.
    struct FlyoverConfigurationsBounds {
        uint256 timelockDelay;
        PegConfiguration pegInMin;
        PegConfiguration pegInMax;
        PegConfiguration pegOutMin;
        PegConfiguration pegOutMax;
    }

    // ERC-7201: keccak256(abi.encode(uint256(keccak256("rsk.flyover.FlyoverConfigurations")) - 1)) &
    // ~bytes32(uint256(0xff))
    bytes32 private constant _FLYOVER_CONFIGURATIONS_STORAGE =
        0x13aa2a37a5354fe7c5dcced2a6c33933ec66091f98f22792660cd2862f158700;

    // ERC-7201: keccak256(abi.encode(uint256(keccak256("rsk.flyover.FlyoverConfigurations.immutables")) - 1)) &
    // ~bytes32(uint256(0xff))
    bytes32 private constant _FLYOVER_CONFIGURATIONS_BOUNDS =
        0x24a0b1aa6ada62b386d00addebc5c6489a9bb8248239ea1e105451a8f65b6800;

    /// @notice Raised when a value falls outside its immutable deployment bound.
    error OutOfBounds(Flow flow, Field field, uint256 value, uint256 min, uint256 max);
    /// @notice Raised when applying a change before its time lock elapses, or when no change is queued.
    error TimelockNotElapsed(uint256 eta, uint256 nowTime);
    /// @notice Raised when no change is queued for the targeted slot.
    error NoQueuedChange(Flow flow);
    /// @notice Raised when a confirmation-tier list is not sorted strictly ascending by maxAmount.
    error TiersNotAscending();
    /// @notice Raised when a confirmation-tier list is empty.
    error EmptyTiers();
    /// @notice Raised when expireTime would not be strictly later than callTime.
    error ExpireTimeNotAfterCallTime(uint256 callTime, uint256 expireTime);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @notice This contract does not accept value
    // solhint-disable-next-line comprehensive-interface
    receive() external payable {
        revert Flyover.PaymentNotAllowed();
    }

    /// @notice Initializes the contract with seed configuration and the immutable bounds.
    /// @param defaultAdmin The default admin of the contract
    /// @param initialDelay The initial delay for changes in the default admin role
    /// @param timelockDelay The delay (seconds) every queued configuration change must wait
    /// @param pegInConfig The initial peg-in configuration
    /// @param pegOutConfig The initial peg-out configuration
    /// @param pegInMin Lower bound for every peg-in scalar field
    /// @param pegInMax Upper bound for every peg-in scalar field
    /// @param pegOutMin Lower bound for every peg-out scalar field
    /// @param pegOutMax Upper bound for every peg-out scalar field
    // solhint-disable-next-line comprehensive-interface
    function initialize(
        address defaultAdmin,
        uint48 initialDelay,
        uint256 timelockDelay,
        PegConfiguration calldata pegInConfig,
        PegConfiguration calldata pegOutConfig,
        PegConfiguration calldata pegInMin,
        PegConfiguration calldata pegInMax,
        PegConfiguration calldata pegOutMin,
        PegConfiguration calldata pegOutMax
    ) external initializer {
        __AccessControlDefaultAdminRules_init(initialDelay, defaultAdmin);

        FlyoverConfigurationsBounds storage b = _getBounds();
        b.timelockDelay = timelockDelay;
        _copyBounds(b.pegInMin, pegInMin);
        _copyBounds(b.pegInMax, pegInMax);
        _copyBounds(b.pegOutMin, pegOutMin);
        _copyBounds(b.pegOutMax, pegOutMax);

        // Seed config must itself respect bounds and the callTime/expireTime invariant.
        _validateWholeConfig(Flow.PegIn, pegInConfig);
        _validateWholeConfig(Flow.PegOut, pegOutConfig);

        FlyoverConfigurationsStorage storage $ = _getStorage();
        _copyConfig($.pegIn, pegInConfig);
        _copyConfig($.pegOut, pegOutConfig);
    }

    // ============================ Time-locked scalar setters ============================

    /// @notice Queues a change to a scalar field. Validates against immutable bounds at queue time.
    /// @param flow The flow (peg-in or peg-out) to change
    /// @param field The scalar field to change
    /// @param value The new value
    // solhint-disable-next-line comprehensive-interface
    function queueChange(Flow flow, Field field, uint256 value) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _checkBound(flow, field, value);
        FlyoverConfigurationsStorage storage $ = _getStorage();
        uint256 eta = block.timestamp + _getBounds().timelockDelay;
        $.pendingScalar[flow][field] = PendingChange({value: value, eta: eta});
    }

    /// @notice Applies a previously queued scalar change once its time lock has elapsed.
    /// Re-validates against bounds and the callTime/expireTime invariant, then emits the
    /// matching `*Changed` event with old and new values.
    /// @param flow The flow to apply the change to
    /// @param field The scalar field to apply
    // solhint-disable-next-line comprehensive-interface
    function applyChange(Flow flow, Field field) external onlyRole(DEFAULT_ADMIN_ROLE) {
        FlyoverConfigurationsStorage storage $ = _getStorage();
        PendingChange memory pending = $.pendingScalar[flow][field];
        if (pending.eta == 0) revert NoQueuedChange(flow);
        if (block.timestamp < pending.eta) revert TimelockNotElapsed(pending.eta, block.timestamp);

        _checkBound(flow, field, pending.value);

        PegConfiguration storage config = flow == Flow.PegIn ? $.pegIn : $.pegOut;
        uint256 oldValue = _readField(config, field);
        _checkDeadlineInvariant(config, field, pending.value);
        _writeField(config, field, pending.value);

        delete $.pendingScalar[flow][field];
        _emitChange(flow, field, oldValue, pending.value);
    }

    // ============================ Time-locked tier setter ============================

    /// @notice Queues a change to the confirmation-tier list. Validates ascending order at queue time.
    /// @param flow The flow whose tiers to change
    /// @param tiers The new tier list (sorted strictly ascending by maxAmount)
    // solhint-disable-next-line comprehensive-interface
    function queueTiersChange(Flow flow, ConfirmationTier[] calldata tiers)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        _validateTiers(tiers);
        FlyoverConfigurationsStorage storage $ = _getStorage();
        PendingTiers storage p = $.pendingTiers[flow];
        delete p.tiers;
        for (uint256 i = 0; i < tiers.length; ++i) {
            p.tiers.push(tiers[i]);
        }
        p.eta = block.timestamp + _getBounds().timelockDelay;
    }

    /// @notice Applies a queued confirmation-tier change once its time lock has elapsed.
    /// @param flow The flow whose tiers to apply
    // solhint-disable-next-line comprehensive-interface
    function applyTiersChange(Flow flow) external onlyRole(DEFAULT_ADMIN_ROLE) {
        FlyoverConfigurationsStorage storage $ = _getStorage();
        PendingTiers storage p = $.pendingTiers[flow];
        if (p.eta == 0) revert NoQueuedChange(flow);
        if (block.timestamp < p.eta) revert TimelockNotElapsed(p.eta, block.timestamp);

        // Re-validate at apply time as well.
        _validateTiersStorage(p.tiers);

        PegConfiguration storage config = flow == Flow.PegIn ? $.pegIn : $.pegOut;
        ConfirmationTier[] memory oldTiers = config.confirmationTiers;
        delete config.confirmationTiers;
        for (uint256 i = 0; i < p.tiers.length; ++i) {
            config.confirmationTiers.push(p.tiers[i]);
        }
        ConfirmationTier[] memory newTiers = config.confirmationTiers;

        delete $.pendingTiers[flow];
        if (flow == Flow.PegIn) {
            emit PegInConfirmationTiersChanged(oldTiers, newTiers);
        } else {
            emit PegOutConfirmationTiersChanged(oldTiers, newTiers);
        }
    }

    // ============================ Aggregate getters ============================

    /// @inheritdoc IFlyoverConfigurations
    function getPegInConfiguration() external view override returns (PegConfiguration memory) {
        return _getStorage().pegIn;
    }

    /// @inheritdoc IFlyoverConfigurations
    function getPegOutConfiguration() external view override returns (PegConfiguration memory) {
        return _getStorage().pegOut;
    }

    /// @inheritdoc IFlyoverConfigurations
    function getRequiredPegInConfirmations(uint256 amount) external view override returns (uint256) {
        return _requiredConfirmations(_getStorage().pegIn, amount);
    }

    /// @inheritdoc IFlyoverConfigurations
    function getRequiredPegOutConfirmations(uint256 amount) external view override returns (uint256) {
        return _requiredConfirmations(_getStorage().pegOut, amount);
    }

    /// @inheritdoc IFlyoverConfigurations
    function calculatePegInFee(uint256 amount) external view override returns (uint256) {
        return _calculateFee(_getStorage().pegIn, amount);
    }

    /// @inheritdoc IFlyoverConfigurations
    function calculatePegOutFee(uint256 amount) external view override returns (uint256) {
        return _calculateFee(_getStorage().pegOut, amount);
    }

    /// @inheritdoc IFlyoverConfigurations
    function getPegInConfigurationBounds()
        external
        view
        override
        returns (PegConfiguration memory min, PegConfiguration memory max)
    {
        FlyoverConfigurationsBounds storage b = _getBounds();
        return (b.pegInMin, b.pegInMax);
    }

    /// @inheritdoc IFlyoverConfigurations
    function getPegOutConfigurationBounds()
        external
        view
        override
        returns (PegConfiguration memory min, PegConfiguration memory max)
    {
        FlyoverConfigurationsBounds storage b = _getBounds();
        return (b.pegOutMin, b.pegOutMax);
    }

    /// @notice Returns the time-lock delay (seconds) applied to every queued change.
    function getTimelockDelay() external view returns (uint256) {
        return _getBounds().timelockDelay;
    }

    /// @notice Returns the queued scalar change for a slot (value, eta); eta == 0 means none queued.
    function getPendingChange(Flow flow, Field field) external view returns (uint256 value, uint256 eta) {
        PendingChange memory p = _getStorage().pendingScalar[flow][field];
        return (p.value, p.eta);
    }

    // ============================ Internal: fee / tiers ============================

    /// @dev fee = fixedFee + amount * percentageFee / 10_000, then rounded DOWN to a satoshi
    /// boundary (mirrors Quotes.checkAgreedAmount), so on-chain fees agree with the bridge.
    function _calculateFee(PegConfiguration storage config, uint256 amount)
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

    /// @dev Returns the confirmations for the first tier whose maxAmount >= amount. If the amount
    /// exceeds every tier's maxAmount, returns the highest (last) tier's confirmations.
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

    function _validateTiers(ConfirmationTier[] calldata tiers) private pure {
        if (tiers.length == 0) revert EmptyTiers();
        for (uint256 i = 1; i < tiers.length; ++i) {
            if (tiers[i].maxAmount <= tiers[i - 1].maxAmount) revert TiersNotAscending();
        }
    }

    function _validateTiersStorage(ConfirmationTier[] storage tiers) private view {
        if (tiers.length == 0) revert EmptyTiers();
        for (uint256 i = 1; i < tiers.length; ++i) {
            if (tiers[i].maxAmount <= tiers[i - 1].maxAmount) revert TiersNotAscending();
        }
    }

    // ============================ Internal: bounds / validation ============================

    /// @dev Validates every scalar field of a full config plus the callTime/expireTime invariant
    /// and the tier ordering. Used for the seed config at initialize time.
    function _validateWholeConfig(Flow flow, PegConfiguration calldata config) private view {
        _checkBound(flow, Field.FixedFee, config.fixedFee);
        _checkBound(flow, Field.PercentageFee, config.percentageFee);
        _checkBound(flow, Field.PenaltyFee, config.penaltyFee);
        _checkBound(flow, Field.CallTime, config.callTime);
        _checkBound(flow, Field.ExpireTime, config.expireTime);
        _checkBound(flow, Field.ExpireBlocks, config.expireBlocks);
        _checkBound(flow, Field.DeliveryGrace, config.deliveryGrace);
        _checkBound(flow, Field.MinAmount, config.minAmount);
        _checkBound(flow, Field.MaxAmount, config.maxAmount);
        if (config.expireTime <= config.callTime) {
            revert ExpireTimeNotAfterCallTime(config.callTime, config.expireTime);
        }
        _validateTiers(config.confirmationTiers);
    }

    /// @dev Enforces `expireTime > callTime` when either deadline field is being changed.
    function _checkDeadlineInvariant(PegConfiguration storage config, Field field, uint256 newValue)
        private
        view
    {
        if (field == Field.CallTime) {
            if (config.expireTime <= newValue) {
                revert ExpireTimeNotAfterCallTime(newValue, config.expireTime);
            }
        } else if (field == Field.ExpireTime) {
            if (newValue <= config.callTime) {
                revert ExpireTimeNotAfterCallTime(config.callTime, newValue);
            }
        }
    }

    function _checkBound(Flow flow, Field field, uint256 value) private view {
        FlyoverConfigurationsBounds storage b = _getBounds();
        PegConfiguration storage minC = flow == Flow.PegIn ? b.pegInMin : b.pegOutMin;
        PegConfiguration storage maxC = flow == Flow.PegIn ? b.pegInMax : b.pegOutMax;
        uint256 minV = _readField(minC, field);
        uint256 maxV = _readField(maxC, field);
        if (value < minV || value > maxV) {
            revert OutOfBounds(flow, field, value, minV, maxV);
        }
    }

    function _readField(PegConfiguration storage config, Field field) private view returns (uint256) {
        if (field == Field.FixedFee) return config.fixedFee;
        if (field == Field.PercentageFee) return config.percentageFee;
        if (field == Field.PenaltyFee) return config.penaltyFee;
        if (field == Field.CallTime) return config.callTime;
        if (field == Field.ExpireTime) return config.expireTime;
        if (field == Field.ExpireBlocks) return config.expireBlocks;
        if (field == Field.DeliveryGrace) return config.deliveryGrace;
        if (field == Field.MinAmount) return config.minAmount;
        return config.maxAmount; // Field.MaxAmount
    }

    function _writeField(PegConfiguration storage config, Field field, uint256 value) private {
        if (field == Field.FixedFee) config.fixedFee = value;
        else if (field == Field.PercentageFee) config.percentageFee = value;
        else if (field == Field.PenaltyFee) config.penaltyFee = value;
        else if (field == Field.CallTime) config.callTime = value;
        else if (field == Field.ExpireTime) config.expireTime = value;
        else if (field == Field.ExpireBlocks) config.expireBlocks = value;
        else if (field == Field.DeliveryGrace) config.deliveryGrace = value;
        else if (field == Field.MinAmount) config.minAmount = value;
        else config.maxAmount = value; // Field.MaxAmount
    }

    function _emitChange(Flow flow, Field field, uint256 oldValue, uint256 newValue) private {
        if (flow == Flow.PegIn) {
            if (field == Field.FixedFee) emit PegInFixedFeeChanged(oldValue, newValue);
            else if (field == Field.PercentageFee) emit PegInPercentageFeeChanged(oldValue, newValue);
            else if (field == Field.PenaltyFee) emit PegInPenaltyFeeChanged(oldValue, newValue);
            else if (field == Field.CallTime) emit PegInCallTimeChanged(oldValue, newValue);
            else if (field == Field.ExpireTime) emit PegInExpireTimeChanged(oldValue, newValue);
            else if (field == Field.ExpireBlocks) emit PegInExpireBlocksChanged(oldValue, newValue);
            else if (field == Field.DeliveryGrace) emit PegInDeliveryGraceChanged(oldValue, newValue);
            else if (field == Field.MinAmount) emit PegInMinAmountChanged(oldValue, newValue);
            else emit PegInMaxAmountChanged(oldValue, newValue);
        } else {
            if (field == Field.FixedFee) emit PegOutFixedFeeChanged(oldValue, newValue);
            else if (field == Field.PercentageFee) emit PegOutPercentageFeeChanged(oldValue, newValue);
            else if (field == Field.PenaltyFee) emit PegOutPenaltyFeeChanged(oldValue, newValue);
            else if (field == Field.CallTime) emit PegOutCallTimeChanged(oldValue, newValue);
            else if (field == Field.ExpireTime) emit PegOutExpireTimeChanged(oldValue, newValue);
            else if (field == Field.ExpireBlocks) emit PegOutExpireBlocksChanged(oldValue, newValue);
            else if (field == Field.DeliveryGrace) emit PegOutDeliveryGraceChanged(oldValue, newValue);
            else if (field == Field.MinAmount) emit PegOutMinAmountChanged(oldValue, newValue);
            else emit PegOutMaxAmountChanged(oldValue, newValue);
        }
    }

    // ============================ Internal: storage copy helpers ============================

    function _copyConfig(PegConfiguration storage dst, PegConfiguration calldata src) private {
        dst.fixedFee = src.fixedFee;
        dst.percentageFee = src.percentageFee;
        dst.penaltyFee = src.penaltyFee;
        dst.callTime = src.callTime;
        dst.expireTime = src.expireTime;
        dst.expireBlocks = src.expireBlocks;
        dst.deliveryGrace = src.deliveryGrace;
        dst.minAmount = src.minAmount;
        dst.maxAmount = src.maxAmount;
        delete dst.confirmationTiers;
        for (uint256 i = 0; i < src.confirmationTiers.length; ++i) {
            dst.confirmationTiers.push(src.confirmationTiers[i]);
        }
    }

    /// @dev Bounds only constrain the scalar fields; tier/deadline invariants do not apply to them.
    function _copyBounds(PegConfiguration storage dst, PegConfiguration calldata src) private {
        dst.fixedFee = src.fixedFee;
        dst.percentageFee = src.percentageFee;
        dst.penaltyFee = src.penaltyFee;
        dst.callTime = src.callTime;
        dst.expireTime = src.expireTime;
        dst.expireBlocks = src.expireBlocks;
        dst.deliveryGrace = src.deliveryGrace;
        dst.minAmount = src.minAmount;
        dst.maxAmount = src.maxAmount;
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
