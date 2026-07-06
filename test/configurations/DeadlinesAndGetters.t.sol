// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {ConfigurationsTestBase} from "./ConfigurationsTestBase.sol";
import {IFlyoverConfigurations} from "../../src/interfaces/IFlyoverConfigurations.sol";

/// @notice Aggregate getters round-trip the seeded deadlines and limits for each flow.
contract DeadlinesAndGettersTest is ConfigurationsTestBase {
    function setUp() public {
        _deploy();
    }

    function test_pegInGetter_roundTrips() public view {
        IFlyoverConfigurations.PegConfiguration memory c = config.getPegInConfiguration();
        assertEq(c.fixedFee, 1000 * SAT);
        assertEq(c.percentageFee, 10);
        assertEq(c.penaltyFee, 0.01 ether);
        assertEq(c.callTime, 2 hours);
        assertEq(c.expireTime, 2 hours + 30 minutes);
        assertEq(c.expireBlocks, 500);
        assertEq(c.deliveryGrace, 60);
        assertEq(c.minAmount, 0.001 ether);
        assertEq(c.maxAmount, 100 ether);
        assertEq(c.confirmationTiers.length, 3);
        assertTrue(c.expireTime > c.callTime);
    }

    function test_pegOutGetter_roundTrips() public view {
        IFlyoverConfigurations.PegConfiguration memory c = config.getPegOutConfiguration();
        assertEq(c.fixedFee, 2000 * SAT);
        assertEq(c.percentageFee, 20);
        assertEq(c.confirmationTiers.length, 2);
        assertEq(c.minAmount, 0.001 ether);
        assertEq(c.maxAmount, 100 ether);
        assertTrue(c.expireTime > c.callTime);
    }

    function test_boundsGetters_returnDeploymentBounds() public view {
        (
            IFlyoverConfigurations.PegConfiguration memory min,
            IFlyoverConfigurations.PegConfiguration memory max
        ) = config.getPegInConfigurationBounds();
        assertEq(min.fixedFee, 0);
        assertEq(max.fixedFee, 1 ether);
        assertEq(max.percentageFee, 1_000);
        assertEq(max.maxAmount, 10_000 ether);

        (min, max) = config.getPegOutConfigurationBounds();
        assertEq(max.callTime, 7 days);
        assertEq(max.expireTime, 8 days);
    }
}
