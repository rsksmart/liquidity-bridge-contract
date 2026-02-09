// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {PegOutFuzzTestBase} from "./PegOutFuzzTestBase.sol";
import {Quotes} from "../../../src/libraries/Quotes.sol";
import {Flyover} from "../../../src/libraries/Flyover.sol";
import {IPegOut} from "../../../src/interfaces/IPegOut.sol";

/// @title PegOutDepositAmounts Fuzz Tests
/// @notice Fuzz tests for PegOut deposit amount calculations and validations
contract PegOutDepositAmountsFuzzTest is PegOutFuzzTestBase {
    function setUp() public {
        deployPegOutContract();
        setupProviders();

        fuzzUser = makeAddr("user");
        vm.deal(fuzzUser, 1000 ether);
    }

    /// @notice Fuzz test: Exact payment should succeed and emit PegOutDeposit event
    function testFuzz_DepositPegOut_AcceptsExactPayment(
        uint128 value,
        uint128 callFee,
        uint64 gasFee
    ) public {
        // Bound to reasonable values
        value = uint128(bound(value, 0.001 ether, 100 ether));
        callFee = uint128(bound(callFee, 0, 1 ether));
        gasFee = uint64(bound(gasFee, 0, 0.01 ether));

        Quotes.PegOutQuote memory quote = createFuzzTestQuote(value);
        quote.callFee = callFee;
        quote.gasFee = gasFee;

        uint256 totalValue = getTotalQuoteValue(quote);
        vm.assume(totalValue <= 500 ether); // Ensure we have enough funds

        bytes32 quoteHash = pegOutContract.hashPegOutQuote(quote);
        bytes memory signature = signFuzzQuote(pegOutLp, quote);

        // Expect PegOutDeposit event with correct parameters
        vm.expectEmit(true, true, true, true);
        emit IPegOut.PegOutDeposit(
            quoteHash,
            fuzzUser,
            block.timestamp,
            totalValue
        );

        // Should succeed with exact payment
        vm.prank(fuzzUser);
        pegOutContract.depositPegOut{value: totalValue}(quote, signature);

        assertFalse(
            pegOutContract.isQuoteCompleted(quoteHash),
            "Quote should not be completed yet"
        );
    }

    /// @notice Fuzz test: Underpayment should revert
    function testFuzz_DepositPegOut_RevertsOnUnderpayment(
        uint128 value,
        uint128 callFee,
        uint128 underpayAmount
    ) public {
        value = uint128(bound(value, 0.001 ether, 100 ether));
        callFee = uint128(bound(callFee, 0, 1 ether));

        Quotes.PegOutQuote memory quote = createFuzzTestQuote(value);
        quote.callFee = callFee;

        uint256 totalValue = getTotalQuoteValue(quote);
        underpayAmount = uint128(bound(underpayAmount, 1, totalValue));
        uint256 sentAmount = totalValue - underpayAmount;

        bytes32 quoteHash = pegOutContract.hashPegOutQuote(quote);
        bytes memory signature = signFuzzQuote(pegOutLp, quoteHash);

        vm.prank(fuzzUser);
        vm.expectRevert(
            abi.encodeWithSelector(
                Flyover.InsufficientAmount.selector,
                sentAmount,
                totalValue
            )
        );
        pegOutContract.depositPegOut{value: sentAmount}(quote, signature);
    }

    /// @notice Fuzz test: Overpayment below dust threshold should keep extra funds
    /// @dev Verifies PegOutDeposit is emitted but PegOutChangePaid is NOT emitted
    function testFuzz_DepositPegOut_KeepsOverpaymentBelowDust(
        uint128 value,
        uint64 extraAmount
    ) public {
        value = uint128(bound(value, 0.001 ether, 100 ether));
        extraAmount = uint64(bound(extraAmount, 1, TEST_DUST_THRESHOLD - 1));

        Quotes.PegOutQuote memory quote = createFuzzTestQuote(value);
        uint256 totalValue = getTotalQuoteValue(quote);
        uint256 paidAmount = totalValue + extraAmount;

        vm.assume(paidAmount <= 500 ether);

        bytes32 quoteHash = pegOutContract.hashPegOutQuote(quote);
        bytes memory signature = signFuzzQuote(pegOutLp, quote);

        uint256 contractBalanceBefore = address(pegOutContract).balance;

        // Expect PegOutDeposit event with the PAID amount (including dust overpayment)
        vm.expectEmit(true, true, true, true);
        emit IPegOut.PegOutDeposit(
            quoteHash,
            fuzzUser,
            block.timestamp,
            paidAmount
        );

        vm.prank(fuzzUser);
        pegOutContract.depositPegOut{value: paidAmount}(quote, signature);

        // Contract should keep the extra (no change paid)
        assertEq(
            address(pegOutContract).balance,
            contractBalanceBefore + paidAmount,
            "Contract should keep full payment including dust overpayment"
        );
    }

    /// @notice Fuzz test: Overpayment above dust threshold should return change
    /// @dev Verifies both PegOutDeposit and PegOutChangePaid events are emitted
    ///      PegOutDeposit emits msg.value (paidAmount), PegOutChangePaid goes to rskRefundAddress
    function testFuzz_DepositPegOut_ReturnsOverpaymentAboveDust(
        uint128 value,
        uint128 extraAmount
    ) public {
        value = uint128(bound(value, 0.001 ether, 100 ether));
        extraAmount = uint128(
            bound(extraAmount, TEST_DUST_THRESHOLD, 10 ether)
        );

        Quotes.PegOutQuote memory quote = createFuzzTestQuote(value);
        uint256 totalValue = getTotalQuoteValue(quote);
        uint256 paidAmount = totalValue + extraAmount;

        vm.assume(paidAmount <= 500 ether);

        bytes32 quoteHash = pegOutContract.hashPegOutQuote(quote);
        bytes memory signature = signFuzzQuote(pegOutLp, quote);

        uint256 userBalanceBefore = fuzzUser.balance;

        // Contract emits PegOutDeposit with msg.value (paidAmount), then PegOutChangePaid
        vm.expectEmit(true, true, true, true);
        emit IPegOut.PegOutDeposit(
            quoteHash,
            fuzzUser,
            block.timestamp,
            paidAmount
        );

        // PegOutChangePaid goes to quote.rskRefundAddress (which is 'fuzzUser' in our test quote)
        vm.expectEmit(true, true, true, true);
        emit IPegOut.PegOutChangePaid(
            quoteHash,
            quote.rskRefundAddress,
            extraAmount
        );

        vm.prank(fuzzUser);
        pegOutContract.depositPegOut{value: paidAmount}(quote, signature);

        // User should receive change back
        assertEq(
            fuzzUser.balance,
            userBalanceBefore - totalValue,
            "User should only pay totalValue (change returned)"
        );
    }

    /// @notice Fuzz test: Fee calculation should not overflow
    function testFuzz_DepositPegOut_HandlesLargeFees(
        uint128 value,
        uint64 callFee,
        uint64 productFeeAmount,
        uint32 gasFee
    ) public {
        value = uint128(bound(value, 0.001 ether, 100 ether));
        callFee = uint64(bound(callFee, 0, 10 ether));
        productFeeAmount = uint64(bound(productFeeAmount, 0, 10 ether));
        gasFee = uint32(bound(gasFee, 0, 0.1 ether));

        // Check for overflow in total calculation
        uint256 total = uint256(value) +
            uint256(callFee) +
            uint256(productFeeAmount) +
            uint256(gasFee);
        vm.assume(total <= 500 ether);
        vm.assume(total < type(uint256).max);

        Quotes.PegOutQuote memory quote = createFuzzTestQuote(value);
        quote.callFee = callFee;
        quote.productFeeAmount = productFeeAmount;
        quote.gasFee = gasFee;

        uint256 totalValue = getTotalQuoteValue(quote);
        bytes32 quoteHash = pegOutContract.hashPegOutQuote(quote);
        bytes memory signature = signFuzzQuote(pegOutLp, quoteHash);

        // Should not revert due to overflow
        vm.prank(fuzzUser);
        pegOutContract.depositPegOut{value: totalValue}(quote, signature);
    }

    /// @notice Fuzz test: Zero value components should be handled correctly
    function testFuzz_DepositPegOut_HandlesZeroFees(
        uint128 value,
        bool zeroCallFee,
        bool zeroProductFee,
        bool zeroGasFee
    ) public {
        value = uint128(bound(value, 0.001 ether, 100 ether));

        Quotes.PegOutQuote memory quote = createFuzzTestQuote(value);
        if (zeroCallFee) quote.callFee = 0;
        if (zeroProductFee) quote.productFeeAmount = 0;
        if (zeroGasFee) quote.gasFee = 0;

        uint256 totalValue = getTotalQuoteValue(quote);
        bytes32 quoteHash = pegOutContract.hashPegOutQuote(quote);
        bytes memory signature = signFuzzQuote(pegOutLp, quoteHash);

        vm.prank(fuzzUser);
        pegOutContract.depositPegOut{value: totalValue}(quote, signature);

        assertFalse(pegOutContract.isQuoteCompleted(quoteHash));
    }

    /// @notice Fuzz test: Multiple deposits with different amounts should track separately
    function testFuzz_DepositPegOut_TracksSeparateQuotes(
        uint128 value1,
        uint128 value2,
        int64 nonce1,
        int64 nonce2
    ) public {
        value1 = uint128(bound(value1, 0.001 ether, 50 ether));
        value2 = uint128(bound(value2, 0.001 ether, 50 ether));
        vm.assume(nonce1 != nonce2);

        Quotes.PegOutQuote memory quote1 = createFuzzTestQuote(value1);
        quote1.nonce = nonce1;
        uint256 totalValue1 = getTotalQuoteValue(quote1);
        bytes32 quoteHash1 = pegOutContract.hashPegOutQuote(quote1);
        bytes memory signature1 = signFuzzQuote(pegOutLp, quoteHash1);

        Quotes.PegOutQuote memory quote2 = createFuzzTestQuote(value2);
        quote2.nonce = nonce2;
        uint256 totalValue2 = getTotalQuoteValue(quote2);
        bytes32 quoteHash2 = pegOutContract.hashPegOutQuote(quote2);
        bytes memory signature2 = signFuzzQuote(pegOutLp, quoteHash2);

        // Deposit both
        vm.startPrank(fuzzUser);
        pegOutContract.depositPegOut{value: totalValue1}(quote1, signature1);
        pegOutContract.depositPegOut{value: totalValue2}(quote2, signature2);
        vm.stopPrank();

        // Both should be tracked separately
        assertFalse(pegOutContract.isQuoteCompleted(quoteHash1));
        assertFalse(pegOutContract.isQuoteCompleted(quoteHash2));
        assertTrue(
            quoteHash1 != quoteHash2,
            "Different nonces should produce different hashes"
        );
    }
}
