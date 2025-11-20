// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {PegInTestBase} from "./PegInTestBase.sol";
import {IPegIn} from "../../contracts/interfaces/IPegIn.sol";
import {Flyover} from "../../contracts/libraries/Flyover.sol";
import {Vm} from "forge-std/Vm.sol";

contract DepositTest is PegInTestBase {
    address public notProvider;

    function setUp() public {
        deployPegInContract();
        setupProviders();

        notProvider = makeAddr("notProvider");
        vm.deal(notProvider, 100 ether);
    }

    // ============ deposit function tests ============

    function test_Deposit_OnlyAllowsLiquidityProvidersToDeposit() public {
        // Not a provider - should revert
        vm.prank(notProvider);
        vm.expectRevert(
            abi.encodeWithSelector(
                Flyover.ProviderNotRegistered.selector,
                notProvider
            )
        );
        pegInContract.deposit{value: 1 ether}();

        // PegOut provider trying to deposit in PegIn contract - should revert
        vm.prank(pegOutLp);
        vm.expectRevert(
            abi.encodeWithSelector(
                Flyover.ProviderNotRegistered.selector,
                pegOutLp
            )
        );
        pegInContract.deposit{value: 1 ether}();

        // PegIn provider - should succeed
        vm.prank(pegInLp);
        pegInContract.deposit{value: 1 ether}();

        // Full provider - should succeed
        vm.prank(fullLp);
        pegInContract.deposit{value: 1 ether}();
    }

    function test_Deposit_IncreasesBalanceProperly() public {
        uint256 value = 1 ether;
        uint256 contractBalanceBefore = address(pegInContract).balance;
        uint256 lpBalanceBefore = fullLp.balance;

        vm.prank(fullLp);
        vm.expectEmit(true, true, false, true);
        emit IPegIn.BalanceIncrease(fullLp, value);
        pegInContract.deposit{value: value}();

        // Verify balances
        assertEq(
            address(pegInContract).balance,
            contractBalanceBefore + value,
            "Contract balance should increase"
        );
        assertEq(
            fullLp.balance,
            lpBalanceBefore - value,
            "LP balance should decrease"
        );
        assertEq(
            pegInContract.getBalance(fullLp),
            value,
            "LP balance in contract should equal deposited amount"
        );
    }

    function test_Deposit_DoesNotEmitEventIfAmountIsZero() public {
        vm.prank(pegInLp);
        // We use recordLogs to check if event was emitted
        vm.recordLogs();
        pegInContract.deposit{value: 0}();

        // Get emitted events
        Vm.Log[] memory entries = vm.getRecordedLogs();

        // No BalanceIncrease event should be emitted
        for (uint i = 0; i < entries.length; i++) {
            assertFalse(
                entries[i].topics[0] ==
                    keccak256("BalanceIncrease(address,uint256)"),
                "BalanceIncrease event should not be emitted for zero amount"
            );
        }

        assertEq(
            pegInContract.getBalance(pegInLp),
            0,
            "Balance should remain 0"
        );
    }
}
