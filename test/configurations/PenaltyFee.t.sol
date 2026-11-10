// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {ConfigurationsTestBase} from "./ConfigurationsTestBase.sol";
import {FlyoverConfigurations} from "../../src/FlyoverConfigurations.sol";
import {IFlyoverConfigurations} from "../../src/interfaces/IFlyoverConfigurations.sol";

/// @title PenaltyFeeTest
contract PenaltyFeeTest is ConfigurationsTestBase {
    function setUp() public {
        _deploy();
    }

    function test_queueChange_rejects_penaltyFee_above_max() public {
        IFlyoverConfigurations.PegInConfiguration memory c = _altConfig();
        c.penaltyFee = BOUND_MAX_PENALTY_FEE + 1;
        vm.prank(owner);
        vm.expectRevert(
            abi.encodeWithSelector(
                FlyoverConfigurations.ConfigValueOutOfBounds.selector,
                FlyoverConfigurations.Field.PenaltyFee,
                BOUND_MAX_PENALTY_FEE + 1,
                BOUND_MIN_PENALTY_FEE,
                BOUND_MAX_PENALTY_FEE
            )
        );
        config.queueChange(c);
    }

    function test_queueBoundsChange_rejects_inverted_penaltyFee_pair() public {
        IFlyoverConfigurations.PegInConfiguration memory min = _boundsMin();
        min.penaltyFee = BOUND_MAX_PENALTY_FEE + 1;
        vm.prank(owner);
        vm.expectRevert(
            abi.encodeWithSelector(
                FlyoverConfigurations.InvalidBounds.selector,
                FlyoverConfigurations.Field.PenaltyFee,
                BOUND_MAX_PENALTY_FEE + 1,
                BOUND_MAX_PENALTY_FEE
            )
        );
        config.queueBoundsChange(min, _boundsMax());
    }

    function test_applyBoundsChange_rejects_bounds_excluding_active_penaltyFee()
        public
    {
        IFlyoverConfigurations.PegInConfiguration memory max = _boundsMax();
        max.penaltyFee = SEED_PENALTY_FEE - 1;
        vm.prank(owner);
        config.queueBoundsChange(_boundsMin(), max);
        vm.warp(block.timestamp + TIMELOCK_DELAY);
        vm.prank(owner);
        vm.expectRevert(
            abi.encodeWithSelector(
                FlyoverConfigurations.ActiveConfigOutsideNewBounds.selector,
                FlyoverConfigurations.Field.PenaltyFee,
                SEED_PENALTY_FEE,
                BOUND_MIN_PENALTY_FEE,
                SEED_PENALTY_FEE - 1
            )
        );
        config.applyBoundsChange();
    }
}
