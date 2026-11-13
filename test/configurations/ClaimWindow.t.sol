// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {ConfigurationsTestBase} from "./ConfigurationsTestBase.sol";
import {FlyoverConfigurations} from "../../src/FlyoverConfigurations.sol";
import {IFlyoverConfigurations} from "../../src/interfaces/IFlyoverConfigurations.sol";

/// @title ClaimWindowTest
contract ClaimWindowTest is ConfigurationsTestBase {
    function setUp() public {
        _deploy();
    }

    function test_queueChange_rejects_claimWindow_above_max() public {
        IFlyoverConfigurations.PegInConfiguration memory c = _altConfig();
        c.claimWindow = PEGIN_BOUND_MAX_CLAIM_WINDOW + 1;
        vm.prank(owner);
        vm.expectRevert(
            abi.encodeWithSelector(
                FlyoverConfigurations.ConfigValueOutOfBounds.selector,
                FlyoverConfigurations.Field.ClaimWindow,
                PEGIN_BOUND_MAX_CLAIM_WINDOW + 1,
                PEGIN_BOUND_MIN_CLAIM_WINDOW,
                PEGIN_BOUND_MAX_CLAIM_WINDOW
            )
        );
        config.queueChange(c);
    }

    function test_queueChange_rejects_claimWindow_below_minimum_when_bounds_allow_it()
        public
    {
        uint256 minimum = config.MIN_PEGIN_CLAIM_WINDOW();
        IFlyoverConfigurations.PegInConfiguration memory min = _boundsMin();
        min.claimWindow = 0;
        _applyBounds(min, _boundsMax());
        IFlyoverConfigurations.PegInConfiguration memory c = _altConfig();
        c.claimWindow = minimum - 1;
        vm.prank(owner);
        vm.expectRevert(
            abi.encodeWithSelector(
                FlyoverConfigurations.PegInClaimWindowTooShort.selector,
                minimum - 1,
                minimum
            )
        );
        config.queueChange(c);
    }

    function test_queueChange_accepts_claimWindow_at_minimum() public {
        IFlyoverConfigurations.PegInConfiguration memory c = _altConfig();
        c.claimWindow = config.MIN_PEGIN_CLAIM_WINDOW();
        vm.prank(owner);
        config.queueChange(c);
        (IFlyoverConfigurations.PegInConfiguration memory pending, ) = config
            .getPendingChange();
        assertEq(pending.claimWindow, config.MIN_PEGIN_CLAIM_WINDOW());
    }

    function test_queueBoundsChange_rejects_inverted_claimWindow_pair() public {
        IFlyoverConfigurations.PegInConfiguration memory min = _boundsMin();
        min.claimWindow = PEGIN_BOUND_MAX_CLAIM_WINDOW + 1;
        vm.prank(owner);
        vm.expectRevert(
            abi.encodeWithSelector(
                FlyoverConfigurations.InvalidBounds.selector,
                FlyoverConfigurations.Field.ClaimWindow,
                PEGIN_BOUND_MAX_CLAIM_WINDOW + 1,
                PEGIN_BOUND_MAX_CLAIM_WINDOW
            )
        );
        config.queueBoundsChange(min, _boundsMax());
    }

    function test_applyBoundsChange_rejects_bounds_excluding_active_claimWindow()
        public
    {
        IFlyoverConfigurations.PegInConfiguration memory max = _boundsMax();
        max.claimWindow = PEGIN_SEED_CLAIM_WINDOW - 1;
        vm.prank(owner);
        config.queueBoundsChange(_boundsMin(), max);
        vm.warp(block.timestamp + TIMELOCK_DELAY);
        vm.prank(owner);
        vm.expectRevert(
            abi.encodeWithSelector(
                FlyoverConfigurations.ActiveConfigOutsideNewBounds.selector,
                FlyoverConfigurations.Field.ClaimWindow,
                PEGIN_SEED_CLAIM_WINDOW,
                PEGIN_BOUND_MIN_CLAIM_WINDOW,
                PEGIN_SEED_CLAIM_WINDOW - 1
            )
        );
        config.applyBoundsChange();
    }
}
