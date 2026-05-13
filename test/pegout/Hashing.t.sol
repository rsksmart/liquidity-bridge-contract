// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {PegOutTestBase} from "./PegOutTestBase.sol";
import {IPegOut} from "../../src/interfaces/IPegOut.sol";
import {Quotes} from "../../src/libraries/Quotes.sol";
import {Flyover} from "../../src/libraries/Flyover.sol";

contract HashingTest is PegOutTestBase {
    function setUp() public {
        deployPegOutContract();
    }

    // ============ hashPegOutQuote function tests ============

    function test_HashPegOutQuote_RevertsIfQuoteChainIdIsFromAnotherNetwork()
        public
    {
        Quotes.PegOutQuote memory quote = createSpecificPegOutQuote1();
        quote.lbcAddress = address(pegOutContract);
        uint256 wrongChainId = block.chainid == 1 ? 31337 : 1;
        quote.chainId = wrongChainId;

        vm.expectRevert(
            abi.encodeWithSelector(
                Flyover.InvalidChainId.selector,
                block.chainid,
                wrongChainId
            )
        );
        pegOutContract.hashPegOutQuote(quote);
    }

    function test_HashPegOutQuote_RevertsIfExpireBlockExceedsNativePegoutBlocks()
        public
    {
        Quotes.PegOutQuote memory quote = createSpecificPegOutQuote1();
        quote.lbcAddress = address(pegOutContract);
        // expireBlock must be <= block.number + 4000; use 4001 to trigger UnfairQuote
        quote.expireBlock = uint32(block.number + 4001);
        quote.expireDate = uint32(block.timestamp + 1000); // within 36h limit

        vm.expectRevert(IPegOut.UnfairQuote.selector);
        pegOutContract.hashPegOutQuote(quote);
    }

    function test_HashPegOutQuote_RevertsIfExpireDateExceedsNativePegoutSeconds()
        public
    {
        Quotes.PegOutQuote memory quote = createSpecificPegOutQuote1();
        quote.lbcAddress = address(pegOutContract);
        quote.expireBlock = uint32(block.number + 100); // within 4000 blocks
        // expireDate must be <= block.timestamp + 129600 (36h); use 129601 to trigger UnfairQuote
        quote.expireDate = uint32(block.timestamp + 129_601);

        vm.expectRevert(IPegOut.UnfairQuote.selector);
        pegOutContract.hashPegOutQuote(quote);
    }

    function test_HashPegOutQuote_RevertsIfRskRefundAddressIsZero() public {
        Quotes.PegOutQuote memory quote = createSpecificPegOutQuote1();
        quote.lbcAddress = address(pegOutContract);
        quote.rskRefundAddress = address(0);

        vm.expectRevert(
            abi.encodeWithSelector(
                Flyover.InvalidAddress.selector,
                address(0)
            )
        );
        pegOutContract.hashPegOutQuote(quote);
    }

    function test_HashPegOutQuoteEIP712_RevertsIfRskRefundAddressIsZero() public {
        Quotes.PegOutQuote memory quote = createSpecificPegOutQuote1();
        quote.lbcAddress = address(pegOutContract);
        quote.rskRefundAddress = address(0);

        vm.expectRevert(
            abi.encodeWithSelector(
                Flyover.InvalidAddress.selector,
                address(0)
            )
        );
        pegOutContract.hashPegOutQuoteEIP712(quote);
    }

    function test_HashPegOutQuote_AcceptsQuoteWithinNativePegoutLimits()
        public
        view
    {
        Quotes.PegOutQuote memory quote = createSpecificPegOutQuote1();
        quote.lbcAddress = address(pegOutContract);
        quote.expireBlock = uint32(block.number + 4000); // exactly at limit
        quote.expireDate = uint32(block.timestamp + 129_600); // exactly at 36h limit

        bytes32 h = pegOutContract.hashPegOutQuote(quote);
        assertTrue(h != bytes32(0), "Hash should be non-zero");
    }

    function test_HashPegOutQuoteEIP712_RevertsIfExpireBlockExceedsNativePegoutBlocks()
        public
    {
        Quotes.PegOutQuote memory quote = createSpecificPegOutQuote1();
        quote.lbcAddress = address(pegOutContract);
        quote.expireBlock = uint32(block.number + 4001);
        quote.expireDate = uint32(block.timestamp + 1000);

        vm.expectRevert(IPegOut.UnfairQuote.selector);
        pegOutContract.hashPegOutQuoteEIP712(quote);
    }

    function test_HashPegOutQuoteEIP712_RevertsIfExpireDateExceedsNativePegoutSeconds()
        public
    {
        Quotes.PegOutQuote memory quote = createSpecificPegOutQuote1();
        quote.lbcAddress = address(pegOutContract);
        quote.expireBlock = uint32(block.number + 100);
        quote.expireDate = uint32(block.timestamp + 129_601);

        vm.expectRevert(IPegOut.UnfairQuote.selector);
        pegOutContract.hashPegOutQuoteEIP712(quote);
    }

    function test_HashPegOutQuote_RevertsIfQuoteBelongsToOtherContract()
        public
    {
        address wrongContract = 0xAA9cAf1e3967600578727F975F283446A3Da6612;

        Quotes.PegOutQuote memory quote = Quotes.PegOutQuote({
            chainId: block.chainid,
            callFee: 300000000000000,
            penaltyFee: 10000000000000,
            value: 471000000000000000,
            gasFee: 5990000000000,
            lbcAddress: wrongContract,
            lpRskAddress: 0x82a06eBDB97776a2da4041dF8f2b2ea8D3257852,
            rskRefundAddress: 0xF52e06Df2E1cbD73fb686442319cbe5Ce495B996,
            nonce: 5570584357569316000,
            agreementTimestamp: 1753461851,
            depositDateLimit: 1753469051,
            transferTime: 7200,
            depositConfirmations: 40,
            transferConfirmations: 2,
            expireBlock: 7822676,
            expireDate: 1753476251,
            depositAddress: new bytes(21),
            btcRefundAddress: new bytes(21),
            lpBtcAddress: new bytes(21)
        });

        vm.expectRevert(
            abi.encodeWithSelector(
                Flyover.IncorrectContract.selector,
                address(pegOutContract),
                wrongContract
            )
        );
        pegOutContract.hashPegOutQuote(quote);
    }

    function test_HashPegOutQuote_HashesPegOutQuoteProperly() public view {
        // Note: Like PegIn hashing tests, we verify determinism rather than exact hashes
        // since the contract address is unpredictable in Foundry tests

        Quotes.PegOutQuote memory quote1 = createSpecificPegOutQuote1();
        quote1.lbcAddress = address(pegOutContract);

        // Hash the quote twice to verify it's deterministic
        bytes32 hash1a = pegOutContract.hashPegOutQuote(quote1);
        bytes32 hash1b = pegOutContract.hashPegOutQuote(quote1);
        assertEq(hash1a, hash1b, "Hash should be deterministic");

        // Verify different quotes produce different hashes
        Quotes.PegOutQuote memory quote2 = createSpecificPegOutQuote2();
        quote2.lbcAddress = address(pegOutContract);
        bytes32 hash2 = pegOutContract.hashPegOutQuote(quote2);

        assertTrue(
            hash1a != hash2,
            "Different quotes should produce different hashes"
        );

        // Verify hash changes when quote value changes
        Quotes.PegOutQuote memory quote3 = createSpecificPegOutQuote1();
        quote3.lbcAddress = address(pegOutContract);
        quote3.value = 1 ether; // Different value
        bytes32 hash3 = pegOutContract.hashPegOutQuote(quote3);

        assertTrue(hash1a != hash3, "Changing quote value should change hash");
    }

    function test_HashPegOutQuote_IncludesAllFieldsInHash() public {
        // This test ensures every field in PegOutQuote affects the hash
        // If a new field is added but not included in the hash function, this test will fail
        Quotes.PegOutQuote memory baseQuote = createSpecificPegOutQuote1();
        baseQuote.lbcAddress = address(pegOutContract);
        bytes32 baseHash = pegOutContract.hashPegOutQuote(baseQuote);

        Quotes.PegOutQuote memory modifiedQuote;

        // Test chainId
        modifiedQuote = baseQuote;
        modifiedQuote.chainId = baseQuote.chainId + 1;
        uint originalChainId = block.chainid;
        vm.chainId(modifiedQuote.chainId); // to prevent the hash from failing
        assertTrue(
            pegOutContract.hashPegOutQuote(modifiedQuote) != baseHash,
            "chainId should affect hash"
        );
        modifiedQuote.chainId = originalChainId;
        vm.chainId(originalChainId);

        // Test callFee
        modifiedQuote = baseQuote;
        modifiedQuote.callFee = baseQuote.callFee + 1;
        assertTrue(
            pegOutContract.hashPegOutQuote(modifiedQuote) != baseHash,
            "callFee should affect hash"
        );

        // Test penaltyFee
        modifiedQuote = baseQuote;
        modifiedQuote.penaltyFee = baseQuote.penaltyFee + 1;
        assertTrue(
            pegOutContract.hashPegOutQuote(modifiedQuote) != baseHash,
            "penaltyFee should affect hash"
        );

        // Test value
        modifiedQuote = baseQuote;
        modifiedQuote.value = baseQuote.value + 1;
        assertTrue(
            pegOutContract.hashPegOutQuote(modifiedQuote) != baseHash,
            "value should affect hash"
        );

        // Test gasFee
        modifiedQuote = baseQuote;
        modifiedQuote.gasFee = baseQuote.gasFee + 1;
        assertTrue(
            pegOutContract.hashPegOutQuote(modifiedQuote) != baseHash,
            "gasFee should affect hash"
        );

        // Test lpRskAddress
        modifiedQuote = baseQuote;
        modifiedQuote.lpRskAddress = address(
            0x1234567890123456789012345678901234567890
        );
        assertTrue(
            pegOutContract.hashPegOutQuote(modifiedQuote) != baseHash,
            "lpRskAddress should affect hash"
        );

        // Test rskRefundAddress
        modifiedQuote = baseQuote;
        modifiedQuote.rskRefundAddress = address(
            0x1234567890123456789012345678901234567890
        );
        assertTrue(
            pegOutContract.hashPegOutQuote(modifiedQuote) != baseHash,
            "rskRefundAddress should affect hash"
        );

        // Test nonce
        modifiedQuote = baseQuote;
        modifiedQuote.nonce = baseQuote.nonce + 1;
        assertTrue(
            pegOutContract.hashPegOutQuote(modifiedQuote) != baseHash,
            "nonce should affect hash"
        );

        // Test agreementTimestamp
        modifiedQuote = baseQuote;
        modifiedQuote.agreementTimestamp = baseQuote.agreementTimestamp + 1;
        assertTrue(
            pegOutContract.hashPegOutQuote(modifiedQuote) != baseHash,
            "agreementTimestamp should affect hash"
        );

        // Test depositDateLimit
        modifiedQuote = baseQuote;
        modifiedQuote.depositDateLimit = baseQuote.depositDateLimit + 1;
        assertTrue(
            pegOutContract.hashPegOutQuote(modifiedQuote) != baseHash,
            "depositDateLimit should affect hash"
        );

        // Test transferTime
        modifiedQuote = baseQuote;
        modifiedQuote.transferTime = baseQuote.transferTime + 1;
        assertTrue(
            pegOutContract.hashPegOutQuote(modifiedQuote) != baseHash,
            "transferTime should affect hash"
        );

        // Test depositConfirmations
        modifiedQuote = baseQuote;
        modifiedQuote.depositConfirmations = baseQuote.depositConfirmations + 1;
        assertTrue(
            pegOutContract.hashPegOutQuote(modifiedQuote) != baseHash,
            "depositConfirmations should affect hash"
        );

        // Test transferConfirmations
        modifiedQuote = baseQuote;
        modifiedQuote.transferConfirmations =
            baseQuote.transferConfirmations +
            1;
        assertTrue(
            pegOutContract.hashPegOutQuote(modifiedQuote) != baseHash,
            "transferConfirmations should affect hash"
        );

        // Test expireBlock
        modifiedQuote = baseQuote;
        modifiedQuote.expireBlock = baseQuote.expireBlock + 1;
        assertTrue(
            pegOutContract.hashPegOutQuote(modifiedQuote) != baseHash,
            "expireBlock should affect hash"
        );

        // Test expireDate
        modifiedQuote = baseQuote;
        modifiedQuote.expireDate = baseQuote.expireDate + 1;
        assertTrue(
            pegOutContract.hashPegOutQuote(modifiedQuote) != baseHash,
            "expireDate should affect hash"
        );

        // Test depositAddress
        modifiedQuote = baseQuote;
        modifiedQuote.depositAddress = new bytes(21);
        modifiedQuote.depositAddress[0] = 0x6f;
        modifiedQuote.depositAddress[1] = 0xff; // Different from baseQuote
        assertTrue(
            pegOutContract.hashPegOutQuote(modifiedQuote) != baseHash,
            "depositAddress should affect hash"
        );

        // Test btcRefundAddress
        modifiedQuote = baseQuote;
        modifiedQuote.btcRefundAddress = new bytes(21);
        modifiedQuote.btcRefundAddress[0] = 0x6f;
        modifiedQuote.btcRefundAddress[1] = 0xff; // Different from baseQuote
        assertTrue(
            pegOutContract.hashPegOutQuote(modifiedQuote) != baseHash,
            "btcRefundAddress should affect hash"
        );

        // Test lpBtcAddress
        modifiedQuote = baseQuote;
        modifiedQuote.lpBtcAddress = new bytes(21);
        modifiedQuote.lpBtcAddress[0] = 0x6f;
        modifiedQuote.lpBtcAddress[1] = 0xff; // Different from baseQuote
        assertTrue(
            pegOutContract.hashPegOutQuote(modifiedQuote) != baseHash,
            "lpBtcAddress should affect hash"
        );
    }

    // ============ Helper Functions ============

    function createSpecificPegOutQuote1()
        internal
        view
        returns (Quotes.PegOutQuote memory)
    {
        bytes memory testBtcAddress = new bytes(21);

        return
            Quotes.PegOutQuote({
                chainId: block.chainid,
                callFee: 300000000000000,
                penaltyFee: 10000000000000,
                value: 471000000000000000,
                gasFee: 5990000000000,
                lbcAddress: 0x4C2F7092C2aE51D986bEFEe378e50BD4dB99C901,
                lpRskAddress: 0x82a06eBDB97776a2da4041dF8f2b2ea8D3257852,
                rskRefundAddress: 0xF52e06Df2E1cbD73fb686442319cbe5Ce495B996,
                nonce: 5570584357569316000,
                agreementTimestamp: 1753461851,
                depositDateLimit: 1753469051,
                transferTime: 7200,
                depositConfirmations: 40,
                transferConfirmations: 2,
                expireBlock: uint32(block.number + 1000),
                expireDate: uint32(block.timestamp + 20_000),
                depositAddress: testBtcAddress,
                btcRefundAddress: testBtcAddress,
                lpBtcAddress: testBtcAddress
            });
    }

    function createSpecificPegOutQuote2()
        internal
        view
        returns (Quotes.PegOutQuote memory)
    {
        bytes memory testBtcAddress = new bytes(21);

        return
            Quotes.PegOutQuote({
                chainId: block.chainid,
                callFee: 300000000000000,
                penaltyFee: 10000000000000,
                value: 27108379819732510,
                gasFee: 11330000000000,
                lbcAddress: 0x4C2F7092C2aE51D986bEFEe378e50BD4dB99C901,
                lpRskAddress: 0x82a06eBDB97776a2da4041dF8f2b2ea8D3257852,
                rskRefundAddress: 0x02E221A95224F090e492066Bc1B7a35B5Fd94542,
                nonce: 3434440345862007300,
                agreementTimestamp: 1753727248,
                depositDateLimit: 1753734448,
                transferTime: 7200,
                depositConfirmations: 40,
                transferConfirmations: 2,
                expireBlock: uint32(block.number + 2000),
                expireDate: uint32(block.timestamp + 30_000),
                depositAddress: testBtcAddress,
                btcRefundAddress: testBtcAddress,
                lpBtcAddress: testBtcAddress
            });
    }

    function createSpecificPegOutQuote3()
        internal
        view
        returns (Quotes.PegOutQuote memory)
    {
        bytes memory testBtcAddress = new bytes(21);

        return
            Quotes.PegOutQuote({
                chainId: block.chainid,
                callFee: 300000000000000,
                penaltyFee: 10000000000000,
                value: 1045000000000000000,
                gasFee: 3140000000000,
                lbcAddress: 0x4C2F7092C2aE51D986bEFEe378e50BD4dB99C901,
                lpRskAddress: 0x82a06eBDB97776a2da4041dF8f2b2ea8D3257852,
                rskRefundAddress: 0x077B8Cd0e024e79eEFc8Ce1Fddc005DbE88A94c7,
                nonce: 877548865611330300,
                agreementTimestamp: 1753945401,
                depositDateLimit: 1753952601,
                transferTime: 7200,
                depositConfirmations: 60,
                transferConfirmations: 3,
                expireBlock: uint32(block.number + 3000),
                expireDate: uint32(block.timestamp + 40_000),
                depositAddress: testBtcAddress,
                btcRefundAddress: testBtcAddress,
                lpBtcAddress: testBtcAddress
            });
    }
}
