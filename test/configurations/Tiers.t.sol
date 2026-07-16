// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {ConfigurationsTestBase} from "./ConfigurationsTestBase.sol";
import {IFlyoverConfigurations} from "../../src/interfaces/IFlyoverConfigurations.sol";

/// @title TiersTest
/// @notice getRequiredPegInBtcConfirmations: per-tier lookup, exact boundaries, above the last
/// tier, and a single-tier configuration.
/// @dev Seed tiers: (1e18,1) (10e18,3) (100e18,6). Walkthrough anchor: step 2.
contract TiersTest is ConfigurationsTestBase {
    function setUp() public {
        _deploy();
    }

    function test_perTier_lookup() public view {
        assertEq(config.getRequiredPegInBtcConfirmations(0.5 ether), 1);
        assertEq(config.getRequiredPegInBtcConfirmations(5 ether), 3);
        assertEq(config.getRequiredPegInBtcConfirmations(50 ether), 6);
    }

    /// @notice An amount exactly equal to a tier's maxAmount falls into that tier (inclusive).
    function test_exactBoundary_inclusive() public view {
        assertEq(config.getRequiredPegInBtcConfirmations(1 ether), 1);
        assertEq(config.getRequiredPegInBtcConfirmations(10 ether), 3);
        assertEq(config.getRequiredPegInBtcConfirmations(100 ether), 6);
    }

    /// @notice One wei above a boundary rolls into the next tier.
    function test_justAboveBoundary_nextTier() public view {
        assertEq(config.getRequiredPegInBtcConfirmations(1 ether + 1), 3);
        assertEq(config.getRequiredPegInBtcConfirmations(10 ether + 1), 6);
    }

    /// @notice Above the last tier's maxAmount the highest (last) tier's confirmations apply.
    function test_aboveLastTier_returnsHighest() public view {
        assertEq(config.getRequiredPegInBtcConfirmations(1000 ether), 6);
        assertEq(config.getRequiredPegInBtcConfirmations(type(uint256).max), 6);
    }

    /// @notice A single-tier configuration answers with that tier's confirmations for every
    /// amount, both within and above the tier's maxAmount.
    function test_singleTierConfig_answersEverything() public {
        IFlyoverConfigurations.PegConfiguration memory c = _altConfig();
        c.confirmationTiers = new IFlyoverConfigurations.ConfirmationTier[](1);
        c.confirmationTiers[0] = IFlyoverConfigurations.ConfirmationTier({maxAmount: 2 ether, confirmations: 9});

        vm.prank(owner);
        config.queueChange(c);
        vm.warp(block.timestamp + TIMELOCK_DELAY);
        vm.prank(owner);
        config.applyChange();

        assertEq(config.getRequiredPegInBtcConfirmations(1 ether), 9); // within the tier
        assertEq(config.getRequiredPegInBtcConfirmations(2 ether), 9); // exact boundary
        assertEq(config.getRequiredPegInBtcConfirmations(100 ether), 9); // above the only tier
        assertEq(config.getRequiredPegInBtcConfirmations(0), 9); // zero amount
    }
}
