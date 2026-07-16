// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {ConfigurationsTestBase} from "./ConfigurationsTestBase.sol";
import {IFlyoverConfigurations} from "../../src/interfaces/IFlyoverConfigurations.sol";

/// @title GettersTest
/// @notice Every read surface: the active configuration (incl. limits), the immutable bounds,
/// the pending change, and the time-lock delay.
contract GettersTest is ConfigurationsTestBase {
    function setUp() public {
        _deploy();
    }

    function test_getPegInConfiguration_roundTripsSeed() public view {
        IFlyoverConfigurations.PegConfiguration memory c = config
            .getPegInConfiguration();
        assertEq(c.fixedFee, SEED_FIXED_FEE);
        assertEq(c.percentageFee, SEED_PCT);
        assertEq(c.minAmount, SEED_MIN_AMOUNT);
        assertEq(c.maxAmount, SEED_MAX_AMOUNT);
        assertEq(c.confirmationTiers.length, 3);
        assertEq(c.confirmationTiers[0].maxAmount, 1 ether);
        assertEq(c.confirmationTiers[0].confirmations, 1);
        assertEq(c.confirmationTiers[2].maxAmount, 100 ether);
        assertEq(c.confirmationTiers[2].confirmations, 6);
    }

    function test_limits_readableFromConfiguration() public view {
        IFlyoverConfigurations.PegConfiguration memory c = config
            .getPegInConfiguration();
        assertEq(c.minAmount, SEED_MIN_AMOUNT);
        assertEq(c.maxAmount, SEED_MAX_AMOUNT);
        assertLe(c.minAmount, c.maxAmount);
    }

    function test_getPegInConfigurationBounds_returnsDeploymentBounds()
        public
        view
    {
        (
            IFlyoverConfigurations.PegConfiguration memory min,
            IFlyoverConfigurations.PegConfiguration memory max
        ) = config.getPegInConfigurationBounds();

        assertEq(min.fixedFee, BOUND_MIN_FIXED_FEE);
        assertEq(min.percentageFee, BOUND_MIN_PCT);
        assertEq(min.minAmount, BOUND_MIN_MIN_AMOUNT);
        assertEq(min.maxAmount, BOUND_MIN_MAX_AMOUNT);

        assertEq(max.fixedFee, BOUND_MAX_FIXED_FEE);
        assertEq(max.percentageFee, BOUND_MAX_PCT);
        assertEq(max.minAmount, BOUND_MAX_MIN_AMOUNT);
        assertEq(max.maxAmount, BOUND_MAX_MAX_AMOUNT);
    }

    function test_getTimelockDelay_returnsConfiguredDelay() public view {
        assertEq(config.getTimelockDelay(), TIMELOCK_DELAY);
    }

    function test_getPendingChange_zeroedWhenNothingQueued() public view {
        (
            IFlyoverConfigurations.PegConfiguration memory pending,
            uint256 eta
        ) = config.getPendingChange();
        assertEq(eta, 0);
        assertEq(pending.fixedFee, 0);
        assertEq(pending.percentageFee, 0);
        assertEq(pending.minAmount, 0);
        assertEq(pending.maxAmount, 0);
        assertEq(pending.confirmationTiers.length, 0);
    }

    function test_getPendingChange_reflectsQueuedChange() public {
        uint256 expectedEta = block.timestamp + TIMELOCK_DELAY;
        IFlyoverConfigurations.PegConfiguration memory queued = _queueAlt();

        (
            IFlyoverConfigurations.PegConfiguration memory pending,
            uint256 eta
        ) = config.getPendingChange();
        assertEq(eta, expectedEta);
        assertEq(pending.fixedFee, queued.fixedFee);
        assertEq(pending.percentageFee, queued.percentageFee);
        assertEq(pending.minAmount, queued.minAmount);
        assertEq(pending.maxAmount, queued.maxAmount);
        assertEq(
            pending.confirmationTiers.length,
            queued.confirmationTiers.length
        );
    }

    function test_getPendingChange_clearedAfterApply() public {
        _queueAlt();
        vm.warp(block.timestamp + TIMELOCK_DELAY);
        vm.prank(owner);
        config.applyChange();

        (
            IFlyoverConfigurations.PegConfiguration memory pending,
            uint256 eta
        ) = config.getPendingChange();
        assertEq(eta, 0);
        assertEq(pending.fixedFee, 0);
        assertEq(pending.confirmationTiers.length, 0);
    }

    function test_version_isSet() public view {
        assertEq(config.VERSION(), "1.0.0");
    }
}
