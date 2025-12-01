// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {PegInFuzzTestBase} from "./PegInFuzzTestBase.sol";
import {Quotes} from "../../../src/libraries/Quotes.sol";
import {IPegIn} from "../../../src/interfaces/IPegIn.sol";
import {Flyover} from "../../../src/libraries/Flyover.sol";

/// @title PegIn CallForUser Fuzz Tests
/// @notice Fuzz tests for the PegIn callForUser functionality
contract PegInCallForUserFuzzTest is PegInFuzzTestBase {
    function setUp() public {
        deployPegInContract();
        setupProviders();

        fuzzUser = makeAddr("user");
        vm.deal(fuzzUser, 1000 ether);
    }

    // ============ CallForUser Success Tests ============

    /// @notice Fuzz test: CallForUser with contract balance should succeed
    function testFuzz_CallForUser_ExecutesWithContractBalance(
        uint128 depositAmount,
        uint128 callValue
    ) public {
        depositAmount = uint128(bound(depositAmount, TEST_MIN_PEGIN, 50 ether));
        callValue = uint128(bound(callValue, TEST_MIN_PEGIN, depositAmount));

        // Deposit first
        vm.prank(pegInLp);
        pegInContract.deposit{value: depositAmount}();

        Quotes.PegInQuote memory quote = createFuzzTestQuoteWithDestination(
            callValue,
            fuzzUser,
            fuzzUser
        );

        bytes32 quoteHash = pegInContract.hashPegInQuote(quote);
        uint256 userBalanceBefore = fuzzUser.balance;
        uint256 lpInternalBalanceBefore = pegInContract.getBalance(pegInLp);

        // Expect CallForUser event with success=true
        vm.expectEmit(true, true, true, true);
        emit IPegIn.CallForUser(
            pegInLp,
            fuzzUser,
            quoteHash,
            quote.gasLimit,
            quote.value,
            new bytes(0),
            true
        );

        vm.prank(pegInLp);
        bool success = pegInContract.callForUser{value: 0}(quote);

        assertTrue(success, "Call should succeed");

        // User should receive the value
        assertEq(
            fuzzUser.balance,
            userBalanceBefore + callValue,
            "User should receive the call value"
        );

        // LP internal balance should decrease
        assertEq(
            pegInContract.getBalance(pegInLp),
            lpInternalBalanceBefore - callValue,
            "LP internal balance should decrease by call value"
        );

        // Quote should be marked as CALL_DONE
        assertEq(
            uint256(pegInContract.getQuoteStatus(quoteHash)),
            uint256(IPegIn.PegInStates.CALL_DONE),
            "Quote should be marked as CALL_DONE"
        );
    }

    /// @notice Fuzz test: CallForUser with transaction value should succeed
    function testFuzz_CallForUser_ExecutesWithTransactionValue(
        uint128 callValue
    ) public {
        callValue = uint128(bound(callValue, TEST_MIN_PEGIN, 50 ether));

        Quotes.PegInQuote memory quote = createFuzzTestQuoteWithDestination(
            callValue,
            fuzzUser,
            fuzzUser
        );

        bytes32 quoteHash = pegInContract.hashPegInQuote(quote);
        uint256 userBalanceBefore = fuzzUser.balance;
        uint256 lpExternalBalanceBefore = pegInLp.balance;

        vm.expectEmit(true, true, true, true);
        emit IPegIn.CallForUser(
            pegInLp,
            fuzzUser,
            quoteHash,
            quote.gasLimit,
            quote.value,
            new bytes(0),
            true
        );

        // Send exactly the call value
        vm.prank(pegInLp);
        bool success = pegInContract.callForUser{value: callValue}(quote);

        assertTrue(success, "Call should succeed");

        // User should receive the value
        assertEq(
            fuzzUser.balance,
            userBalanceBefore + callValue,
            "User should receive the call value"
        );

        // LP should have spent the call value externally
        assertEq(
            pegInLp.balance,
            lpExternalBalanceBefore - callValue,
            "LP external balance should decrease by call value"
        );
    }

    /// @notice Fuzz test: CallForUser with combined balance should succeed
    function testFuzz_CallForUser_ExecutesWithCombinedBalance(
        uint128 depositAmount,
        uint128 txValue
    ) public {
        // Ensure combined balance is above minimum peg in
        depositAmount = uint128(bound(depositAmount, 0.1 ether, 10 ether));
        txValue = uint128(bound(txValue, 0.1 ether, 10 ether));

        uint256 totalAvailable = uint256(depositAmount) + uint256(txValue);
        // callValue must be at least TEST_MIN_PEGIN for the quote to be valid
        uint256 callValue = TEST_MIN_PEGIN + 0.1 ether;
        vm.assume(totalAvailable >= callValue);

        // Deposit first
        vm.prank(pegInLp);
        pegInContract.deposit{value: depositAmount}();

        Quotes.PegInQuote memory quote = createFuzzTestQuoteWithDestination(
            callValue,
            fuzzUser,
            fuzzUser
        );
        bytes32 quoteHash = pegInContract.hashPegInQuote(quote);

        uint256 userBalanceBefore = fuzzUser.balance;

        vm.prank(pegInLp);
        bool success = pegInContract.callForUser{value: txValue}(quote);

        assertTrue(success, "Call should succeed");

        assertEq(
            fuzzUser.balance,
            userBalanceBefore + callValue,
            "User should receive the call value"
        );

        // LP internal balance should be: depositAmount + txValue - callValue
        assertEq(
            pegInContract.getBalance(pegInLp),
            totalAvailable - callValue,
            "LP internal balance should be remainder"
        );

        assertEq(
            uint256(pegInContract.getQuoteStatus(quoteHash)),
            uint256(IPegIn.PegInStates.CALL_DONE),
            "Quote should be marked as CALL_DONE"
        );
    }

    // ============ CallForUser Failure Tests ============

    /// @notice Fuzz test: CallForUser should revert if LP not registered
    function testFuzz_CallForUser_RevertsIfLPNotRegistered(
        uint128 callValue
    ) public {
        callValue = uint128(bound(callValue, TEST_MIN_PEGIN, 10 ether));

        Quotes.PegInQuote memory quote = createFuzzTestQuoteForLP(
            callValue,
            fuzzUser,
            fuzzUser,
            pegOutLp // PegOut LP is not registered for PegIn
        );

        vm.prank(pegOutLp);
        vm.expectRevert(
            abi.encodeWithSelector(
                Flyover.ProviderNotRegistered.selector,
                pegOutLp
            )
        );
        pegInContract.callForUser{value: callValue}(quote);
    }

    /// @notice Fuzz test: CallForUser should revert if sender doesn't match quote LP
    function testFuzz_CallForUser_RevertsIfSenderNotQuoteLP(
        uint128 callValue
    ) public {
        callValue = uint128(bound(callValue, TEST_MIN_PEGIN, 10 ether));

        // Quote specifies fullLp
        Quotes.PegInQuote memory quote = createFuzzTestQuoteForLP(
            callValue,
            fuzzUser,
            fuzzUser,
            fullLp
        );

        // But pegInLp tries to call
        vm.prank(pegInLp);
        vm.expectRevert(
            abi.encodeWithSelector(
                Flyover.InvalidSender.selector,
                fullLp,
                pegInLp
            )
        );
        pegInContract.callForUser{value: callValue}(quote);
    }

    /// @notice Fuzz test: CallForUser should revert if balance insufficient
    function testFuzz_CallForUser_RevertsIfBalanceInsufficient(
        uint128 depositAmount,
        uint128 shortfall
    ) public {
        depositAmount = uint128(bound(depositAmount, 0.01 ether, 5 ether));
        shortfall = uint128(bound(shortfall, 0.001 ether, 1 ether));

        uint256 callValue = uint256(depositAmount) + uint256(shortfall);
        vm.assume(callValue <= 10 ether);
        vm.assume(callValue >= TEST_MIN_PEGIN);

        // Deposit less than needed
        vm.prank(pegInLp);
        pegInContract.deposit{value: depositAmount}();

        Quotes.PegInQuote memory quote = createFuzzTestQuoteWithDestination(
            callValue,
            fuzzUser,
            fuzzUser
        );

        // Try to call with no additional value (only using deposited balance)
        vm.prank(pegInLp);
        vm.expectRevert(
            abi.encodeWithSelector(
                Flyover.InsufficientAmount.selector,
                depositAmount,
                callValue
            )
        );
        pegInContract.callForUser{value: 0}(quote);
    }

    /// @notice Fuzz test: CallForUser should revert if quote already processed
    function testFuzz_CallForUser_RevertsIfQuoteAlreadyProcessed(
        uint128 callValue
    ) public {
        callValue = uint128(bound(callValue, TEST_MIN_PEGIN, 10 ether));

        Quotes.PegInQuote memory quote = createFuzzTestQuoteWithDestination(
            callValue,
            fuzzUser,
            fuzzUser
        );
        bytes32 quoteHash = pegInContract.hashPegInQuote(quote);

        // First call succeeds
        vm.prank(pegInLp);
        pegInContract.callForUser{value: callValue}(quote);

        // Second call with same quote should fail
        vm.prank(pegInLp);
        vm.expectRevert(
            abi.encodeWithSelector(
                IPegIn.QuoteAlreadyProcessed.selector,
                quoteHash
            )
        );
        pegInContract.callForUser{value: callValue}(quote);
    }

    /// @notice Fuzz test: Different nonces should produce different quote hashes
    function testFuzz_CallForUser_DifferentNoncesAllowSameValueCalls(
        uint128 callValue,
        int64 nonce1,
        int64 nonce2
    ) public {
        callValue = uint128(bound(callValue, TEST_MIN_PEGIN, 10 ether));
        vm.assume(nonce1 != nonce2);

        Quotes.PegInQuote memory quote1 = createFuzzTestQuoteWithDestination(
            callValue,
            fuzzUser,
            fuzzUser
        );
        quote1.nonce = nonce1;

        Quotes.PegInQuote memory quote2 = createFuzzTestQuoteWithDestination(
            callValue,
            fuzzUser,
            fuzzUser
        );
        quote2.nonce = nonce2;

        bytes32 hash1 = pegInContract.hashPegInQuote(quote1);
        bytes32 hash2 = pegInContract.hashPegInQuote(quote2);

        assertTrue(
            hash1 != hash2,
            "Different nonces should produce different hashes"
        );

        // Both calls should succeed
        vm.startPrank(pegInLp);
        pegInContract.callForUser{value: callValue}(quote1);
        pegInContract.callForUser{value: callValue}(quote2);
        vm.stopPrank();

        assertEq(
            uint256(pegInContract.getQuoteStatus(hash1)),
            uint256(IPegIn.PegInStates.CALL_DONE)
        );
        assertEq(
            uint256(pegInContract.getQuoteStatus(hash2)),
            uint256(IPegIn.PegInStates.CALL_DONE)
        );
    }
}
