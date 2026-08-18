// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {IFlyoverConfigurations} from "../interfaces/IFlyoverConfigurations.sol";

/// @title FlyoverConfigurationsRegtest
/// @notice Provisional regtest values for {FlyoverConfigurations}: the seed peg-in configuration,
/// the seed bounds, and the time-lock delay. Shipped with the contract so the deploy wiring can
/// consume them without hardcoding numbers in a script. The bounds seeded here are the starting
/// pair, not a permanent one: the admin can move them later through the contract's time-locked
/// bounds change.
/// @dev EVERY value here is provisional and calibrated only for regtest; none are production
/// values. The fixed-fee floor is a SECURITY parameter, not just pricing: if it drops below
/// worst-case RSK gas during congestion, an attacker can make minimum-amount peg-ins no LP will
/// serve, and every LP eats the global slash. Amounts are in wei; percentageFee is in basis
/// points over 10_000 (10_000 == 100%); the delay is in seconds. Grounded on the existing regtest
/// defaults in script/HelperConfig.s.sol (e.g. minimumPegIn ~= 0.005 ether).
library FlyoverConfigurationsRegtest {
    /// @notice Provisional time-lock delay (seconds) every queued configuration change must wait.
    /// @dev Short on regtest so changes can be exercised quickly; production expects a
    /// governance-grade delay (cf. TIMELOCK_MIN_DELAY, 7 days, in script/HelperConfig.s.sol).
    uint256 internal constant TIMELOCK_DELAY = 5 minutes;

    /// @notice The provisional seed peg-in configuration.
    /// @return config The seed configuration written at initialization
    function pegInConfig() internal pure returns (IFlyoverConfigurations.PegConfiguration memory config) {
        config.fixedFee = 0.0001 ether; // SECURITY floor: worst-case RSK serve cost
        config.percentageFee = 10; // pricing: 0.10% (10 / 10_000)
        config.minAmount = 0.005 ether; // amount limit: Flyover peg-in floor
        config.maxAmount = 10 ether; // amount limit: Flyover peg-in ceiling
        config.registrantFee = 1e14; // first-peg-in registrant payout (0.0001 RBTC)
        config.confirmationTiers = _tiers();
    }

    /// @notice Lower bound for every peg-in scalar field, as seeded at deployment.
    /// @dev min.fixedFee IS the security floor: no queued change may set the fixed fee below it,
    /// so the floor holds even against a compromised admin role. Lowering the floor is itself a
    /// time-locked bounds change, so it stays observable for a full delay before it takes effect.
    /// @return bound The lower bound configuration
    function pegInMin() internal pure returns (IFlyoverConfigurations.PegConfiguration memory bound) {
        bound.fixedFee = 0.0001 ether; // SECURITY floor: hard minimum fixed fee
        bound.percentageFee = 0; // percentage may be zeroed
        bound.minAmount = 0.001 ether; // lowest permissible Flyover floor
        bound.maxAmount = 0.01 ether; // lowest permissible Flyover ceiling
        bound.registrantFee = 0;
        // Tiers are validated for ordering/non-emptiness only, never min/max-bounded.
        bound.confirmationTiers = new IFlyoverConfigurations.ConfirmationTier[](0);
    }

    /// @notice Upper bound for every peg-in scalar field, as seeded at deployment.
    /// @dev Caps how high the admin can push each field, so a mistake cannot set absurd values.
    /// @return bound The upper bound configuration
    function pegInMax() internal pure returns (IFlyoverConfigurations.PegConfiguration memory bound) {
        bound.fixedFee = 0.01 ether; // fixed-fee ceiling
        bound.percentageFee = 1_000; // 10% max (1_000 / 10_000)
        bound.minAmount = 1 ether; // highest permissible Flyover floor
        bound.maxAmount = 1_000 ether; // highest permissible Flyover ceiling
        bound.registrantFee = 0.001 ether - 1;
        bound.confirmationTiers = new IFlyoverConfigurations.ConfirmationTier[](0);
    }

    /// @dev Provisional confirmation tiers, strictly ascending by maxAmount. Larger deposits
    /// demand more BTC confirmations before an LP may claim; the last tier's confirmations answer
    /// any amount above the top bound.
    function _tiers() private pure returns (IFlyoverConfigurations.ConfirmationTier[] memory tiers) {
        tiers = new IFlyoverConfigurations.ConfirmationTier[](3);
        tiers[0] = IFlyoverConfigurations.ConfirmationTier({maxAmount: 0.1 ether, confirmations: 2});
        tiers[1] = IFlyoverConfigurations.ConfirmationTier({maxAmount: 1 ether, confirmations: 20});
        tiers[2] = IFlyoverConfigurations.ConfirmationTier({maxAmount: 10 ether, confirmations: 100});
    }
}
