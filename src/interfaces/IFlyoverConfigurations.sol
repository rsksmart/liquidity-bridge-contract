// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

/// @title FlyoverConfigurations interface
/// @notice The single shared read for the commit-first protocol parameters. With no quote,
/// the fee, the confirmation tiers, and the amount limits still need a source every party
/// trusts equally: the SDK's estimate, every LPS's serve decision, and the settlement
/// validation all read the same numbers from this contract.
/// @dev ABI-stable; struct and function changes affect all consumers.
interface IFlyoverConfigurations {

    /// @notice One confirmation tier: deposits up to maxAmount require confirmations
    /// @dev Tiers are strictly ascending by maxAmount.
    /// @param maxAmount The upper amount bound of the tier, in wei
    /// @param confirmations The BTC confirmations required for amounts in the tier
    struct ConfirmationTier {
        uint256 maxAmount;
        uint256 confirmations;
    }

    /// @notice The full peg-in parameter set
    /// @dev fixedFee is a security floor, not only a price parameter.
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
    /// @return configuration The active PegConfiguration
    function getPegInConfiguration() external view returns (PegConfiguration memory configuration);

    /// @notice Calculates the peg-in fee for an amount under the active configuration
    /// @dev Returns fixedFee plus the percentage of the amount.
    /// @param amount The peg-in amount, in wei
    /// @return fee The fee, in wei
    function calculatePegInFee(uint256 amount) external view returns (uint256 fee);

    /// @notice Returns the BTC confirmations required before a peg-in of the given amount
    /// may be claimed
    /// @dev The first tier covering the amount answers.
    /// @param amount The peg-in amount, in wei
    /// @return confirmations The required BTC confirmations
    function getRequiredPegInBtcConfirmations(uint256 amount) external view returns (uint256 confirmations);

    /// @notice Queues a configuration change, the first step of the time-locked admin change
    /// @dev Admin-only. Values are validated against immutable deployment bounds at queue time.
    /// @param newConfiguration The configuration to activate after the delay
    function queueChange(PegConfiguration calldata newConfiguration) external;

    /// @notice Activates the queued configuration change, the second step of the time-locked
    /// admin change
    /// @dev Admin-only. Reverts before the delay elapses; values are re-validated at apply time.
    function applyChange() external;
}
