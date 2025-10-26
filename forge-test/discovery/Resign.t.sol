// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {DiscoveryTestBase} from "./DiscoveryTestBase.sol";
import {ICollateralManagement} from "../../contracts/interfaces/ICollateralManagement.sol";
import {Flyover} from "../../contracts/libraries/Flyover.sol";

contract ResignTest is DiscoveryTestBase {
    address public nonRegisteredAccount;

    function setUp() public {
        deployDiscovery();
        setupProviders();

        // Create non-registered account
        nonRegisteredAccount = makeAddr("nonRegistered");
        vm.deal(nonRegisteredAccount, 100 ether);
    }

    // ============ Resign flow tests ============

    function test_Resign_PreventsNonRegisteredAccountFromResigning() public {
        vm.prank(nonRegisteredAccount);
        vm.expectRevert(
            abi.encodeWithSelector(
                Flyover.ProviderNotRegistered.selector,
                nonRegisteredAccount
            )
        );
        collateralManagement.resign();
    }

    function test_Resign_PreventsCollateralWithdrawalBeforeDelayAndAllowsAfter() public {
        uint256 resignBlocks = collateralManagement.getResignDelayInBlocks();

        // Cannot withdraw before resigning
        vm.prank(pegInLp);
        vm.expectRevert(
            abi.encodeWithSelector(
                ICollateralManagement.NotResigned.selector,
                pegInLp
            )
        );
        collateralManagement.withdrawCollateral();

        // Resign
        vm.prank(pegInLp);
        collateralManagement.resign();

        // Cannot withdraw immediately after resigning
        vm.prank(pegInLp);
        vm.expectRevert(); // ResignationDelayNotMet
        collateralManagement.withdrawCollateral();

        // Wait for resign delay
        vm.roll(block.number + resignBlocks);

        // Now withdrawal should succeed
        vm.prank(pegInLp);
        collateralManagement.withdrawCollateral();
    }

    function test_Resign_PreventsDoubleResign() public {
        // First resign succeeds
        vm.prank(pegOutLp);
        collateralManagement.resign();

        // Second resign fails
        vm.prank(pegOutLp);
        vm.expectRevert(
            abi.encodeWithSelector(
                ICollateralManagement.AlreadyResigned.selector,
                pegOutLp
            )
        );
        collateralManagement.resign();
    }

    // ============ Happy path resign tests ============

    function test_Resign_AllowsResignWhenLPIsBothPegInAndPegOut() public {
        uint256 collateral = MIN_COLLATERAL * 2; // Both provider registers with 2x min collateral
        uint256 resignBlocks = collateralManagement.getResignDelayInBlocks();

        uint256 contractBalanceBefore = address(collateralManagement).balance;

        // Resign
        vm.prank(fullLp);
        vm.expectEmit(true, false, false, true);
        emit ICollateralManagement.Resigned(fullLp);
        collateralManagement.resign();

        // Contract balance should not change after resign
        assertEq(
            address(collateralManagement).balance,
            contractBalanceBefore,
            "Contract balance should not change after resign"
        );

        // Wait for resign delay
        vm.roll(block.number + resignBlocks);

        // Withdraw collateral
        uint256 lpBalanceBefore = fullLp.balance;

        vm.prank(fullLp);
        vm.expectEmit(true, true, false, true);
        emit ICollateralManagement.WithdrawCollateral(fullLp, collateral);
        collateralManagement.withdrawCollateral();

        // Verify LP balance increased
        assertEq(
            fullLp.balance,
            lpBalanceBefore + collateral,
            "LP balance should increase by collateral amount"
        );

        // Verify contract balance decreased
        assertEq(
            address(collateralManagement).balance,
            contractBalanceBefore - collateral,
            "Contract balance should decrease by collateral amount"
        );

        // Verify collaterals are zero
        assertEq(collateralManagement.getPegInCollateral(fullLp), 0, "PegIn collateral should be 0");
        assertEq(collateralManagement.getPegOutCollateral(fullLp), 0, "PegOut collateral should be 0");
    }

    function test_Resign_AllowsResignWhenLPIsPegInOnly() public {
        uint256 collateral = MIN_COLLATERAL;
        uint256 resignBlocks = collateralManagement.getResignDelayInBlocks();

        uint256 contractBalanceBefore = address(collateralManagement).balance;

        // Resign
        vm.prank(pegInLp);
        vm.expectEmit(true, false, false, true);
        emit ICollateralManagement.Resigned(pegInLp);
        collateralManagement.resign();

        // Contract balance should not change after resign
        assertEq(
            address(collateralManagement).balance,
            contractBalanceBefore,
            "Contract balance should not change after resign"
        );

        // Wait for resign delay
        vm.roll(block.number + resignBlocks);

        // Withdraw collateral
        uint256 lpBalanceBefore = pegInLp.balance;

        vm.prank(pegInLp);
        vm.expectEmit(true, true, false, true);
        emit ICollateralManagement.WithdrawCollateral(pegInLp, collateral);
        collateralManagement.withdrawCollateral();

        // Verify LP balance increased
        assertEq(
            pegInLp.balance,
            lpBalanceBefore + collateral,
            "LP balance should increase by collateral amount"
        );

        // Verify contract balance decreased
        assertEq(
            address(collateralManagement).balance,
            contractBalanceBefore - collateral,
            "Contract balance should decrease by collateral amount"
        );

        // Verify collaterals are zero
        assertEq(collateralManagement.getPegInCollateral(pegInLp), 0, "PegIn collateral should be 0");
        assertEq(collateralManagement.getPegOutCollateral(pegInLp), 0, "PegOut collateral should be 0");
    }

    function test_Resign_AllowsResignWhenLPIsPegOutOnly() public {
        uint256 collateral = MIN_COLLATERAL;
        uint256 resignBlocks = collateralManagement.getResignDelayInBlocks();

        uint256 contractBalanceBefore = address(collateralManagement).balance;

        // Resign
        vm.prank(pegOutLp);
        vm.expectEmit(true, false, false, true);
        emit ICollateralManagement.Resigned(pegOutLp);
        collateralManagement.resign();

        // Contract balance should not change after resign
        assertEq(
            address(collateralManagement).balance,
            contractBalanceBefore,
            "Contract balance should not change after resign"
        );

        // Wait for resign delay
        vm.roll(block.number + resignBlocks);

        // Withdraw collateral
        uint256 lpBalanceBefore = pegOutLp.balance;

        vm.prank(pegOutLp);
        vm.expectEmit(true, true, false, true);
        emit ICollateralManagement.WithdrawCollateral(pegOutLp, collateral);
        collateralManagement.withdrawCollateral();

        // Verify LP balance increased
        assertEq(
            pegOutLp.balance,
            lpBalanceBefore + collateral,
            "LP balance should increase by collateral amount"
        );

        // Verify contract balance decreased
        assertEq(
            address(collateralManagement).balance,
            contractBalanceBefore - collateral,
            "Contract balance should decrease by collateral amount"
        );

        // Verify collaterals are zero
        assertEq(collateralManagement.getPegInCollateral(pegOutLp), 0, "PegIn collateral should be 0");
        assertEq(collateralManagement.getPegOutCollateral(pegOutLp), 0, "PegOut collateral should be 0");
    }
}
