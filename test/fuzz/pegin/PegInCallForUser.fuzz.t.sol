// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {PegInFuzzTestBase} from "./PegInFuzzTestBase.sol";
import {Quotes} from "../../../src/libraries/Quotes.sol";
import {IPegIn} from "../../../src/interfaces/IPegIn.sol";

/// @title PegIn CallForUser Fuzz Tests
/// @notice Fuzz tests for the PegIn callForUser functionality
contract PegInCallForUserFuzzTest is PegInFuzzTestBase {
    function setUp() public {
        deployPegInContract();
        setupProviders();

        fuzzUser = makeAddr("user");
        vm.deal(fuzzUser, 1000 ether);
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
