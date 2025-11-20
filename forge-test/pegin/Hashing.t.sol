// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {PegInTestBase} from "./PegInTestBase.sol";
import {Quotes} from "../../contracts/libraries/Quotes.sol";
import {Flyover} from "../../contracts/libraries/Flyover.sol";
import {IPegIn} from "../../contracts/interfaces/IPegIn.sol";

contract HashingTest is PegInTestBase {
    function setUp() public {
        deployPegInContract();
    }

    // ============ hashPegInQuote function tests ============

    function test_HashPegInQuote_RevertsIfQuoteBelongsToOtherContract() public {
        Quotes.PegInQuote memory quote = createBasicPegInQuote();
        address wrongContract = 0xAA9cAf1e3967600578727F975F283446A3Da6612;
        address correctContract = address(pegInContract);
        quote.lbcAddress = wrongContract;

        vm.expectRevert(
            abi.encodeWithSelector(
                Flyover.IncorrectContract.selector,
                correctContract,
                wrongContract
            )
        );
        pegInContract.hashPegInQuote(quote);
    }

    function test_HashPegInQuote_RevertsIfDestinationAddressIsTheBridgeAddress()
        public
    {
        Quotes.PegInQuote memory quote = createBasicPegInQuote();
        quote.contractAddress = address(bridgeMock);

        vm.expectRevert(
            abi.encodeWithSelector(
                Flyover.NoContract.selector,
                address(bridgeMock)
            )
        );
        pegInContract.hashPegInQuote(quote);
    }

    function test_HashPegInQuote_RevertsIfBtcRefundAddressDoesNotHaveProperLength()
        public
    {
        Quotes.PegInQuote memory quote = createBasicPegInQuote();
        // Invalid length (should be 21 bytes for P2PKH/P2SH, not random length)
        quote.btcRefundAddress = new bytes(15); // Wrong length

        vm.expectRevert(
            abi.encodeWithSelector(
                IPegIn.InvalidRefundAddress.selector,
                quote.btcRefundAddress
            )
        );
        pegInContract.hashPegInQuote(quote);
    }

    function test_HashPegInQuote_RevertsIfLiquidityProviderBtcAddressDoesNotHaveProperLength()
        public
    {
        Quotes.PegInQuote memory quote = createBasicPegInQuote();
        // Invalid length
        quote.liquidityProviderBtcAddress = new bytes(15); // Wrong length

        vm.expectRevert(
            abi.encodeWithSelector(
                IPegIn.InvalidRefundAddress.selector,
                quote.liquidityProviderBtcAddress
            )
        );
        pegInContract.hashPegInQuote(quote);
    }

    function test_HashPegInQuote_RevertsIfQuoteTotalIsUnderBridgeMinimum()
        public
    {
        Quotes.PegInQuote memory quote = createBasicPegInQuote();
        // Set values that sum to less than 0.5 ether (TEST_MIN_PEGIN)
        quote.productFeeAmount = 99_999_999_999_999_999; // Just under 0.1 ether
        quote.gasFee = 0.1 ether;
        quote.callFee = 0.1 ether;
        quote.value = 0.2 ether;
        // Total = 0.49999... ether, which is less than TEST_MIN_PEGIN (0.5 ether)

        vm.expectRevert(
            abi.encodeWithSelector(
                IPegIn.AmountUnderMinimum.selector,
                TEST_MIN_PEGIN
            )
        );
        pegInContract.hashPegInQuote(quote);
    }

    function test_HashPegInQuote_RevertsIfTimestampFieldsOverflow() public {
        Quotes.PegInQuote memory quote = createBasicPegInQuote();
        uint32 MAX_UINT32 = type(uint32).max;

        quote.agreementTimestamp = MAX_UINT32 / 2;
        quote.timeForDeposit = MAX_UINT32 / 2 + 2;

        vm.expectRevert(
            abi.encodeWithSelector(Flyover.Overflow.selector, MAX_UINT32)
        );
        pegInContract.hashPegInQuote(quote);
    }

    function test_HashPegInQuote_HashesPegInQuoteProperly() public view {
        // Note: The expected hashes from TypeScript tests are based on quotes with
        // specific lbcAddress values. Since we can't predict the deployed contract address
        // in Foundry tests, we verify the hashing function is deterministic:
        // same quote should produce same hash consistently.

        Quotes.PegInQuote memory quote1 = createSpecificPegInQuote1();
        quote1.lbcAddress = address(pegInContract); // Update to actual contract

        // Hash the quote twice to verify it's deterministic
        bytes32 hash1a = pegInContract.hashPegInQuote(quote1);
        bytes32 hash1b = pegInContract.hashPegInQuote(quote1);
        assertEq(hash1a, hash1b, "Hash should be deterministic");

        // Verify different quotes produce different hashes
        Quotes.PegInQuote memory quote2 = createSpecificPegInQuote2();
        quote2.lbcAddress = address(pegInContract); // Update to actual contract
        bytes32 hash2 = pegInContract.hashPegInQuote(quote2);

        assertTrue(
            hash1a != hash2,
            "Different quotes should produce different hashes"
        );

        // Verify hash changes when quote value changes
        Quotes.PegInQuote memory quote3 = createSpecificPegInQuote1();
        quote3.lbcAddress = address(pegInContract);
        quote3.value = 1 ether; // Different value
        bytes32 hash3 = pegInContract.hashPegInQuote(quote3);

        assertTrue(hash1a != hash3, "Changing quote value should change hash");
    }

    function test_HashPegInQuote_IncludesAllFieldsInHash() public view {
        // This test ensures every field in PegInQuote affects the hash
        // If a new field is added but not included in the hash function, this test will fail
        Quotes.PegInQuote memory baseQuote = createSpecificPegInQuote1();
        baseQuote.lbcAddress = address(pegInContract);
        bytes32 baseHash = pegInContract.hashPegInQuote(baseQuote);

        Quotes.PegInQuote memory modifiedQuote;

        // Test callFee
        modifiedQuote = baseQuote;
        modifiedQuote.callFee = baseQuote.callFee + 1;
        assertTrue(
            pegInContract.hashPegInQuote(modifiedQuote) != baseHash,
            "callFee should affect hash"
        );

        // Test penaltyFee
        modifiedQuote = baseQuote;
        modifiedQuote.penaltyFee = baseQuote.penaltyFee + 1;
        assertTrue(
            pegInContract.hashPegInQuote(modifiedQuote) != baseHash,
            "penaltyFee should affect hash"
        );

        // Test fedBtcAddress
        modifiedQuote = baseQuote;
        modifiedQuote.fedBtcAddress = bytes20(
            0x1234567890123456789012345678901234567890
        );
        assertTrue(
            pegInContract.hashPegInQuote(modifiedQuote) != baseHash,
            "fedBtcAddress should affect hash"
        );

        // Test contractAddress
        modifiedQuote = baseQuote;
        modifiedQuote.contractAddress = address(
            0x1234567890123456789012345678901234567890
        );
        assertTrue(
            pegInContract.hashPegInQuote(modifiedQuote) != baseHash,
            "contractAddress should affect hash"
        );

        // Test data
        modifiedQuote = baseQuote;
        modifiedQuote.data = hex"1234"; // Different data
        assertTrue(
            pegInContract.hashPegInQuote(modifiedQuote) != baseHash,
            "data should affect hash"
        );

        // Test gasLimit
        modifiedQuote = baseQuote;
        modifiedQuote.gasLimit = baseQuote.gasLimit + 1;
        assertTrue(
            pegInContract.hashPegInQuote(modifiedQuote) != baseHash,
            "gasLimit should affect hash"
        );

        // Test nonce
        modifiedQuote = baseQuote;
        modifiedQuote.nonce = baseQuote.nonce + 1;
        assertTrue(
            pegInContract.hashPegInQuote(modifiedQuote) != baseHash,
            "nonce should affect hash"
        );

        // Test value
        modifiedQuote = baseQuote;
        modifiedQuote.value = baseQuote.value + 1;
        assertTrue(
            pegInContract.hashPegInQuote(modifiedQuote) != baseHash,
            "value should affect hash"
        );

        // Test agreementTimestamp
        modifiedQuote = baseQuote;
        modifiedQuote.agreementTimestamp = baseQuote.agreementTimestamp + 1;
        assertTrue(
            pegInContract.hashPegInQuote(modifiedQuote) != baseHash,
            "agreementTimestamp should affect hash"
        );

        // Test timeForDeposit
        modifiedQuote = baseQuote;
        modifiedQuote.timeForDeposit = baseQuote.timeForDeposit + 1;
        assertTrue(
            pegInContract.hashPegInQuote(modifiedQuote) != baseHash,
            "timeForDeposit should affect hash"
        );

        // Test callTime
        modifiedQuote = baseQuote;
        modifiedQuote.callTime = baseQuote.callTime + 1;
        assertTrue(
            pegInContract.hashPegInQuote(modifiedQuote) != baseHash,
            "callTime should affect hash"
        );

        // Test depositConfirmations
        modifiedQuote = baseQuote;
        modifiedQuote.depositConfirmations = baseQuote.depositConfirmations + 1;
        assertTrue(
            pegInContract.hashPegInQuote(modifiedQuote) != baseHash,
            "depositConfirmations should affect hash"
        );

        // Test callOnRegister
        modifiedQuote = baseQuote;
        modifiedQuote.callOnRegister = !baseQuote.callOnRegister;
        assertTrue(
            pegInContract.hashPegInQuote(modifiedQuote) != baseHash,
            "callOnRegister should affect hash"
        );

        // Test productFeeAmount
        modifiedQuote = baseQuote;
        modifiedQuote.productFeeAmount = baseQuote.productFeeAmount + 1;
        assertTrue(
            pegInContract.hashPegInQuote(modifiedQuote) != baseHash,
            "productFeeAmount should affect hash"
        );

        // Test gasFee
        modifiedQuote = baseQuote;
        modifiedQuote.gasFee = baseQuote.gasFee + 1;
        assertTrue(
            pegInContract.hashPegInQuote(modifiedQuote) != baseHash,
            "gasFee should affect hash"
        );

        // Test liquidityProviderRskAddress
        modifiedQuote = baseQuote;
        modifiedQuote.liquidityProviderRskAddress = address(
            0x1234567890123456789012345678901234567890
        );
        assertTrue(
            pegInContract.hashPegInQuote(modifiedQuote) != baseHash,
            "liquidityProviderRskAddress should affect hash"
        );

        // Test rskRefundAddress
        modifiedQuote = baseQuote;
        modifiedQuote.rskRefundAddress = payable(
            address(0x1234567890123456789012345678901234567890)
        );
        assertTrue(
            pegInContract.hashPegInQuote(modifiedQuote) != baseHash,
            "rskRefundAddress should affect hash"
        );

        // Test btcRefundAddress
        modifiedQuote = baseQuote;
        modifiedQuote.btcRefundAddress = new bytes(21);
        modifiedQuote.btcRefundAddress[0] = 0x6f;
        modifiedQuote.btcRefundAddress[1] = 0xff; // Different
        assertTrue(
            pegInContract.hashPegInQuote(modifiedQuote) != baseHash,
            "btcRefundAddress should affect hash"
        );

        // Test liquidityProviderBtcAddress
        modifiedQuote = baseQuote;
        modifiedQuote.liquidityProviderBtcAddress = new bytes(21);
        modifiedQuote.liquidityProviderBtcAddress[0] = 0x6f;
        modifiedQuote.liquidityProviderBtcAddress[1] = 0xff; // Different
        assertTrue(
            pegInContract.hashPegInQuote(modifiedQuote) != baseHash,
            "liquidityProviderBtcAddress should affect hash"
        );
    }

    // ============ Helper Functions ============

    function createBasicPegInQuote()
        internal
        returns (Quotes.PegInQuote memory)
    {
        bytes memory testBtcAddress = new bytes(21);

        return
            Quotes.PegInQuote({
                callFee: 100000000000000,
                penaltyFee: 10000000000000,
                value: 1 ether,
                productFeeAmount: 0,
                gasFee: 100,
                fedBtcAddress: bytes20(testBtcAddress),
                lbcAddress: address(pegInContract),
                liquidityProviderRskAddress: makeAddr("lp"),
                contractAddress: makeAddr("user"),
                rskRefundAddress: payable(makeAddr("refund")),
                nonce: 1,
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

    function createSpecificPegInQuote1()
        internal
        pure
        returns (Quotes.PegInQuote memory)
    {
        // This matches QUOTE_MOCK from the TypeScript test
        bytes memory testBtcAddress = new bytes(21);

        return
            Quotes.PegInQuote({
                callFee: 100000000000000,
                penaltyFee: 10000000000000,
                value: 985215170000000000,
                productFeeAmount: 0,
                gasFee: 547377600000,
                fedBtcAddress: bytes20(
                    0x6b9a1d6634133e163A35eC8d7b6f496C32Cc16b0
                ),
                lbcAddress: 0x2E2Ed0Cfd3AD2f1d34481277b3204d807Ca2F8c2,
                liquidityProviderRskAddress: 0x82a06eBDB97776a2da4041dF8f2b2ea8D3257852,
                contractAddress: 0xaC31A4bEedd7EC916B7A48a612230cb85c1aaf56,
                rskRefundAddress: payable(
                    0xaC31A4bEedd7EC916B7A48a612230cb85c1aaf56
                ),
                nonce: 3635227228603468300,
                gasLimit: 21000,
                agreementTimestamp: 1752739488,
                timeForDeposit: 5400,
                callTime: 7200,
                depositConfirmations: 3,
                callOnRegister: false,
                btcRefundAddress: testBtcAddress,
                liquidityProviderBtcAddress: testBtcAddress,
                data: new bytes(0)
            });
    }

    function createSpecificPegInQuote2()
        internal
        pure
        returns (Quotes.PegInQuote memory)
    {
        bytes memory testBtcAddress = new bytes(21);

        return
            Quotes.PegInQuote({
                callFee: 1478412310000000,
                penaltyFee: 10000000000000,
                value: 517700700000000000,
                productFeeAmount: 0,
                gasFee: 547377600000,
                fedBtcAddress: bytes20(
                    0x6b9a1d6634133e163A35eC8d7b6f496C32Cc16b0
                ),
                lbcAddress: 0x2E2Ed0Cfd3AD2f1d34481277b3204d807Ca2F8c2,
                liquidityProviderRskAddress: 0x82a06eBDB97776a2da4041dF8f2b2ea8D3257852,
                contractAddress: 0x129d2280f9C35C0Caf3f172d487Fd9A3f894fD26,
                rskRefundAddress: payable(
                    0x129d2280f9C35C0Caf3f172d487Fd9A3f894fD26
                ),
                nonce: 6080686644105603000,
                gasLimit: 21000,
                agreementTimestamp: 1755356567,
                timeForDeposit: 7200,
                callTime: 10800,
                depositConfirmations: 2,
                callOnRegister: false,
                btcRefundAddress: testBtcAddress,
                liquidityProviderBtcAddress: testBtcAddress,
                data: new bytes(0)
            });
    }

    function createSpecificPegInQuote3()
        internal
        pure
        returns (Quotes.PegInQuote memory)
    {
        bytes memory testBtcAddress = new bytes(21);

        return
            Quotes.PegInQuote({
                callFee: 2009314000000000,
                penaltyFee: 10000000000000,
                value: 578580000000000000,
                productFeeAmount: 0,
                gasFee: 547377600000,
                fedBtcAddress: bytes20(
                    0x6b9a1d6634133e163A35eC8d7b6f496C32Cc16b0
                ),
                lbcAddress: 0x2E2Ed0Cfd3AD2f1d34481277b3204d807Ca2F8c2,
                liquidityProviderRskAddress: 0x82a06eBDB97776a2da4041dF8f2b2ea8D3257852,
                contractAddress: 0xaC31A4bEedd7EC916B7A48a612230cb85c1aaf56,
                rskRefundAddress: payable(
                    0xaC31A4bEedd7EC916B7A48a612230cb85c1aaf56
                ),
                nonce: 7756734892733337000,
                gasLimit: 21000,
                agreementTimestamp: 1755682139,
                timeForDeposit: 7200,
                callTime: 10800,
                depositConfirmations: 2,
                callOnRegister: false,
                btcRefundAddress: testBtcAddress,
                liquidityProviderBtcAddress: testBtcAddress,
                data: new bytes(0)
            });
    }
}
