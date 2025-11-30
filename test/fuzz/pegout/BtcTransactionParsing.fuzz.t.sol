// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {PegOutTestBase} from "../../pegout/PegOutTestBase.sol";
import {Quotes} from "../../../src/libraries/Quotes.sol";
import {IPegOut} from "../../../src/interfaces/IPegOut.sol";
import {Flyover} from "../../../src/libraries/Flyover.sol";

/// @title BtcTransactionParsing Fuzz Tests
/// @notice Fuzz tests for BTC transaction parsing and validation in PegOut refunds
contract BtcTransactionParsingFuzzTest is PegOutTestBase {
    address public user;

    function setUp() public {
        deployPegOutContract();
        setupProviders();
        initBtcMocks();

        user = makeAddr("user");
        vm.deal(user, 100 ether);
    }

    /// @notice Fuzz test: OP_RETURN script with different hash values
    function testFuzz_RefundPegOut_ValidatesOpReturnHash(
        bytes32 correctHash,
        bytes32 wrongHash
    ) public {
        vm.assume(correctHash != wrongHash);

        Quotes.PegOutQuote memory quote = createAndDepositQuote(1 ether);
        bytes32 quoteHash = pegOutContract.hashPegOutQuote(quote);

        // Generate BTC tx with wrong hash in OP_RETURN
        bytes memory btcTxWrongHash = generateBtcTxWithCustomHash(quote, wrongHash);

        // Setup bridge
        setupBridgeMock(quote);

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

        Quotes.PegOutQuote memory quote = createAndDepositQuote(quoteValue);
        bytes32 quoteHash = pegOutContract.hashPegOutQuote(quote);

        // Generate BTC tx with different amount
        bytes memory btcTx = generateBtcTxWithCustomAmount(quote, quoteHash, btcTxAmount);

        // Setup bridge
        setupBridgeMock(quote);

        // Should revert with MalformedTransaction when amount validation fails
        // The output script parsing extracts amount, and validation fails on amount mismatch
        bytes memory expectedOutputScript = abi.encodePacked(
            hex"76a914",
            extractHash160FromAddress(quote.depositAddress),
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

        Quotes.PegOutQuote memory quote = createAndDepositQuote(quoteValue);
        bytes32 quoteHash = pegOutContract.hashPegOutQuote(quote);

        // Generate BTC tx with exact or higher amount
        bytes memory btcTx = generateBtcTxWithCustomAmount(quote, quoteHash, btcTxAmount);

        // Setup bridge
        setupBridgeMock(quote);

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

    /// @notice Fuzz test: Malformed transaction bytes
    function testFuzz_RefundPegOut_RejectsMalformedTransactions(
        uint8 txLength
    ) public {
        // Test very short transactions (< 10 bytes is definitely invalid)
        txLength = uint8(bound(txLength, 1, 9));

        Quotes.PegOutQuote memory quote = createAndDepositQuote(1 ether);
        bytes32 quoteHash = pegOutContract.hashPegOutQuote(quote);

        bytes memory malformedTx = new bytes(txLength);

        // Setup bridge
        setupBridgeMock(quote);

        vm.prank(pegOutLp);
        // Will revert during parsing with panic (array out of bounds)
        vm.expectRevert(abi.encodeWithSignature("Panic(uint256)", 0x32));
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

        Quotes.PegOutQuote memory quote = createAndDepositQuote(1 ether);
        bytes32 quoteHash = pegOutContract.hashPegOutQuote(quote);

        // Generate BTC tx with wrong OP_RETURN size
        bytes memory btcTx = generateBtcTxWithWrongOpReturnSize(quote, quoteHash, sizePrefix);

        // Setup bridge
        setupBridgeMock(quote);

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

    /// @notice Fuzz test: Different P2PKH address hash160 values should all work
    function testFuzz_RefundPegOut_AcceptsDifferentAddressTypes(
        uint8 /* seed */,
        bytes20 hash160
    ) public {
        // Only test P2PKH addresses since that's what our helper functions support
        // Testing other types would require implementing proper output script generation
        vm.assume(hash160 != bytes20(0)); // Avoid zero address

        Quotes.PegOutQuote memory quote = createTestQuoteWithAddressType(
            1 ether,
            "p2pkh",
            hash160
        );

        bytes32 quoteHash = pegOutContract.hashPegOutQuote(quote);
        bytes memory signature = signQuote(pegOutLp, quoteHash);

        // Deposit
        vm.prank(user);
        pegOutContract.depositPegOut{value: getTotalValue(quote)}(quote, signature);

        // Generate appropriate BTC tx for P2PKH
        bytes memory btcTx = generateMockBtcTx(quote, quoteHash);

        // Setup bridge
        setupBridgeMock(quote);

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
    function testFuzz_RefundPegOut_RejectsWrongDestination(
        bytes20 correctHash,
        bytes20 wrongHash
    ) public {
        vm.assume(correctHash != wrongHash);
        vm.assume(correctHash != bytes20(0) && wrongHash != bytes20(0));

        Quotes.PegOutQuote memory quote = createTestQuoteWithAddressType(
            1 ether,
            "p2pkh",
            correctHash
        );

        bytes32 quoteHash = pegOutContract.hashPegOutQuote(quote);
        bytes memory signature = signQuote(pegOutLp, quoteHash);

        // Deposit
        vm.prank(user);
        pegOutContract.depositPegOut{value: getTotalValue(quote)}(quote, signature);

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
        setupBridgeMock(quote);

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

    // ============ Helper Functions ============

    /// @notice Extracts the 20-byte hash160 from a BTC address (skips version byte)
    function extractHash160FromAddress(bytes memory btcAddress) internal pure returns (bytes memory) {
        bytes memory hash160 = new bytes(20);
        for (uint i = 0; i < 20; i++) {
            hash160[i] = btcAddress[i + 1];
        }
        return hash160;
    }

    function createAndDepositQuote(uint256 value) internal returns (Quotes.PegOutQuote memory) {
        Quotes.PegOutQuote memory quote = createTestQuote(value);
        bytes32 quoteHash = pegOutContract.hashPegOutQuote(quote);
        bytes memory signature = signQuote(pegOutLp, quoteHash);

        vm.prank(user);
        pegOutContract.depositPegOut{value: getTotalValue(quote)}(quote, signature);

        return quote;
    }

    function createTestQuote(uint256 value) internal view returns (Quotes.PegOutQuote memory) {
        bytes memory testBtcAddress = abi.encodePacked(
            hex"6f",
            hex"89abcdefabbaabbaabbaabbaabbaabbaabbaabba"
        );
        uint32 currentTime = uint32(block.timestamp);

        return Quotes.PegOutQuote({
            callFee: 100000000000000,
            penaltyFee: 10000000000000,
            value: value,
            productFeeAmount: 0,
            gasFee: 100,
            lbcAddress: address(pegOutContract),
            lpRskAddress: pegOutLp,
            rskRefundAddress: user,
            nonce: int64(uint64(block.timestamp)),
            agreementTimestamp: currentTime,
            depositDateLimit: currentTime + 7200,
            transferTime: 3600,
            depositConfirmations: 10,
            transferConfirmations: 2,
            expireBlock: uint32(block.number + 1000),
            expireDate: currentTime + 20000,
            depositAddress: testBtcAddress,
            btcRefundAddress: testBtcAddress,
            lpBtcAddress: testBtcAddress
        });
    }

    function createTestQuoteWithAddressType(
        uint256 value,
        string memory addressType,
        bytes20 hash160
    ) internal view returns (Quotes.PegOutQuote memory) {
        bytes memory btcAddress;

        if (keccak256(bytes(addressType)) == keccak256(bytes("p2pkh"))) {
            btcAddress = abi.encodePacked(hex"6f", hash160);
        } else if (keccak256(bytes(addressType)) == keccak256(bytes("p2sh"))) {
            btcAddress = abi.encodePacked(hex"c4", hash160);
        } else if (keccak256(bytes(addressType)) == keccak256(bytes("p2wpkh"))) {
            btcAddress = abi.encodePacked(hex"00", hash160);
        } else if (keccak256(bytes(addressType)) == keccak256(bytes("p2wsh"))) {
            btcAddress = abi.encodePacked(hex"00", hash160, hex"0000000000000000000000"); // 32 bytes for WSH
        } else { // p2tr
            btcAddress = abi.encodePacked(hex"01", hash160, hex"0000000000000000000000"); // 32 bytes for Taproot
        }

        uint32 currentTime = uint32(block.timestamp);

        return Quotes.PegOutQuote({
            callFee: 100000000000000,
            penaltyFee: 10000000000000,
            value: value,
            productFeeAmount: 0,
            gasFee: 100,
            lbcAddress: address(pegOutContract),
            lpRskAddress: pegOutLp,
            rskRefundAddress: user,
            nonce: int64(uint64(block.timestamp)),
            agreementTimestamp: currentTime,
            depositDateLimit: currentTime + 7200,
            transferTime: 3600,
            depositConfirmations: 10,
            transferConfirmations: 2,
            expireBlock: uint32(block.number + 1000),
            expireDate: currentTime + 20000,
            depositAddress: btcAddress,
            btcRefundAddress: btcAddress,
            lpBtcAddress: btcAddress
        });
    }

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

    function generateBtcTxForAddressType(
        Quotes.PegOutQuote memory quote,
        bytes32 quoteHash,
        string memory /* addressType */
    ) internal pure returns (bytes memory) {
        // For simplicity, generate standard P2PKH tx
        // In production, this would generate appropriate scripts for each type
        return generateMockBtcTx(quote, quoteHash);
    }

    function setupBridgeMock(Quotes.PegOutQuote memory quote) internal {
        bytes memory header = createBtcBlockHeader(uint32(block.timestamp + 100));
        bridgeMock.setHeaderByHash(BLOCK_HEADER_HASH, header);
        bridgeMock.setConfirmations(int256(uint256(quote.transferConfirmations)));
    }

    function getTotalValue(Quotes.PegOutQuote memory quote) internal pure returns (uint256) {
        return quote.value + quote.callFee + quote.productFeeAmount + quote.gasFee;
    }

    function signQuote(address signer, bytes32 quoteHash) internal view returns (bytes memory) {
        uint256 privateKey;
        if (signer == fullLp) {
            privateKey = fullLpKey;
        } else if (signer == pegInLp) {
            privateKey = pegInLpKey;
        } else if (signer == pegOutLp) {
            privateKey = pegOutLpKey;
        } else {
            revert("Unknown signer");
        }

        bytes32 ethSignedMessageHash = keccak256(
            abi.encodePacked("\x19Ethereum Signed Message:\n32", quoteHash)
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, ethSignedMessageHash);
        return abi.encodePacked(r, s, v);
    }
}
