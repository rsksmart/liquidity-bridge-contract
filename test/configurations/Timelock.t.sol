// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {ConfigurationsTestBase} from "./ConfigurationsTestBase.sol";
import {FlyoverConfigurations} from "../../src/FlyoverConfigurations.sol";
import {IFlyoverConfigurations} from "../../src/interfaces/IFlyoverConfigurations.sol";

/// @notice Time-lock mechanics: not applied before delay, applied after, emits, bounds, invariant.
contract TimelockTest is ConfigurationsTestBase {
    FlyoverConfigurations.Flow internal pegIn = FlyoverConfigurations.Flow.PegIn;

    function setUp() public {
        _deploy();
    }

    function test_changeNotAppliedBeforeDelay() public {
        uint256 newFee = 2000 * SAT;
        vm.prank(owner);
        config.queueChange(pegIn, FlyoverConfigurations.Field.FixedFee, newFee);

        // still old value
        assertEq(config.getPegInConfiguration().fixedFee, 1000 * SAT);

        // applying before the delay reverts
        vm.prank(owner);
        vm.expectRevert();
        config.applyChange(pegIn, FlyoverConfigurations.Field.FixedFee);

        // still old value
        assertEq(config.getPegInConfiguration().fixedFee, 1000 * SAT);
    }

    function test_changeAppliedAfterDelay_emitsEvent() public {
        uint256 newFee = 2000 * SAT;
        vm.prank(owner);
        config.queueChange(pegIn, FlyoverConfigurations.Field.FixedFee, newFee);

        vm.warp(block.timestamp + TIMELOCK_DELAY);

        vm.prank(owner);
        vm.expectEmit(true, true, true, true);
        emit IFlyoverConfigurations.PegInFixedFeeChanged(1000 * SAT, newFee);
        config.applyChange(pegIn, FlyoverConfigurations.Field.FixedFee);

        assertEq(config.getPegInConfiguration().fixedFee, newFee);
    }

    function test_applyAtExactEta_succeeds() public {
        vm.prank(owner);
        config.queueChange(pegIn, FlyoverConfigurations.Field.PenaltyFee, 0.02 ether);
        (, uint256 eta) = config.getPendingChange(pegIn, FlyoverConfigurations.Field.PenaltyFee);

        vm.warp(eta); // block.timestamp == eta is allowed
        vm.prank(owner);
        config.applyChange(pegIn, FlyoverConfigurations.Field.PenaltyFee);
        assertEq(config.getPegInConfiguration().penaltyFee, 0.02 ether);
    }

    function test_queueOutOfBounds_reverts() public {
        // fixedFee max bound is 1 ether
        vm.prank(owner);
        vm.expectRevert(
            abi.encodeWithSelector(
                FlyoverConfigurations.OutOfBounds.selector,
                pegIn,
                FlyoverConfigurations.Field.FixedFee,
                2 ether,
                0,
                1 ether
            )
        );
        config.queueChange(pegIn, FlyoverConfigurations.Field.FixedFee, 2 ether);
    }

    function test_applyExpireTimeBelowCallTime_reverts() public {
        // callTime is 2h; queue an expireTime <= callTime (but within bounds) and expect revert at apply.
        uint256 badExpire = 1 hours; // within [0, 8 days] bound but <= callTime
        vm.prank(owner);
        config.queueChange(pegIn, FlyoverConfigurations.Field.ExpireTime, badExpire);

        vm.warp(block.timestamp + TIMELOCK_DELAY);
        vm.prank(owner);
        vm.expectRevert(
            abi.encodeWithSelector(
                FlyoverConfigurations.ExpireTimeNotAfterCallTime.selector,
                2 hours,
                badExpire
            )
        );
        config.applyChange(pegIn, FlyoverConfigurations.Field.ExpireTime);
    }

    function test_applyCallTimeAboveExpireTime_reverts() public {
        // expireTime is 2h30; queue a callTime >= expireTime within bounds.
        uint256 badCall = 3 hours;
        vm.prank(owner);
        config.queueChange(pegIn, FlyoverConfigurations.Field.CallTime, badCall);

        vm.warp(block.timestamp + TIMELOCK_DELAY);
        vm.prank(owner);
        vm.expectRevert(
            abi.encodeWithSelector(
                FlyoverConfigurations.ExpireTimeNotAfterCallTime.selector,
                badCall,
                2 hours + 30 minutes
            )
        );
        config.applyChange(pegIn, FlyoverConfigurations.Field.CallTime);
    }

    function test_applyWithoutQueue_reverts() public {
        vm.prank(owner);
        vm.expectRevert(
            abi.encodeWithSelector(FlyoverConfigurations.NoQueuedChange.selector, pegIn)
        );
        config.applyChange(pegIn, FlyoverConfigurations.Field.FixedFee);
    }

    function test_nonAdmin_cannotQueue() public {
        vm.prank(stranger);
        vm.expectRevert();
        config.queueChange(pegIn, FlyoverConfigurations.Field.FixedFee, 2000 * SAT);
    }
}
