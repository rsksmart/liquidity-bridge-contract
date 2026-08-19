// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

/// @title FlyoverConfigurations interface
/// @notice The single shared read for the commit-first protocol parameters. With no quote,
/// the fee, the confirmation tiers, and the amount limits still need a source every party
/// trusts equally: the SDK's estimate, every LPS's serve decision, and the settlement
/// validation all read the same numbers from this contract. Peg-in and peg-out share this
/// deployment (paired getters).
/// @dev This interface is frozen: any change to it is a cross-lane ABI event, not a side
/// effect of another task.
interface IFlyoverConfigurations {

    /// @notice One confirmation tier: deposits up to maxAmount require confirmations
    /// @dev Struct fields are ABI and freeze here. Tiers are kept strictly ascending by
    /// maxAmount.
    /// @param maxAmount The upper amount bound of the tier, in wei
    /// @param confirmations The BTC confirmations required for amounts in the tier
    struct ConfirmationTier {
        uint256 maxAmount;
        uint256 confirmations;
    }

    /// @notice The full peg-in parameter set
    /// @dev Struct fields are ABI and freeze here. The fee floor is a security parameter,
    /// not just pricing.
    /// @param fixedFee The fixed component of the peg-in fee, in wei
    /// @param percentageFee The proportional component of the fee, in basis points over
    /// 10,000
    /// @param minAmount The minimum peg-in amount, in wei
    /// @param maxAmount The maximum peg-in amount, in wei
    /// @param confirmationTiers The confirmation tiers, strictly ascending by maxAmount
    struct PegConfiguration {
        uint256 fixedFee;
        uint256 percentageFee;
        uint256 minAmount;
        uint256 maxAmount;
        ConfirmationTier[] confirmationTiers;
    }

    /// @notice Returns the active peg-in parameter set
    /// @dev The SDK reads it for the user's estimate, every LPS for its serve decision,
    /// and settlement for amount validation.
    /// @return configuration The active PegConfiguration
    function getPegInConfiguration() external view returns (PegConfiguration memory configuration);

    /// @notice Calculates the peg-in fee for an amount under the active configuration
    /// @dev fixedFee plus the percentage of the amount.
    /// @param amount The peg-in amount, in wei
    /// @return fee The fee, in wei
    function calculatePegInFee(uint256 amount) external view returns (uint256 fee);

    /// @notice Returns the BTC confirmations required before a peg-in of the given amount
    /// may be claimed
    /// @dev The first tier covering the amount answers. Read by the LPS before claiming
    /// and enforced by requestPegIn.
    /// @param amount The peg-in amount, in wei
    /// @return confirmations The required BTC confirmations
    function getRequiredPegInBtcConfirmations(uint256 amount) external view returns (uint256 confirmations);

    /// @notice Queues a configuration change, the first step of the time-locked admin change
    /// @dev Admin-only. The change activates only through applyChange after the configured
    /// delay; the values are validated against the active bounds at queue time.
    /// Returns nothing. Walkthrough anchors: step 2, decision block 2·D.
    /// @param newConfiguration The configuration to activate after the delay
    function queueChange(PegConfiguration calldata newConfiguration) external;

    /// @notice Activates the queued configuration change, the second step of the time-locked
    /// admin change
    /// @dev Admin-only. Reverts before the configured delay has elapsed; the values are
    /// re-validated against the active bounds at apply time, which may themselves have moved
    /// during the delay through the implementation's own time-locked bounds change.
    /// Returns nothing.
    /// Walkthrough anchors: step 2, decision block 2·D.
    function applyChange() external;

    // -------------------------------------------------------------------------
    // Peg-out
    // -------------------------------------------------------------------------

    /// @notice The full peg-out parameter set
    /// @dev Struct fields are ABI and freeze here. Peg-in fee/limits/tiers plus claim /
    /// fulfillment deadlines and `maxMinerFee`. Escrow request-id preimage, amount/fee
    /// split, and overpayment rule: see {IPegOutEscrow}.
    /// @param fixedFee Fixed component of the peg-out fee, in wei (security floor)
    /// @param percentageFee Proportional fee, basis points over 10_000
    /// @param minAmount Minimum serviceable peg-out amount, in wei
    /// @param maxAmount Maximum serviceable peg-out amount, in wei
    /// @param confirmationTiers BTC confirmations by amount (transferConfirmations)
    /// @param penaltyFee Individual / global slash total, in wei
    /// @param claimWindow Seconds from request → claim-by deadline (`depositDateLimit`)
    /// @param claimWindowBlocks Blocks from request → claim-by block bound
    /// @param callTime Fulfillment window duration from claim (`transferTime`)
    /// @param expireTime Seconds after latest claim time → user-refund `expireDate`
    /// @param expireBlocks Blocks after latest claim block → user-refund `expireBlock`
    /// @param maxMinerFee Cap used by the short-delivery floor, in wei
    struct PegOutConfiguration {
        uint256 fixedFee;
        uint256 percentageFee;
        uint256 minAmount;
        uint256 maxAmount;
        ConfirmationTier[] confirmationTiers;
        uint256 penaltyFee;
        uint256 claimWindow;
        uint256 claimWindowBlocks;
        uint256 callTime;
        uint256 expireTime;
        uint256 expireBlocks;
        uint256 maxMinerFee;
    }

    /// @notice Returns the active peg-out parameter set
    /// @dev SDK estimate, every LPS serve decision, and PegOutEscrow.requestPegOut all
    /// read this. Fee inputs for the frozen amount / fee split live here (`fixedFee`,
    /// `percentageFee`, `minAmount`, `maxAmount`).
    function getPegOutConfiguration() external view returns (PegOutConfiguration memory configuration);

    /// @notice Calculates the peg-out fee for an amount under the active peg-out configuration
    /// @dev `fixedFee + percentageFee·amount / 10_000` (satoshi-floored). Same formula
    /// escrow uses for `callFee` under the frozen amount / fee split.
    /// @param amount The peg-out principal, in wei
    /// @return fee The fee, in wei
    function calculatePegOutFee(uint256 amount) external view returns (uint256 fee);

    /// @notice Returns BTC confirmations required before a peg-out of this amount may settle
    /// @dev First covering tier. Consumed at request (snapshotted into the quote) and at
    /// refundPegOut.
    /// @param amount The peg-out principal, in wei
    /// @return confirmations The required BTC confirmations
    function getRequiredPegOutBtcConfirmations(uint256 amount) external view returns (uint256 confirmations);

    /// @notice Queues a peg-out configuration change (time-locked admin path)
    /// @dev Admin-only. Activates only through {applyPegOutChange} after the configured
    /// delay (shared timelock policy with peg-in).
    function queuePegOutChange(PegOutConfiguration calldata newConfiguration) external;

    /// @notice Activates the queued peg-out configuration change
    /// @dev Admin-only. Reverts before the configured delay has elapsed.
    function applyPegOutChange() external;
}
