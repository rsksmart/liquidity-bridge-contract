// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {ConfigurationsTestBase} from "./ConfigurationsTestBase.sol";
import {FlyoverConfigurations} from "../../src/FlyoverConfigurations.sol";
import {IFlyoverConfigurations} from "../../src/interfaces/IFlyoverConfigurations.sol";

/// @title MaxGasPriceAboveBaseFeeTest
/// @notice maxGasPriceAboveBaseFee is bounded like the other peg-in scalars: at queue and apply time, in bounds
/// pairs, and against the active configuration on a bounds change.
contract MaxGasPriceAboveBaseFeeTest is ConfigurationsTestBase {
    function setUp() public {
        _deploy();
    }

    function test_initialize_seeds_maxGasPriceAboveBaseFee() public view {
        assertEq(
            config.getPegInConfiguration().maxGasPriceAboveBaseFee,
            PEGIN_SEED_MAX_GAS_PRICE_ABOVE_BASE_FEE
        );
    }

    function test_queueChange_rejects_maxGasPriceAboveBaseFee_above_max()
        public
    {
        IFlyoverConfigurations.PegInConfiguration memory c = _altConfig();
        c.maxGasPriceAboveBaseFee =
            PEGIN_BOUND_MAX_MAX_GAS_PRICE_ABOVE_BASE_FEE +
            1;
        vm.prank(owner);
        vm.expectRevert(
            abi.encodeWithSelector(
                FlyoverConfigurations.ConfigValueOutOfBounds.selector,
                FlyoverConfigurations.Field.MaxGasPriceAboveBaseFee,
                PEGIN_BOUND_MAX_MAX_GAS_PRICE_ABOVE_BASE_FEE + 1,
                PEGIN_BOUND_MIN_MAX_GAS_PRICE_ABOVE_BASE_FEE,
                PEGIN_BOUND_MAX_MAX_GAS_PRICE_ABOVE_BASE_FEE
            )
        );
        config.queueChange(c);
    }

    function test_queueChange_rejects_maxGasPriceAboveBaseFee_below_min()
        public
    {
        IFlyoverConfigurations.PegInConfiguration memory min = _boundsMin();
        min.maxGasPriceAboveBaseFee = 1_000;
        _applyBounds(min, _boundsMax());
        IFlyoverConfigurations.PegInConfiguration memory c = _altConfig();
        c.maxGasPriceAboveBaseFee = 999;
        vm.prank(owner);
        vm.expectRevert(
            abi.encodeWithSelector(
                FlyoverConfigurations.ConfigValueOutOfBounds.selector,
                FlyoverConfigurations.Field.MaxGasPriceAboveBaseFee,
                999,
                1_000,
                PEGIN_BOUND_MAX_MAX_GAS_PRICE_ABOVE_BASE_FEE
            )
        );
        config.queueChange(c);
    }

    /// @notice 0 is a valid value: callGasFee then uses at most block.basefee
    function test_queueChange_then_applyChange_accepts_zero_maxGasPriceAboveBaseFee()
        public
    {
        IFlyoverConfigurations.PegInConfiguration memory c = _altConfig();
        c.maxGasPriceAboveBaseFee = 0;
        vm.prank(owner);
        config.queueChange(c);
        vm.warp(block.timestamp + TIMELOCK_DELAY);
        vm.prank(owner);
        config.applyChange();
        assertEq(config.getPegInConfiguration().maxGasPriceAboveBaseFee, 0);
    }

    function test_applyChange_updates_maxGasPriceAboveBaseFee() public {
        IFlyoverConfigurations.PegInConfiguration memory c = _queueAlt();
        vm.warp(block.timestamp + TIMELOCK_DELAY);
        vm.prank(owner);
        config.applyChange();
        assertEq(
            config.getPegInConfiguration().maxGasPriceAboveBaseFee,
            c.maxGasPriceAboveBaseFee
        );
    }

    function test_queueBoundsChange_rejects_inverted_maxGasPriceAboveBaseFee_pair()
        public
    {
        IFlyoverConfigurations.PegInConfiguration memory min = _boundsMin();
        min.maxGasPriceAboveBaseFee =
            PEGIN_BOUND_MAX_MAX_GAS_PRICE_ABOVE_BASE_FEE +
            1;
        vm.prank(owner);
        vm.expectRevert(
            abi.encodeWithSelector(
                FlyoverConfigurations.InvalidBounds.selector,
                FlyoverConfigurations.Field.MaxGasPriceAboveBaseFee,
                PEGIN_BOUND_MAX_MAX_GAS_PRICE_ABOVE_BASE_FEE + 1,
                PEGIN_BOUND_MAX_MAX_GAS_PRICE_ABOVE_BASE_FEE
            )
        );
        config.queueBoundsChange(min, _boundsMax());
    }

    function test_applyBoundsChange_rejects_bounds_excluding_active_maxGasPriceAboveBaseFee()
        public
    {
        IFlyoverConfigurations.PegInConfiguration memory max = _boundsMax();
        max.maxGasPriceAboveBaseFee =
            PEGIN_SEED_MAX_GAS_PRICE_ABOVE_BASE_FEE -
            1;
        vm.prank(owner);
        config.queueBoundsChange(_boundsMin(), max);
        vm.warp(block.timestamp + TIMELOCK_DELAY);
        vm.prank(owner);
        vm.expectRevert(
            abi.encodeWithSelector(
                FlyoverConfigurations.ActiveConfigOutsideNewBounds.selector,
                FlyoverConfigurations.Field.MaxGasPriceAboveBaseFee,
                PEGIN_SEED_MAX_GAS_PRICE_ABOVE_BASE_FEE,
                PEGIN_BOUND_MIN_MAX_GAS_PRICE_ABOVE_BASE_FEE,
                PEGIN_SEED_MAX_GAS_PRICE_ABOVE_BASE_FEE - 1
            )
        );
        config.applyBoundsChange();
    }
}
