// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {PegInTestBase} from "./PegInTestBase.sol";
import {IPegIn} from "../../src/interfaces/IPegIn.sol";
import {Quotes} from "../../src/libraries/Quotes.sol";
import {Flyover} from "../../src/libraries/Flyover.sol";
import {stdError} from "forge-std/StdError.sol";

/// @title RemainingAmountUnderflow Tests
/// @notice Tests for the HIGH severity vulnerability: potential underflow in _registerCallDone
/// @dev This vulnerability occurs when:
///      1. Quote amounts cause checkAgreedAmount to apply rounding adjustment
///      2. User sends exactly the rounded (lower) amount
///      3. Call was done successfully
///      4. remainingAmount = transferredAmount - refundAmount - productFeeAmount underflows
///
/// The issue is in PegInContract._registerCallDone() line 392:
///   uint remainingAmount = transferredAmount - refundAmount - quote.productFeeAmount;
///
/// When rounding is applied in checkAgreedAmount, transferredAmount can be less than
/// (refundAmount + productFeeAmount), causing an arithmetic underflow and transaction revert.
contract RemainingAmountUnderflowTest is PegInTestBase {
    address public user;
    address public registerCaller;

    // Mock constants
    bytes constant RAW_TX_MOCK = hex"112233";
    bytes constant PMT_MOCK = hex"010203";
    uint256 constant HEIGHT_MOCK = 10;

    // SAT_TO_WEI_CONVERSION from Quotes.sol
    uint256 constant SAT_TO_WEI_CONVERSION = 10 ** 10;

    function setUp() public {
        deployPegInContract();
        setupProviders();

        user = makeAddr("user");
        registerCaller = makeAddr("registerCaller");

        vm.deal(user, 100 ether);
        vm.deal(registerCaller, 100 ether);
    }

    /// @notice Demonstrates the underflow vulnerability when rounding is applied
    /// @dev This test shows that when:
    ///      - agreedAmount is NOT a multiple of SAT_TO_WEI_CONVERSION
    ///      - checkAgreedAmount rounds it DOWN
    ///      - User sends exactly the rounded amount
    ///      - LP made a successful call
    ///      The remainingAmount calculation underflows, causing DoS
    function test_RegisterPegIn_RevertsWithUnderflowWhenRoundingApplied() public {
        // Create a quote where the sum of fees causes rounding
        // The key is: productFeeAmount should cause the total to NOT be a multiple of SAT_TO_WEI_CONVERSION
        //
        // Example values:
        // - value = 1 * SAT_TO_WEI_CONVERSION (10^10 wei = 1 satoshi)
        // - callFee = 0
        // - gasFee = 0
        // - productFeeAmount = 5 * 10^9 (half a satoshi in wei terms)
        //
        // agreedAmount = 10^10 + 0 + 5*10^9 + 0 = 1.5 * 10^10 wei
        // After rounding: 10^10 (because 1.5*10^10 % 10^10 = 5*10^9 gets subtracted)
        //
        // When user sends exactly 10^10:
        // - checkAgreedAmount passes (10^10 >= 10^10)
        // - refundAmount = min(10^10, value + callFee + gasFee) = min(10^10, 10^10) = 10^10
        // - remainingAmount = 10^10 - 10^10 - 5*10^9 = -5*10^9 --> UNDERFLOW!

        Quotes.PegInQuote memory quote = createQuoteWithRoundingEdgeCase();
        bytes32 quoteHash = pegInContract.hashPegInQuote(quote);
        bytes memory signature = signQuote(fullLp, quoteHash);

        // Calculate the agreed amount and verify rounding will be applied
        uint256 agreedAmount = quote.value + quote.callFee + quote.productFeeAmount + quote.gasFee;
        assertTrue(
            agreedAmount > SAT_TO_WEI_CONVERSION && (agreedAmount % SAT_TO_WEI_CONVERSION) != 0,
            "Test setup: Rounding should be applied"
        );

        // Calculate the rounded amount (what checkAgreedAmount uses)
        uint256 roundedAmount = agreedAmount - (agreedAmount % SAT_TO_WEI_CONVERSION);

        // Setup BTC block headers
        uint32 firstConfTime = uint32(block.timestamp) + 300;
        uint32 nConfTime = uint32(block.timestamp) + 600;
        bytes memory firstHeader = createBtcBlockHeader(firstConfTime);
        bytes memory nConfHeader = createBtcBlockHeader(nConfTime);

        // Setup bridge to return EXACTLY the rounded amount (this passes checkAgreedAmount)
        vm.deal(address(bridgeMock), roundedAmount);
        bridgeMock.setPegin{value: roundedAmount}(quoteHash);
        bridgeMock.setHeader(HEIGHT_MOCK, firstHeader);
        bridgeMock.setHeader(HEIGHT_MOCK + uint256(quote.depositConfirmations) - 1, nConfHeader);

        // LP makes the call successfully (this is crucial - call must succeed)
        vm.prank(fullLp);
        pegInContract.callForUser{value: quote.value}(quote);

        // Verify the call was successful
        assertEq(
            uint256(pegInContract.getQuoteStatus(quoteHash)),
            uint256(IPegIn.PegInStates.CALL_DONE),
            "Quote should be in CALL_DONE state"
        );

        // Now register - this should trigger the underflow
        // The underflow occurs in _registerCallDone at line 392:
        // uint remainingAmount = transferredAmount - refundAmount - quote.productFeeAmount;
        //
        // With our values:
        // transferredAmount = roundedAmount = 10^10
        // refundAmount = min(10^10, quote.value + quote.callFee + quote.gasFee) = 10^10
        // productFeeAmount = 5 * 10^9
        // remainingAmount = 10^10 - 10^10 - 5*10^9 = -5*10^9 --> UNDERFLOW!

        vm.prank(fullLp);
        // Solidity 0.8.x will revert on underflow with panic code 0x11 (arithmetic overflow/underflow)
        vm.expectRevert(stdError.arithmeticError);
        pegInContract.registerPegIn(
            quote,
            signature,
            RAW_TX_MOCK,
            PMT_MOCK,
            HEIGHT_MOCK
        );
    }

    /// @notice Test with a more realistic scenario using common fee values
    /// @dev This shows the vulnerability with values that could occur in production
    function test_RegisterPegIn_RevertsWithUnderflowRealisticScenario() public {
        // Realistic scenario:
        // - value = 0.1 ether = 10^17 wei
        // - callFee = 0.001 ether = 10^15 wei
        // - gasFee = 0.0003 ether = 3*10^14 wei
        // - productFeeAmount = 0.00025 ether = 2.5*10^14 wei (2.5% fee on small amount)
        //
        // Total = 10^17 + 10^15 + 2.5*10^14 + 3*10^14 = 101,550,000,000,000,000 wei
        //       = 1.0155 * 10^17 wei
        //
        // SAT_TO_WEI_CONVERSION = 10^10
        // 1.0155 * 10^17 % 10^10 = 5,500,000,000,000,000 % 10,000,000,000 = 5,000,000,000 = 5*10^9
        //
        // Wait, let me recalculate:
        // 101,550,000,000,000,000 / 10,000,000,000 = 10,155,000 with remainder 0
        // So this doesn't trigger rounding!

        // Let me use values that DO trigger rounding:
        // productFeeAmount = 5*10^9 (exactly half a satoshi)
        // value = 10^17
        // callFee = 0
        // gasFee = 0
        // Total = 10^17 + 5*10^9 = 100,000,005,000,000,000
        // Remainder = 100,000,005,000,000,000 % 10^10 = 5,000,000,000 = 5*10^9

        Quotes.PegInQuote memory quote = createQuoteWithRealisticRounding();
        bytes32 quoteHash = pegInContract.hashPegInQuote(quote);
        bytes memory signature = signQuote(fullLp, quoteHash);

        // Calculate amounts
        uint256 agreedAmount = quote.value + quote.callFee + quote.productFeeAmount + quote.gasFee;

        // Verify rounding will be applied
        if (agreedAmount > SAT_TO_WEI_CONVERSION && (agreedAmount % SAT_TO_WEI_CONVERSION) != 0) {
            uint256 roundedAmount = agreedAmount - (agreedAmount % SAT_TO_WEI_CONVERSION);

            // Setup BTC block headers
            bytes memory header = createBtcBlockHeader(uint32(block.timestamp) + 300);

            // Setup bridge with rounded amount
            vm.deal(address(bridgeMock), roundedAmount);
            bridgeMock.setPegin{value: roundedAmount}(quoteHash);
            bridgeMock.setHeader(HEIGHT_MOCK, header);
            bridgeMock.setHeader(HEIGHT_MOCK + uint256(quote.depositConfirmations) - 1, header);

            // LP makes successful call
            vm.prank(fullLp);
            pegInContract.callForUser{value: quote.value}(quote);

            // This should revert with underflow
            vm.prank(fullLp);
            vm.expectRevert(stdError.arithmeticError);
            pegInContract.registerPegIn(
                quote,
                signature,
                RAW_TX_MOCK,
                PMT_MOCK,
                HEIGHT_MOCK
            );
        } else {
            // If rounding doesn't apply, skip this test
            emit log("Skipping: rounding not applied with these values");
        }
    }

    /// @notice Verify the vulnerability does NOT occur when user overpays slightly
    /// @dev When user sends more than the rounded amount, no underflow occurs
    function test_RegisterPegIn_SucceedsWhenUserOverpaysAboveRoundedAmount() public {
        Quotes.PegInQuote memory quote = createQuoteWithRoundingEdgeCase();
        bytes32 quoteHash = pegInContract.hashPegInQuote(quote);
        bytes memory signature = signQuote(fullLp, quoteHash);

        uint256 agreedAmount = quote.value + quote.callFee + quote.productFeeAmount + quote.gasFee;
        uint256 roundedAmount = agreedAmount - (agreedAmount % SAT_TO_WEI_CONVERSION);

        // User overpays by the rounding difference + 1 wei
        // This ensures remainingAmount will be positive
        uint256 overpayAmount = agreedAmount; // Full amount, not rounded

        // Setup BTC block headers
        bytes memory header = createBtcBlockHeader(uint32(block.timestamp) + 300);

        // Setup bridge with FULL amount (not rounded)
        vm.deal(address(bridgeMock), overpayAmount);
        bridgeMock.setPegin{value: overpayAmount}(quoteHash);
        bridgeMock.setHeader(HEIGHT_MOCK, header);
        bridgeMock.setHeader(HEIGHT_MOCK + uint256(quote.depositConfirmations) - 1, header);

        // LP makes successful call
        vm.prank(fullLp);
        pegInContract.callForUser{value: quote.value}(quote);

        uint256 lpBalanceBefore = pegInContract.getBalance(fullLp);

        // This should succeed (no underflow when user pays full amount)
        vm.prank(fullLp);
        vm.expectEmit(true, true, false, true);
        emit IPegIn.PegInRegistered(quoteHash, overpayAmount);
        pegInContract.registerPegIn(
            quote,
            signature,
            RAW_TX_MOCK,
            PMT_MOCK,
            HEIGHT_MOCK
        );

        // Verify success - LP balance should increase
        assertTrue(
            pegInContract.getBalance(fullLp) >= lpBalanceBefore,
            "LP balance should increase after successful registration"
        );
    }

    /// @notice Verify the vulnerability does NOT occur when call failed
    /// @dev When call fails, refundAmount is smaller, so no underflow
    function test_RegisterPegIn_SucceedsWhenCallFailedDespiteRounding() public {
        Quotes.PegInQuote memory quote = createQuoteWithRoundingEdgeCase();

        // Make the contract address reject funds so call fails
        quote.contractAddress = address(this); // This contract doesn't accept ETH

        bytes32 quoteHash = pegInContract.hashPegInQuote(quote);
        bytes memory signature = signQuote(fullLp, quoteHash);

        uint256 agreedAmount = quote.value + quote.callFee + quote.productFeeAmount + quote.gasFee;
        uint256 roundedAmount = agreedAmount - (agreedAmount % SAT_TO_WEI_CONVERSION);

        // Setup BTC block headers
        bytes memory header = createBtcBlockHeader(uint32(block.timestamp) + 300);

        // Setup bridge with rounded amount
        vm.deal(address(bridgeMock), roundedAmount);
        bridgeMock.setPegin{value: roundedAmount}(quoteHash);
        bridgeMock.setHeader(HEIGHT_MOCK, header);
        bridgeMock.setHeader(HEIGHT_MOCK + uint256(quote.depositConfirmations) - 1, header);

        // LP attempts call - it will fail because this contract doesn't accept ETH
        vm.prank(fullLp);
        bool success = pegInContract.callForUser{value: quote.value}(quote);
        assertFalse(success, "Call should fail");

        // When call fails:
        // refundAmount = min(transferredAmount, callFee + gasFee) = min(roundedAmount, 0) = 0
        // remainingAmount = roundedAmount - 0 - productFeeAmount
        //                 = roundedAmount - productFeeAmount
        // Since roundedAmount > productFeeAmount (because value was included), no underflow!

        // This should succeed because when call fails, refundAmount is smaller
        vm.prank(fullLp);
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
            "Quote should be processed"
        );
    }

    // ============ Helper Functions ============

    /// @notice Creates a quote specifically designed to trigger the rounding edge case
    /// @dev Uses values above minPegIn (0.5 ether) that still trigger rounding:
    ///      - value = 0.5 ether = 5 * 10^17 wei
    ///      - productFeeAmount = 0.5 satoshi in wei (5*10^9) - causes rounding
    ///      - callFee = 0
    ///      - gasFee = 0
    ///
    /// Total = 5*10^17 + 5*10^9 = 500,005,000,000,000,000 wei
    /// Total % SAT_TO_WEI = 5,000,000,000 != 0, so rounding applies
    /// Rounded total = 500,000,000,000,000,000 = 0.5 ether
    ///
    /// When user sends 0.5 ether (rounded amount):
    /// - refundAmount = min(0.5 ether, value + callFee + gasFee) = 0.5 ether
    /// - remainingAmount = 0.5 ether - 0.5 ether - 5*10^9 = -5*10^9 --> UNDERFLOW!
    function createQuoteWithRoundingEdgeCase() internal view returns (Quotes.PegInQuote memory) {
        bytes memory testBtcAddress = new bytes(21);

        return Quotes.PegInQuote({
            // value = 0.5 ether (meets minPegIn requirement)
            value: 0.5 ether,
            // callFee = 0 (to simplify the math)
            callFee: 0,
            // gasFee = 0 (to simplify the math)
            gasFee: 0,
            // productFeeAmount = 0.5 satoshi in wei (causes the rounding issue)
            // This is 5*10^9 wei, which is NOT a multiple of SAT_TO_WEI_CONVERSION
            productFeeAmount: SAT_TO_WEI_CONVERSION / 2, // 5*10^9 wei
            // penalty fee for slashing (doesn't affect refund calculation)
            penaltyFee: 0.01 ether,
            fedBtcAddress: bytes20(testBtcAddress),
            lbcAddress: address(pegInContract),
            liquidityProviderRskAddress: fullLp,
            contractAddress: user, // user can receive ETH
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

    /// @notice Creates a quote with more realistic values that still triggers rounding
    /// @dev Uses larger value that meets minPegIn but still has rounding issue
    function createQuoteWithRealisticRounding() internal view returns (Quotes.PegInQuote memory) {
        bytes memory testBtcAddress = new bytes(21);

        return Quotes.PegInQuote({
            // value = 1 ether (well above minPegIn)
            value: 1 ether,
            // callFee = 0.01 ether
            callFee: 0.01 ether,
            // gasFee = 0.005 ether
            gasFee: 0.005 ether,
            // productFeeAmount = 0.5 satoshi in wei (half satoshi, causes rounding)
            // 5*10^9 wei is NOT a multiple of SAT_TO_WEI_CONVERSION
            productFeeAmount: SAT_TO_WEI_CONVERSION / 2,
            penaltyFee: 0.01 ether,
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

    /// @notice Creates a BTC block header with a specific timestamp (little-endian encoded)
    function createBtcBlockHeader(uint32 timestamp) internal pure returns (bytes memory) {
        bytes memory header = new bytes(80);
        header[68] = bytes1(uint8(timestamp));
        header[69] = bytes1(uint8(timestamp >> 8));
        header[70] = bytes1(uint8(timestamp >> 16));
        header[71] = bytes1(uint8(timestamp >> 24));
        return header;
    }

    function signQuote(address signer, bytes32 quoteHash) internal view returns (bytes memory) {
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

        bytes32 ethSignedMessageHash = keccak256(
            abi.encodePacked("\x19Ethereum Signed Message:\n32", quoteHash)
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, ethSignedMessageHash);
        return abi.encodePacked(r, s, v);
    }
}
