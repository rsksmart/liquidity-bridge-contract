// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {FlyoverConfigurations} from "../FlyoverConfigurations.sol";
import {IFlyoverConfigurations} from "../interfaces/IFlyoverConfigurations.sol";

/// @title FlyoverConfigurationsRegtest
/// @notice Provisional regtest values for {FlyoverConfigurations}: seed peg-in / peg-out
/// configurations, immutable deployment bounds, and the time-lock delay.
/// @dev EVERY value here is provisional and calibrated only for regtest; none are production
/// values. Amounts are in wei; percentageFee is in basis points over 10_000.
library FlyoverConfigurationsRegtest {
    /// @notice Provisional time-lock delay (seconds) every queued configuration change must wait.
    /// @dev Short on regtest so changes can be exercised quickly; production expects a
    /// governance-grade delay (cf. TIMELOCK_MIN_DELAY, 7 days, in script/HelperConfig.s.sol).
    uint256 internal constant TIMELOCK_DELAY = 5 minutes;

    /// @notice The provisional seed peg-in configuration.
    function pegInConfig() internal pure returns (IFlyoverConfigurations.PegConfiguration memory config) {
        config.fixedFee = 0.0001 ether; // SECURITY floor: worst-case RSK serve cost
        config.percentageFee = 10; // pricing: 0.10% (10 / 10_000)
        config.minAmount = 0.005 ether; // amount limit: Flyover peg-in floor
        config.maxAmount = 10 ether; // amount limit: Flyover peg-in ceiling
        config.confirmationTiers = _tiers();
    }

    /// @notice Lower bound for every peg-in scalar field (immutable at deployment).
    function pegInMin() internal pure returns (IFlyoverConfigurations.PegConfiguration memory bound) {
        bound.fixedFee = 0.0001 ether; // SECURITY floor: hard minimum fixed fee
        bound.percentageFee = 0; // percentage may be zeroed
        bound.minAmount = 0.001 ether; // lowest permissible Flyover floor
        bound.maxAmount = 0.01 ether; // lowest permissible Flyover ceiling
        bound.confirmationTiers = new IFlyoverConfigurations.ConfirmationTier[](0);
    }

    /// @notice Upper bound for every peg-in scalar field (immutable at deployment).
    function pegInMax() internal pure returns (IFlyoverConfigurations.PegConfiguration memory bound) {
        bound.fixedFee = 0.01 ether; // fixed-fee ceiling
        bound.percentageFee = 1_000; // 10% max (1_000 / 10_000)
        bound.minAmount = 1 ether; // highest permissible Flyover floor
        bound.maxAmount = 1_000 ether; // highest permissible Flyover ceiling
        bound.confirmationTiers = new IFlyoverConfigurations.ConfirmationTier[](0);
    }

    /// @notice The provisional seed peg-out configuration (for {FlyoverConfigurations.initializePegOut}).
    function pegOutConfig()
        internal
        pure
        returns (IFlyoverConfigurations.PegOutConfiguration memory config)
    {
        config.fixedFee = 0.0001 ether;
        config.percentageFee = 10;
        config.minAmount = 0.005 ether;
        config.maxAmount = 10 ether;
        config.confirmationTiers = _tiers();
        config.penaltyFee = 0.01 ether;
        config.claimWindow = 30 minutes;
        config.claimWindowBlocks = 600;
        config.callTime = 2 hours;
        config.expireTime = 4 hours;
        // PegOutContract rejects expireBlock > block.number + 4000; keep
        // claimWindowBlocks + expireBlocks within that native cap.
        config.expireBlocks = 3_300;
        config.maxMinerFee = 0.0005 ether;
        config.gasFee = 0.0001 ether;
        config.depositConfirmations = 1;
    }

    /// @notice Lower bound for every peg-out scalar field.
    function pegOutMin()
        internal
        pure
        returns (IFlyoverConfigurations.PegOutConfiguration memory bound)
    {
        bound.fixedFee = 0.0001 ether;
        bound.percentageFee = 0;
        bound.minAmount = 0.001 ether;
        bound.maxAmount = 0.01 ether;
        bound.confirmationTiers = new IFlyoverConfigurations.ConfirmationTier[](0);
        bound.penaltyFee = 0.001 ether;
        bound.claimWindow = 5 minutes;
        bound.claimWindowBlocks = 1;
        bound.callTime = 30 minutes;
        bound.expireTime = 1 hours;
        bound.expireBlocks = 1;
        bound.maxMinerFee = 0;
        bound.gasFee = 0;
        bound.depositConfirmations = 0;
    }

    /// @notice Upper bound for every peg-out scalar field.
    function pegOutMax()
        internal
        pure
        returns (IFlyoverConfigurations.PegOutConfiguration memory bound)
    {
        bound.fixedFee = 0.01 ether;
        bound.percentageFee = 1_000;
        bound.minAmount = 1 ether;
        bound.maxAmount = 1_000 ether;
        bound.confirmationTiers = new IFlyoverConfigurations.ConfirmationTier[](0);
        bound.penaltyFee = 1 ether;
        bound.claimWindow = 1 days;
        bound.claimWindowBlocks = 50_000;
        bound.callTime = 2 days;
        bound.expireTime = 7 days;
        bound.expireBlocks = 200_000;
        bound.maxMinerFee = 0.1 ether;
        bound.gasFee = 0.01 ether;
        bound.depositConfirmations = 100;
    }

    function _tiers() private pure returns (IFlyoverConfigurations.ConfirmationTier[] memory tiers) {
        tiers = new IFlyoverConfigurations.ConfirmationTier[](3);
        tiers[0] = IFlyoverConfigurations.ConfirmationTier({maxAmount: 0.1 ether, confirmations: 2});
        tiers[1] = IFlyoverConfigurations.ConfirmationTier({maxAmount: 1 ether, confirmations: 20});
        tiers[2] = IFlyoverConfigurations.ConfirmationTier({maxAmount: 10 ether, confirmations: 100});
    }
}
