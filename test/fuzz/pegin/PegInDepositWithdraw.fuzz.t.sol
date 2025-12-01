// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {PegInFuzzTestBase} from "./PegInFuzzTestBase.sol";
import {Quotes} from "../../../src/libraries/Quotes.sol";
import {IPegIn} from "../../../src/interfaces/IPegIn.sol";
import {Flyover} from "../../../src/libraries/Flyover.sol";

/// @title PegIn Deposit/Withdraw Fuzz Tests
/// @notice Fuzz tests for PegIn deposit and withdrawal functionality
contract PegInDepositWithdrawFuzzTest is PegInFuzzTestBase {
    function setUp() public {
        deployPegInContract();
        setupProviders();

        fuzzUser = makeAddr("user");
        vm.deal(fuzzUser, 1000 ether);
    }

    // ============ Deposit Fuzz Tests ============

    /// @notice Fuzz test: Valid deposits should succeed and emit BalanceIncrease
    function testFuzz_Deposit_IncreasesBalanceProperly(
        uint128 depositAmount
    ) public {
        depositAmount = uint128(bound(depositAmount, 0.001 ether, 50 ether));

        uint256 contractBalanceBefore = address(pegInContract).balance;
        uint256 lpBalanceBefore = pegInLp.balance;

        // Expect BalanceIncrease event
        vm.expectEmit(true, true, false, true);
        emit IPegIn.BalanceIncrease(pegInLp, depositAmount);

        vm.prank(pegInLp);
        pegInContract.deposit{value: depositAmount}();

        // Verify contract balance increased
        assertEq(
            address(pegInContract).balance,
            contractBalanceBefore + depositAmount,
            "Contract balance should increase by deposit amount"
        );

        // Verify LP external balance decreased
        assertEq(
            pegInLp.balance,
            lpBalanceBefore - depositAmount,
            "LP external balance should decrease by deposit amount"
        );

        // Verify LP internal balance increased
        assertEq(
            pegInContract.getBalance(pegInLp),
            depositAmount,
            "LP internal balance should equal deposit amount"
        );
    }

    /// @notice Fuzz test: Multiple deposits should accumulate correctly
    function testFuzz_Deposit_AccumulatesMultipleDeposits(
        uint64 deposit1,
        uint64 deposit2,
        uint64 deposit3
    ) public {
        deposit1 = uint64(bound(deposit1, 0.001 ether, 10 ether));
        deposit2 = uint64(bound(deposit2, 0.001 ether, 10 ether));
        deposit3 = uint64(bound(deposit3, 0.001 ether, 10 ether));

        uint256 expectedTotal = uint256(deposit1) +
            uint256(deposit2) +
            uint256(deposit3);
        vm.assume(expectedTotal <= 50 ether);

        vm.startPrank(fullLp);
        pegInContract.deposit{value: deposit1}();
        pegInContract.deposit{value: deposit2}();
        pegInContract.deposit{value: deposit3}();
        vm.stopPrank();

        assertEq(
            pegInContract.getBalance(fullLp),
            expectedTotal,
            "Balance should equal sum of all deposits"
        );
    }

    /// @notice Fuzz test: Non-provider should be rejected
    function testFuzz_Deposit_RevertsForNonProvider(
        uint128 depositAmount
    ) public {
        depositAmount = uint128(bound(depositAmount, 0.001 ether, 10 ether));

        vm.prank(fuzzUser);
        vm.expectRevert(
            abi.encodeWithSelector(
                Flyover.ProviderNotRegistered.selector,
                fuzzUser
            )
        );
        pegInContract.deposit{value: depositAmount}();
    }

    /// @notice Fuzz test: PegOut-only provider should be rejected for PegIn deposit
    function testFuzz_Deposit_RevertsPegOutOnlyProvider(
        uint128 depositAmount
    ) public {
        depositAmount = uint128(bound(depositAmount, 0.001 ether, 10 ether));

        vm.prank(pegOutLp);
        vm.expectRevert(
            abi.encodeWithSelector(
                Flyover.ProviderNotRegistered.selector,
                pegOutLp
            )
        );
        pegInContract.deposit{value: depositAmount}();
    }

    // ============ Withdraw Fuzz Tests ============

    /// @notice Fuzz test: Valid withdrawals should succeed and emit Withdrawal
    function testFuzz_Withdraw_DecreasesBalanceProperly(
        uint128 depositAmount,
        uint128 withdrawAmount
    ) public {
        depositAmount = uint128(bound(depositAmount, 0.01 ether, 50 ether));
        withdrawAmount = uint128(
            bound(withdrawAmount, 0.001 ether, depositAmount)
        );

        // Deposit first
        vm.prank(pegInLp);
        pegInContract.deposit{value: depositAmount}();

        uint256 contractBalanceBefore = address(pegInContract).balance;
        uint256 lpBalanceBefore = pegInLp.balance;

        // Expect Withdrawal event
        vm.expectEmit(true, true, false, true);
        emit IPegIn.Withdrawal(pegInLp, withdrawAmount);

        vm.prank(pegInLp);
        pegInContract.withdraw(withdrawAmount);

        // Verify contract balance decreased
        assertEq(
            address(pegInContract).balance,
            contractBalanceBefore - withdrawAmount,
            "Contract balance should decrease by withdrawal amount"
        );

        // Verify LP external balance increased
        assertEq(
            pegInLp.balance,
            lpBalanceBefore + withdrawAmount,
            "LP external balance should increase by withdrawal amount"
        );

        // Verify LP internal balance decreased
        assertEq(
            pegInContract.getBalance(pegInLp),
            depositAmount - withdrawAmount,
            "LP internal balance should decrease by withdrawal amount"
        );
    }

    /// @notice Fuzz test: Withdrawing more than balance should revert
    function testFuzz_Withdraw_RevertsOnInsufficientBalance(
        uint128 depositAmount,
        uint128 extraAmount
    ) public {
        depositAmount = uint128(bound(depositAmount, 0.001 ether, 10 ether));
        extraAmount = uint128(bound(extraAmount, 1, 10 ether));

        // Deposit first
        vm.prank(pegInLp);
        pegInContract.deposit{value: depositAmount}();

        uint256 withdrawAmount = uint256(depositAmount) + uint256(extraAmount);

        vm.prank(pegInLp);
        vm.expectRevert(
            abi.encodeWithSelector(
                Flyover.NoBalance.selector,
                withdrawAmount,
                depositAmount
            )
        );
        pegInContract.withdraw(withdrawAmount);
    }

    /// @notice Fuzz test: Multiple partial withdrawals should work correctly
    function testFuzz_Withdraw_MultiplePartialWithdrawals(
        uint128 depositAmount,
        uint64 withdraw1Percent,
        uint64 withdraw2Percent
    ) public {
        depositAmount = uint128(bound(depositAmount, 1 ether, 50 ether));
        withdraw1Percent = uint64(bound(withdraw1Percent, 1, 40)); // 1-40%
        withdraw2Percent = uint64(bound(withdraw2Percent, 1, 40)); // 1-40%

        // Deposit first
        vm.prank(fullLp);
        pegInContract.deposit{value: depositAmount}();

        uint256 withdraw1 = (uint256(depositAmount) * withdraw1Percent) / 100;
        uint256 withdraw2 = (uint256(depositAmount) * withdraw2Percent) / 100;
        uint256 expectedRemaining = depositAmount - withdraw1 - withdraw2;

        vm.startPrank(fullLp);
        pegInContract.withdraw(withdraw1);
        pegInContract.withdraw(withdraw2);
        vm.stopPrank();

        assertEq(
            pegInContract.getBalance(fullLp),
            expectedRemaining,
            "Balance should equal deposit minus withdrawals"
        );
    }

    /// @notice Fuzz test: Full withdrawal should leave zero balance
    function testFuzz_Withdraw_FullWithdrawalLeavesZeroBalance(
        uint128 depositAmount
    ) public {
        depositAmount = uint128(bound(depositAmount, 0.001 ether, 50 ether));

        // Deposit first
        vm.prank(pegInLp);
        pegInContract.deposit{value: depositAmount}();

        // Withdraw full amount
        vm.prank(pegInLp);
        pegInContract.withdraw(depositAmount);

        assertEq(
            pegInContract.getBalance(pegInLp),
            0,
            "Balance should be zero after full withdrawal"
        );
    }

    /// @notice Fuzz test: Deposit and withdraw cycles should track correctly
    function testFuzz_DepositWithdraw_CycleTracksCorrectly(
        uint64 deposit1,
        uint64 withdraw1,
        uint64 deposit2
    ) public {
        deposit1 = uint64(bound(deposit1, 0.1 ether, 10 ether));
        withdraw1 = uint64(bound(withdraw1, 0.01 ether, deposit1 - 0.01 ether));
        deposit2 = uint64(bound(deposit2, 0.1 ether, 10 ether));

        vm.assume(deposit1 > withdraw1);

        vm.startPrank(fullLp);

        // Deposit 1
        pegInContract.deposit{value: deposit1}();
        assertEq(pegInContract.getBalance(fullLp), deposit1);

        // Withdraw
        pegInContract.withdraw(withdraw1);
        assertEq(pegInContract.getBalance(fullLp), deposit1 - withdraw1);

        // Deposit 2
        pegInContract.deposit{value: deposit2}();
        assertEq(
            pegInContract.getBalance(fullLp),
            uint256(deposit1) - uint256(withdraw1) + uint256(deposit2)
        );

        vm.stopPrank();
    }
}
