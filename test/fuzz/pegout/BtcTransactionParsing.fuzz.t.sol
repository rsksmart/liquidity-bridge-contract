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
        bytes memory btcTxWrongHash = generateBtcTxWithCustomHash(quote, wrongHash);

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

    /// @notice Fuzz test: BTC transaction with varying amounts
    /// @dev Tests that refunds fail when BTC tx amount is less than quote value
    function testFuzz_RefundPegOut_ValidatesTransactionAmount(
        uint128 quoteValue,
        uint128 btcTxAmount
    ) public {
        quoteValue = uint128(bound(quoteValue, 0.001 ether, 10 ether));
        btcTxAmount = uint128(bound(btcTxAmount, 0.0001 ether, 10 ether));

        // Skip if amounts match (that's the success case)
        vm.assume(btcTxAmount < quoteValue);

        Quotes.PegOutQuote memory quote = createAndDepositFuzzQuote(quoteValue);
        bytes32 quoteHash = pegOutContract.hashPegOutQuote(quote);

        // Generate BTC tx with different amount
        bytes memory btcTx = generateBtcTxWithCustomAmount(quote, quoteHash, btcTxAmount);

        // Setup bridge
        setupFuzzBridgeMock(quote);

        // Should revert with MalformedTransaction when amount validation fails
        // The output script parsing extracts amount, and validation fails on amount mismatch
        bytes memory expectedOutputScript = abi.encodePacked(
            hex"76a914",
            extractHash160(quote.depositAddress),
            hex"88ac"
        );

        vm.prank(pegOutLp);
        vm.expectRevert(
            abi.encodeWithSelector(
                IPegOut.MalformedTransaction.selector,
                expectedOutputScript
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
        bytes memory btcTx = generateBtcTxWithCustomAmount(quote, quoteHash, btcTxAmount);

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
    ///      with MalformedTransaction error instead of relying on panics
    function testFuzz_RefundPegOut_RejectsMalformedTransactions(
        uint8 invalidScriptLength
    ) public {
        // Generate invalid output script lengths that would fail validation
        // Valid P2PKH is 25 bytes, so anything < 5 or > 100 is clearly invalid
        invalidScriptLength = uint8(bound(invalidScriptLength, 1, 4));

        Quotes.PegOutQuote memory quote = createAndDepositFuzzQuote(1 ether);
        bytes32 quoteHash = pegOutContract.hashPegOutQuote(quote);

        // Create a transaction with valid structure but malformed output script
        uint64 satAmount = uint64(quote.value / 1e10);

        // Create an invalid output script (too short to be valid P2PKH/P2SH/etc.)
        bytes memory invalidOutputScript = new bytes(invalidScriptLength);
        for (uint8 i = 0; i < invalidScriptLength; i++) {
            invalidOutputScript[i] = bytes1(i);  // Fill with some data
        }

        // Build transaction with malformed output script
        bytes memory malformedTx = abi.encodePacked(
            hex"01000000",  // Version
            hex"01",       // 1 input
            hex"013503c427ba46058d2d8ac9221a2f6fd50734a69f19dae65420191e3ada2d40",
            hex"00000000",
            hex"6a",
            hex"47304402205d047dbd8c49aea5bd0400b85a57b2da7e139cec632fb138b7bee1d382fd70ca02201aa529f59b4f66fdf86b0728937a91a40962aedd3f6e30bce5208fec0464d54901210255507b238c6f14735a7abe96a635058da47b05b61737a610bef757f009eea2a4",
            hex"ffffffff",
            hex"02",       // 2 outputs
            toLittleEndian64(satAmount),
            invalidScriptLength,
            invalidOutputScript,
            hex"0000000000000000",  // 0 amount for OP_RETURN
            hex"22",               // script length (34 bytes)
            hex"6a20",             // OP_RETURN PUSH32
            quoteHash,
            hex"00000000"          // Locktime
        );

        // Setup bridge
        setupFuzzBridgeMock(quote);

        // Should revert with MalformedTransaction for the invalid output script
        vm.prank(pegOutLp);
        vm.expectRevert(
            abi.encodeWithSelector(
                IPegOut.MalformedTransaction.selector,
                invalidOutputScript
            )
        );
        pegOutContract.refundPegOut(
            quoteHash,
            malformedTx,
            BLOCK_HEADER_HASH,
            PARTIAL_MERKLE_TREE,
            merkleHashes
        );
    }

    /// @notice Fuzz test: OP_RETURN with incorrect size prefix
    /// @dev Tests that malformed OP_RETURN scripts are rejected
    function testFuzz_RefundPegOut_RejectsWrongOpReturnSize(
        uint8 sizePrefix
    ) public {
        // Valid OP_RETURN for 32-byte hash should be 0x20 (32 in decimal)
        // Bound to reasonable sizes first
        sizePrefix = uint8(bound(sizePrefix, 1, 75));
        // Then skip the valid size range (30-35 to account for off-by-one variations)
        vm.assume(sizePrefix < 30 || sizePrefix > 35);

        Quotes.PegOutQuote memory quote = createAndDepositFuzzQuote(1 ether);
        bytes32 quoteHash = pegOutContract.hashPegOutQuote(quote);

        // Generate BTC tx with wrong OP_RETURN size
        bytes memory btcTx = generateBtcTxWithWrongOpReturnSize(quote, quoteHash, sizePrefix);

        // Setup bridge
        setupFuzzBridgeMock(quote);

        // Will revert with MalformedTransaction due to incorrect OP_RETURN script
        // Build the expected malformed OP_RETURN script
        bytes memory malformedOpReturn = abi.encodePacked(
            hex"6a",        // OP_RETURN
            sizePrefix,    // Wrong size prefix
            quoteHash      // Quote hash (but size prefix doesn't match)
        );

        vm.prank(pegOutLp);
        vm.expectRevert(
            abi.encodeWithSelector(
                IPegOut.MalformedTransaction.selector,
                malformedOpReturn
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

    /// @notice Fuzz test: Different BTC address types should all work
    /// @dev Maps the fuzz input to supported address types and tests each
    function testFuzz_RefundPegOut_AcceptsDifferentAddressTypes(
        uint8 addressTypeIndex,
        bytes20 hash160
    ) public {
        // Bound to supported address types (0-3: p2pkh, p2sh, p2wpkh, p2tr)
        addressTypeIndex = uint8(bound(addressTypeIndex, 0, 3));
        vm.assume(hash160 != bytes20(0)); // Avoid zero address

        string memory addressType = getAddressTypeFromIndex(addressTypeIndex);

        Quotes.PegOutQuote memory quote = createFuzzTestQuoteWithAddressType(
            1 ether,
            addressType,
            hash160
        );

        bytes32 quoteHash = pegOutContract.hashPegOutQuote(quote);
        bytes memory signature = signFuzzQuote(pegOutLp, quoteHash);

        // Deposit
        vm.prank(fuzzUser);
        pegOutContract.depositPegOut{value: getTotalQuoteValue(quote)}(quote, signature);

        // Generate BTC tx based on address type
        bytes memory btcTx = generateBtcTxForAddressType(quote, quoteHash, addressType);

        // Setup bridge
        setupFuzzBridgeMock(quote);

        // Refund should succeed for all supported address types
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

    /// @notice Generates a BTC transaction for the specified address type
    function generateBtcTxForAddressType(
        Quotes.PegOutQuote memory quote,
        bytes32 quoteHash,
        string memory addressType
    ) internal pure returns (bytes memory) {
        uint64 satAmount = uint64(quote.value / 1e10);
        bytes memory outputScript = getOutputScriptForAddressType(quote.depositAddress, addressType);

        return abi.encodePacked(
            hex"01000000",  // Version
            hex"01",       // 1 input
            hex"013503c427ba46058d2d8ac9221a2f6fd50734a69f19dae65420191e3ada2d40",
            hex"00000000",
            hex"6a",
            hex"47304402205d047dbd8c49aea5bd0400b85a57b2da7e139cec632fb138b7bee1d382fd70ca02201aa529f59b4f66fdf86b0728937a91a40962aedd3f6e30bce5208fec0464d54901210255507b238c6f14735a7abe96a635058da47b05b61737a610bef757f009eea2a4",
            hex"ffffffff",
            hex"02",       // 2 outputs
            toLittleEndian64(satAmount),
            uint8(outputScript.length),
            outputScript,
            hex"0000000000000000",  // 0 amount for OP_RETURN
            hex"22",               // script length (34 bytes)
            hex"6a20",             // OP_RETURN PUSH32
            quoteHash,
            hex"00000000"          // Locktime
        );
    }

    /// @notice Generates the appropriate output script for the given address type
    function getOutputScriptForAddressType(
        bytes memory btcAddress,
        string memory addressType
    ) internal pure returns (bytes memory) {
        bytes memory hash160 = new bytes(20);
        for (uint i = 0; i < 20; i++) {
            hash160[i] = btcAddress[i + 1];
        }

        bytes32 addressTypeHash = keccak256(bytes(addressType));

        if (addressTypeHash == keccak256(bytes("p2pkh"))) {
            // P2PKH: OP_DUP OP_HASH160 <20 bytes> OP_EQUALVERIFY OP_CHECKSIG
            return abi.encodePacked(hex"76a914", hash160, hex"88ac");
        } else if (addressTypeHash == keccak256(bytes("p2sh"))) {
            // P2SH: OP_HASH160 <20 bytes> OP_EQUAL
            return abi.encodePacked(hex"a914", hash160, hex"87");
        } else if (addressTypeHash == keccak256(bytes("p2wpkh"))) {
            // P2WPKH: OP_0 <20 bytes>
            return abi.encodePacked(hex"0014", hash160);
        } else {
            // P2TR: OP_1 <32 bytes> (use hash160 padded to 32 bytes for simplicity)
            return abi.encodePacked(hex"5120", hash160, hex"000000000000000000000000");
        }
    }

    /// @notice Fuzz test: Transaction with wrong destination address
    /// @dev Tests that BTC transactions paying to wrong address are rejected
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
        bytes memory signature = signFuzzQuote(pegOutLp, quoteHash);

        // Deposit
        vm.prank(fuzzUser);
        pegOutContract.depositPegOut{value: getTotalQuoteValue(quote)}(quote, signature);

        // Generate BTC tx with wrong destination (use explicit wrong output script)
        uint64 satAmount = uint64(quote.value / 1e10);
        bytes memory wrongOutputScript = abi.encodePacked(hex"76a914", wrongHash, hex"88ac");
        bytes memory expectedOutputScript = abi.encodePacked(hex"76a914", correctHash, hex"88ac");

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

        // Should revert with InvalidDestination error
        vm.prank(pegOutLp);
        vm.expectRevert(
            abi.encodeWithSelector(
                IPegOut.InvalidDestination.selector,
                expectedOutputScript,
                wrongOutputScript
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

        bytes memory outputScript = abi.encodePacked(hex"76a914", hash160, hex"88ac");

        return abi.encodePacked(
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

        bytes memory outputScript = abi.encodePacked(hex"76a914", hash160, hex"88ac");

        return abi.encodePacked(
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

        bytes memory outputScript = abi.encodePacked(hex"76a914", hash160, hex"88ac");

        return abi.encodePacked(
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
