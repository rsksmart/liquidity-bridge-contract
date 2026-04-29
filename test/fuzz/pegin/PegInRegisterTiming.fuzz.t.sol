// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {PegInFuzzTestBase} from "./PegInFuzzTestBase.sol";
import {Quotes} from "../../../src/libraries/Quotes.sol";
import {IPegIn} from "../../../src/interfaces/IPegIn.sol";
import {ICollateralManagement} from "../../../src/interfaces/ICollateralManagement.sol";
import {Flyover} from "../../../src/libraries/Flyover.sol";
import {SignatureValidator} from "../../../src/libraries/SignatureValidator.sol";

/// @title PegIn RegisterPegIn Timing Fuzz Tests
/// @notice Fuzz tests for timing-based penalties in PegIn registration
contract PegInRegisterTimingFuzzTest is PegInFuzzTestBase {
    // Mock constants for BTC transaction data
    bytes constant RAW_TX_MOCK = hex"112233";
    bytes constant PMT_MOCK = hex"010203";
    uint256 constant HEIGHT_MOCK = 10;

    function setUp() public {
        deployPegInContract();
        setupProviders();

        fuzzUser = makeAddr("user");
        vm.deal(fuzzUser, 1000 ether);
    }

    // ============ Signature Validation Tests ============

    /// @notice Fuzz test: Invalid signature should revert with IncorrectSignature
    function testFuzz_RegisterPegIn_RevertsOnInvalidSignature(
        uint128 callValue,
        bytes32 randomHash
    ) public {
        callValue = uint128(bound(callValue, TEST_MIN_PEGIN, 10 ether));

        Quotes.PegInQuote memory quote = createFuzzTestQuoteForLP(
            callValue,
            fuzzUser,
            fuzzUser,
            fullLp
        );
        bytes32 eip712Hash = pegInContract.hashPegInQuoteEIP712(quote);

        // First do callForUser to set state to CALL_DONE
        vm.prank(fullLp);
        pegInContract.callForUser{value: callValue}(quote);

        // Sign a different hash (wrong signature)
        vm.assume(randomHash != eip712Hash);
        bytes memory wrongSignature = signMessageHash(pegInLp, randomHash);

        vm.expectRevert(
            abi.encodeWithSelector(
                SignatureValidator.IncorrectSignature.selector,
                fullLp,
                eip712Hash,
                wrongSignature
            )
        );
        pegInContract.registerPegIn(
            quote,
            wrongSignature,
            RAW_TX_MOCK,
            PMT_MOCK,
            HEIGHT_MOCK
        );
    }

    /// @notice Fuzz test: Wrong signer should revert with IncorrectSignature
    function testFuzz_RegisterPegIn_RevertsOnWrongSigner(
        uint128 callValue
    ) public {
        callValue = uint128(bound(callValue, TEST_MIN_PEGIN, 10 ether));

        Quotes.PegInQuote memory quote = createFuzzTestQuoteForLP(
            callValue,
            fuzzUser,
            fuzzUser,
            fullLp
        );
        bytes32 eip712Hash = pegInContract.hashPegInQuoteEIP712(quote);

        // First do callForUser
        vm.prank(fullLp);
        pegInContract.callForUser{value: callValue}(quote);

        // Sign with wrong LP (pegInLp instead of fullLp)
        bytes memory wrongSignature = signFuzzQuote(pegInLp, quote);

        vm.expectRevert(
            abi.encodeWithSelector(
                SignatureValidator.IncorrectSignature.selector,
                fullLp,
                eip712Hash,
                wrongSignature
            )
        );
        pegInContract.registerPegIn(
            quote,
            wrongSignature,
            RAW_TX_MOCK,
            PMT_MOCK,
            HEIGHT_MOCK
        );
    }

    // ============ Height Validation Tests ============

    /// @notice Fuzz test: Height exceeding max int32 should revert with Overflow
    function testFuzz_RegisterPegIn_RevertsOnHeightOverflow(
        uint128 callValue,
        uint256 heightOffset
    ) public {
        callValue = uint128(bound(callValue, TEST_MIN_PEGIN, 10 ether));
        heightOffset = bound(heightOffset, 1, 1000000);

        Quotes.PegInQuote memory quote = createFuzzTestQuoteForLP(
            callValue,
            fuzzUser,
            fuzzUser,
            fullLp
        );
        bytes memory signature = signFuzzQuote(fullLp, quote);

        // First do callForUser
        vm.prank(fullLp);
        pegInContract.callForUser{value: callValue}(quote);

        // Height exceeding max int32
        int32 maxInt32 = type(int32).max;
        uint256 invalidHeight = uint256(uint32(maxInt32)) + heightOffset;

        vm.expectRevert(
            abi.encodeWithSelector(Flyover.Overflow.selector, maxInt32)
        );
        pegInContract.registerPegIn(
            quote,
            signature,
            RAW_TX_MOCK,
            PMT_MOCK,
            invalidHeight
        );
    }

    // ============ Quote State Tests ============

    /// @notice Fuzz test: Quote already processed should revert
    function testFuzz_RegisterPegIn_RevertsIfQuoteAlreadyProcessed(
        uint128 callValue
    ) public {
        callValue = uint128(bound(callValue, TEST_MIN_PEGIN, 10 ether));

        Quotes.PegInQuote memory quote = createFuzzTestQuoteForLP(
            callValue,
            fuzzUser,
            fuzzUser,
            fullLp
        );
        bytes32 quoteHash = pegInContract.hashPegInQuote(quote);
        bytes memory signature = signFuzzQuote(fullLp, quote);

        uint256 peginAmount = getTotalQuoteValue(quote);

        // Setup BTC block headers
        uint32 firstConfTime = uint32(block.timestamp) + 300;
        uint32 nConfTime = uint32(block.timestamp) + 600;
        bytes memory firstHeader = createBtcBlockHeader(firstConfTime);
        bytes memory nConfHeader = createBtcBlockHeader(nConfTime);

        // Setup bridge to return success
        vm.deal(address(bridgeMock), peginAmount);
        bridgeMock.setPegin{value: peginAmount}(quoteHash);
        bridgeMock.setHeader(HEIGHT_MOCK, firstHeader);
        bridgeMock.setHeader(
            HEIGHT_MOCK + uint256(quote.depositConfirmations) - 1,
            nConfHeader
        );

        // First do callForUser
        vm.prank(fullLp);
        pegInContract.callForUser{value: callValue}(quote);

        // First registration succeeds
        vm.prank(fullLp);
        pegInContract.registerPegIn(
            quote,
            signature,
            RAW_TX_MOCK,
            PMT_MOCK,
            HEIGHT_MOCK
        );

        // Second registration should fail
        vm.prank(fullLp);
        vm.expectRevert(
            abi.encodeWithSelector(
                IPegIn.QuoteAlreadyProcessed.selector,
                quoteHash
            )
        );
        pegInContract.registerPegIn(
            quote,
            signature,
            RAW_TX_MOCK,
            PMT_MOCK,
            HEIGHT_MOCK
        );
    }

    // ============ Bridge Error Tests ============

    /// @notice Fuzz test: Not enough confirmations should revert
    function testFuzz_RegisterPegIn_RevertsOnNotEnoughConfirmations(
        uint128 callValue
    ) public {
        callValue = uint128(bound(callValue, TEST_MIN_PEGIN, 10 ether));

        Quotes.PegInQuote memory quote = createFuzzTestQuoteForLP(
            callValue,
            fuzzUser,
            fuzzUser,
            fullLp
        );
        bytes memory signature = signFuzzQuote(fullLp, quote);

        // Setup bridge to return confirmations error
        int256 BRIDGE_UNPROCESSABLE_ERROR = -303;
        bridgeMock.setPeginError(BRIDGE_UNPROCESSABLE_ERROR);

        // First do callForUser
        vm.prank(fullLp);
        pegInContract.callForUser{value: callValue}(quote);

        vm.expectRevert(
            abi.encodeWithSelector(IPegIn.NotEnoughConfirmations.selector)
        );
        pegInContract.registerPegIn(
            quote,
            signature,
            RAW_TX_MOCK,
            PMT_MOCK,
            HEIGHT_MOCK
        );
    }

    /// @notice Fuzz test: Unexpected bridge error should revert
    function testFuzz_RegisterPegIn_RevertsOnUnexpectedBridgeError(
        uint128 callValue,
        int256 errorCode
    ) public {
        callValue = uint128(bound(callValue, TEST_MIN_PEGIN, 10 ether));
        // Avoid known error codes: -100 (user refund), -200 (LP refund), -303 (confirmations)
        errorCode = int256(bound(uint256(errorCode), 304, 1000));
        errorCode = -errorCode; // Make negative

        Quotes.PegInQuote memory quote = createFuzzTestQuoteForLP(
            callValue,
            fuzzUser,
            fuzzUser,
            fullLp
        );
        bytes memory signature = signFuzzQuote(fullLp, quote);

        // Setup bridge to return unexpected error
        bridgeMock.setPeginError(errorCode);

        // First do callForUser
        vm.prank(fullLp);
        pegInContract.callForUser{value: callValue}(quote);

        vm.expectRevert(
            abi.encodeWithSelector(
                IPegIn.UnexpectedBridgeError.selector,
                errorCode
            )
        );
        pegInContract.registerPegIn(
            quote,
            signature,
            RAW_TX_MOCK,
            PMT_MOCK,
            HEIGHT_MOCK
        );
    }

    // ============ Bridge Cap Exceeded Tests ============

    /// @notice Fuzz test: User refund error should emit BridgeCapExceeded
    function testFuzz_RegisterPegIn_EmitsBridgeCapExceededOnUserRefund(
        uint128 callValue
    ) public {
        callValue = uint128(bound(callValue, TEST_MIN_PEGIN, 10 ether));

        Quotes.PegInQuote memory quote = createFuzzTestQuoteForLP(
            callValue,
            fuzzUser,
            fuzzUser,
            fullLp
        );
        bytes32 quoteHash = pegInContract.hashPegInQuote(quote);
        bytes memory signature = signFuzzQuote(fullLp, quote);

        // Setup BTC block headers
        bytes memory firstHeader = createBtcBlockHeader(
            uint32(block.timestamp) + 300
        );
        bytes memory nConfHeader = createBtcBlockHeader(
            uint32(block.timestamp) + 600
        );

        // Setup bridge to return user refund error
        int256 BRIDGE_REFUNDED_USER_ERROR = -100;
        bridgeMock.setPeginError(BRIDGE_REFUNDED_USER_ERROR);
        bridgeMock.setHeader(HEIGHT_MOCK, firstHeader);
        bridgeMock.setHeader(
            HEIGHT_MOCK + uint256(quote.depositConfirmations) - 1,
            nConfHeader
        );

        // First do callForUser
        vm.prank(fullLp);
        pegInContract.callForUser{value: callValue}(quote);

        vm.prank(fullLp);
        vm.expectEmit(true, true, false, true);
        emit IPegIn.BridgeCapExceeded(quoteHash, BRIDGE_REFUNDED_USER_ERROR);
        pegInContract.registerPegIn(
            quote,
            signature,
            RAW_TX_MOCK,
            PMT_MOCK,
            HEIGHT_MOCK
        );

        // Verify quote is processed
        assertEq(
            uint256(pegInContract.getQuoteStatus(quoteHash)),
            uint256(IPegIn.PegInStates.PROCESSED_QUOTE)
        );
    }

    /// @notice Fuzz test: LP refund error should emit BridgeCapExceeded
    function testFuzz_RegisterPegIn_EmitsBridgeCapExceededOnLPRefund(
        uint128 callValue
    ) public {
        callValue = uint128(bound(callValue, TEST_MIN_PEGIN, 10 ether));

        Quotes.PegInQuote memory quote = createFuzzTestQuoteForLP(
            callValue,
            fuzzUser,
            fuzzUser,
            fullLp
        );
        bytes32 quoteHash = pegInContract.hashPegInQuote(quote);
        bytes memory signature = signFuzzQuote(fullLp, quote);

        // Setup BTC block headers
        bytes memory firstHeader = createBtcBlockHeader(
            uint32(block.timestamp) + 300
        );
        bytes memory nConfHeader = createBtcBlockHeader(
            uint32(block.timestamp) + 600
        );

        // Setup bridge to return LP refund error
        int256 BRIDGE_REFUNDED_LP_ERROR = -200;
        bridgeMock.setPeginError(BRIDGE_REFUNDED_LP_ERROR);
        bridgeMock.setHeader(HEIGHT_MOCK, firstHeader);
        bridgeMock.setHeader(
            HEIGHT_MOCK + uint256(quote.depositConfirmations) - 1,
            nConfHeader
        );

        // First do callForUser
        vm.prank(fullLp);
        pegInContract.callForUser{value: callValue}(quote);

        vm.prank(fullLp);
        vm.expectEmit(true, true, false, true);
        emit IPegIn.BridgeCapExceeded(quoteHash, BRIDGE_REFUNDED_LP_ERROR);
        pegInContract.registerPegIn(
            quote,
            signature,
            RAW_TX_MOCK,
            PMT_MOCK,
            HEIGHT_MOCK
        );

        // Verify quote is processed
        assertEq(
            uint256(pegInContract.getQuoteStatus(quoteHash)),
            uint256(IPegIn.PegInStates.PROCESSED_QUOTE)
        );
    }

    // ============ Successful Registration Tests ============

    /// @notice Fuzz test: Successful registration emits PegInRegistered
    function testFuzz_RegisterPegIn_EmitsPegInRegisteredOnSuccess(
        uint128 callValue
    ) public {
        callValue = uint128(bound(callValue, TEST_MIN_PEGIN, 10 ether));

        Quotes.PegInQuote memory quote = createFuzzTestQuoteForLP(
            callValue,
            fuzzUser,
            fuzzUser,
            fullLp
        );
        bytes32 quoteHash = pegInContract.hashPegInQuote(quote);
        bytes memory signature = signFuzzQuote(fullLp, quote);

        uint256 peginAmount = getTotalQuoteValue(quote);

        // Setup BTC block headers
        uint32 firstConfTime = uint32(block.timestamp) + 300;
        uint32 nConfTime = uint32(block.timestamp) + 600;
        bytes memory firstHeader = createBtcBlockHeader(firstConfTime);
        bytes memory nConfHeader = createBtcBlockHeader(nConfTime);

        // Setup bridge to return success
        vm.deal(address(bridgeMock), peginAmount);
        bridgeMock.setPegin{value: peginAmount}(quoteHash);
        bridgeMock.setHeader(HEIGHT_MOCK, firstHeader);
        bridgeMock.setHeader(
            HEIGHT_MOCK + uint256(quote.depositConfirmations) - 1,
            nConfHeader
        );

        // First do callForUser
        vm.prank(fullLp);
        pegInContract.callForUser{value: callValue}(quote);

        vm.prank(fullLp);
        vm.expectEmit(true, true, false, true);
        emit IPegIn.PegInRegistered(quoteHash, peginAmount);
        pegInContract.registerPegIn(
            quote,
            signature,
            RAW_TX_MOCK,
            PMT_MOCK,
            HEIGHT_MOCK
        );

        // Verify quote is processed
        assertEq(
            uint256(pegInContract.getQuoteStatus(quoteHash)),
            uint256(IPegIn.PegInStates.PROCESSED_QUOTE)
        );
    }

    /// @notice Fuzz test: LP balance increases on successful registration
    function testFuzz_RegisterPegIn_IncreasesLPBalance(
        uint128 callValue,
        uint64 initialDeposit
    ) public {
        callValue = uint128(bound(callValue, TEST_MIN_PEGIN, 10 ether));
        initialDeposit = uint64(bound(initialDeposit, 0.1 ether, 5 ether));

        Quotes.PegInQuote memory quote = createFuzzTestQuoteForLP(
            callValue,
            fuzzUser,
            fuzzUser,
            fullLp
        );
        bytes32 quoteHash = pegInContract.hashPegInQuote(quote);
        bytes memory signature = signFuzzQuote(fullLp, quote);

        uint256 peginAmount = getTotalQuoteValue(quote);

        // Setup BTC block headers
        uint32 firstConfTime = uint32(block.timestamp) + 300;
        uint32 nConfTime = uint32(block.timestamp) + 600;
        bytes memory firstHeader = createBtcBlockHeader(firstConfTime);
        bytes memory nConfHeader = createBtcBlockHeader(nConfTime);

        // Setup bridge to return success
        vm.deal(address(bridgeMock), peginAmount);
        bridgeMock.setPegin{value: peginAmount}(quoteHash);
        bridgeMock.setHeader(HEIGHT_MOCK, firstHeader);
        bridgeMock.setHeader(
            HEIGHT_MOCK + uint256(quote.depositConfirmations) - 1,
            nConfHeader
        );

        // First do callForUser
        vm.prank(fullLp);
        pegInContract.callForUser{value: callValue}(quote);

        // LP deposits additional funds
        vm.prank(fullLp);
        pegInContract.deposit{value: initialDeposit}();

        uint256 lpBalanceBefore = pegInContract.getBalance(fullLp);

        vm.prank(fullLp);
        pegInContract.registerPegIn(
            quote,
            signature,
            RAW_TX_MOCK,
            PMT_MOCK,
            HEIGHT_MOCK
        );

        // LP balance should increase by peginAmount
        assertEq(
            pegInContract.getBalance(fullLp),
            lpBalanceBefore + peginAmount,
            "LP balance should increase"
        );
    }

    // ============ Overpayment/Underpayment Tests ============

    /// @notice Fuzz test: User overpayment should be refunded
    function testFuzz_RegisterPegIn_RefundsOverpayment(
        uint128 callValue,
        uint64 extraPaid
    ) public {
        callValue = uint128(bound(callValue, TEST_MIN_PEGIN, 5 ether));
        extraPaid = uint64(bound(extraPaid, TEST_DUST_THRESHOLD + 1, 5 ether));

        Quotes.PegInQuote memory quote = createFuzzTestQuoteForLP(
            callValue,
            fuzzUser,
            fuzzUser,
            fullLp
        );
        bytes32 quoteHash = pegInContract.hashPegInQuote(quote);
        bytes memory signature = signFuzzQuote(fullLp, quote);

        uint256 peginAmount = getTotalQuoteValue(quote);
        uint256 totalPaid = peginAmount + extraPaid;

        // Setup BTC block headers
        bytes memory firstHeader = createBtcBlockHeader(
            uint32(block.timestamp) + 300
        );
        bytes memory nConfHeader = createBtcBlockHeader(
            uint32(block.timestamp) + 600
        );

        // Setup bridge to return overpayment
        vm.deal(address(bridgeMock), totalPaid);
        bridgeMock.setPegin{value: totalPaid}(quoteHash);
        bridgeMock.setHeader(HEIGHT_MOCK, firstHeader);
        bridgeMock.setHeader(
            HEIGHT_MOCK + uint256(quote.depositConfirmations) - 1,
            nConfHeader
        );

        // First do callForUser
        vm.prank(fullLp);
        pegInContract.callForUser{value: callValue}(quote);

        uint256 userBalanceBefore = fuzzUser.balance;

        vm.prank(fullLp);
        vm.expectEmit(true, true, false, true);
        emit IPegIn.PegInRegistered(quoteHash, totalPaid);
        // Expect refund event for overpayment
        vm.expectEmit(true, true, true, true);
        emit IPegIn.Refund(fuzzUser, quoteHash, extraPaid, true);
        pegInContract.registerPegIn(
            quote,
            signature,
            RAW_TX_MOCK,
            PMT_MOCK,
            HEIGHT_MOCK
        );

        // Verify user received the refund
        assertEq(
            fuzzUser.balance,
            userBalanceBefore + extraPaid,
            "User should receive overpayment refund"
        );
    }

    /// @notice Fuzz test: Underpayment should revert
    function testFuzz_RegisterPegIn_RevertsOnUnderpayment(
        uint128 callValue,
        uint64 underpayment
    ) public {
        callValue = uint128(bound(callValue, TEST_MIN_PEGIN, 10 ether));
        underpayment = uint64(bound(underpayment, 0.01 ether, 1 ether));

        Quotes.PegInQuote memory quote = createFuzzTestQuoteForLP(
            callValue,
            fuzzUser,
            fuzzUser,
            fullLp
        );
        bytes32 quoteHash = pegInContract.hashPegInQuote(quote);
        bytes memory signature = signFuzzQuote(fullLp, quote);

        uint256 peginAmount = getTotalQuoteValue(quote);
        vm.assume(underpayment < peginAmount);
        uint256 paidAmount = peginAmount - underpayment;

        // Setup BTC block headers
        bytes memory firstHeader = createBtcBlockHeader(
            uint32(block.timestamp) + 300
        );
        bytes memory nConfHeader = createBtcBlockHeader(
            uint32(block.timestamp) + 600
        );

        // Setup bridge to return underpayment
        vm.deal(address(bridgeMock), paidAmount);
        bridgeMock.setPegin{value: paidAmount}(quoteHash);
        bridgeMock.setHeader(HEIGHT_MOCK, firstHeader);
        bridgeMock.setHeader(
            HEIGHT_MOCK + uint256(quote.depositConfirmations) - 1,
            nConfHeader
        );

        // Don't call callForUser - test without it

        // Calculate expected amounts for error
        uint256 agreedAmount = peginAmount;
        uint256 SAT_TO_WEI_CONVERSION = 10 ** 10;
        if (
            agreedAmount > SAT_TO_WEI_CONVERSION &&
            (agreedAmount % SAT_TO_WEI_CONVERSION) != 0
        ) {
            agreedAmount -= (agreedAmount % SAT_TO_WEI_CONVERSION);
        }

        vm.prank(fullLp);
        vm.expectRevert(
            abi.encodeWithSelector(
                Quotes.AmountTooLow.selector,
                paidAmount,
                agreedAmount
            )
        );
        pegInContract.registerPegIn(
            quote,
            signature,
            RAW_TX_MOCK,
            PMT_MOCK,
            HEIGHT_MOCK
        );
    }
}
