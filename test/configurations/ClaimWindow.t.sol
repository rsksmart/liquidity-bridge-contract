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
        c.claimWindow = BOUND_MAX_CLAIM_WINDOW + 1;
        vm.prank(owner);
        vm.expectRevert(
            abi.encodeWithSelector(
                FlyoverConfigurations.ConfigValueOutOfBounds.selector,
                FlyoverConfigurations.Field.ClaimWindow,
                BOUND_MAX_CLAIM_WINDOW + 1,
                BOUND_MIN_CLAIM_WINDOW,
                BOUND_MAX_CLAIM_WINDOW
            )
        );
        config.queueChange(c);
    }

    function test_queueBoundsChange_rejects_inverted_claimWindow_pair() public {
        IFlyoverConfigurations.PegInConfiguration memory min = _boundsMin();
        min.claimWindow = BOUND_MAX_CLAIM_WINDOW + 1;
        vm.prank(owner);
        vm.expectRevert(
            abi.encodeWithSelector(
                FlyoverConfigurations.InvalidBounds.selector,
                FlyoverConfigurations.Field.ClaimWindow,
                BOUND_MAX_CLAIM_WINDOW + 1,
                BOUND_MAX_CLAIM_WINDOW
            )
        );
        config.queueBoundsChange(min, _boundsMax());
    }

    function test_applyBoundsChange_rejects_bounds_excluding_active_claimWindow()
        public
    {
        IFlyoverConfigurations.PegInConfiguration memory max = _boundsMax();
        max.claimWindow = SEED_CLAIM_WINDOW - 1;
        vm.prank(owner);
        config.queueBoundsChange(_boundsMin(), max);
        vm.warp(block.timestamp + TIMELOCK_DELAY);
        vm.prank(owner);
        vm.expectRevert(
            abi.encodeWithSelector(
                FlyoverConfigurations.ActiveConfigOutsideNewBounds.selector,
                FlyoverConfigurations.Field.ClaimWindow,
                SEED_CLAIM_WINDOW,
                BOUND_MIN_CLAIM_WINDOW,
                SEED_CLAIM_WINDOW - 1
            )
        );
        config.applyBoundsChange();
    }
}
