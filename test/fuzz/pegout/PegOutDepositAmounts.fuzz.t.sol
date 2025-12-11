// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {PegOutFuzzTestBase} from "./PegOutFuzzTestBase.sol";
import {Quotes} from "../../../src/libraries/Quotes.sol";
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
        uint128 productFeeAmount,
        uint64 gasFee
    ) public {
        // Bound to reasonable values
        value = uint128(bound(value, 0.001 ether, 100 ether));
        callFee = uint128(bound(callFee, 0, 1 ether));
        productFeeAmount = uint128(bound(productFeeAmount, 0, 1 ether));
        gasFee = uint64(bound(gasFee, 0, 0.01 ether));

        Quotes.PegOutQuote memory quote = createFuzzTestQuote(value);
        quote.callFee = callFee;
        quote.productFeeAmount = productFeeAmount;
        quote.gasFee = gasFee;

        uint256 totalValue = getTotalQuoteValue(quote);
        vm.assume(totalValue <= 500 ether); // Ensure we have enough funds

        bytes32 quoteHash = pegOutContract.hashPegOutQuote(quote);
        bytes memory signature = signFuzzQuote(pegOutLp, quoteHash);

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
        bytes memory signature = signFuzzQuote(pegOutLp, quoteHash);

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
        bytes memory signature = signFuzzQuote(pegOutLp, quoteHash);

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
}
