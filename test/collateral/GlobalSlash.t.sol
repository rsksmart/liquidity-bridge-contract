// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {CollateralTestBase} from "./CollateralTestBase.sol";
import {Vm} from "forge-std/Vm.sol";
import {CollateralManagementContract} from "../../src/CollateralManagement.sol";
import {ICollateralManagement} from "../../src/interfaces/ICollateralManagement.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";

/// @title Proportional global slash tests (E3.2)
contract GlobalSlashTest is CollateralTestBase {
    uint256 constant GRACE = 100; // DEFAULT_GRACE_WINDOW

    function setUp() public {
        deployCollateralManagement();
        setupRoles();
    }

    function _addPegIn(address lp, uint256 amount) internal {
        vm.deal(lp, amount);
        vm.prank(adder);
        collateralManagement.addPegInCollateralTo{value: amount}(lp);
    }

    /// @notice Two eligible LPs with equal collateral split the total evenly and the
    /// sum of reductions equals the total.
    function test_GlobalSlash_ProportionalDistributionSumsToTotal() public {
        address a = makeAddr("slashA");
        address b = makeAddr("slashB");
        // Unequal collateral to exercise proportionality: a=3x, b=1x.
        _addPegIn(a, 3 ether);
        _addPegIn(b, 1 ether);

        // Move past the grace window so both are eligible.
        vm.roll(block.number + GRACE + 1);

        uint256 total = 0.04 ether; // sumEligible = 4 ether
        uint256 aBefore = collateralManagement.getPegInCollateral(a);
        uint256 bBefore = collateralManagement.getPegInCollateral(b);

        vm.prank(slasher);
        collateralManagement.globalSlash(total);

        uint256 aReduction = aBefore - collateralManagement.getPegInCollateral(a);
        uint256 bReduction = bBefore - collateralManagement.getPegInCollateral(b);

        // a should lose 3/4 of total, b 1/4.
        assertEq(aReduction, (total * 3) / 4, "a loses proportional share");
        assertEq(bReduction, (total * 1) / 4, "b loses proportional share");
        assertEq(aReduction + bReduction, total, "reductions sum to total");

        // Reward/penalty split: total reward = 10% of total, penalties = the rest.
        uint256 expectedReward = (total * TEST_REWARD_PERCENTAGE) / 10000;
        assertEq(collateralManagement.getRewards(slasher), expectedReward, "slasher reward = 10% of total");
        assertEq(collateralManagement.getPenalties(), total - expectedReward, "penalties pool = total - reward");
    }

    /// @notice An LP inside its grace window is not slashed and is excluded from the denominator,
    /// so the eligible LP absorbs the entire total.
    function test_GlobalSlash_InGraceLpSkippedAndExcludedFromDenominator() public {
        address eligible = makeAddr("eligibleLp");
        _addPegIn(eligible, 2 ether);
        // Advance so the eligible LP is past grace.
        vm.roll(block.number + GRACE + 1);

        // Register a fresh LP right now: it is inside its grace window.
        address fresh = makeAddr("freshLp");
        _addPegIn(fresh, 10 ether);

        uint256 total = 0.05 ether;
        uint256 freshBefore = collateralManagement.getPegInCollateral(fresh);
        uint256 eligibleBefore = collateralManagement.getPegInCollateral(eligible);

        vm.prank(slasher);
        collateralManagement.globalSlash(total);

        // Fresh LP untouched.
        assertEq(collateralManagement.getPegInCollateral(fresh), freshBefore, "in-grace LP not slashed");
        // Eligible LP absorbs the full total (it was the only one in the denominator).
        assertEq(
            eligibleBefore - collateralManagement.getPegInCollateral(eligible),
            total,
            "eligible LP absorbs full total"
        );
    }

    function test_GlobalSlash_OnlySlasherRoleCanCall() public {
        address a = makeAddr("onlyA");
        _addPegIn(a, 1 ether);
        vm.roll(block.number + GRACE + 1);

        address notSlasher = makeAddr("notSlasher");
        bytes32 slasherRole = collateralManagement.COLLATERAL_SLASHER();
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                notSlasher,
                slasherRole
            )
        );
        vm.prank(notSlasher);
        collateralManagement.globalSlash(0.01 ether);
    }

    function test_GlobalSlash_EmitsPenalizedPerEligibleLp() public {
        address a = makeAddr("evA");
        address b = makeAddr("evB");
        _addPegIn(a, 1 ether);
        _addPegIn(b, 1 ether);
        vm.roll(block.number + GRACE + 1);

        // Expect a Penalized event for each eligible LP (recordLogs to count).
        vm.recordLogs();
        vm.prank(slasher);
        collateralManagement.globalSlash(0.02 ether);

        bytes32 penalizedSig = ICollateralManagement.Penalized.selector;
        uint256 count = 0;
        Vm.Log[] memory entries = vm.getRecordedLogs();
        for (uint256 i = 0; i < entries.length; ++i) {
            if (entries[i].topics.length > 0 && entries[i].topics[0] == penalizedSig) {
                ++count;
            }
        }
        assertEq(count, 2, "one Penalized per eligible LP");
    }

    function test_GlobalSlash_RevertsWhenNoEligibleCollateral() public {
        // Only an in-grace LP exists -> no eligible collateral.
        address fresh = makeAddr("freshOnly");
        _addPegIn(fresh, 1 ether);

        vm.prank(slasher);
        vm.expectRevert(CollateralManagementContract.NoEligibleCollateral.selector);
        collateralManagement.globalSlash(0.01 ether);
    }

    function test_GlobalSlash_RevertsOnZeroTotal() public {
        address a = makeAddr("zeroA");
        _addPegIn(a, 1 ether);
        vm.roll(block.number + GRACE + 1);

        vm.prank(slasher);
        vm.expectRevert(CollateralManagementContract.InvalidGlobalSlashAmount.selector);
        collateralManagement.globalSlash(0);
    }
}
