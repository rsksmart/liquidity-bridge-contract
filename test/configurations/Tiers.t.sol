// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {ConfigurationsTestBase} from "./ConfigurationsTestBase.sol";
import {FlyoverConfigurations} from "../../src/FlyoverConfigurations.sol";
import {IFlyoverConfigurations} from "../../src/interfaces/IFlyoverConfigurations.sol";

/// @notice Confirmation-tier lookup, boundaries, separate per-flow lists, and unsorted rejection.
contract TiersTest is ConfigurationsTestBase {
    function setUp() public {
        _deploy();
    }

    function test_perTier_pegIn() public view {
        // tiers: (1e18,1) (10e18,3) (100e18,6)
        assertEq(config.getRequiredPegInConfirmations(0.5 ether), 1);
        assertEq(config.getRequiredPegInConfirmations(5 ether), 3);
        assertEq(config.getRequiredPegInConfirmations(50 ether), 6);
    }

    function test_boundary_inclusive() public view {
        // amount exactly at a tier's maxAmount falls into that tier.
        assertEq(config.getRequiredPegInConfirmations(1 ether), 1);
        assertEq(config.getRequiredPegInConfirmations(10 ether), 3);
        assertEq(config.getRequiredPegInConfirmations(100 ether), 6);
    }

    function test_aboveTopTier_returnsHighest() public view {
        assertEq(config.getRequiredPegInConfirmations(1000 ether), 6);
    }

    function test_pegOut_separateList() public view {
        // peg-out tiers: (5e18,2) (50e18,4)
        assertEq(config.getRequiredPegOutConfirmations(1 ether), 2);
        assertEq(config.getRequiredPegOutConfirmations(5 ether), 2);
        assertEq(config.getRequiredPegOutConfirmations(20 ether), 4);
        assertEq(config.getRequiredPegOutConfirmations(1000 ether), 4);
    }

    function test_queueTiers_rejectsUnsorted() public {
        IFlyoverConfigurations.ConfirmationTier[] memory bad =
            new IFlyoverConfigurations.ConfirmationTier[](2);
        bad[0] = IFlyoverConfigurations.ConfirmationTier({maxAmount: 10 ether, confirmations: 3});
        bad[1] = IFlyoverConfigurations.ConfirmationTier({maxAmount: 1 ether, confirmations: 1});

        vm.prank(owner);
        vm.expectRevert(FlyoverConfigurations.TiersNotAscending.selector);
        config.queueTiersChange(FlyoverConfigurations.Flow.PegIn, bad);
    }

    function test_queueTiers_rejectsEqualMaxAmounts() public {
        IFlyoverConfigurations.ConfirmationTier[] memory bad =
            new IFlyoverConfigurations.ConfirmationTier[](2);
        bad[0] = IFlyoverConfigurations.ConfirmationTier({maxAmount: 1 ether, confirmations: 1});
        bad[1] = IFlyoverConfigurations.ConfirmationTier({maxAmount: 1 ether, confirmations: 2});

        vm.prank(owner);
        vm.expectRevert(FlyoverConfigurations.TiersNotAscending.selector);
        config.queueTiersChange(FlyoverConfigurations.Flow.PegIn, bad);
    }

    function test_tiersChange_appliesAfterDelayAndEmits() public {
        IFlyoverConfigurations.ConfirmationTier[] memory newTiers =
            new IFlyoverConfigurations.ConfirmationTier[](1);
        newTiers[0] = IFlyoverConfigurations.ConfirmationTier({maxAmount: 2 ether, confirmations: 9});

        vm.prank(owner);
        config.queueTiersChange(FlyoverConfigurations.Flow.PegIn, newTiers);

        // not applied yet
        assertEq(config.getRequiredPegInConfirmations(0.5 ether), 1);

        vm.warp(block.timestamp + TIMELOCK_DELAY);
        vm.prank(owner);
        vm.expectEmit(false, false, false, false);
        emit IFlyoverConfigurations.PegInConfirmationTiersChanged(newTiers, newTiers);
        config.applyTiersChange(FlyoverConfigurations.Flow.PegIn);

        assertEq(config.getRequiredPegInConfirmations(0.5 ether), 9);
        assertEq(config.getRequiredPegInConfirmations(100 ether), 9); // single top tier
    }
}
