// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {PegInTestBase} from "../../pegin/PegInTestBase.sol";
import {Quotes} from "../../../src/libraries/Quotes.sol";
import {IPegIn} from "../../../src/interfaces/IPegIn.sol";
import {Flyover} from "../../../src/libraries/Flyover.sol";

/// @title PegIn Quote Hashing Fuzz Tests
/// @notice Fuzz tests for PegIn quote hashing to ensure uniqueness and collision resistance
contract PegInQuoteHashingFuzzTest is PegInTestBase {
    function setUp() public {
        deployPegInContract();
    }

    /// @notice Fuzz test: Hash should be deterministic for same quote
    function testFuzz_HashPegInQuote_IsDeterministic(
        uint128 value,
        uint64 callFee,
        int64 nonce,
        uint32 agreementTimestamp
    ) public view {
        // Bound agreementTimestamp to avoid overflow
        agreementTimestamp = uint32(bound(agreementTimestamp, 1000000, type(uint32).max - 10000));
        // Ensure total (value + callFee + gasFee) is above minimum
        // createBasicQuote has gasFee=100, so we need value + callFee >= TEST_MIN_PEGIN - 100
        value = uint128(bound(value, TEST_MIN_PEGIN, 10 ether));

        Quotes.PegInQuote memory quote = createBasicQuote();
        quote.value = value;
        quote.callFee = callFee;
        quote.nonce = nonce;
        quote.agreementTimestamp = agreementTimestamp;

        // Hash twice and ensure deterministic
        bytes32 hash1 = pegInContract.hashPegInQuote(quote);
        bytes32 hash2 = pegInContract.hashPegInQuote(quote);

        assertEq(hash1, hash2, "Hash should be deterministic");
    }

    /// @notice Fuzz test: Different values should produce different hashes
    function testFuzz_HashPegInQuote_ValueChangesHash(
        uint256 value1,
        uint256 value2
    ) public view {
        // Bound to valid range (above min peg in)
        value1 = bound(value1, TEST_MIN_PEGIN, type(uint128).max);
        value2 = bound(value2, TEST_MIN_PEGIN, type(uint128).max);
        vm.assume(value1 != value2);

        Quotes.PegInQuote memory quote1 = createBasicQuote();
        quote1.value = value1;

        Quotes.PegInQuote memory quote2 = createBasicQuote();
        quote2.value = value2;

        bytes32 hash1 = pegInContract.hashPegInQuote(quote1);
        bytes32 hash2 = pegInContract.hashPegInQuote(quote2);

        assertTrue(hash1 != hash2, "Different values should produce different hashes");
    }

    /// @notice Fuzz test: Different nonces should produce different hashes
    function testFuzz_HashPegInQuote_NonceChangesHash(
        int64 nonce1,
        int64 nonce2
    ) public view {
        vm.assume(nonce1 != nonce2);

        Quotes.PegInQuote memory quote1 = createBasicQuote();
        quote1.nonce = nonce1;

        Quotes.PegInQuote memory quote2 = createBasicQuote();
        quote2.nonce = nonce2;

        bytes32 hash1 = pegInContract.hashPegInQuote(quote1);
        bytes32 hash2 = pegInContract.hashPegInQuote(quote2);

        assertTrue(hash1 != hash2, "Different nonces should produce different hashes");
    }

    /// @notice Fuzz test: Different LP addresses should produce different hashes
    function testFuzz_HashPegInQuote_LpAddressChangesHash(
        address lp1,
        address lp2
    ) public view {
        vm.assume(lp1 != lp2);
        vm.assume(lp1 != address(0));
        vm.assume(lp2 != address(0));

        Quotes.PegInQuote memory quote1 = createBasicQuote();
        quote1.liquidityProviderRskAddress = lp1;

        Quotes.PegInQuote memory quote2 = createBasicQuote();
        quote2.liquidityProviderRskAddress = lp2;

        bytes32 hash1 = pegInContract.hashPegInQuote(quote1);
        bytes32 hash2 = pegInContract.hashPegInQuote(quote2);

        assertTrue(hash1 != hash2, "Different LP addresses should produce different hashes");
    }

    /// @notice Fuzz test: Different contract addresses should produce different hashes
    function testFuzz_HashPegInQuote_ContractAddressChangesHash(
        address contract1,
        address contract2
    ) public view {
        vm.assume(contract1 != contract2);
        vm.assume(contract1 != address(0) && contract1 != address(bridgeMock));
        vm.assume(contract2 != address(0) && contract2 != address(bridgeMock));

        Quotes.PegInQuote memory quote1 = createBasicQuote();
        quote1.contractAddress = contract1;

        Quotes.PegInQuote memory quote2 = createBasicQuote();
        quote2.contractAddress = contract2;

        bytes32 hash1 = pegInContract.hashPegInQuote(quote1);
        bytes32 hash2 = pegInContract.hashPegInQuote(quote2);

        assertTrue(hash1 != hash2, "Different contract addresses should produce different hashes");
    }

    /// @notice Fuzz test: Different timestamps should produce different hashes
    function testFuzz_HashPegInQuote_TimestampChangesHash(
        uint32 timestamp1,
        uint32 timestamp2
    ) public view {
        // Bound to avoid overflow with timeForDeposit
        timestamp1 = uint32(bound(timestamp1, 1000000, type(uint32).max - 10000));
        timestamp2 = uint32(bound(timestamp2, 1000000, type(uint32).max - 10000));
        vm.assume(timestamp1 != timestamp2);

        Quotes.PegInQuote memory quote1 = createBasicQuote();
        quote1.agreementTimestamp = timestamp1;

        Quotes.PegInQuote memory quote2 = createBasicQuote();
        quote2.agreementTimestamp = timestamp2;

        bytes32 hash1 = pegInContract.hashPegInQuote(quote1);
        bytes32 hash2 = pegInContract.hashPegInQuote(quote2);

        assertTrue(hash1 != hash2, "Different timestamps should produce different hashes");
    }

    /// @notice Fuzz test: Wrong contract address should revert
    function testFuzz_HashPegInQuote_RevertsOnWrongContract(
        address wrongContract
    ) public {
        vm.assume(wrongContract != address(pegInContract));
        vm.assume(wrongContract != address(0));

        Quotes.PegInQuote memory quote = createBasicQuote();
        quote.lbcAddress = wrongContract;

        vm.expectRevert(
            abi.encodeWithSelector(
                Flyover.IncorrectContract.selector,
                address(pegInContract),
                wrongContract
            )
        );
        pegInContract.hashPegInQuote(quote);
    }

    /// @notice Fuzz test: All fee combinations should produce unique hashes
    function testFuzz_HashPegInQuote_FeeFieldsChangeHash(
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
        callFee1 = bound(callFee1, 0, 1 ether);
        penaltyFee1 = bound(penaltyFee1, 0, 1 ether);
        productFeeAmount1 = bound(productFeeAmount1, 0, 1 ether);
        gasFee1 = bound(gasFee1, 0, 0.1 ether);

        callFee2 = bound(callFee2, 0, 1 ether);
        penaltyFee2 = bound(penaltyFee2, 0, 1 ether);
        productFeeAmount2 = bound(productFeeAmount2, 0, 1 ether);
        gasFee2 = bound(gasFee2, 0, 0.1 ether);

        // Ensure at least one fee is different
        vm.assume(
            callFee1 != callFee2 ||
            penaltyFee1 != penaltyFee2 ||
            productFeeAmount1 != productFeeAmount2 ||
            gasFee1 != gasFee2
        );

        Quotes.PegInQuote memory quote1 = createBasicQuote();
        quote1.callFee = callFee1;
        quote1.penaltyFee = penaltyFee1;
        quote1.productFeeAmount = productFeeAmount1;
        quote1.gasFee = gasFee1;
        // Ensure total is above min peg in
        quote1.value = TEST_MIN_PEGIN;

        Quotes.PegInQuote memory quote2 = createBasicQuote();
        quote2.callFee = callFee2;
        quote2.penaltyFee = penaltyFee2;
        quote2.productFeeAmount = productFeeAmount2;
        quote2.gasFee = gasFee2;
        quote2.value = TEST_MIN_PEGIN;

        bytes32 hash1 = pegInContract.hashPegInQuote(quote1);
        bytes32 hash2 = pegInContract.hashPegInQuote(quote2);

        assertTrue(hash1 != hash2, "Different fee combinations should produce different hashes");
    }

    /// @notice Fuzz test: Invalid BTC refund address length should revert
    function testFuzz_HashPegInQuote_RevertsOnInvalidRefundAddressLength(
        uint8 length
    ) public {
        // Valid length is 21, test invalid lengths
        // Bound first, then assume to properly exclude 21
        length = uint8(bound(length, 1, 100));
        vm.assume(length != 21);

        Quotes.PegInQuote memory quote = createBasicQuote();
        quote.btcRefundAddress = new bytes(length);

        vm.expectRevert(
            abi.encodeWithSelector(
                IPegIn.InvalidRefundAddress.selector,
                quote.btcRefundAddress
            )
        );
        pegInContract.hashPegInQuote(quote);
    }

    /// @notice Fuzz test: Amount under minimum should revert
    function testFuzz_HashPegInQuote_RevertsOnAmountUnderMinimum(
        uint128 value,
        uint64 callFee,
        uint64 productFeeAmount,
        uint32 gasFee
    ) public {
        // Bound so total is definitely under minimum
        value = uint128(bound(value, 0, 0.1 ether));
        callFee = uint64(bound(callFee, 0, 0.1 ether));
        productFeeAmount = uint64(bound(productFeeAmount, 0, 0.1 ether));
        gasFee = uint32(bound(gasFee, 0, 0.01 ether));

        uint256 total = uint256(value) + uint256(callFee) + uint256(productFeeAmount) + uint256(gasFee);
        vm.assume(total < TEST_MIN_PEGIN);

        Quotes.PegInQuote memory quote = createBasicQuote();
        quote.value = value;
        quote.callFee = callFee;
        quote.productFeeAmount = productFeeAmount;
        quote.gasFee = gasFee;

        vm.expectRevert(
            abi.encodeWithSelector(
                IPegIn.AmountUnderMinimum.selector,
                TEST_MIN_PEGIN
            )
        );
        pegInContract.hashPegInQuote(quote);
    }

    // ============ Helper Functions ============

    function createBasicQuote() internal view returns (Quotes.PegInQuote memory) {
        bytes memory testBtcAddress = new bytes(21);
        testBtcAddress[0] = 0x6f; // Testnet version byte

        address destination = address(0x1234567890123456789012345678901234567890);
        address refund = address(0xABcdEFABcdEFabcdEfAbCdefabcdeFABcDEFabCD);
        address lp = address(0x9876543210987654321098765432109876543210);

        return Quotes.PegInQuote({
            callFee: 100000000000000,
            penaltyFee: 10000000000000,
            value: TEST_MIN_PEGIN,
            productFeeAmount: 0,
            gasFee: 100,
            fedBtcAddress: bytes20(testBtcAddress),
            lbcAddress: address(pegInContract),
            liquidityProviderRskAddress: lp,
            contractAddress: destination,
            rskRefundAddress: payable(refund),
            nonce: 12345,
            gasLimit: 21000,
            agreementTimestamp: 1000000,
            timeForDeposit: 3600,
            callTime: 7200,
            depositConfirmations: 10,
            callOnRegister: false,
            btcRefundAddress: testBtcAddress,
            liquidityProviderBtcAddress: testBtcAddress,
            data: new bytes(0)
        });
    }
}
