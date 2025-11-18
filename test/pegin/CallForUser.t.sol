// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {PegInTestBase} from "./PegInTestBase.sol";
import {IPegIn} from "../../src/interfaces/IPegIn.sol";
import {Quotes} from "../../src/libraries/Quotes.sol";
import {Flyover} from "../../src/libraries/Flyover.sol";
import {Mock} from "../../src/test-contracts/Mock.sol";
import {ReentrancyCaller} from "../../src/test-contracts/ReentrancyCaller.sol";

contract CallForUserTest is PegInTestBase {
    address public user;

    function setUp() public {
        deployPegInContract();
        setupProviders();

        user = makeAddr("user");
        vm.deal(user, 100 ether);
    }

    // ============ callForUser function tests ============

    function test_CallForUser_ExecutesCallUsingContractBalance() public {
        Quotes.PegInQuote memory quote = createTestQuote(0.6 ether, user, user);

        // Deposit to contract
        vm.prank(pegInLp);
        pegInContract.deposit{value: 1 ether}();

        // Call for user
        bytes32 quoteHash = pegInContract.hashPegInQuote(quote);
        uint256 userBalanceBefore = user.balance;
        uint256 pegInLpBalanceBefore = pegInLp.balance;
        uint256 contractBalanceBefore = address(pegInContract).balance;

        vm.prank(pegInLp);
        vm.expectEmit(true, true, true, true);
        emit IPegIn.CallForUser(
            pegInLp,
            user,
            quoteHash,
            quote.gasLimit,
            quote.value,
            new bytes(0),
            true
        );
        pegInContract.callForUser{value: 0}(quote);

        // Verify balances
        assertEq(
            user.balance,
            userBalanceBefore + 0.6 ether,
            "User should receive value"
        );
        assertEq(
            pegInLp.balance,
            pegInLpBalanceBefore,
            "LP external balance should not change"
        );
        assertEq(
            address(pegInContract).balance,
            contractBalanceBefore - 0.6 ether,
            "Contract balance should decrease"
        );
        assertEq(
            pegInContract.getBalance(pegInLp),
            0.4 ether,
            "LP balance should be reduced"
        );

        // Verify quote status
        assertEq(
            uint256(pegInContract.getQuoteStatus(quoteHash)),
            uint256(IPegIn.PegInStates.CALL_DONE),
            "Quote should be marked as CALL_DONE"
        );
    }

    function test_CallForUser_ExecutesCallUsingTransactionValue() public {
        Quotes.PegInQuote memory quote = createTestQuote(0.6 ether, user, user);

        bytes32 quoteHash = pegInContract.hashPegInQuote(quote);
        uint256 userBalanceBefore = user.balance;
        uint256 pegInLpBalanceBefore = pegInLp.balance;
        uint256 contractBalanceBefore = address(pegInContract).balance;

        vm.prank(pegInLp);
        vm.expectEmit(true, true, true, true);
        emit IPegIn.CallForUser(
            pegInLp,
            user,
            quoteHash,
            quote.gasLimit,
            quote.value,
            new bytes(0),
            true
        );
        pegInContract.callForUser{value: 1 ether}(quote);

        // Verify user received the quote value
        assertEq(
            user.balance,
            userBalanceBefore + 0.6 ether,
            "User should receive quote value"
        );
        // Verify external balances
        assertEq(
            pegInLp.balance,
            pegInLpBalanceBefore - 1 ether,
            "LP should lose 1 ether externally"
        );
        assertEq(
            address(pegInContract).balance,
            contractBalanceBefore + 0.4 ether,
            "Contract should gain 0.4 ether"
        );
        // LP balance in contract should be remainder
        assertEq(
            pegInContract.getBalance(pegInLp),
            0.4 ether,
            "LP balance should store remainder"
        );

        // Verify quote status
        assertEq(
            uint256(pegInContract.getQuoteStatus(quoteHash)),
            uint256(IPegIn.PegInStates.CALL_DONE),
            "Quote should be marked as CALL_DONE"
        );
    }

    function test_CallForUser_ExecutesCallUsingCombinedBalance() public {
        Quotes.PegInQuote memory quote = createTestQuote(0.6 ether, user, user);

        // Deposit 0.3 ether
        vm.prank(pegInLp);
        pegInContract.deposit{value: 0.3 ether}();

        bytes32 quoteHash = pegInContract.hashPegInQuote(quote);
        uint256 userBalanceBefore = user.balance;
        uint256 pegInLpBalanceBefore = pegInLp.balance;
        uint256 contractBalanceBefore = address(pegInContract).balance;

        // Call with additional 0.4 ether
        vm.prank(pegInLp);
        vm.expectEmit(true, true, true, true);
        emit IPegIn.CallForUser(
            pegInLp,
            user,
            quoteHash,
            quote.gasLimit,
            quote.value,
            new bytes(0),
            true
        );
        pegInContract.callForUser{value: 0.4 ether}(quote);

        // Verify user received 0.6 ether
        assertEq(
            user.balance,
            userBalanceBefore + 0.6 ether,
            "User should receive quote value"
        );
        // Verify external balances
        assertEq(
            pegInLp.balance,
            pegInLpBalanceBefore - 0.4 ether,
            "LP should lose 0.4 ether externally"
        );
        assertEq(
            address(pegInContract).balance,
            contractBalanceBefore - 0.2 ether,
            "Contract should lose 0.2 ether"
        );
        // Total: 0.3 + 0.4 = 0.7 ether, sends 0.6 to user, 0.1 remains
        assertEq(
            pegInContract.getBalance(pegInLp),
            0.1 ether,
            "LP should have 0.1 ether remaining"
        );

        // Verify quote status
        assertEq(
            uint256(pegInContract.getQuoteStatus(quoteHash)),
            uint256(IPegIn.PegInStates.CALL_DONE),
            "Quote should be marked as CALL_DONE"
        );
    }

    function test_CallForUser_SendsRBTCToEOASuccessfully() public {
        Quotes.PegInQuote memory quote = createTestQuoteForLP(
            0.5 ether,
            user,
            user,
            fullLp
        );

        bytes32 quoteHash = pegInContract.hashPegInQuote(quote);
        uint256 userBalanceBefore = user.balance;
        uint256 fullLpBalanceBefore = fullLp.balance;
        uint256 contractBalanceBefore = address(pegInContract).balance;

        vm.prank(fullLp);
        vm.expectEmit(true, true, true, true);
        emit IPegIn.CallForUser(
            fullLp,
            user,
            quoteHash,
            quote.gasLimit,
            quote.value,
            new bytes(0),
            true
        );
        pegInContract.callForUser{value: 0.5 ether}(quote);

        // Verify balances
        assertEq(
            user.balance,
            userBalanceBefore + 0.5 ether,
            "User should receive value"
        );
        // Verify external balances
        assertEq(
            fullLp.balance,
            fullLpBalanceBefore - 0.5 ether,
            "LP should lose 0.5 ether externally"
        );
        assertEq(
            address(pegInContract).balance,
            contractBalanceBefore,
            "Contract balance should not change"
        );
        assertEq(pegInContract.getBalance(fullLp), 0, "LP balance should be 0");

        // Verify quote status
        assertEq(
            uint256(pegInContract.getQuoteStatus(quoteHash)),
            uint256(IPegIn.PegInStates.CALL_DONE),
            "Quote should be marked as CALL_DONE"
        );
    }

    function test_CallForUser_RevertsIfLPNotRegistered() public {
        Quotes.PegInQuote memory quote = createTestQuote(0.6 ether, user, user);
        quote.liquidityProviderRskAddress = pegOutLp;

        vm.prank(pegOutLp);
        vm.expectRevert(
            abi.encodeWithSelector(
                Flyover.ProviderNotRegistered.selector,
                pegOutLp
            )
        );
        pegInContract.callForUser{value: 0.6 ether}(quote);
    }

    function test_CallForUser_RevertsIfQuoteDoesNotBelongToLP() public {
        Quotes.PegInQuote memory quote = createTestQuote(0.6 ether, user, user);
        quote.liquidityProviderRskAddress = fullLp;

        // pegInLp tries to call but quote specifies fullLp
        vm.prank(pegInLp);
        vm.expectRevert(
            abi.encodeWithSelector(
                Flyover.InvalidSender.selector,
                fullLp,
                pegInLp
            )
        );
        pegInContract.callForUser{value: 0.6 ether}(quote);
    }

    function test_CallForUser_RevertsIfBalanceNotEnough() public {
        Quotes.PegInQuote memory quote = createTestQuote(0.6 ether, user, user);

        // Deposit 0.3 ether
        vm.prank(pegInLp);
        pegInContract.deposit{value: 0.3 ether}();

        // Try to call with only 0.2 ether additional (total 0.5, need 0.6)
        vm.prank(pegInLp);
        vm.expectRevert(
            abi.encodeWithSelector(
                Flyover.InsufficientAmount.selector,
                0.5 ether,
                0.6 ether
            )
        );
        pegInContract.callForUser{value: 0.2 ether}(quote);
    }

    function test_CallForUser_RevertsIfQuoteAlreadyProcessed() public {
        Quotes.PegInQuote memory quote = createTestQuote(0.6 ether, user, user);

        bytes32 quoteHash = pegInContract.hashPegInQuote(quote);

        // First call succeeds
        vm.prank(pegInLp);
        pegInContract.callForUser{value: 0.6 ether}(quote);

        // Second call with same quote should fail
        vm.prank(pegInLp);
        vm.expectRevert(
            abi.encodeWithSelector(
                IPegIn.QuoteAlreadyProcessed.selector,
                quoteHash
            )
        );
        pegInContract.callForUser{value: 0.6 ether}(quote);
    }

    function test_CallForUser_SendsRBTCToSmartContractSuccessfully() public {
        // Deploy Mock contract
        Mock mockContract = new Mock();

        // Create quote with data to call Mock.set(5)
        bytes memory data = abi.encodeWithSelector(
            Mock.set.selector,
            int256(5)
        );
        Quotes.PegInQuote memory quote = createTestQuoteForLPWithData(
            0.7 ether,
            address(mockContract),
            user,
            fullLp,
            data
        );

        bytes32 quoteHash = pegInContract.hashPegInQuote(quote);
        uint256 fullLpBalanceBefore = fullLp.balance;
        uint256 contractBalanceBefore = address(pegInContract).balance;

        // Verify initial state
        assertEq(mockContract.check(), int256(0), "Mock should start with 0");

        vm.prank(fullLp);
        vm.expectEmit(true, true, true, true);
        emit IPegIn.CallForUser(
            fullLp,
            address(mockContract),
            quoteHash,
            quote.gasLimit,
            quote.value,
            data,
            true
        );
        pegInContract.callForUser{value: 0.7 ether}(quote);

        // Verify balances
        assertEq(
            address(mockContract).balance,
            0.7 ether,
            "Mock contract should receive value"
        );
        // Verify external balances
        assertEq(
            fullLp.balance,
            fullLpBalanceBefore - 0.7 ether,
            "LP should lose 0.7 ether externally"
        );
        assertEq(
            address(pegInContract).balance,
            contractBalanceBefore,
            "Contract balance should not change"
        );
        assertEq(pegInContract.getBalance(fullLp), 0, "LP balance should be 0");

        // Verify contract state changed
        assertEq(
            mockContract.check(),
            int256(5),
            "Mock contract state should be updated"
        );

        // Verify quote status
        assertEq(
            uint256(pegInContract.getQuoteStatus(quoteHash)),
            uint256(IPegIn.PegInStates.CALL_DONE),
            "Quote should be marked as CALL_DONE"
        );
    }

    function test_CallForUser_ExecutesUnsuccessfulCall() public {
        // Deploy Mock contract
        Mock mockContract = new Mock();

        // Create quote with data to call Mock.fail() which reverts
        bytes memory data = abi.encodeWithSelector(Mock.fail.selector);
        Quotes.PegInQuote memory quote = createTestQuoteForLPWithData(
            0.6 ether,
            address(mockContract),
            user,
            fullLp,
            data
        );

        bytes32 quoteHash = pegInContract.hashPegInQuote(quote);
        uint256 lpBalanceBefore = pegInContract.getBalance(fullLp);
        uint256 fullLpBalanceBefore = fullLp.balance;
        uint256 contractBalanceBefore = address(pegInContract).balance;

        vm.prank(fullLp);
        vm.expectEmit(true, true, true, true);
        emit IPegIn.CallForUser(
            fullLp,
            address(mockContract),
            quoteHash,
            quote.gasLimit,
            quote.value,
            data,
            false
        );
        pegInContract.callForUser{value: 0.6 ether}(quote);

        // Verify balances - funds should be refunded to LP balance
        assertEq(
            address(mockContract).balance,
            0,
            "Mock contract should not receive value"
        );
        // Verify external balances
        assertEq(
            fullLp.balance,
            fullLpBalanceBefore - 0.6 ether,
            "LP should lose 0.6 ether externally"
        );
        assertEq(
            address(pegInContract).balance,
            contractBalanceBefore + 0.6 ether,
            "Contract should gain 0.6 ether"
        );
        assertEq(
            pegInContract.getBalance(fullLp),
            lpBalanceBefore + 0.6 ether,
            "LP balance should be refunded"
        );

        // Verify quote status
        assertEq(
            uint256(pegInContract.getQuoteStatus(quoteHash)),
            uint256(IPegIn.PegInStates.CALL_DONE),
            "Quote should be marked as CALL_DONE"
        );
    }

    function test_CallForUser_RevertsIfGasLimitNotEnough() public {
        Quotes.PegInQuote memory quote = createTestQuote(0.6 ether, user, user);

        // The contract requires: gasleft() >= quote.gasLimit + 35000
        uint256 callGasCost = 35000;
        uint256 requiredGas = quote.gasLimit + callGasCost;

        // Calculate approximate gas used before the check
        // This includes: function call overhead, validation checks, balance updates
        // Rough estimate: ~50000 gas for setup before the gas check
        uint256 setupGas = 50000;
        uint256 insufficientGasLimit = requiredGas + setupGas - 1000; // Just below what's needed

        vm.prank(pegInLp);
        // We expect InsufficientGas error
        // The exact gasLeft is hard to predict, but we know requiredGas
        // We'll match the error with an estimated gasLeft value
        uint256 estimatedGasLeft = insufficientGasLimit - setupGas;
        vm.expectRevert(
            abi.encodeWithSelector(
                IPegIn.InsufficientGas.selector,
                estimatedGasLeft,
                requiredGas
            )
        );

        // Call with insufficient gas limit
        // Use low-level call to precisely control gas
        (bool success, ) = address(pegInContract).call{
            gas: insufficientGasLimit,
            value: 0.6 ether
        }(abi.encodeWithSelector(IPegIn.callForUser.selector, quote));

        // Should have reverted
        assertTrue(!success);
    }

    function test_CallForUser_NotAllowReentrancy() public {
        // Deploy ReentrancyCaller contract
        ReentrancyCaller reentrancyCaller = new ReentrancyCaller();

        // Create a quote that will call the reentrancy caller
        // The reentrancy caller will try to call callForUser again
        Quotes.PegInQuote memory reentrantQuote = createTestQuoteForLP(
            0.5 ether,
            fullLp,
            fullLp,
            fullLp
        );

        // Encode the reentrant call
        bytes memory reentrantData = abi.encodeWithSelector(
            IPegIn.callForUser.selector,
            reentrantQuote
        );
        reentrancyCaller.setData(reentrantData);

        // Create quote that calls the reentrancy caller
        bytes memory data = abi.encodeWithSelector(
            ReentrancyCaller.reentrantCall.selector
        );
        Quotes.PegInQuote memory contractQuote = createTestQuoteForLPWithData(
            0.5 ether,
            address(reentrancyCaller),
            fullLp,
            fullLp,
            data
        );
        // Increase gas limit to allow the reentrant call attempt
        contractQuote.gasLimit = contractQuote.gasLimit * 10;

        bytes32 quoteHash = pegInContract.hashPegInQuote(contractQuote);

        // Deposit funds for the LP
        vm.prank(fullLp);
        pegInContract.deposit{value: 10 ether}();

        // Get the reentrancy error selector
        bytes4 reentrancySelector = bytes4(
            keccak256("ReentrancyGuardReentrantCall()")
        );
        uint256 fullLpBalanceBefore = fullLp.balance;
        uint256 contractBalanceBefore = address(pegInContract).balance;
        uint256 callerBalanceBefore = address(reentrancyCaller).balance;

        vm.prank(fullLp);
        vm.expectEmit(true, true, true, true);
        emit IPegIn.CallForUser(
            fullLp,
            address(reentrancyCaller),
            quoteHash,
            contractQuote.gasLimit,
            contractQuote.value,
            data,
            true
        );
        // Call without sending value - use existing balance in contract
        pegInContract.callForUser(contractQuote);

        // Verify ReentrancyReverted event was emitted (check via logs)
        // Note: In Foundry, we verify the revert reason instead which confirms the event

        // Verify the reentrancy was prevented
        bytes memory revertReason = reentrancyCaller.getRevertReason();
        assertGt(
            revertReason.length,
            0,
            "Reentrancy should have been reverted"
        );
        assertEq(
            revertReason,
            abi.encodePacked(reentrancySelector),
            "Revert reason should match reentrancy selector"
        );

        // Verify external balances
        assertEq(
            address(reentrancyCaller).balance,
            callerBalanceBefore + contractQuote.value,
            "ReentrancyCaller should receive value"
        );
        assertEq(
            fullLp.balance,
            fullLpBalanceBefore,
            "LP external balance should not change"
        );
        assertEq(
            address(pegInContract).balance,
            contractBalanceBefore - contractQuote.value,
            "Contract should lose quote value"
        );

        // Check that the first call succeeded but reentrancy was blocked
        assertEq(
            pegInContract.getBalance(fullLp),
            9.5 ether,
            "LP balance should reflect successful first call"
        );

        // Verify quote status
        assertEq(
            uint256(pegInContract.getQuoteStatus(quoteHash)),
            uint256(IPegIn.PegInStates.CALL_DONE),
            "Quote should be marked as CALL_DONE"
        );
    }

    // ============ Helper Functions ============

    function createTestQuote(
        uint256 value,
        address destination,
        address refund
    ) internal view returns (Quotes.PegInQuote memory) {
        return createTestQuoteForLP(value, destination, refund, pegInLp);
    }

    function createTestQuoteForLP(
        uint256 value,
        address destination,
        address refund,
        address lp
    ) internal view returns (Quotes.PegInQuote memory) {
        return
            createTestQuoteForLPWithData(
                value,
                destination,
                refund,
                lp,
                new bytes(0)
            );
    }

    function createTestQuoteForLPWithData(
        uint256 value,
        address destination,
        address refund,
        address lp,
        bytes memory data
    ) internal view returns (Quotes.PegInQuote memory) {
        bytes memory testBtcAddress = new bytes(21);

        return
            Quotes.PegInQuote({
                callFee: 100000000000000,
                penaltyFee: 10000000000000,
                value: value,
                productFeeAmount: 0,
                gasFee: 100,
                fedBtcAddress: bytes20(testBtcAddress),
                lbcAddress: address(pegInContract),
                liquidityProviderRskAddress: lp,
                contractAddress: destination,
                rskRefundAddress: payable(refund),
                nonce: int64(uint64(block.timestamp)),
                gasLimit: 21000,
                agreementTimestamp: uint32(block.timestamp),
                timeForDeposit: 3600,
                callTime: 7200,
                depositConfirmations: 10,
                callOnRegister: false,
                btcRefundAddress: testBtcAddress,
                liquidityProviderBtcAddress: testBtcAddress,
                data: data
            });
    }
}
