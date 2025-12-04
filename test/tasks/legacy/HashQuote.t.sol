// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import "lib/forge-std/src/Test.sol";
import "lib/forge-std/src/console.sol";
import {QuotesV2} from "src/legacy/QuotesV2.sol";
import {LiquidityBridgeContractV2} from "src/legacy/LiquidityBridgeContractV2.sol";
import {HashQuote} from "../../../script/legacy/tasks/HashQuote.s.sol";
import {BtcAddressParser} from "../../../script/helpers/BtcAddressParser.sol";

/**
 * @title HashQuoteTest
 * @notice Test for the legacy hash-quote task
 */
contract HashQuoteTest is Test, BtcAddressParser {
    HashQuote public hashScript;
    LiquidityBridgeContractV2 public lbc;

    function setUp() public {
        lbc = new LiquidityBridgeContractV2();
        hashScript = new HashQuote();
        vm.setEnv("LBC_ADDRESS", vm.toString(address(lbc)));
    }

    function test_HashPeginQuoteWithParsing() public {
        console.log("\n=== TEST HASH PEGIN QUOTE (VIA PARSING) ===\n");
        address expectedLbcAddress = 0x2E2Ed0Cfd3AD2f1d34481277b3204d807Ca2F8c2;
        bytes32 expectedHash = 0x67e68a14a4a1ed6300970c7cd532cfd558206b3d7ac3fbc10e4cd67e5816e39d;

        bytes20 fedBtcAddress = parseFedBtcAddress("3GQ87zLKyTygsRMZ1hfCHZSdBxujzKoCCU");
        bytes memory btcRefundAddress = parseBtcAddress("1111111111111111111114oLvT2");
        bytes memory lpBtcAddress = parseBtcAddress("1D2xucTYkxCHvaaZuaKVJTfZQWr4PUjzAy");

        address rskRefundAddr = 0xaC31A4bEedd7EC916B7A48a612230cb85c1aaf56;
        QuotesV2.PeginQuote memory quote = QuotesV2.PeginQuote({
            fedBtcAddress: fedBtcAddress,
            lbcAddress: expectedLbcAddress,
            liquidityProviderRskAddress: 0x82a06eBDB97776a2da4041dF8f2b2ea8D3257852,
            btcRefundAddress: btcRefundAddress,
            rskRefundAddress: payable(rskRefundAddr),
            liquidityProviderBtcAddress: lpBtcAddress,
            callFee: 100000000000000,
            penaltyFee: 10000000000000,
            contractAddress: rskRefundAddr,
            data: hex"",
            gasLimit: 21000,
            nonce: 3635227228603468300,
            value: 985215170000000000,
            agreementTimestamp: 1752739488,
            timeForDeposit: 5400,
            callTime: 7200,
            depositConfirmations: 3,
            callOnRegister: false,
            productFeeAmount: 0,
            gasFee: 547377600000
        });

        bytes memory code = address(lbc).code;
        vm.etch(expectedLbcAddress, code);
        LiquidityBridgeContractV2 lbcAtExpectedAddress = LiquidityBridgeContractV2(payable(expectedLbcAddress));

        bytes32 hash = lbcAtExpectedAddress.hashQuote(quote);
        bytes32 hash2 = lbcAtExpectedAddress.hashQuote(quote);
        assertEq(hash, hash2, "Hash should be deterministic");
        assertTrue(hash != bytes32(0), "Hash should not be zero");
        assertEq(hash, expectedHash, "Hash should match expected value");
    }

    function test_HashPegoutQuoteFromContract() public view {
        console.log("\n=== TEST HASH PEGOUT QUOTE (FROM CONTRACT) ===\n");
        QuotesV2.PegOutQuote memory quote = createTestPegoutQuote();
        bytes32 hash = lbc.hashPegoutQuote(quote);
        console.log("PegOut quote hashed successfully:");
        console.logBytes32(hash);
        console.log("\n[PASS] HashQuote for PegOut works correctly!");
    }

    function createTestPegoutQuote() internal view returns (QuotesV2.PegOutQuote memory) {
        bytes memory testBtcAddress = hex"0076a914000000000000000000000000000000000000000088ac";
        address lpAddr = address(0x1234567890123456789012345678901234567890);
        address userAddr = address(0x2234567890123456789012345678901234567891);

        return QuotesV2.PegOutQuote({
            lbcAddress: address(lbc),
            lpRskAddress: lpAddr,
            btcRefundAddress: testBtcAddress,
            rskRefundAddress: userAddr,
            lpBtcAddress: testBtcAddress,
            callFee: 100000000000000,
            penaltyFee: 10000000000000,
            nonce: 12345,
            deposityAddress: testBtcAddress,
            value: 0.5 ether,
            agreementTimestamp: 1735243258,
            depositDateLimit: 1735253058,
            transferTime: 3600,
            depositConfirmations: 10,
            transferConfirmations: 2,
            productFeeAmount: 0,
            gasFee: 100,
            expireBlock: 100,
            expireDate: 1735339658
        });
    }
}
