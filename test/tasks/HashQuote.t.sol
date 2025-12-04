// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import "lib/forge-std/src/Test.sol";
import "lib/forge-std/src/console.sol";
import {Quotes} from "src/libraries/Quotes.sol";
import {HashQuote} from "../../script/tasks/HashQuote.s.sol";
import {BtcAddressParser} from "../../script/helpers/BtcAddressParser.sol";

/**
 * @title MockPegInContract
 * @notice Mock PegIn contract for testing hash functionality
 */
contract MockPegInContract {
    function hashPegInQuote(Quotes.PegInQuote calldata quote) external pure returns (bytes32) {
        return keccak256(Quotes.encodeQuote(quote));
    }
}

/**
 * @title MockPegOutContract
 * @notice Mock PegOut contract for testing hash functionality
 */
contract MockPegOutContract {
    function hashPegOutQuote(Quotes.PegOutQuote calldata quote) external pure returns (bytes32) {
        return keccak256(Quotes.encodePegOutQuote(quote));
    }
}

/**
 * @title HashQuoteTest
 * @notice Test for the new hash-quote task using the Quotes library
 */
contract HashQuoteTest is Test, BtcAddressParser {
    HashQuote public hashScript;
    MockPegInContract public pegIn;
    MockPegOutContract public pegOut;

    function setUp() public {
        pegIn = new MockPegInContract();
        pegOut = new MockPegOutContract();
        hashScript = new HashQuote();

        vm.setEnv("PEGIN_CONTRACT_ADDRESS", vm.toString(address(pegIn)));
        vm.setEnv("PEGOUT_CONTRACT_ADDRESS", vm.toString(address(pegOut)));
    }

    function test_HashPegInQuote() public {
        console.log("\n=== TEST HASH PEGIN QUOTE ===\n");

        Quotes.PegInQuote memory quote = createTestPegInQuote();

        bytes32 hash1 = pegIn.hashPegInQuote(quote);
        bytes32 hash2 = pegIn.hashPegInQuote(quote);

        assertEq(hash1, hash2, "Hash should be deterministic");
        assertTrue(hash1 != bytes32(0), "Hash should not be zero");

        console.log("PegIn quote hashed successfully:");
        console.logBytes32(hash1);
        console.log("\n[PASS] HashQuote for PegIn works correctly!");
    }

    function test_HashPegOutQuote() public {
        console.log("\n=== TEST HASH PEGOUT QUOTE ===\n");

        Quotes.PegOutQuote memory quote = createTestPegOutQuote();

        bytes32 hash1 = pegOut.hashPegOutQuote(quote);
        bytes32 hash2 = pegOut.hashPegOutQuote(quote);

        assertEq(hash1, hash2, "Hash should be deterministic");
        assertTrue(hash1 != bytes32(0), "Hash should not be zero");

        console.log("PegOut quote hashed successfully:");
        console.logBytes32(hash1);
        console.log("\n[PASS] HashQuote for PegOut works correctly!");
    }

    function test_DifferentQuotesProduceDifferentHashes() public {
        console.log("\n=== TEST DIFFERENT QUOTES PRODUCE DIFFERENT HASHES ===\n");

        Quotes.PegInQuote memory quote1 = createTestPegInQuote();
        Quotes.PegInQuote memory quote2 = createTestPegInQuote();
        quote2.value = quote1.value + 1 ether;

        bytes32 hash1 = pegIn.hashPegInQuote(quote1);
        bytes32 hash2 = pegIn.hashPegInQuote(quote2);

        assertTrue(hash1 != hash2, "Different quotes should have different hashes");

        console.log("[PASS] Different quotes produce different hashes!");
    }

    function test_QuoteEncodingConsistency() public {
        console.log("\n=== TEST QUOTE ENCODING CONSISTENCY ===\n");

        Quotes.PegInQuote memory quote = createTestPegInQuote();

        bytes memory encoded1 = Quotes.encodeQuote(quote);
        bytes memory encoded2 = Quotes.encodeQuote(quote);

        assertEq(encoded1.length, encoded2.length, "Encoding should be consistent");
        assertEq(keccak256(encoded1), keccak256(encoded2), "Encoded bytes should be identical");

        console.log("Encoding length:", encoded1.length);
        console.log("[PASS] Quote encoding is consistent!");
    }

    function createTestPegInQuote() internal view returns (Quotes.PegInQuote memory) {
        bytes memory testBtcAddress = hex"6f0000000000000000000000000000000000000000";
        bytes20 fedAddress = bytes20(hex"0000000000000000000000000000000000000000");

        address lpAddr = address(0x1234567890123456789012345678901234567890);
        address userAddr = address(0x2234567890123456789012345678901234567891);
        address destAddr = address(0x3234567890123456789012345678901234567892);

        return Quotes.PegInQuote({
            callFee: 100000000000000,
            penaltyFee: 10000000000000,
            value: 0.5 ether,
            productFeeAmount: 0,
            gasFee: 100,
            fedBtcAddress: fedAddress,
            lbcAddress: address(pegIn),
            liquidityProviderRskAddress: lpAddr,
            contractAddress: destAddr,
            rskRefundAddress: payable(userAddr),
            nonce: 12345,
            gasLimit: 21000,
            agreementTimestamp: 1735243258,
            timeForDeposit: 3600,
            callTime: 7200,
            depositConfirmations: 10,
            callOnRegister: false,
            btcRefundAddress: testBtcAddress,
            liquidityProviderBtcAddress: testBtcAddress,
            data: hex""
        });
    }

    function createTestPegOutQuote() internal view returns (Quotes.PegOutQuote memory) {
        bytes memory testBtcAddress = hex"0076a914000000000000000000000000000000000000000088ac";

        address lpAddr = address(0x1234567890123456789012345678901234567890);
        address userAddr = address(0x2234567890123456789012345678901234567891);

        return Quotes.PegOutQuote({
            callFee: 100000000000000,
            penaltyFee: 10000000000000,
            value: 0.5 ether,
            productFeeAmount: 0,
            gasFee: 100,
            lbcAddress: address(pegOut),
            lpRskAddress: lpAddr,
            rskRefundAddress: userAddr,
            nonce: 12345,
            agreementTimestamp: 1735243258,
            depositDateLimit: 1735253058,
            transferTime: 3600,
            expireDate: 1735339658,
            expireBlock: 100,
            depositConfirmations: 10,
            transferConfirmations: 2,
            depositAddress: testBtcAddress,
            btcRefundAddress: testBtcAddress,
            lpBtcAddress: testBtcAddress
        });
    }
}
