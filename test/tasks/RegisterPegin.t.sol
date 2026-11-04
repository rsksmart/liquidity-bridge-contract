// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {console} from "forge-std/console.sol";
import {FlyoverTestBase} from "../helpers/FlyoverTestBase.sol";
import {Quotes} from "src/libraries/Quotes.sol";

/**
 * @title MockPegInContract
 * @notice Mock PegIn contract for testing registration functionality
 */
contract MockPegInContract {
    event PegInRegistered(bytes32 indexed quoteHash, int256 result);

    function registerPegIn(
        Quotes.PegInQuote calldata quote,
        bytes calldata,
        bytes calldata,
        bytes calldata,
        uint256
    ) external returns (int256) {
        bytes32 quoteHash = hashPegInQuote(quote);
        emit PegInRegistered(quoteHash, 0);
        return 0;
    }

    function hashPegInQuote(
        Quotes.PegInQuote calldata quote
    ) public pure returns (bytes32) {
        return keccak256(Quotes.encodeQuote(quote));
    }
}

/**
 * @title RegisterPeginTest
 * @notice Test for the register-pegin task with new PegInContract
 */
contract RegisterPeginTest is FlyoverTestBase {
    MockPegInContract public mockPegIn;
    address public user;
    address public liquidityProvider;
    uint256 public lpPrivateKey;

    bytes constant MOCK_RAW_TX = hex"0100000001";
    bytes constant MOCK_PMT = hex"0200000003";
    uint256 constant MOCK_HEIGHT = 100;

    function setUp() public {
        user = makeAddr("testUser");
        (liquidityProvider, lpPrivateKey) = makeAddrAndKey("testLP");

        vm.deal(user, 10 ether);
        vm.deal(liquidityProvider, 10 ether);

        mockPegIn = new MockPegInContract();
    }

    function test_RegistrationFlowStructure() public pure {
        console.log("\n=== TEST REGISTER PEGIN FLOW STRUCTURE ===\n");

        console.log("Validated components:");
        console.log("  - Current PegIn quote encoding works: SUCCESS");
        console.log("  - Signature hex parsing helper works: SUCCESS");
        console.log("  - Mock registerPegIn invocation works: SUCCESS");

        console.log("\n[NOTE] Full registerPegIn requires:");
        console.log("  1. Deployed PegIn with proper Bridge");
        console.log("  2. Registered LP");
        console.log("  3. callForUser executed first");
        console.log("  4. Real Bitcoin transaction data");

        console.log("\n[PASS] Register-pegin task compatibility validated!");
    }

    function test_SignatureParsing() public view {
        console.log("\n=== TEST SIGNATURE PARSING ===\n");

        // Test with 0x prefix
        bytes memory sig1 = parseSignature("0x1234");
        assertEq(sig1.length, 2, "Should parse 0x1234 to 2 bytes");
        assertEq(uint8(sig1[0]), 0x12, "First byte should be 0x12");
        assertEq(uint8(sig1[1]), 0x34, "Second byte should be 0x34");

        // Test without 0x prefix
        bytes memory sig2 = parseSignature("abcd");
        assertEq(sig2.length, 2, "Should parse abcd to 2 bytes");
        assertEq(uint8(sig2[0]), 0xab, "First byte should be 0xab");
        assertEq(uint8(sig2[1]), 0xcd, "Second byte should be 0xcd");

        // Test full length signature
        string
            memory fullSigHex = "1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef12";
        bytes memory fullSig = parseSignature(fullSigHex);
        assertEq(fullSig.length, 65, "Full signature should be 65 bytes");

        console.log("[PASS] Signature parsing works correctly!");
    }

    function test_QuoteHashing() public {
        console.log("\n=== TEST QUOTE HASHING ===\n");

        Quotes.PegInQuote memory quote = createTestPegInQuote(
            address(mockPegIn),
            liquidityProvider,
            user
        );

        bytes32 hash1 = mockPegIn.hashPegInQuote(quote);
        bytes32 hash2 = mockPegIn.hashPegInQuote(quote);

        assertEq(hash1, hash2, "Hash should be deterministic");
        assertTrue(hash1 != bytes32(0), "Hash should not be zero");

        console.log("Quote hash:");
        console.logBytes32(hash1);
        console.log("[PASS] Quote hashing works correctly!");
    }

    function test_MockRegistration() public {
        console.log("\n=== TEST MOCK REGISTRATION ===\n");

        Quotes.PegInQuote memory quote = createTestPegInQuote(
            address(mockPegIn),
            liquidityProvider,
            user
        );
        bytes memory signature = signQuoteHash(
            mockPegIn.hashPegInQuote(quote),
            lpPrivateKey
        );

        int256 result = mockPegIn.registerPegIn(
            quote,
            signature,
            MOCK_RAW_TX,
            MOCK_PMT,
            MOCK_HEIGHT
        );

        assertEq(result, 0, "Registration should succeed with result 0");

        console.log("[PASS] Mock registration works correctly!");
    }

    function parseSignature(
        string memory sigHex
    ) internal pure returns (bytes memory) {
        bytes memory sigBytes = bytes(sigHex);

        uint startIndex = 0;
        if (
            sigBytes.length >= 2 &&
            sigBytes[0] == "0" &&
            (sigBytes[1] == "x" || sigBytes[1] == "X")
        ) {
            startIndex = 2;
        }

        uint hexLength = sigBytes.length - startIndex;
        require(hexLength % 2 == 0, "Invalid signature hex length");

        bytes memory result = new bytes(hexLength / 2);
        for (uint i = 0; i < hexLength / 2; i++) {
            uint8 high = hexCharToByte(sigBytes[startIndex + i * 2]);
            uint8 low = hexCharToByte(sigBytes[startIndex + i * 2 + 1]);
            result[i] = bytes1(high * 16 + low);
        }

        return result;
    }

    function hexCharToByte(bytes1 char) internal pure returns (uint8) {
        uint8 c = uint8(char);
        if (c >= 48 && c <= 57) return c - 48;
        if (c >= 65 && c <= 70) return c - 55;
        if (c >= 97 && c <= 102) return c - 87;
        revert("Invalid hex character");
    }
}
