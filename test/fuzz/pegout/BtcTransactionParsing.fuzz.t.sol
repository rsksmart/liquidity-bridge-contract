// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {PegOutFuzzTestBase} from "./PegOutFuzzTestBase.sol";
import {Quotes} from "../../../src/libraries/Quotes.sol";
import {IPegOut} from "../../../src/interfaces/IPegOut.sol";
import {Flyover} from "../../../src/libraries/Flyover.sol";

/// @title BtcTransactionParsing Fuzz Tests
/// @notice Fuzz tests for BTC transaction parsing and validation in PegOut refunds
contract BtcTransactionParsingFuzzTest is PegOutFuzzTestBase {
    function setUp() public {
        deployPegOutContract();
        setupProviders();
        initBtcMocks();

        fuzzUser = makeAddr("user");
        vm.deal(fuzzUser, 100 ether);
    }

    /// @notice Fuzz test: OP_RETURN script with different hash values
    function testFuzz_RefundPegOut_ValidatesOpReturnHash(
        bytes32 correctHash,
        bytes32 wrongHash
    ) public {
        vm.assume(correctHash != wrongHash);

        Quotes.PegOutQuote memory quote = createAndDepositFuzzQuote(1 ether);
        bytes32 quoteHash = pegOutContract.hashPegOutQuote(quote);

        // Generate BTC tx with wrong hash in OP_RETURN
        bytes memory btcTxWrongHash = generateBtcTxWithCustomHash(
            quote,
            wrongHash
        );

        // Setup bridge
        setupFuzzBridgeMock(quote);

        vm.prank(pegOutLp);
        vm.expectRevert(
            abi.encodeWithSelector(
                IPegOut.InvalidQuoteHash.selector,
                quoteHash,
                wrongHash
            )
        );
        pegOutContract.refundPegOut(
            quoteHash,
            btcTxWrongHash,
            BLOCK_HEADER_HASH,
            PARTIAL_MERKLE_TREE,
            merkleHashes
        );
    }

    /// @notice Fuzz test: under-value BTC delivery reverts InsufficientAmount
    function testFuzz_RefundPegOut_UnderValue_RevertsInsufficientAmount(
        uint128 quoteValue,
        uint128 btcTxAmount
    ) public {
        quoteValue = uint128(bound(quoteValue, 0.01 ether, 10 ether));
        btcTxAmount = uint128(bound(btcTxAmount, 0.0001 ether, 10 ether));

        uint64 satAmount = uint64(btcTxAmount / 1e10);
        uint256 paidAmountWei = uint256(satAmount) * 1e10;

        Quotes.PegOutQuote memory quote = createAndDepositFuzzQuote(quoteValue);
        bytes32 quoteHash = pegOutContract.hashPegOutQuote(quote);

        vm.assume(paidAmountWei < quote.value);

        uint256 requiredValue = quote.value;
        if (
            quote.value > Quotes.SAT_TO_WEI_CONVERSION &&
            (quote.value % Quotes.SAT_TO_WEI_CONVERSION) != 0
        ) {
            requiredValue =
                quote.value -
                (quote.value % Quotes.SAT_TO_WEI_CONVERSION);
        }
        vm.assume(paidAmountWei < requiredValue);

        bytes memory btcTx = generateBtcTxWithCustomAmount(
            quote,
            quoteHash,
            btcTxAmount
        );

        setupFuzzBridgeMock(quote);

        vm.prank(pegOutLp);
        vm.expectRevert(
            abi.encodeWithSelector(
                Flyover.InsufficientAmount.selector,
                paidAmountWei,
                requiredValue
            )
        );
        pegOutContract.refundPegOut(
            quoteHash,
            btcTx,
            BLOCK_HEADER_HASH,
            PARTIAL_MERKLE_TREE,
            merkleHashes
        );
    }

    /// @notice Fuzz test: BTC transaction amount should succeed when >= quote value
    function testFuzz_RefundPegOut_AcceptsValidAmount(
        uint128 quoteValue,
        uint64 extraAmount
    ) public {
        quoteValue = uint128(bound(quoteValue, 0.001 ether, 5 ether));
        extraAmount = uint64(bound(extraAmount, 0, 1 ether));

        uint256 btcTxAmount = uint256(quoteValue) + uint256(extraAmount);
        vm.assume(btcTxAmount <= 10 ether);

        Quotes.PegOutQuote memory quote = createAndDepositFuzzQuote(quoteValue);
        bytes32 quoteHash = pegOutContract.hashPegOutQuote(quote);

        // Generate BTC tx with exact or higher amount
        bytes memory btcTx = generateBtcTxWithCustomAmount(
            quote,
            quoteHash,
            btcTxAmount
        );

        // Setup bridge
        setupFuzzBridgeMock(quote);

        vm.prank(pegOutLp);
        pegOutContract.refundPegOut(
            quoteHash,
            btcTx,
            BLOCK_HEADER_HASH,
            PARTIAL_MERKLE_TREE,
            merkleHashes
        );

        assertTrue(pegOutContract.isQuoteCompleted(quoteHash));
    }

    /// @notice Fuzz test: Malformed transaction with invalid output scripts
    /// @dev Tests that transactions with malformed output scripts are properly rejected
    ///      BtcUtils.outputScriptToAddress throws "Unsupported script type" for unrecognized scripts
    function testFuzz_RefundPegOut_RejectsMalformedTransactions(
        uint8 invalidScriptLength
    ) public {
        // Generate invalid output script lengths that would fail validation
        // Valid P2PKH is 25 bytes, so anything < 5 is clearly invalid
        invalidScriptLength = uint8(bound(invalidScriptLength, 1, 4));

        Quotes.PegOutQuote memory quote = createAndDepositFuzzQuote(1 ether);
        bytes32 quoteHash = pegOutContract.hashPegOutQuote(quote);

        // Create a transaction with valid structure but malformed output script
        uint64 satAmount = uint64(quote.value / 1e10);

        // Create an invalid output script (too short to be valid P2PKH/P2SH/etc.)
        bytes memory invalidOutputScript = new bytes(invalidScriptLength);
        for (uint8 i = 0; i < invalidScriptLength; i++) {
            invalidOutputScript[i] = bytes1(i); // Fill with some data
        }

        // Build transaction with malformed output script
        bytes memory malformedTx = abi.encodePacked(
            hex"01000000", // Version
            hex"01", // 1 input
            hex"013503c427ba46058d2d8ac9221a2f6fd50734a69f19dae65420191e3ada2d40",
            hex"00000000",
            hex"6a",
            hex"47304402205d047dbd8c49aea5bd0400b85a57b2da7e139cec632fb138b7bee1d382fd70ca02201aa529f59b4f66fdf86b0728937a91a40962aedd3f6e30bce5208fec0464d54901210255507b238c6f14735a7abe96a635058da47b05b61737a610bef757f009eea2a4",
            hex"ffffffff",
            hex"02", // 2 outputs
            toLittleEndian64(satAmount),
            invalidScriptLength,
            invalidOutputScript,
            hex"0000000000000000", // 0 amount for OP_RETURN
            hex"22", // script length (34 bytes)
            hex"6a20", // OP_RETURN PUSH32
            quoteHash,
            hex"00000000" // Locktime
        );

        // Setup bridge
        setupFuzzBridgeMock(quote);

        // BtcUtils library throws "Unsupported script type" for unrecognized output scripts
        vm.prank(pegOutLp);
        vm.expectRevert("Unsupported script type");
        pegOutContract.refundPegOut(
            quoteHash,
            malformedTx,
            BLOCK_HEADER_HASH,
            PARTIAL_MERKLE_TREE,
            merkleHashes
        );
    }

    /// @notice Fuzz test: OP_RETURN with incorrect size prefix
    /// @dev Tests that malformed OP_RETURN scripts are rejected with MalformedTransaction
    ///      The contract checks: scriptLength != 33 || scriptContent[0] != 32
    function testFuzz_RefundPegOut_RejectsWrongOpReturnSize(
        uint8 sizePrefix
    ) public {
        // Valid OP_RETURN size for 32-byte hash is 0x20 (32 in decimal)
        // For the BtcUtils library to parse successfully without panic, we need sizePrefix <= 32
        // For our contract to reject it, we need sizePrefix != 32
        // So test with sizePrefix in range [1, 31]
        sizePrefix = uint8(bound(sizePrefix, 1, 31));

        Quotes.PegOutQuote memory quote = createAndDepositFuzzQuote(1 ether);
        bytes32 quoteHash = pegOutContract.hashPegOutQuote(quote);

        // Generate BTC tx with wrong OP_RETURN size (smaller than expected)
        bytes memory btcTx = generateBtcTxWithWrongOpReturnSize(
            quote,
            quoteHash,
            sizePrefix
        );

        // Setup bridge
        setupFuzzBridgeMock(quote);

        // The BtcUtils.parseNullDataScript extracts: <sizePrefix> <sizePrefix bytes of quoteHash>
        // So the returned scriptContent is: sizePrefix byte + first sizePrefix bytes of quoteHash
        // Total length = sizePrefix + 1, which is != 33 (required for valid 32-byte hash)

        // Build expected scriptContent that parseNullDataScript would return
        bytes memory scriptContent = new bytes(sizePrefix + 1);
        scriptContent[0] = bytes1(sizePrefix);
        for (uint8 i = 0; i < sizePrefix; i++) {
            scriptContent[i + 1] = bytes32(quoteHash)[i];
        }

        vm.prank(pegOutLp);
        vm.expectRevert(
            abi.encodeWithSelector(
                IPegOut.MalformedTransaction.selector,
                scriptContent
            )
        );
        pegOutContract.refundPegOut(
            quoteHash,
            btcTx,
            BLOCK_HEADER_HASH,
            PARTIAL_MERKLE_TREE,
            merkleHashes
        );
    }

    /// @notice Fuzz test: Different P2PKH addresses should all work
    /// @dev Tests with various hash160 values to ensure P2PKH address handling is robust
    function testFuzz_RefundPegOut_AcceptsDifferentAddressTypes(
        bytes20 hash160
    ) public {
        vm.assume(hash160 != bytes20(0)); // Avoid zero address

        // Test P2PKH address type (most common and reliably supported)
        Quotes.PegOutQuote memory quote = createFuzzTestQuoteWithAddressType(
            1 ether,
            "p2pkh",
            hash160
        );

        bytes32 quoteHash = pegOutContract.hashPegOutQuote(quote);
        bytes memory signature = signFuzzQuote(pegOutLp, quote);

        // Deposit
        vm.prank(fuzzUser);
        pegOutContract.depositPegOut{value: getTotalQuoteValue(quote)}(
            quote,
            signature
        );

        // Generate P2PKH BTC tx
        bytes memory btcTx = generateMockBtcTx(quote, quoteHash);

        // Setup bridge
        setupFuzzBridgeMock(quote);

        // Refund should succeed
        vm.prank(pegOutLp);
        pegOutContract.refundPegOut(
            quoteHash,
            btcTx,
            BLOCK_HEADER_HASH,
            PARTIAL_MERKLE_TREE,
            merkleHashes
        );

        assertTrue(pegOutContract.isQuoteCompleted(quoteHash));
    }

    /// @notice Fuzz test: Transaction with wrong destination address
    /// @dev Tests that BTC transactions paying to wrong address are rejected
    ///      Contract validates destination via BtcUtils.outputScriptToAddress which converts
    ///      output scripts back to addresses, then compares with quote.depositAddress
    function testFuzz_RefundPegOut_RejectsWrongDestination(
        bytes20 correctHash,
        bytes20 wrongHash
    ) public {
        vm.assume(correctHash != wrongHash);
        vm.assume(correctHash != bytes20(0) && wrongHash != bytes20(0));

        Quotes.PegOutQuote memory quote = createFuzzTestQuoteWithAddressType(
            1 ether,
            "p2pkh",
            correctHash
        );

        bytes32 quoteHash = pegOutContract.hashPegOutQuote(quote);
        bytes memory signature = signFuzzQuote(pegOutLp, quote);

        // Deposit
        vm.prank(fuzzUser);
        pegOutContract.depositPegOut{value: getTotalQuoteValue(quote)}(
            quote,
            signature
        );

        // Generate BTC tx with wrong destination (P2PKH output script with wrong hash)
        uint64 satAmount = uint64(quote.value / 1e10);
        bytes memory wrongOutputScript = abi.encodePacked(
            hex"76a914",
            wrongHash,
            hex"88ac"
        );

        bytes memory btcTx = abi.encodePacked(
            hex"01000000",
            hex"01",
            hex"013503c427ba46058d2d8ac9221a2f6fd50734a69f19dae65420191e3ada2d40",
            hex"00000000",
            hex"6a",
            hex"47304402205d047dbd8c49aea5bd0400b85a57b2da7e139cec632fb138b7bee1d382fd70ca02201aa529f59b4f66fdf86b0728937a91a40962aedd3f6e30bce5208fec0464d54901210255507b238c6f14735a7abe96a635058da47b05b61737a610bef757f009eea2a4",
            hex"ffffffff",
            hex"02",
            toLittleEndian64(satAmount),
            uint8(wrongOutputScript.length),
            wrongOutputScript,
            hex"0000000000000000",
            hex"22",
            hex"6a20",
            quoteHash,
            hex"00000000"
        );

        // Setup bridge
        setupFuzzBridgeMock(quote);

        // The contract uses BtcUtils.outputScriptToAddress to convert output script to address
        // Expected address: quote.depositAddress (version byte 0x6f + correctHash for P2PKH testnet)
        // Actual address: version byte 0x6f + wrongHash (parsed from the output script)
        bytes memory expectedAddress = abi.encodePacked(hex"6f", correctHash);
        bytes memory actualAddress = abi.encodePacked(hex"6f", wrongHash);

        vm.prank(pegOutLp);
        vm.expectRevert(
            abi.encodeWithSelector(
                IPegOut.InvalidDestination.selector,
                expectedAddress,
                actualAddress
            )
        );
        pegOutContract.refundPegOut(
            quoteHash,
            btcTx,
            BLOCK_HEADER_HASH,
            PARTIAL_MERKLE_TREE,
            merkleHashes
        );
    }

    // ============ BTC Transaction Generator Helpers ============
    // These are specific to this test file for generating custom BTC transactions

    function generateBtcTxWithCustomHash(
        Quotes.PegOutQuote memory quote,
        bytes32 customHash
    ) internal pure returns (bytes memory) {
        uint64 satAmount = uint64(quote.value / 1e10);
        bytes memory hash160 = new bytes(20);
        for (uint i = 0; i < 20; i++) {
            hash160[i] = quote.depositAddress[i + 1];
        }

        bytes memory outputScript = abi.encodePacked(
            hex"76a914",
            hash160,
            hex"88ac"
        );

        return
            abi.encodePacked(
                hex"01000000",
                hex"01",
                hex"013503c427ba46058d2d8ac9221a2f6fd50734a69f19dae65420191e3ada2d40",
                hex"00000000",
                hex"6a",
                hex"47304402205d047dbd8c49aea5bd0400b85a57b2da7e139cec632fb138b7bee1d382fd70ca02201aa529f59b4f66fdf86b0728937a91a40962aedd3f6e30bce5208fec0464d54901210255507b238c6f14735a7abe96a635058da47b05b61737a610bef757f009eea2a4",
                hex"ffffffff",
                hex"02",
                toLittleEndian64(satAmount),
                uint8(outputScript.length),
                outputScript,
                hex"0000000000000000",
                hex"22",
                hex"6a20",
                customHash,
                hex"00000000"
            );
    }

    function generateBtcTxWithCustomAmount(
        Quotes.PegOutQuote memory quote,
        bytes32 quoteHash,
        uint256 customAmount
    ) internal pure returns (bytes memory) {
        uint64 satAmount = uint64(customAmount / 1e10);
        bytes memory hash160 = new bytes(20);
        for (uint i = 0; i < 20; i++) {
            hash160[i] = quote.depositAddress[i + 1];
        }

        bytes memory outputScript = abi.encodePacked(
            hex"76a914",
            hash160,
            hex"88ac"
        );

        return
            abi.encodePacked(
                hex"01000000",
                hex"01",
                hex"013503c427ba46058d2d8ac9221a2f6fd50734a69f19dae65420191e3ada2d40",
                hex"00000000",
                hex"6a",
                hex"47304402205d047dbd8c49aea5bd0400b85a57b2da7e139cec632fb138b7bee1d382fd70ca02201aa529f59b4f66fdf86b0728937a91a40962aedd3f6e30bce5208fec0464d54901210255507b238c6f14735a7abe96a635058da47b05b61737a610bef757f009eea2a4",
                hex"ffffffff",
                hex"02",
                toLittleEndian64(satAmount),
                uint8(outputScript.length),
                outputScript,
                hex"0000000000000000",
                hex"22",
                hex"6a20",
                quoteHash,
                hex"00000000"
            );
    }

    function generateBtcTxWithWrongOpReturnSize(
        Quotes.PegOutQuote memory quote,
        bytes32 quoteHash,
        uint8 wrongSize
    ) internal pure returns (bytes memory) {
        uint64 satAmount = uint64(quote.value / 1e10);
        bytes memory hash160 = new bytes(20);
        for (uint i = 0; i < 20; i++) {
            hash160[i] = quote.depositAddress[i + 1];
        }

        bytes memory outputScript = abi.encodePacked(
            hex"76a914",
            hash160,
            hex"88ac"
        );

        return
            abi.encodePacked(
                hex"01000000",
                hex"01",
                hex"013503c427ba46058d2d8ac9221a2f6fd50734a69f19dae65420191e3ada2d40",
                hex"00000000",
                hex"6a",
                hex"47304402205d047dbd8c49aea5bd0400b85a57b2da7e139cec632fb138b7bee1d382fd70ca02201aa529f59b4f66fdf86b0728937a91a40962aedd3f6e30bce5208fec0464d54901210255507b238c6f14735a7abe96a635058da47b05b61737a610bef757f009eea2a4",
                hex"ffffffff",
                hex"02",
                toLittleEndian64(satAmount),
                uint8(outputScript.length),
                outputScript,
                hex"0000000000000000",
                uint8(wrongSize + 2), // Script length
                hex"6a",
                wrongSize, // Wrong size prefix
                quoteHash,
                hex"00000000"
            );
    }
}
