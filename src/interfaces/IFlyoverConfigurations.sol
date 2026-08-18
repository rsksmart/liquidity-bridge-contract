// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

/// @title FlyoverConfigurations interface
/// @notice The single shared read for the commit-first protocol parameters. With no quote,
/// the fee, the confirmation tiers, and the amount limits still need a source every party
/// trusts equally: the SDK's estimate, every LPS's serve decision, and the settlement
/// validation all read the same numbers from this contract.
/// @dev Walkthrough (WALKTHROUGH-pegin.md) anchors: step 2, decision block 2·D, decision D2.
/// This interface is frozen (S0): any change to it is a cross-lane ABI event, not a side
/// effect of another task.
interface IFlyoverConfigurations {

    /// @notice One confirmation tier: deposits up to maxAmount require confirmations
    /// @dev Struct fields are ABI, so they freeze here, not in S2. Tiers are kept strictly
    /// ascending by maxAmount. Walkthrough anchor: step 2.
    /// @param maxAmount The upper amount bound of the tier, in wei
    /// @param confirmations The BTC confirmations required for amounts in the tier
    struct ConfirmationTier {
        uint256 maxAmount;
        uint256 confirmations;
    }

    /// @notice The full peg-in parameter set
    /// @dev Struct fields are ABI, so they freeze here, not in S2. The fee floor is a
    /// security parameter, not just pricing (2·D). Walkthrough anchors: step 2, decision D2.
    /// @param fixedFee The fixed component of the peg-in fee, in wei
    /// @param percentageFee The proportional component of the fee, in basis points over
    /// 10,000
    /// @param minAmount The minimum peg-in amount, in wei
    /// @param maxAmount The maximum peg-in amount, in wei
    /// @param registrantFee The fee paid to the registrant on the first claimed peg-in per
    /// destination address, in wei; read at settlement from live config and clamped to feeAtClaim
    /// @param confirmationTiers The confirmation tiers, strictly ascending by maxAmount
    struct PegConfiguration {
        uint256 fixedFee;
        uint256 percentageFee;
        uint256 minAmount;
        uint256 maxAmount;
        uint256 registrantFee;
        ConfirmationTier[] confirmationTiers;
    }

    /// @notice Returns the active peg-in parameter set
    /// @dev The SDK reads it for the user's estimate (step 1-2), every LPS for its serve
    /// decision (step 10), and settlement for the amount validation (exception A4).
    /// Walkthrough anchors: step 2, decision D2.
    /// @return configuration The active PegConfiguration
    function getPegInConfiguration() external view returns (PegConfiguration memory configuration);

    /// @notice Calculates the peg-in fee for an amount under the active configuration
    /// @dev fixedFee plus the percentage of the amount. Walkthrough anchors: step 2,
    /// decision block 2·D.
    /// @param amount The peg-in amount, in wei
    /// @return fee The fee, in wei
    function calculatePegInFee(uint256 amount) external view returns (uint256 fee);

    /// @notice Returns the BTC confirmations required before a peg-in of the given amount
    /// may be claimed
    /// @dev The first tier covering the amount answers. Read by the LPS before claiming
    /// (step 10) and enforced by requestPegIn (step 11). Walkthrough anchor: step 2.
    /// @param amount The peg-in amount, in wei
    /// @return confirmations The required BTC confirmations
    function getRequiredPegInBtcConfirmations(uint256 amount) external view returns (uint256 confirmations);

    /// @notice Queues a configuration change, the first step of the time-locked admin change
    /// @dev Admin-only. The change activates only through applyChange after the configured
    /// delay; the values are validated against the immutable deployment bounds at queue time.
    /// Returns nothing. Walkthrough anchors: step 2, decision block 2·D.
    /// @param newConfiguration The configuration to activate after the delay
    function queueChange(PegConfiguration calldata newConfiguration) external;

    /// @notice Activates the queued configuration change, the second step of the time-locked
    /// admin change
    /// @dev Admin-only. Reverts before the configured delay has elapsed; the values are
    /// re-validated against the immutable deployment bounds at apply time. Returns nothing.
    /// Walkthrough anchors: step 2, decision block 2·D.
    function applyChange() external;
}
