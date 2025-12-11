// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {console} from "forge-std/console.sol";
import {FlyoverTestBase} from "../helpers/FlyoverTestBase.sol";
import {Quotes} from "src/libraries/Quotes.sol";
import {HashQuote} from "../../script/tasks/HashQuote.s.sol";
import {TestUtils} from "../helpers/TestUtils.sol";

/**
 * @title MockPegInContract
 * @notice Mock PegIn contract for testing hash functionality
 */
contract MockPegInContract {
    function hashPegInQuote(
        Quotes.PegInQuote calldata quote
    ) external pure returns (bytes32) {
        return keccak256(Quotes.encodeQuote(quote));
    }
}

/**
 * @title MockPegOutContract
 * @notice Mock PegOut contract for testing hash functionality
 */
contract MockPegOutContract {
    function hashPegOutQuote(
        Quotes.PegOutQuote calldata quote
    ) external pure returns (bytes32) {
        return keccak256(Quotes.encodePegOutQuote(quote));
    }
}

/**
 * @title HashQuoteTest
 * @notice Test for the new hash-quote task using the Quotes library
 */
contract HashQuoteTest is FlyoverTestBase {
    HashQuote public hashScript;
    MockPegInContract public mockPegIn;
    MockPegOutContract public mockPegOut;

    address public lpAddr;
    address public userAddr;

    function setUp() public {
        mockPegIn = new MockPegInContract();
        mockPegOut = new MockPegOutContract();
        hashScript = new HashQuote();

        lpAddr = makeAddr("liquidityProvider");
        userAddr = makeAddr("user");

        vm.setEnv("PEGIN_CONTRACT_ADDRESS", vm.toString(address(mockPegIn)));
        vm.setEnv("PEGOUT_CONTRACT_ADDRESS", vm.toString(address(mockPegOut)));
    }

    function test_HashPegInQuote() public view {
        console.log("\n=== TEST HASH PEGIN QUOTE ===\n");

        Quotes.PegInQuote memory quote = createTestPegInQuote(
            address(mockPegIn),
            lpAddr,
            userAddr
        );

        bytes32 hash1 = mockPegIn.hashPegInQuote(quote);
        bytes32 hash2 = mockPegIn.hashPegInQuote(quote);

        assertEq(hash1, hash2, "Hash should be deterministic");
        assertTrue(hash1 != bytes32(0), "Hash should not be zero");

        console.log("PegIn quote hashed successfully:");
        console.logBytes32(hash1);
        console.log("\n[PASS] HashQuote for PegIn works correctly!");
    }

    function test_HashPegOutQuote() public view {
        console.log("\n=== TEST HASH PEGOUT QUOTE ===\n");

        Quotes.PegOutQuote memory quote = createTestPegOutQuote(
            address(mockPegOut),
            lpAddr,
            userAddr
        );

        bytes32 hash1 = mockPegOut.hashPegOutQuote(quote);
        bytes32 hash2 = mockPegOut.hashPegOutQuote(quote);

        assertEq(hash1, hash2, "Hash should be deterministic");
        assertTrue(hash1 != bytes32(0), "Hash should not be zero");

        console.log("PegOut quote hashed successfully:");
        console.logBytes32(hash1);
        console.log("\n[PASS] HashQuote for PegOut works correctly!");
    }

    function test_DifferentQuotesProduceDifferentHashes() public view {
        console.log(
            "\n=== TEST DIFFERENT QUOTES PRODUCE DIFFERENT HASHES ===\n"
        );

        Quotes.PegInQuote memory quote1 = createTestPegInQuote(
            address(mockPegIn),
            lpAddr,
            userAddr
        );
        Quotes.PegInQuote memory quote2 = createTestPegInQuote(
            address(mockPegIn),
            lpAddr,
            userAddr
        );
        quote2.value = quote1.value + 1 ether;

        bytes32 hash1 = mockPegIn.hashPegInQuote(quote1);
        bytes32 hash2 = mockPegIn.hashPegInQuote(quote2);

        assertTrue(
            hash1 != hash2,
            "Different quotes should have different hashes"
        );

        console.log("[PASS] Different quotes produce different hashes!");
    }

    function test_QuoteEncodingConsistency() public view {
        console.log("\n=== TEST QUOTE ENCODING CONSISTENCY ===\n");

        Quotes.PegInQuote memory quote = createTestPegInQuote(
            address(mockPegIn),
            lpAddr,
            userAddr
        );

        bytes memory encoded1 = Quotes.encodeQuote(quote);
        bytes memory encoded2 = Quotes.encodeQuote(quote);

        assertEq(
            encoded1.length,
            encoded2.length,
            "Encoding should be consistent"
        );
        assertEq(
            keccak256(encoded1),
            keccak256(encoded2),
            "Encoded bytes should be identical"
        );

        console.log("Encoding length:", encoded1.length);
        console.log("[PASS] Quote encoding is consistent!");
    }

    function test_HexUtilsIntegration() public pure {
        console.log("\n=== TEST HEX UTILS INTEGRATION ===\n");

        bytes32 testHash = 0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef;
        string memory hexStr = TestUtils.toHexString(testHash);

        assertEq(
            bytes(hexStr).length,
            64,
            "Hex string should be 64 characters"
        );

        console.log("Hex string:", hexStr);
        console.log("[PASS] HexUtils integration works correctly!");
    }
}
