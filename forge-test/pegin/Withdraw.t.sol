// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {PegInTestBase} from "./PegInTestBase.sol";
import {IPegIn} from "../../contracts/interfaces/IPegIn.sol";
import {Flyover} from "../../contracts/libraries/Flyover.sol";
import {WalletMock} from "../../contracts/test-contracts/WalletMock.sol";
import {CollateralManagementContract} from "../../contracts/CollateralManagement.sol";
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

    function test_Withdraw_RevertsIfWithdrawalFails() public {
        // Deploy a WalletMock that will reject payments
        WalletMock walletMock = new WalletMock();

        // Deploy a mock CollateralManagement (no registration check)
        CollateralManagementContract mockCM = new CollateralManagementContract();
        bytes memory initData = abi.encodeCall(
            CollateralManagementContract.initialize,
            (
                owner,
                TEST_DEFAULT_ADMIN_DELAY,
                TEST_MIN_COLLATERAL,
                TEST_RESIGN_DELAY_BLOCKS,
                TEST_REWARD_PERCENTAGE
            )
        );
        ERC1967Proxy mockCMProxy = new ERC1967Proxy(address(mockCM), initData);

        // Set the mock CollateralManagement
        vm.warp(block.timestamp + TEST_DEFAULT_ADMIN_DELAY + 1);
        vm.prank(owner);
        pegInContract.setCollateralManagement(address(mockCMProxy));

        // Wallet deposits via execute
        uint256 depositAmount = 0.1 ether;
        vm.deal(address(walletMock), 10 ether);
        bytes memory depositData = abi.encodeWithSelector(
            pegInContract.deposit.selector
        );
        walletMock.execute{value: depositAmount}(
            address(pegInContract),
            depositAmount,
            depositData
        );

        // Set wallet to reject funds
        walletMock.setRejectFunds(true);

        // Try to withdraw - should fail
        bytes memory withdrawData = abi.encodeWithSelector(
            pegInContract.withdraw.selector,
            depositAmount
        );

        vm.expectEmit(true, true, false, false);
        emit WalletMock.TransactionRejected(
            address(pegInContract),
            0,
            bytes("")
        );
        walletMock.execute(address(pegInContract), 0, withdrawData);
    }
}
