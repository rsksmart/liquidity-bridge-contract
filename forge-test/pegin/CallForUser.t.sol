// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {PegInTestBase} from "./PegInTestBase.sol";
import {IPegIn} from "../../contracts/interfaces/IPegIn.sol";
import {Quotes} from "../../contracts/libraries/Quotes.sol";
import {Flyover} from "../../contracts/libraries/Flyover.sol";

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
        assertEq(user.balance, userBalanceBefore + 0.6 ether, "User should receive value");
        assertEq(address(pegInContract).balance, contractBalanceBefore - 0.6 ether, "Contract balance should decrease");
        assertEq(pegInContract.getBalance(pegInLp), 0.4 ether, "LP balance should be reduced");

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
        assertEq(user.balance, userBalanceBefore + 0.6 ether, "User should receive quote value");
        // LP balance in contract should be remainder
        assertEq(pegInContract.getBalance(pegInLp), 0.4 ether, "LP balance should store remainder");

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
        assertEq(user.balance, userBalanceBefore + 0.6 ether, "User should receive quote value");
        // Total: 0.3 + 0.4 = 0.7 ether, sends 0.6 to user, 0.1 remains
        assertEq(pegInContract.getBalance(pegInLp), 0.1 ether, "LP should have 0.1 ether remaining");

        // Verify quote status
        assertEq(
            uint256(pegInContract.getQuoteStatus(quoteHash)),
            uint256(IPegIn.PegInStates.CALL_DONE),
            "Quote should be marked as CALL_DONE"
        );
    }

    function test_CallForUser_SendsRBTCToEOASuccessfully() public {
        Quotes.PegInQuote memory quote = createTestQuoteForLP(0.5 ether, user, user, fullLp);

        bytes32 quoteHash = pegInContract.hashPegInQuote(quote);
        uint256 userBalanceBefore = user.balance;

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
        assertEq(user.balance, userBalanceBefore + 0.5 ether, "User should receive value");
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
            abi.encodeWithSelector(Flyover.ProviderNotRegistered.selector, pegOutLp)
        );
        pegInContract.callForUser{value: 0.6 ether}(quote);
    }

    function test_CallForUser_RevertsIfQuoteDoesNotBelongToLP() public {
        Quotes.PegInQuote memory quote = createTestQuote(0.6 ether, user, user);
        quote.liquidityProviderRskAddress = fullLp;

        // pegInLp tries to call but quote specifies fullLp
        vm.prank(pegInLp);
        vm.expectRevert(
            abi.encodeWithSelector(Flyover.InvalidSender.selector, fullLp, pegInLp)
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
            abi.encodeWithSelector(Flyover.InsufficientAmount.selector, 0.5 ether, 0.6 ether)
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
            abi.encodeWithSelector(IPegIn.QuoteAlreadyProcessed.selector, quoteHash)
        );
        pegInContract.callForUser{value: 0.6 ether}(quote);
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
        bytes memory testBtcAddress = new bytes(21);

        return Quotes.PegInQuote({
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
            data: new bytes(0)
        });
    }
}
