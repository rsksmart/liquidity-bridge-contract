// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {ConfigurationsTestBase} from "./ConfigurationsTestBase.sol";
import {FlyoverConfigurations} from "../../src/FlyoverConfigurations.sol";
import {IFlyoverConfigurations} from "../../src/interfaces/IFlyoverConfigurations.sol";

/// @title MaxCallGasTest
/// @notice maxCallGas is bounded like the other peg-in scalars: at queue and apply time, in bounds
/// pairs, and against the active configuration on a bounds change.
contract MaxCallGasTest is ConfigurationsTestBase {
    function setUp() public {
        _deploy();
    }

    function test_initialize_seeds_maxCallGas() public view {
        assertEq(
            config.getPegInConfiguration().maxCallGas,
            PEGIN_SEED_MAX_CALL_GAS
        );
    }

    function test_queueChange_rejects_maxCallGas_above_max() public {
        IFlyoverConfigurations.PegInConfiguration memory c = _altConfig();
        c.maxCallGas = PEGIN_BOUND_MAX_MAX_CALL_GAS + 1;
        vm.prank(owner);
        vm.expectRevert(
            abi.encodeWithSelector(
                FlyoverConfigurations.ConfigValueOutOfBounds.selector,
                FlyoverConfigurations.Field.MaxCallGas,
                PEGIN_BOUND_MAX_MAX_CALL_GAS + 1,
                PEGIN_BOUND_MIN_MAX_CALL_GAS,
                PEGIN_BOUND_MAX_MAX_CALL_GAS
            )
        );
        config.queueChange(c);
    }

    function test_queueChange_rejects_maxCallGas_below_min() public {
        IFlyoverConfigurations.PegInConfiguration memory min = _boundsMin();
        min.maxCallGas = 100_000;
        _applyBounds(min, _boundsMax());
        IFlyoverConfigurations.PegInConfiguration memory c = _altConfig();
        c.maxCallGas = 99_999;
        vm.prank(owner);
        vm.expectRevert(
            abi.encodeWithSelector(
                FlyoverConfigurations.ConfigValueOutOfBounds.selector,
                FlyoverConfigurations.Field.MaxCallGas,
                99_999,
                100_000,
                PEGIN_BOUND_MAX_MAX_CALL_GAS
            )
        );
        config.queueChange(c);
    }

    /// @notice 0 is a valid value: it turns off contract calls
    function test_queueChange_then_applyChange_accepts_zero_maxCallGas()
        public
    {
        IFlyoverConfigurations.PegInConfiguration memory c = _altConfig();
        c.maxCallGas = 0;
        vm.prank(owner);
        config.queueChange(c);
        vm.warp(block.timestamp + TIMELOCK_DELAY);
        vm.prank(owner);
        config.applyChange();
        assertEq(config.getPegInConfiguration().maxCallGas, 0);
    }

    function test_applyChange_updates_maxCallGas() public {
        IFlyoverConfigurations.PegInConfiguration memory c = _queueAlt();
        vm.warp(block.timestamp + TIMELOCK_DELAY);
        vm.prank(owner);
        config.applyChange();
        assertEq(config.getPegInConfiguration().maxCallGas, c.maxCallGas);
    }

    function test_queueBoundsChange_rejects_inverted_maxCallGas_pair() public {
        IFlyoverConfigurations.PegInConfiguration memory min = _boundsMin();
        min.maxCallGas = PEGIN_BOUND_MAX_MAX_CALL_GAS + 1;
        vm.prank(owner);
        vm.expectRevert(
            abi.encodeWithSelector(
                FlyoverConfigurations.InvalidBounds.selector,
                FlyoverConfigurations.Field.MaxCallGas,
                PEGIN_BOUND_MAX_MAX_CALL_GAS + 1,
                PEGIN_BOUND_MAX_MAX_CALL_GAS
            )
        );
        config.queueBoundsChange(min, _boundsMax());
    }

    function test_applyBoundsChange_rejects_bounds_excluding_active_maxCallGas()
        public
    {
        IFlyoverConfigurations.PegInConfiguration memory max = _boundsMax();
        max.maxCallGas = PEGIN_SEED_MAX_CALL_GAS - 1;
        vm.prank(owner);
        config.queueBoundsChange(_boundsMin(), max);
        vm.warp(block.timestamp + TIMELOCK_DELAY);
        vm.prank(owner);
        vm.expectRevert(
            abi.encodeWithSelector(
                FlyoverConfigurations.ActiveConfigOutsideNewBounds.selector,
                FlyoverConfigurations.Field.MaxCallGas,
                PEGIN_SEED_MAX_CALL_GAS,
                PEGIN_BOUND_MIN_MAX_CALL_GAS,
                PEGIN_SEED_MAX_CALL_GAS - 1
            )
        );
        config.applyBoundsChange();
    }
}
