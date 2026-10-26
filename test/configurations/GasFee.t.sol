// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {ConfigurationsTestBase} from "./ConfigurationsTestBase.sol";
import {FlyoverConfigurations} from "../../src/FlyoverConfigurations.sol";
import {IFlyoverConfigurations} from "../../src/interfaces/IFlyoverConfigurations.sol";

/// @title GasFeeTest
contract GasFeeTest is ConfigurationsTestBase {
    function setUp() public {
        _deploy();
    }

    function test_queueChange_rejects_gasFee_above_max() public {
        IFlyoverConfigurations.PegConfiguration memory c = _altConfig();
        c.gasFee = BOUND_MAX_GAS_FEE + 1;
        vm.prank(owner);
        vm.expectRevert(
            abi.encodeWithSelector(
                FlyoverConfigurations.ConfigValueOutOfBounds.selector,
                FlyoverConfigurations.Field.GasFee,
                BOUND_MAX_GAS_FEE + 1,
                BOUND_MIN_GAS_FEE,
                BOUND_MAX_GAS_FEE
            )
        );
        config.queueChange(c);
    }

    function test_applyChange_activates_gasFee() public {
        IFlyoverConfigurations.PegConfiguration memory c = _altConfig();
        c.gasFee = BOUND_MAX_GAS_FEE;
        _applyConfig(c);
        assertEq(config.getPegInConfiguration().gasFee, BOUND_MAX_GAS_FEE);
    }

    function test_queueBoundsChange_rejects_inverted_gasFee_pair() public {
        IFlyoverConfigurations.PegConfiguration memory min = _boundsMin();
        min.gasFee = BOUND_MAX_GAS_FEE + 1;
        vm.prank(owner);
        vm.expectRevert(
            abi.encodeWithSelector(
                FlyoverConfigurations.InvalidBounds.selector,
                FlyoverConfigurations.Field.GasFee,
                BOUND_MAX_GAS_FEE + 1,
                BOUND_MAX_GAS_FEE
            )
        );
        config.queueBoundsChange(min, _boundsMax());
    }

    function test_applyBoundsChange_rejects_bounds_excluding_active_gasFee()
        public
    {
        IFlyoverConfigurations.PegConfiguration memory max = _boundsMax();
        max.gasFee = SEED_GAS_FEE - 1;
        vm.prank(owner);
        config.queueBoundsChange(_boundsMin(), max);
        vm.warp(block.timestamp + TIMELOCK_DELAY);
        vm.prank(owner);
        vm.expectRevert(
            abi.encodeWithSelector(
                FlyoverConfigurations.ActiveConfigOutsideNewBounds.selector,
                FlyoverConfigurations.Field.GasFee,
                SEED_GAS_FEE,
                BOUND_MIN_GAS_FEE,
                SEED_GAS_FEE - 1
            )
        );
        config.applyBoundsChange();
    }
}
