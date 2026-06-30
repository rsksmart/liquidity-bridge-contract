// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

/// @title IFlyoverConfigurations
/// @notice Holds both peg-in and peg-out configuration. `callTime` and `expireTime` are kept
/// separate per the S0.2 decision. Setters are time-locked (E1.5) and bounded by immutable
/// deployment-time minimum/maximum bounds.
/// @author Rootstock Labs
interface IFlyoverConfigurations {
    /// @notice A single confirmation tier: amounts up to and including `maxAmount` require
    /// `confirmations` BTC confirmations.
    struct ConfirmationTier {
        uint256 maxAmount;
        uint256 confirmations;
    }

    /// @notice The full configuration for one flow (peg-in or peg-out).
    struct PegConfiguration {
        uint256 fixedFee;        // fee floor
        uint256 percentageFee;   // 10_000 = 100%
        uint256 penaltyFee;      // individual slash amount
        ConfirmationTier[] confirmationTiers; // sorted ascending by maxAmount
        uint256 callTime;        // LP action deadline
        uint256 expireTime;      // refund-enable; strictly later than callTime
        uint256 expireBlocks;
        uint256 deliveryGrace;   // tolerance added to callTime before an individual slash (S0.1 D4)
        uint256 minAmount;
        uint256 maxAmount;
    }

    // --- Change events: one per field, per flow, emitted on apply -----------------------------

    event PegInFixedFeeChanged(uint256 oldValue, uint256 newValue);
    event PegInPercentageFeeChanged(uint256 oldValue, uint256 newValue);
    event PegInPenaltyFeeChanged(uint256 oldValue, uint256 newValue);
    event PegInConfirmationTiersChanged(ConfirmationTier[] oldValue, ConfirmationTier[] newValue);
    event PegInCallTimeChanged(uint256 oldValue, uint256 newValue);
    event PegInExpireTimeChanged(uint256 oldValue, uint256 newValue);
    event PegInExpireBlocksChanged(uint256 oldValue, uint256 newValue);
    event PegInDeliveryGraceChanged(uint256 oldValue, uint256 newValue);
    event PegInMinAmountChanged(uint256 oldValue, uint256 newValue);
    event PegInMaxAmountChanged(uint256 oldValue, uint256 newValue);

    event PegOutFixedFeeChanged(uint256 oldValue, uint256 newValue);
    event PegOutPercentageFeeChanged(uint256 oldValue, uint256 newValue);
    event PegOutPenaltyFeeChanged(uint256 oldValue, uint256 newValue);
    event PegOutConfirmationTiersChanged(ConfirmationTier[] oldValue, ConfirmationTier[] newValue);
    event PegOutCallTimeChanged(uint256 oldValue, uint256 newValue);
    event PegOutExpireTimeChanged(uint256 oldValue, uint256 newValue);
    event PegOutExpireBlocksChanged(uint256 oldValue, uint256 newValue);
    event PegOutDeliveryGraceChanged(uint256 oldValue, uint256 newValue);
    event PegOutMinAmountChanged(uint256 oldValue, uint256 newValue);
    event PegOutMaxAmountChanged(uint256 oldValue, uint256 newValue);

    // --- Aggregate getters --------------------------------------------------------------------

    function getPegInConfiguration() external view returns (PegConfiguration memory);
    function getPegOutConfiguration() external view returns (PegConfiguration memory);

    function getRequiredPegInConfirmations(uint256 amount) external view returns (uint256);
    function getRequiredPegOutConfirmations(uint256 amount) external view returns (uint256);

    function calculatePegInFee(uint256 amount) external view returns (uint256);
    function calculatePegOutFee(uint256 amount) external view returns (uint256);

    // immutable, set at deployment
    function getPegInConfigurationBounds() external view returns (PegConfiguration memory min, PegConfiguration memory max);
    function getPegOutConfigurationBounds() external view returns (PegConfiguration memory min, PegConfiguration memory max);
}
