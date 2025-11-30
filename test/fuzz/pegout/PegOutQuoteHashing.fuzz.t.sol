// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {PegOutTestBase} from "../../pegout/PegOutTestBase.sol";
import {Quotes} from "../../../src/libraries/Quotes.sol";
import {Flyover} from "../../../src/libraries/Flyover.sol";

/// @title PegOutQuoteHashing Fuzz Tests
/// @notice Fuzz tests for PegOut quote hashing to ensure uniqueness and collision resistance
contract PegOutQuoteHashingFuzzTest is PegOutTestBase {
    function setUp() public {
        deployPegOutContract();
    }

    /// @notice Fuzz test: Hash should be deterministic for same quote
    function testFuzz_HashPegOutQuote_IsDeterministic(
        uint128 value,
        uint64 callFee,
        int64 nonce,
        uint32 agreementTimestamp
    ) public view {
        // Bound agreementTimestamp to avoid overflow when adding time deltas
        agreementTimestamp = uint32(bound(agreementTimestamp, 1000000, type(uint32).max - 20000));

        // Ensure addresses are not zero
        address lpRskAddress = address(0x1234567890123456789012345678901234567890);
        address rskRefundAddress = address(0xABcdEFABcdEFabcdEfAbCdefabcdeFABcDEFabCD);

        bytes memory testBtcAddress = new bytes(21);
        testBtcAddress[0] = 0x6f; // Testnet P2PKH version byte

        Quotes.PegOutQuote memory quote = Quotes.PegOutQuote({
            callFee: callFee,
            penaltyFee: 10000000000000,
            value: value,
            productFeeAmount: 0,
            gasFee: 100,
            lbcAddress: address(pegOutContract),
            lpRskAddress: lpRskAddress,
            rskRefundAddress: rskRefundAddress,
            nonce: nonce,
            agreementTimestamp: agreementTimestamp,
            depositDateLimit: agreementTimestamp + 7200,
            transferTime: 3600,
            depositConfirmations: 10,
            transferConfirmations: 2,
            expireBlock: 1000,
            expireDate: agreementTimestamp + 14400,
            depositAddress: testBtcAddress,
            btcRefundAddress: testBtcAddress,
            lpBtcAddress: testBtcAddress
        });

        // Hash twice and ensure deterministic
        bytes32 hash1 = pegOutContract.hashPegOutQuote(quote);
        bytes32 hash2 = pegOutContract.hashPegOutQuote(quote);

        assertEq(hash1, hash2, "Hash should be deterministic");
    }

    /// @notice Fuzz test: Different values should produce different hashes
    function testFuzz_HashPegOutQuote_ValueChangesHash(
        uint256 value1,
        uint256 value2
    ) public view {
        value1 = bound(value1, 0, type(uint128).max);
        value2 = bound(value2, 0, type(uint128).max);
        vm.assume(value1 != value2);

        bytes memory testBtcAddress = new bytes(21);
        testBtcAddress[0] = 0x6f;

        Quotes.PegOutQuote memory quote1 = createBasicQuote();
        quote1.value = value1;
        quote1.lbcAddress = address(pegOutContract);

        Quotes.PegOutQuote memory quote2 = createBasicQuote();
        quote2.value = value2;
        quote2.lbcAddress = address(pegOutContract);

        bytes32 hash1 = pegOutContract.hashPegOutQuote(quote1);
        bytes32 hash2 = pegOutContract.hashPegOutQuote(quote2);

        assertTrue(hash1 != hash2, "Different values should produce different hashes");
    }

    /// @notice Fuzz test: Different nonces should produce different hashes
    function testFuzz_HashPegOutQuote_NonceChangesHash(
        int64 nonce1,
        int64 nonce2
    ) public view {
        vm.assume(nonce1 != nonce2);

        Quotes.PegOutQuote memory quote1 = createBasicQuote();
        quote1.nonce = nonce1;
        quote1.lbcAddress = address(pegOutContract);

        Quotes.PegOutQuote memory quote2 = createBasicQuote();
        quote2.nonce = nonce2;
        quote2.lbcAddress = address(pegOutContract);

        bytes32 hash1 = pegOutContract.hashPegOutQuote(quote1);
        bytes32 hash2 = pegOutContract.hashPegOutQuote(quote2);

        assertTrue(hash1 != hash2, "Different nonces should produce different hashes");
    }

    /// @notice Fuzz test: Different LP addresses should produce different hashes
    function testFuzz_HashPegOutQuote_LpAddressChangesHash(
        address lp1,
        address lp2
    ) public view {
        vm.assume(lp1 != lp2);
        vm.assume(lp1 != address(0));
        vm.assume(lp2 != address(0));

        Quotes.PegOutQuote memory quote1 = createBasicQuote();
        quote1.lpRskAddress = lp1;
        quote1.lbcAddress = address(pegOutContract);

        Quotes.PegOutQuote memory quote2 = createBasicQuote();
        quote2.lpRskAddress = lp2;
        quote2.lbcAddress = address(pegOutContract);

        bytes32 hash1 = pegOutContract.hashPegOutQuote(quote1);
        bytes32 hash2 = pegOutContract.hashPegOutQuote(quote2);

        assertTrue(hash1 != hash2, "Different LP addresses should produce different hashes");
    }

    /// @notice Fuzz test: Different timestamps should produce different hashes
    function testFuzz_HashPegOutQuote_TimestampChangesHash(
        uint32 timestamp1,
        uint32 timestamp2
    ) public view {
        vm.assume(timestamp1 != timestamp2);

        Quotes.PegOutQuote memory quote1 = createBasicQuote();
        quote1.agreementTimestamp = timestamp1;
        quote1.lbcAddress = address(pegOutContract);

        Quotes.PegOutQuote memory quote2 = createBasicQuote();
        quote2.agreementTimestamp = timestamp2;
        quote2.lbcAddress = address(pegOutContract);

        bytes32 hash1 = pegOutContract.hashPegOutQuote(quote1);
        bytes32 hash2 = pegOutContract.hashPegOutQuote(quote2);

        assertTrue(hash1 != hash2, "Different timestamps should produce different hashes");
    }

    /// @notice Fuzz test: Different BTC deposit addresses should produce different hashes
    function testFuzz_HashPegOutQuote_DepositAddressChangesHash(
        bytes20 hash1,
        bytes20 hash2
    ) public view {
        vm.assume(hash1 != hash2);

        bytes memory btcAddress1 = new bytes(21);
        btcAddress1[0] = 0x6f; // Version byte
        for (uint i = 0; i < 20; i++) {
            btcAddress1[i + 1] = bytes1(hash1[i]);
        }

        bytes memory btcAddress2 = new bytes(21);
        btcAddress2[0] = 0x6f; // Version byte
        for (uint i = 0; i < 20; i++) {
            btcAddress2[i + 1] = bytes1(hash2[i]);
        }

        Quotes.PegOutQuote memory quote1 = createBasicQuote();
        quote1.depositAddress = btcAddress1;
        quote1.lbcAddress = address(pegOutContract);

        Quotes.PegOutQuote memory quote2 = createBasicQuote();
        quote2.depositAddress = btcAddress2;
        quote2.lbcAddress = address(pegOutContract);

        bytes32 quoteHash1 = pegOutContract.hashPegOutQuote(quote1);
        bytes32 quoteHash2 = pegOutContract.hashPegOutQuote(quote2);

        assertTrue(quoteHash1 != quoteHash2, "Different deposit addresses should produce different hashes");
    }

    /// @notice Fuzz test: Verify incorrect contract address is rejected
    function testFuzz_HashPegOutQuote_RevertsOnWrongContract(
        address wrongContract
    ) public {
        vm.assume(wrongContract != address(pegOutContract));
        vm.assume(wrongContract != address(0));

        Quotes.PegOutQuote memory quote = createBasicQuote();
        quote.lbcAddress = wrongContract;

        vm.expectRevert(
            abi.encodeWithSelector(
                Flyover.IncorrectContract.selector,
                address(pegOutContract),
                wrongContract
            )
        );
        pegOutContract.hashPegOutQuote(quote);
    }

    /// @notice Fuzz test: All fee combinations should produce unique hashes
    function testFuzz_HashPegOutQuote_FeeFieldsChangeHash(
        uint256 callFee1,
        uint256 penaltyFee1,
        uint256 productFeeAmount1,
        uint256 gasFee1,
        uint256 callFee2,
        uint256 penaltyFee2,
        uint256 productFeeAmount2,
        uint256 gasFee2
    ) public view {
        // Bound to reasonable values
        callFee1 = bound(callFee1, 0, type(uint128).max);
        penaltyFee1 = bound(penaltyFee1, 0, type(uint128).max);
        productFeeAmount1 = bound(productFeeAmount1, 0, type(uint128).max);
        gasFee1 = bound(gasFee1, 0, type(uint128).max);

        callFee2 = bound(callFee2, 0, type(uint128).max);
        penaltyFee2 = bound(penaltyFee2, 0, type(uint128).max);
        productFeeAmount2 = bound(productFeeAmount2, 0, type(uint128).max);
        gasFee2 = bound(gasFee2, 0, type(uint128).max);

        // Ensure at least one fee is different
        vm.assume(
            callFee1 != callFee2 ||
            penaltyFee1 != penaltyFee2 ||
            productFeeAmount1 != productFeeAmount2 ||
            gasFee1 != gasFee2
        );

        Quotes.PegOutQuote memory quote1 = createBasicQuote();
        quote1.callFee = callFee1;
        quote1.penaltyFee = penaltyFee1;
        quote1.productFeeAmount = productFeeAmount1;
        quote1.gasFee = gasFee1;
        quote1.lbcAddress = address(pegOutContract);

        Quotes.PegOutQuote memory quote2 = createBasicQuote();
        quote2.callFee = callFee2;
        quote2.penaltyFee = penaltyFee2;
        quote2.productFeeAmount = productFeeAmount2;
        quote2.gasFee = gasFee2;
        quote2.lbcAddress = address(pegOutContract);

        bytes32 hash1 = pegOutContract.hashPegOutQuote(quote1);
        bytes32 hash2 = pegOutContract.hashPegOutQuote(quote2);

        assertTrue(hash1 != hash2, "Different fee combinations should produce different hashes");
    }

    // ============ Helper Functions ============

    function createBasicQuote() internal pure returns (Quotes.PegOutQuote memory) {
        bytes memory testBtcAddress = new bytes(21);
        testBtcAddress[0] = 0x6f; // Testnet P2PKH version byte

        return Quotes.PegOutQuote({
            callFee: 100000000000000,
            penaltyFee: 10000000000000,
            value: 1 ether,
            productFeeAmount: 0,
            gasFee: 100,
            lbcAddress: address(0), // Will be set in tests
            lpRskAddress: address(0x1234567890123456789012345678901234567890),
            rskRefundAddress: address(0xABcdEFABcdEFabcdEfAbCdefabcdeFABcDEFabCD),
            nonce: 12345,
            agreementTimestamp: 1000000,
            depositDateLimit: 1007200,
            transferTime: 3600,
            depositConfirmations: 10,
            transferConfirmations: 2,
            expireBlock: 1000,
            expireDate: 1014400,
            depositAddress: testBtcAddress,
            btcRefundAddress: testBtcAddress,
            lpBtcAddress: testBtcAddress
        });
    }
}
