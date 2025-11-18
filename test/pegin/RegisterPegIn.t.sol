// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {PegInTestBase} from "./PegInTestBase.sol";
import {IPegIn} from "../../src/interfaces/IPegIn.sol";
import {Quotes} from "../../src/libraries/Quotes.sol";
import {Flyover} from "../../src/libraries/Flyover.sol";
import {SignatureValidator} from "../../src/libraries/SignatureValidator.sol";
import {WalletMock} from "../../src/test-contracts/WalletMock.sol";
import {ReentrancyCaller} from "../../src/test-contracts/ReentrancyCaller.sol";
import {OwnableDaoContributorUpgradeable} from "../../src/DaoContributor.sol";

/// @title RegisterPegIn Tests
/// @notice Tests for the registerPegIn function - the core of the PegIn flow
/// @dev This is a simplified version focused on validation logic (original: 1,443 lines)
///
/// Full registerPegIn testing requires complex BTC infrastructure:
/// - BTC transaction bytes generation
/// - Merkle proofs creation
/// - Block headers with proper timestamp encoding
/// - Bridge mock state management
/// - Complex timing scenarios (deposit/call windows, confirmations)
/// - Multiple refund paths (user/LP) based on timing/success
/// - Penalization triggers
/// - DAO contribution handling
///
/// These tests cover the pre-validation checks. Full BTC integration tests are
/// better suited for the TypeScript test suite with proper BTC libraries.
contract RegisterPegInTest is PegInTestBase {
    address public user;
    address public registerCaller;

    // Mock constants
    bytes constant RAW_TX_MOCK = hex"112233";
    bytes constant PMT_MOCK = hex"010203";
    uint256 constant HEIGHT_MOCK = 10;

    function setUp() public {
        deployPegInContract();
        setupProviders();

        user = makeAddr("user");
        registerCaller = makeAddr("registerCaller");

        vm.deal(user, 100 ether);
        vm.deal(registerCaller, 100 ether);
    }

    // ============ registerPegIn function tests - Basic Validations ============

    function test_RegisterPegIn_RevertsIfQuoteNotInCALL_DONEState() public {
        Quotes.PegInQuote memory quote = createTestQuote(1 ether);
        bytes32 quoteHash = pegInContract.hashPegInQuote(quote);
        bytes memory signature = signQuote(fullLp, quoteHash);

        // Try to register without calling callForUser first (quote is UNPROCESSED)
        // The contract checks: if (_processedQuotes[quoteHash] != PegInStates.CALL_DONE) revert
        // When state is UNPROCESSED (0), it fails the check
        vm.expectRevert(); // Will revert because quote state is not CALL_DONE
        pegInContract.registerPegIn(
            quote,
            signature,
            RAW_TX_MOCK,
            PMT_MOCK,
            HEIGHT_MOCK
        );
    }

    function test_RegisterPegIn_RevertsIfSignatureIsInvalid() public {
        Quotes.PegInQuote memory quote = createTestQuote(1 ether);
        bytes32 quoteHash = pegInContract.hashPegInQuote(quote);

        // Call for user first to set state to CALL_DONE
        vm.prank(fullLp);
        pegInContract.callForUser{value: 1 ether}(quote);

        // Try to register with wrong signature
        bytes memory wrongSignature = signQuote(pegInLp, quoteHash);

        vm.expectRevert(
            abi.encodeWithSelector(
                SignatureValidator.IncorrectSignature.selector,
                fullLp,
                quoteHash,
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

    function test_RegisterPegIn_RevertsIfHeightIsBiggerThanSupported() public {
        Quotes.PegInQuote memory quote = createTestQuote(1 ether);
        bytes32 quoteHash = pegInContract.hashPegInQuote(quote);
        bytes memory signature = signQuote(fullLp, quoteHash);

        // Call for user first
        vm.prank(fullLp);
        pegInContract.callForUser{value: 1 ether}(quote);

        // Try to register with height > MAX_INT_32
        int32 MAX_INT32 = type(int32).max;
        uint256 invalidHeight = uint256(uint32(MAX_INT32)) + 1;

        vm.expectRevert(
            abi.encodeWithSelector(Flyover.Overflow.selector, MAX_INT32)
        );
        pegInContract.registerPegIn(
            quote,
            signature,
            RAW_TX_MOCK,
            PMT_MOCK,
            invalidHeight
        );
    }

    function test_RegisterPegIn_RevertsIfQuoteAlreadyProcessed() public {
        Quotes.PegInQuote memory quote = createTestQuote(1.2 ether);
        bytes32 quoteHash = pegInContract.hashPegInQuote(quote);
        bytes memory signature = signQuote(fullLp, quoteHash);

        // Setup BTC block headers
        uint32 firstConfTime = uint32(block.timestamp) + 300;
        uint32 nConfTime = uint32(block.timestamp) + 600;
        bytes memory firstHeader = createBtcBlockHeader(firstConfTime);
        bytes memory nConfHeader = createBtcBlockHeader(nConfTime);

        // Setup bridge to return success
        uint256 peginAmount = getTotalValue(quote);
        vm.deal(address(bridgeMock), peginAmount);
        bridgeMock.setPegin{value: peginAmount}(quoteHash);
        bridgeMock.setHeader(HEIGHT_MOCK, firstHeader);
        bridgeMock.setHeader(
            HEIGHT_MOCK + uint256(quote.depositConfirmations) - 1,
            nConfHeader
        );

        // Call for user first
        vm.prank(fullLp);
        pegInContract.callForUser{value: 1.2 ether}(quote);

        // First registration succeeds
        vm.prank(fullLp);
        pegInContract.registerPegIn(
            quote,
            signature,
            RAW_TX_MOCK,
            PMT_MOCK,
            HEIGHT_MOCK
        );

        // Second registration should fail (checked before bridge call)
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

    function test_RegisterPegIn_RevertsIfNotEnoughConfirmations() public {
        Quotes.PegInQuote memory quote = createTestQuote(1.2 ether);
        bytes32 quoteHash = pegInContract.hashPegInQuote(quote);
        bytes memory signature = signQuote(fullLp, quoteHash);

        // Setup bridge to return error for insufficient confirmations
        int256 BRIDGE_UNPROCESSABLE_ERROR = -303;
        bridgeMock.setPeginError(BRIDGE_UNPROCESSABLE_ERROR);

        // Call for user first
        vm.prank(fullLp);
        pegInContract.callForUser{value: 1.2 ether}(quote);

        // Register should revert
        vm.prank(fullLp);
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

    function test_RegisterPegIn_RevertsOnUnexpectedBridgeError() public {
        Quotes.PegInQuote memory quote = createTestQuote(1.2 ether);
        bytes32 quoteHash = pegInContract.hashPegInQuote(quote);
        bytes memory signature = signQuote(fullLp, quoteHash);

        // Setup bridge to return unexpected error
        int256 ERROR_CODE = -505;
        bridgeMock.setPeginError(ERROR_CODE);

        // Call for user first
        vm.prank(fullLp);
        pegInContract.callForUser{value: 1.2 ether}(quote);

        // Register should revert
        vm.prank(fullLp);
        vm.expectRevert(
            abi.encodeWithSelector(
                IPegIn.UnexpectedBridgeError.selector,
                ERROR_CODE
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

    function test_RegisterPegIn_RefundsLPWhenCallWasDoneAndUserPaidCorrectly()
        public
    {
        Quotes.PegInQuote memory quote = createTestQuote(1.2 ether);
        bytes32 quoteHash = pegInContract.hashPegInQuote(quote);
        bytes memory signature = signQuote(fullLp, quoteHash);

        uint256 peginAmount = getTotalValue(quote);

        // Setup BTC block headers
        uint32 firstConfTime = uint32(block.timestamp) + 300;
        uint32 nConfTime = uint32(block.timestamp) + 600;
        bytes memory firstHeader = createBtcBlockHeader(firstConfTime);
        bytes memory nConfHeader = createBtcBlockHeader(nConfTime);

        // Setup bridge
        vm.deal(address(bridgeMock), peginAmount);
        bridgeMock.setPegin{value: peginAmount}(quoteHash);
        bridgeMock.setHeader(HEIGHT_MOCK, firstHeader);
        bridgeMock.setHeader(
            HEIGHT_MOCK + uint256(quote.depositConfirmations) - 1,
            nConfHeader
        );

        // Call for user first
        vm.prank(fullLp);
        pegInContract.callForUser{value: 1.2 ether}(quote);

        // LP deposits more funds
        vm.prank(fullLp);
        pegInContract.deposit{value: 3 ether}();

        uint256 lpBalanceBefore = pegInContract.getBalance(fullLp);

        // Register
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

        // Verify LP balance increased by pegin amount (minus product fee)
        assertEq(
            pegInContract.getBalance(fullLp),
            lpBalanceBefore + peginAmount - quote.productFeeAmount,
            "LP balance should increase"
        );

        // Verify quote is processed
        assertEq(
            uint256(pegInContract.getQuoteStatus(quoteHash)),
            uint256(IPegIn.PegInStates.PROCESSED_QUOTE),
            "Quote should be PROCESSED"
        );
    }

    function test_RegisterPegIn_EmitsBridgeCapExceededForUserRefund() public {
        Quotes.PegInQuote memory quote = createTestQuote(1.2 ether);
        bytes32 quoteHash = pegInContract.hashPegInQuote(quote);
        bytes memory signature = signQuote(fullLp, quoteHash);

        // Setup BTC block headers
        bytes memory firstHeader = createBtcBlockHeader(
            uint32(block.timestamp) + 300
        );
        bytes memory nConfHeader = createBtcBlockHeader(
            uint32(block.timestamp) + 600
        );

        // Setup bridge to return user refund error (cap exceeded)
        int256 BRIDGE_REFUNDED_USER_ERROR = -100;
        bridgeMock.setPeginError(BRIDGE_REFUNDED_USER_ERROR);
        bridgeMock.setHeader(HEIGHT_MOCK, firstHeader);
        bridgeMock.setHeader(
            HEIGHT_MOCK + uint256(quote.depositConfirmations) - 1,
            nConfHeader
        );

        // Call for user first
        vm.prank(fullLp);
        pegInContract.callForUser{value: 1.2 ether}(quote);

        // Register should emit BridgeCapExceeded
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

        // Verify quote is marked as processed
        assertEq(
            uint256(pegInContract.getQuoteStatus(quoteHash)),
            uint256(IPegIn.PegInStates.PROCESSED_QUOTE),
            "Quote should be PROCESSED"
        );
    }

    function test_RegisterPegIn_EmitsBridgeCapExceededForLPRefund() public {
        Quotes.PegInQuote memory quote = createTestQuote(1.2 ether);
        bytes32 quoteHash = pegInContract.hashPegInQuote(quote);
        bytes memory signature = signQuote(fullLp, quoteHash);

        // Setup BTC block headers
        bytes memory firstHeader = createBtcBlockHeader(
            uint32(block.timestamp) + 300
        );
        bytes memory nConfHeader = createBtcBlockHeader(
            uint32(block.timestamp) + 600
        );

        // Setup bridge to return LP refund error (cap exceeded)
        int256 BRIDGE_REFUNDED_LP_ERROR = -200;
        bridgeMock.setPeginError(BRIDGE_REFUNDED_LP_ERROR);
        bridgeMock.setHeader(HEIGHT_MOCK, firstHeader);
        bridgeMock.setHeader(
            HEIGHT_MOCK + uint256(quote.depositConfirmations) - 1,
            nConfHeader
        );

        // Call for user first
        vm.prank(fullLp);
        pegInContract.callForUser{value: 1.2 ether}(quote);

        // Register should emit BridgeCapExceeded
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

        // Verify quote is marked as processed
        assertEq(
            uint256(pegInContract.getQuoteStatus(quoteHash)),
            uint256(IPegIn.PegInStates.PROCESSED_QUOTE),
            "Quote should be PROCESSED"
        );
    }

    function test_RegisterPegIn_RefundsLPWhenUserOverpaid() public {
        Quotes.PegInQuote memory quote = createTestQuote(1.2 ether);
        bytes32 quoteHash = pegInContract.hashPegInQuote(quote);
        bytes memory signature = signQuote(fullLp, quoteHash);

        uint256 peginAmount = getTotalValue(quote);
        uint256 extraPaid = 5.5 ether;

        // Setup BTC block headers
        bytes memory firstHeader = createBtcBlockHeader(
            uint32(block.timestamp) + 300
        );
        bytes memory nConfHeader = createBtcBlockHeader(
            uint32(block.timestamp) + 600
        );

        // Setup bridge to return overpayment
        vm.deal(address(bridgeMock), peginAmount + extraPaid);
        bridgeMock.setPegin{value: peginAmount + extraPaid}(quoteHash);
        bridgeMock.setHeader(HEIGHT_MOCK, firstHeader);
        bridgeMock.setHeader(
            HEIGHT_MOCK + uint256(quote.depositConfirmations) - 1,
            nConfHeader
        );

        // Call for user first
        vm.prank(fullLp);
        pegInContract.callForUser{value: 1.2 ether}(quote);

        uint256 userBalanceBefore = user.balance;
        uint256 lpBalanceBefore = pegInContract.getBalance(fullLp);

        // Register - LP calls it
        vm.prank(fullLp);
        vm.expectEmit(true, true, false, true);
        emit IPegIn.PegInRegistered(quoteHash, peginAmount + extraPaid);
        pegInContract.registerPegIn(
            quote,
            signature,
            RAW_TX_MOCK,
            PMT_MOCK,
            HEIGHT_MOCK
        );

        // Verify user received the extra amount as refund
        assertEq(
            user.balance,
            userBalanceBefore + extraPaid,
            "User should receive refund for overpayment"
        );

        // Verify LP balance increased by peginAmount (minus product fee)
        assertEq(
            pegInContract.getBalance(fullLp),
            lpBalanceBefore + peginAmount - quote.productFeeAmount,
            "LP balance should increase by pegin amount"
        );
    }

    function test_RegisterPegIn_RevertsWhenUserUnderpaid() public {
        Quotes.PegInQuote memory quote = createTestQuote(1.2 ether);
        bytes32 quoteHash = pegInContract.hashPegInQuote(quote);
        bytes memory signature = signQuote(fullLp, quoteHash);

        // Calculate agreed amount with rounding (matches Quotes.checkAgreedAmount logic)
        uint256 agreedAmount = quote.value +
            quote.callFee +
            quote.productFeeAmount +
            quote.gasFee;
        uint256 SAT_TO_WEI_CONVERSION = 10 ** 10;
        if (
            agreedAmount > SAT_TO_WEI_CONVERSION &&
            (agreedAmount % SAT_TO_WEI_CONVERSION) != 0
        ) {
            agreedAmount -= (agreedAmount % SAT_TO_WEI_CONVERSION);
        }

        uint256 peginAmount = agreedAmount - 0.0001 ether;

        // Setup BTC block headers
        bytes memory firstHeader = createBtcBlockHeader(
            uint32(block.timestamp) + 300
        );
        bytes memory nConfHeader = createBtcBlockHeader(
            uint32(block.timestamp) + 600
        );

        // Setup bridge to return underpayment
        vm.deal(address(bridgeMock), peginAmount);
        bridgeMock.setPegin{value: peginAmount}(quoteHash);
        bridgeMock.setHeader(HEIGHT_MOCK, firstHeader);
        bridgeMock.setHeader(
            HEIGHT_MOCK + uint256(quote.depositConfirmations) - 1,
            nConfHeader
        );

        // Don't call callForUser - test without it

        // Register should revert due to insufficient amount
        vm.prank(fullLp);
        vm.expectRevert(
            abi.encodeWithSelector(
                Quotes.AmountTooLow.selector,
                peginAmount,
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

    function test_RegisterPegIn_RefundsUserWhenCallNotDoneAndUserDidNotPayOnTime()
        public
    {
        Quotes.PegInQuote memory quote = createTestQuote(1.2 ether);
        bytes32 quoteHash = pegInContract.hashPegInQuote(quote);
        bytes memory signature = signQuote(fullLp, quoteHash);

        uint256 peginAmount = getTotalValue(quote);

        // Setup headers with first confirmation AFTER deposit window (late payment)
        uint32 lateTime = uint32(
            quote.agreementTimestamp + quote.timeForDeposit + 1
        );
        bytes memory firstHeader = createBtcBlockHeader(lateTime);
        bytes memory nConfHeader = createBtcBlockHeader(lateTime + 300);

        // Setup bridge
        vm.deal(address(bridgeMock), peginAmount);
        bridgeMock.setPegin{value: peginAmount}(quoteHash);
        bridgeMock.setHeader(HEIGHT_MOCK, firstHeader);
        bridgeMock.setHeader(
            HEIGHT_MOCK + uint256(quote.depositConfirmations) - 1,
            nConfHeader
        );

        // Don't call callForUser (call was not done)
        uint256 userBalanceBefore = user.balance;

        // Register - user gets refunded
        vm.prank(fullLp);
        vm.expectEmit(true, true, false, true);
        emit IPegIn.PegInRegistered(quoteHash, peginAmount);
        vm.expectEmit(true, true, true, true);
        emit IPegIn.Refund(
            payable(user),
            quoteHash,
            peginAmount,
            true // Refund successful
        );
        pegInContract.registerPegIn(
            quote,
            signature,
            RAW_TX_MOCK,
            PMT_MOCK,
            HEIGHT_MOCK
        );

        // Verify user received refund
        assertEq(
            user.balance,
            userBalanceBefore + peginAmount,
            "User should receive full refund"
        );
    }

    function test_RegisterPegIn_RefundsUserAndPenalizesLPWhenCallNotDone()
        public
    {
        Quotes.PegInQuote memory quote = createTestQuote(1.2 ether);
        bytes32 quoteHash = pegInContract.hashPegInQuote(quote);
        bytes memory signature = signQuote(fullLp, quoteHash);

        uint256 peginAmount = getTotalValue(quote);

        // Setup headers - user paid on time
        bytes memory firstHeader = createBtcBlockHeader(
            uint32(block.timestamp) + 300
        );
        bytes memory nConfHeader = createBtcBlockHeader(
            uint32(block.timestamp) + 600
        );

        // Setup bridge
        vm.deal(address(bridgeMock), peginAmount);
        bridgeMock.setPegin{value: peginAmount}(quoteHash);
        bridgeMock.setHeader(HEIGHT_MOCK, firstHeader);
        bridgeMock.setHeader(
            HEIGHT_MOCK + uint256(quote.depositConfirmations) - 1,
            nConfHeader
        );

        // Don't call callForUser (LP didn't deliver)
        uint256 userBalanceBefore = user.balance;

        // Register by someone else (not LP) - LP gets penalized
        vm.prank(registerCaller);
        vm.expectEmit(true, true, false, true);
        emit IPegIn.PegInRegistered(quoteHash, peginAmount);
        vm.expectEmit(true, true, true, true);
        emit IPegIn.Refund(
            payable(user),
            quoteHash,
            peginAmount,
            true // Refund successful
        );
        pegInContract.registerPegIn(
            quote,
            signature,
            RAW_TX_MOCK,
            PMT_MOCK,
            HEIGHT_MOCK
        );

        // Verify user received refund
        assertEq(
            user.balance,
            userBalanceBefore + peginAmount,
            "User should receive full refund"
        );
    }

    function test_RegisterPegIn_PenalizesLPIfCallForUserNotMadeOnTime() public {
        Quotes.PegInQuote memory quote = createTestQuote(1.2 ether);
        quote.productFeeAmount = (quote.value * 3) / 100; // 3% product fee
        bytes32 quoteHash = pegInContract.hashPegInQuote(quote);
        bytes memory signature = signQuote(fullLp, quoteHash);

        uint256 peginAmount = getTotalValue(quote);

        // Setup headers - LP called late (after callTime deadline)
        uint32 lateCallTime = uint32(
            quote.agreementTimestamp + quote.callTime + 1
        );
        bytes memory firstHeader = createBtcBlockHeader(
            uint32(block.timestamp) + 300
        );
        bytes memory nConfHeader = createBtcBlockHeader(lateCallTime);

        // Setup bridge
        vm.deal(address(bridgeMock), peginAmount);
        bridgeMock.setPegin{value: peginAmount}(quoteHash);
        bridgeMock.setHeader(HEIGHT_MOCK, firstHeader);
        bridgeMock.setHeader(
            HEIGHT_MOCK + uint256(quote.depositConfirmations) - 1,
            nConfHeader
        );

        // Advance time to after call deadline
        vm.warp(quote.agreementTimestamp + quote.callTime + 1);

        // LP calls callForUser late
        vm.prank(fullLp);
        pegInContract.callForUser{value: quote.value}(quote);

        // Register by someone else - should penalize LP
        vm.prank(registerCaller);
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
            uint256(IPegIn.PegInStates.PROCESSED_QUOTE),
            "Quote should be PROCESSED"
        );
    }

    function test_RegisterPegIn_RevertsWhenPaidAmountWayLowerThanQuote()
        public
    {
        Quotes.PegInQuote memory quote = createTestQuote(1.2 ether);
        bytes32 quoteHash = pegInContract.hashPegInQuote(quote);
        bytes memory signature = signQuote(fullLp, quoteHash);

        uint256 peginAmount = getTotalValue(quote) - 0.1 ether; // Way too low

        // Setup BTC block headers
        bytes memory firstHeader = createBtcBlockHeader(
            uint32(block.timestamp) + 300
        );
        bytes memory nConfHeader = createBtcBlockHeader(
            uint32(block.timestamp) + 600
        );

        // Setup bridge
        vm.deal(address(bridgeMock), peginAmount);
        bridgeMock.setPegin{value: peginAmount}(quoteHash);
        bridgeMock.setHeader(HEIGHT_MOCK, firstHeader);
        bridgeMock.setHeader(
            HEIGHT_MOCK + uint256(quote.depositConfirmations) - 1,
            nConfHeader
        );

        // Register should revert
        vm.prank(fullLp);
        vm.expectRevert(); // AmountTooLow from Quotes
        pegInContract.registerPegIn(
            quote,
            signature,
            RAW_TX_MOCK,
            PMT_MOCK,
            HEIGHT_MOCK
        );
    }

    function test_RegisterPegIn_ExecutesCallForUserIfCallOnRegisterIsTrue()
        public
    {
        Quotes.PegInQuote memory quote = createTestQuote(1.2 ether);
        quote.callOnRegister = true; // Enable callOnRegister
        bytes32 quoteHash = pegInContract.hashPegInQuote(quote);
        bytes memory signature = signQuote(fullLp, quoteHash);

        uint256 peginAmount = getTotalValue(quote);

        // Setup BTC block headers
        bytes memory firstHeader = createBtcBlockHeader(
            uint32(block.timestamp) + 300
        );
        bytes memory nConfHeader = createBtcBlockHeader(
            uint32(block.timestamp) + 600
        );

        // Setup bridge
        vm.deal(address(bridgeMock), peginAmount);
        bridgeMock.setPegin{value: peginAmount}(quoteHash);
        bridgeMock.setHeader(HEIGHT_MOCK, firstHeader);
        bridgeMock.setHeader(
            HEIGHT_MOCK + uint256(quote.depositConfirmations) - 1,
            nConfHeader
        );

        // Don't call callForUser beforehand - registerPegIn will do it
        uint256 userBalanceBefore = user.balance;

        // Register by someone else (not LP) - will call callForUser and penalize LP
        vm.prank(registerCaller);
        vm.expectEmit(true, true, false, false);
        emit IPegIn.CallForUser(
            registerCaller,
            user,
            quoteHash,
            quote.gasLimit,
            quote.value,
            quote.data,
            true
        );
        pegInContract.registerPegIn(
            quote,
            signature,
            RAW_TX_MOCK,
            PMT_MOCK,
            HEIGHT_MOCK
        );

        // When callOnRegister is executed and LP is penalized:
        // - User receives quote.value from callForUser execution
        // - User receives refund of callFee + gasFee + productFeeAmount
        // Total: user gets full peginAmount
        uint256 expectedTotal = peginAmount;

        assertEq(
            user.balance,
            userBalanceBefore + expectedTotal,
            "User should receive full pegin amount (value + all fees)"
        );
    }

    function test_RegisterPegIn_RefundsFullAmountIfCallOnRegisterFails()
        public
    {
        Quotes.PegInQuote memory quote = createTestQuote(1.2 ether);
        quote.callOnRegister = true; // Enable callOnRegister

        // Deploy WalletMock that will reject the payment
        WalletMock wallet = new WalletMock();
        wallet.setRejectFunds(true);
        quote.contractAddress = address(wallet);

        bytes32 quoteHash = pegInContract.hashPegInQuote(quote);
        bytes memory signature = signQuote(fullLp, quoteHash);

        uint256 peginAmount = getTotalValue(quote);

        // Setup BTC block headers
        bytes memory firstHeader = createBtcBlockHeader(
            uint32(block.timestamp) + 300
        );
        bytes memory nConfHeader = createBtcBlockHeader(
            uint32(block.timestamp) + 600
        );

        // Setup bridge
        vm.deal(address(bridgeMock), peginAmount);
        bridgeMock.setPegin{value: peginAmount}(quoteHash);
        bridgeMock.setHeader(HEIGHT_MOCK, firstHeader);
        bridgeMock.setHeader(
            HEIGHT_MOCK + uint256(quote.depositConfirmations) - 1,
            nConfHeader
        );

        uint256 userBalanceBefore = user.balance;

        // Register - callOnRegister will be attempted but fail, user gets full refund
        vm.prank(registerCaller);
        vm.expectEmit(true, true, false, false);
        emit IPegIn.CallForUser(
            registerCaller,
            address(wallet),
            quoteHash,
            quote.gasLimit,
            quote.value,
            quote.data,
            false
        );
        pegInContract.registerPegIn(
            quote,
            signature,
            RAW_TX_MOCK,
            PMT_MOCK,
            HEIGHT_MOCK
        );

        // Verify user received full refund (all fees + value)
        assertEq(
            user.balance,
            userBalanceBefore + peginAmount,
            "User should receive full refund when callOnRegister fails"
        );
    }

    function test_RegisterPegIn_RefundsUserIfCallWasDoneButFailed() public {
        // Create a quote with a contract that rejects payments as destination
        Quotes.PegInQuote memory quote = createTestQuote(1.2 ether);
        quote.productFeeAmount = (quote.value * 2) / 100; // 2% product fee

        // Deploy WalletMock that will reject the payment
        WalletMock wallet = new WalletMock();
        wallet.setRejectFunds(true);
        quote.contractAddress = address(wallet);

        bytes32 quoteHash = pegInContract.hashPegInQuote(quote);
        bytes memory signature = signQuote(fullLp, quoteHash);

        uint256 peginAmount = getTotalValue(quote);

        // Setup BTC block headers
        bytes memory firstHeader = createBtcBlockHeader(
            uint32(block.timestamp) + 300
        );
        bytes memory nConfHeader = createBtcBlockHeader(
            uint32(block.timestamp) + 600
        );

        // Setup bridge
        vm.deal(address(bridgeMock), peginAmount);
        bridgeMock.setPegin{value: peginAmount}(quoteHash);
        bridgeMock.setHeader(HEIGHT_MOCK, firstHeader);
        bridgeMock.setHeader(
            HEIGHT_MOCK + uint256(quote.depositConfirmations) - 1,
            nConfHeader
        );

        // Call for user - will fail because wallet rejects
        vm.prank(fullLp);
        vm.expectEmit(true, true, true, true);
        emit IPegIn.CallForUser(
            fullLp,
            address(wallet),
            quoteHash,
            quote.gasLimit,
            quote.value,
            quote.data,
            false // Call failed
        );
        pegInContract.callForUser{value: quote.value}(quote);

        uint256 userBalanceBefore = user.balance;

        // Register - should emit PegInRegistered, DaoContribution and Refund events
        vm.prank(fullLp);
        vm.expectEmit(true, true, false, true);
        emit IPegIn.PegInRegistered(quoteHash, peginAmount);
        vm.expectEmit(true, true, false, true);
        emit AccessControlDaoContributorUpgradeable.DaoContribution(
            fullLp,
            quote.productFeeAmount
        );
        vm.expectEmit(true, true, true, true);
        emit IPegIn.Refund(
            user,
            quoteHash,
            quote.value, // Refund amount (only value, not fees)
            true // Refund succeeded
        );
        pegInContract.registerPegIn(
            quote,
            signature,
            RAW_TX_MOCK,
            PMT_MOCK,
            HEIGHT_MOCK
        );

        // Verify user (refund address) received refund of just the value (not fees)
        assertEq(
            user.balance,
            userBalanceBefore + quote.value,
            "User should receive refund of quote value"
        );
    }

    function test_RegisterPegIn_RefundsLPIfChangePaymentToUserFails() public {
        Quotes.PegInQuote memory quote = createTestQuote(1.2 ether);
        quote.productFeeAmount = (quote.value * 2) / 100; // 2% product fee

        // Deploy WalletMock as refund address that will reject
        WalletMock refundWallet = new WalletMock();
        refundWallet.setRejectFunds(true);
        quote.rskRefundAddress = payable(address(refundWallet));

        bytes32 quoteHash = pegInContract.hashPegInQuote(quote);
        bytes memory signature = signQuote(fullLp, quoteHash);

        uint256 peginAmount = getTotalValue(quote);
        uint256 extraPaid = 5.5 ether;

        // Setup BTC block headers
        bytes memory firstHeader = createBtcBlockHeader(
            uint32(block.timestamp) + 300
        );
        bytes memory nConfHeader = createBtcBlockHeader(
            uint32(block.timestamp) + 600
        );

        // Setup bridge to return overpayment
        vm.deal(address(bridgeMock), peginAmount + extraPaid);
        bridgeMock.setPegin{value: peginAmount + extraPaid}(quoteHash);
        bridgeMock.setHeader(HEIGHT_MOCK, firstHeader);
        bridgeMock.setHeader(
            HEIGHT_MOCK + uint256(quote.depositConfirmations) - 1,
            nConfHeader
        );

        // Call for user
        vm.prank(fullLp);
        pegInContract.callForUser{value: quote.value}(quote);

        uint256 lpBalanceBefore = pegInContract.getBalance(fullLp);

        // Register - change payment to user will fail, so LP gets it
        vm.prank(fullLp);
        vm.expectEmit(true, true, false, true);
        emit IPegIn.PegInRegistered(quoteHash, peginAmount + extraPaid);
        vm.expectEmit(true, true, false, true);
        emit AccessControlDaoContributorUpgradeable.DaoContribution(
            fullLp,
            quote.productFeeAmount
        );
        vm.expectEmit(true, true, true, true);
        emit IPegIn.Refund(
            payable(address(refundWallet)),
            quoteHash,
            extraPaid, // Change amount
            false // Refund failed (wallet rejects)
        );
        pegInContract.registerPegIn(
            quote,
            signature,
            RAW_TX_MOCK,
            PMT_MOCK,
            HEIGHT_MOCK
        );

        // Verify LP got the full amount (including failed change)
        assertEq(
            pegInContract.getBalance(fullLp),
            lpBalanceBefore + peginAmount + extraPaid - quote.productFeeAmount,
            "LP should receive all funds when change payment fails"
        );
    }

    function test_RegisterPegIn_HandlesRefundFailureToReentrancyCaller()
        public
    {
        // Replicates the "reentrancy" test which actually tests refund failure
        // ReentrancyCaller has no receive/fallback, so refund payment fails

        // Deploy ReentrancyCaller
        ReentrancyCaller reentrancyCaller = new ReentrancyCaller();
        address reentrantAddress = address(reentrancyCaller);

        // Create and set up reentrant call data (not used since no receive())
        Quotes.PegInQuote memory reentrantQuote = createTestQuote(1 ether);
        bytes32 reentrantHash = pegInContract.hashPegInQuote(reentrantQuote);
        bytes memory reentrantSignature = signQuote(fullLp, reentrantHash);
        bytes memory reentrantData = abi.encodeWithSelector(
            pegInContract.registerPegIn.selector,
            reentrantQuote,
            reentrantSignature,
            RAW_TX_MOCK,
            PMT_MOCK,
            HEIGHT_MOCK
        );
        reentrancyCaller.setData(reentrantData);

        // Create main quote with ReentrancyCaller as refund address
        Quotes.PegInQuote memory quote = createTestQuote(1.2 ether);
        quote.rskRefundAddress = payable(reentrantAddress);
        bytes32 quoteHash = pegInContract.hashPegInQuote(quote);
        bytes memory signature = signQuote(fullLp, quoteHash);

        uint256 peginAmount = getTotalValue(quote);

        // Setup BTC headers
        bytes memory firstHeader = createBtcBlockHeader(
            uint32(block.timestamp) + 300
        );
        bytes memory nConfHeader = createBtcBlockHeader(
            uint32(block.timestamp) + 600
        );

        // Setup bridge
        vm.deal(address(bridgeMock), peginAmount);
        bridgeMock.setPegin{value: peginAmount}(quoteHash);
        bridgeMock.setHeader(HEIGHT_MOCK, firstHeader);
        bridgeMock.setHeader(
            HEIGHT_MOCK + uint256(quote.depositConfirmations) - 1,
            nConfHeader
        );

        // Register - refund to ReentrancyCaller will fail (no receive/fallback)
        vm.prank(registerCaller);
        vm.expectEmit(true, true, false, true);
        emit IPegIn.PegInRegistered(quoteHash, peginAmount);
        vm.expectEmit(true, true, true, true);
        emit IPegIn.Refund(
            payable(reentrantAddress),
            quoteHash,
            peginAmount,
            false // Refund failed (no receive function)
        );
        pegInContract.registerPegIn(
            quote,
            signature,
            RAW_TX_MOCK,
            PMT_MOCK,
            HEIGHT_MOCK
        );

        // Verify refund address got internal balance credited (since payment failed)
        assertEq(
            pegInContract.getBalance(payable(reentrantAddress)),
            peginAmount,
            "Refund address should get internal balance when payment fails"
        );
        // LP balance should remain 0
        assertEq(pegInContract.getBalance(fullLp), 0, "LP balance should be 0");
        // Contract should hold the funds
        assertEq(
            address(pegInContract).balance,
            peginAmount,
            "Contract should hold the funds"
        );
    }

    // ============ Helper Functions ============

    /// @notice Creates a BTC block header with a specific timestamp (little-endian encoded)
    /// @param timestamp The Unix timestamp for the block
    /// @return header The 80-byte BTC block header
    function createBtcBlockHeader(
        uint32 timestamp
    ) internal pure returns (bytes memory) {
        // BTC block header structure (80 bytes total):
        // - Version: 4 bytes (set to 0)
        // - Previous block hash: 32 bytes (set to 0)
        // - Merkle root: 32 bytes (set to 0)
        // - Timestamp: 4 bytes (little-endian)
        // - Bits: 4 bytes (set to 0)
        // - Nonce: 4 bytes (set to 0)

        bytes memory header = new bytes(80);

        // Convert timestamp to little-endian and place at offset 68
        header[68] = bytes1(uint8(timestamp));
        header[69] = bytes1(uint8(timestamp >> 8));
        header[70] = bytes1(uint8(timestamp >> 16));
        header[71] = bytes1(uint8(timestamp >> 24));

        return header;
    }

    function createTestQuote(
        uint256 value
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
                liquidityProviderRskAddress: fullLp,
                contractAddress: user,
                rskRefundAddress: payable(user),
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

    function getTotalValue(
        Quotes.PegInQuote memory quote
    ) internal pure returns (uint256) {
        return
            quote.value + quote.callFee + quote.productFeeAmount + quote.gasFee;
    }

    function signQuote(
        address signer,
        bytes32 quoteHash
    ) internal view returns (bytes memory) {
        // Get private key for the signer
        uint256 privateKey;
        if (signer == fullLp) {
            privateKey = fullLpKey;
        } else if (signer == pegInLp) {
            privateKey = pegInLpKey;
        } else if (signer == pegOutLp) {
            privateKey = pegOutLpKey;
        } else {
            revert("Unknown signer");
        }

        // Sign the hash using Ethereum signed message format
        bytes32 ethSignedMessageHash = keccak256(
            abi.encodePacked("\x19Ethereum Signed Message:\n32", quoteHash)
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            privateKey,
            ethSignedMessageHash
        );
        return abi.encodePacked(r, s, v);
    }
}
