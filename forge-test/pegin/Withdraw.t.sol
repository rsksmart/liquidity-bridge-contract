// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {PegInTestBase} from "./PegInTestBase.sol";
import {IPegIn} from "../../contracts/interfaces/IPegIn.sol";
import {Flyover} from "../../contracts/libraries/Flyover.sol";
import {WalletMock} from "../../contracts/test-contracts/WalletMock.sol";
import {WithdrawReceiver} from "../../contracts/test-contracts/WithdrawReceiver.sol";
import {CollateralManagementContract} from "../../contracts/CollateralManagement.sol";
import {CollateralManagementMock} from "../../contracts/test-contracts/CollateralManagementMock.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract WithdrawTest is PegInTestBase {
    function setUp() public {
        deployPegInContract();
        setupProviders();
    }

    // ============ withdraw function tests ============

    function test_Withdraw_DoesNotAllowWithdrawMoreThanCurrentBalance() public {
        uint256 depositedAmount = 1 ether;
        uint256 withdrawAmount = 1.000000000000000001 ether;

        // Deposit
        vm.prank(fullLp);
        pegInContract.deposit{value: depositedAmount}();

        // Try to withdraw more than deposited
        vm.prank(fullLp);
        vm.expectRevert(
            abi.encodeWithSelector(
                Flyover.NoBalance.selector,
                withdrawAmount,
                depositedAmount
            )
        );
        pegInContract.withdraw(withdrawAmount);
    }

    function test_Withdraw_AllowsToWithdrawEverything() public {
        uint256 balance = 1 ether;

        // Deposit
        vm.prank(fullLp);
        pegInContract.deposit{value: balance}();

        // Withdraw everything
        vm.prank(fullLp);
        vm.expectEmit(true, true, false, true);
        emit IPegIn.BalanceDecrease(fullLp, balance);
        vm.expectEmit(true, true, false, true);
        emit IPegIn.Withdrawal(fullLp, balance);
        pegInContract.withdraw(balance);

        // Verify balance is 0
        assertEq(pegInContract.getBalance(fullLp), 0, "Balance should be 0");
    }

    function test_Withdraw_DecreasesBalanceProperly() public {
        uint256 balance = 1 ether;
        uint256 withdrawAmount = 0.2 ether;

        // Deposit
        vm.prank(fullLp);
        pegInContract.deposit{value: balance}();

        // Withdraw partial amount
        vm.prank(fullLp);
        vm.expectEmit(true, true, false, true);
        emit IPegIn.BalanceDecrease(fullLp, withdrawAmount);
        vm.expectEmit(true, true, false, true);
        emit IPegIn.Withdrawal(fullLp, withdrawAmount);
        pegInContract.withdraw(withdrawAmount);

        // Verify remaining balance
        assertEq(
            pegInContract.getBalance(fullLp),
            0.8 ether,
            "Balance should be 0.8 ether"
        );
    }

    function test_Withdraw_RevertsIfWithdrawalPaymentFails() public {
        // Deploy a mock CollateralManagement (allows any address to deposit without registration)
        CollateralManagementMock mockCM = new CollateralManagementMock();

        // Set the mock CollateralManagement
        vm.warp(block.timestamp + TEST_DEFAULT_ADMIN_DELAY + 1);
        vm.prank(owner);
        pegInContract.setCollateralManagement(address(mockCM));

        // Deploy WithdrawReceiver that will reject payments
        WithdrawReceiver receiver = new WithdrawReceiver(
            address(pegInContract)
        );
        address receiverAddress = address(receiver);

        // Deposit via receiver
        uint256 withdrawAmount = 0.1 ether;
        vm.deal(receiverAddress, 10 ether);
        vm.prank(receiverAddress);
        receiver.deposit{value: withdrawAmount}();

        // Set receiver to reject funds
        vm.prank(receiverAddress);
        receiver.setFail(true);

        // Try to withdraw - should fail with PaymentFailed
        vm.prank(receiverAddress);
        vm.expectRevert(
            abi.encodeWithSelector(
                Flyover.PaymentFailed.selector,
                receiverAddress,
                withdrawAmount,
                abi.encodeWithSelector(WithdrawReceiver.SomeError.selector)
            )
        );
        receiver.withdraw(withdrawAmount);
    }

    function test_Withdraw_RevertsOnReentrancy() public {
        // Deploy a mock CollateralManagement (allows any address to deposit without registration)
        CollateralManagementMock mockCM = new CollateralManagementMock();

        // Set the mock CollateralManagement
        vm.warp(block.timestamp + TEST_DEFAULT_ADMIN_DELAY + 1);
        vm.prank(owner);
        pegInContract.setCollateralManagement(address(mockCM));

        // Deploy WithdrawReceiver that will attempt reentrancy
        WithdrawReceiver receiver = new WithdrawReceiver(
            address(pegInContract)
        );
        address receiverAddress = address(receiver);

        // Deposit via receiver
        uint256 withdrawAmount = 0.1 ether;
        vm.deal(receiverAddress, 10 ether);
        vm.prank(receiverAddress);
        receiver.deposit{value: withdrawAmount}();

        // Set receiver to NOT fail (will attempt reentrancy instead)
        vm.prank(receiverAddress);
        receiver.setFail(false);

        // Try to withdraw - receiver will attempt reentrancy in its receive()
        // This should revert with ReentrancyGuardReentrantCall
        vm.prank(receiverAddress);
        vm.expectRevert(
            abi.encodeWithSelector(
                Flyover.PaymentFailed.selector,
                receiverAddress,
                withdrawAmount,
                abi.encodeWithSignature("ReentrancyGuardReentrantCall()")
            )
        );
        receiver.withdraw(withdrawAmount);
    }
}
