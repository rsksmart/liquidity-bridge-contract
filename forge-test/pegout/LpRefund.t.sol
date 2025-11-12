// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {PegOutTestBase} from "./PegOutTestBase.sol";
import {IPegOut} from "../../contracts/interfaces/IPegOut.sol";
import {ICollateralManagement} from "../../contracts/interfaces/ICollateralManagement.sol";
import {Quotes} from "../../contracts/libraries/Quotes.sol";
import {Flyover} from "../../contracts/libraries/Flyover.sol";

/// @title LpRefund Tests
/// @notice Tests for the refundPegOut function - LP proves BTC payment
/// @dev This is a simplified version (original: 691 lines with 100+ test combinations)
///
/// Full refundPegOut testing requires complex BTC infrastructure:
/// - BTC transaction generation with proper scripts (P2PKH, P2SH, P2WPKH, P2WSH, P2TR)
/// - Merkle proof creation and validation
/// - Block header mocking with proper timestamps
/// - Testing 5 address types × 10 amount precisions = 50+ combinations
/// - SAT/WEI conversion and truncation logic
/// - Penalization based on timing (transfer windows, block/time expiry)
///
/// These tests cover the main validation paths. Full BTC transaction testing
/// with all address types and amounts is in the TypeScript integration tests.
contract LpRefundTest is PegOutTestBase {
    address public user;

    // Mock BTC proof data
    bytes32 constant BLOCK_HEADER_HASH = bytes32(uint256(1));
    uint256 constant PARTIAL_MERKLE_TREE = 0;
    bytes32[] merkleHashes;

    function setUp() public {
        deployPegOutContract();
        setupProviders();

        user = makeAddr("user");
        vm.deal(user, 100 ether);

        // Setup merkle hashes array
        merkleHashes = new bytes32[](1);
        merkleHashes[0] = bytes32(uint256(1));
    }

    // ============ refundPegOut function tests ============

    function test_RefundPegOut_RevertsIfLPResigned() public {
        // First, deposit a quote
        Quotes.PegOutQuote memory quote = createAndDepositQuote();
        bytes32 quoteHash = pegOutContract.hashPegOutQuote(quote);

        // LP resigns
        vm.prank(pegOutLp);
        collateralManagement.resign();

        // Try to refund - should fail
        bytes memory btcTx = generateBtcTx(quote, quoteHash);

        vm.prank(pegOutLp);
        vm.expectRevert(
            abi.encodeWithSelector(
                Flyover.ProviderNotRegistered.selector,
                pegOutLp
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

    function test_RefundPegOut_RevertsIfQuoteWasNotPaid() public {
        Quotes.PegOutQuote memory quote = createTestPegOutQuote(
            1 ether,
            pegOutLp
        );
        bytes32 quoteHash = pegOutContract.hashPegOutQuote(quote);

        // Don't deposit - try to refund directly
        bytes memory btcTx = generateBtcTx(quote, quoteHash);

        vm.prank(pegOutLp);
        vm.expectRevert(
            abi.encodeWithSelector(Flyover.QuoteNotFound.selector, quoteHash)
        );
        pegOutContract.refundPegOut(
            quoteHash,
            btcTx,
            BLOCK_HEADER_HASH,
            PARTIAL_MERKLE_TREE,
            merkleHashes
        );
    }

    function test_RefundPegOut_RevertsIfNotCalledByLP() public {
        Quotes.PegOutQuote memory quote = createAndDepositQuote();
        bytes32 quoteHash = pegOutContract.hashPegOutQuote(quote);

        bytes memory btcTx = generateBtcTx(quote, quoteHash);

        // fullLp tries to refund pegOutLp's quote
        vm.prank(fullLp);
        vm.expectRevert(
            abi.encodeWithSelector(
                Flyover.InvalidSender.selector,
                pegOutLp,
                fullLp
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

    function test_RefundPegOut_RevertsIfBtcTxNotRelatedToQuote() public {
        Quotes.PegOutQuote memory quote = createAndDepositQuote();
        bytes32 quoteHash = pegOutContract.hashPegOutQuote(quote);

        // Create a different quote and generate tx for it (different hash in OP_RETURN)
        Quotes.PegOutQuote memory otherQuote = createTestPegOutQuote(
            0.5 ether,
            pegOutLp
        );
        bytes32 otherQuoteHash = pegOutContract.hashPegOutQuote(otherQuote);

        // Generate BTC tx with the OTHER quote's hash
        bytes memory btcTx = generateBtcTx(quote, otherQuoteHash); // Wrong hash!

        vm.prank(pegOutLp);
        vm.expectRevert(
            abi.encodeWithSelector(
                IPegOut.InvalidQuoteHash.selector,
                quoteHash,
                otherQuoteHash
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

    function test_RefundPegOut_RevertsIfNullDataMalformed() public {
        Quotes.PegOutQuote memory quote = createAndDepositQuote();
        bytes32 quoteHash = pegOutContract.hashPegOutQuote(quote);

        // Test that a malformed Bitcoin transaction (too short) reverts
        // Using a minimal invalid tx hex"010203" instead of properly formed tx
        vm.prank(pegOutLp);
        vm.expectRevert(); // MalformedTransaction
        pegOutContract.refundPegOut(
            quoteHash,
            hex"010203",
            BLOCK_HEADER_HASH,
            PARTIAL_MERKLE_TREE,
            merkleHashes
        );
    }

    function test_RefundPegOut_RevertsIfCantGetConfirmationsFromBridge()
        public
    {
        Quotes.PegOutQuote memory quote = createAndDepositQuote();
        bytes32 quoteHash = pegOutContract.hashPegOutQuote(quote);

        // Setup block header
        bytes memory header = createBtcBlockHeader(
            uint32(block.timestamp + 100)
        );
        bridgeMock.setHeaderByHash(BLOCK_HEADER_HASH, header);

        // Set bridge to return negative confirmations (error)
        bridgeMock.setConfirmations(-5);

        bytes memory btcTx = generateBtcTx(quote, quoteHash);

        vm.prank(pegOutLp);
        vm.expectRevert(
            abi.encodeWithSelector(
                IPegOut.UnableToGetConfirmations.selector,
                -5
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

    function test_RefundPegOut_RevertsIfNotEnoughConfirmations() public {
        Quotes.PegOutQuote memory quote = createAndDepositQuote();
        bytes32 quoteHash = pegOutContract.hashPegOutQuote(quote);

        // Setup block header
        bytes memory header = createBtcBlockHeader(
            uint32(block.timestamp + 100)
        );
        bridgeMock.setHeaderByHash(BLOCK_HEADER_HASH, header);

        // Set bridge to return only 1 confirmation (need 2)
        bridgeMock.setConfirmations(1);

        bytes memory btcTx = generateBtcTx(quote, quoteHash);

        vm.prank(pegOutLp);
        vm.expectRevert(
            abi.encodeWithSelector(
                IPegOut.NotEnoughConfirmations.selector,
                quote.transferConfirmations,
                1
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

    function test_RefundPegOut_RevertsIfBtcTxDoesNotHaveHighEnoughAmount()
        public
    {
        Quotes.PegOutQuote memory quote = createAndDepositQuote();
        bytes32 quoteHash = pegOutContract.hashPegOutQuote(quote);
        uint256 originalValue = quote.value; // Store original value before modification

        // Generate BTC tx with insufficient amount (0.9 ETH when quote needs 1 ETH)
        Quotes.PegOutQuote memory lowQuote = quote;
        lowQuote.value = 0.9 ether;
        bytes memory btcTx = generateBtcTx(lowQuote, quoteHash); // Low amount!

        // Setup headers
        bytes memory header = createBtcBlockHeader(
            uint32(block.timestamp + 100)
        );
        bridgeMock.setHeaderByHash(BLOCK_HEADER_HASH, header);
        bridgeMock.setConfirmations(
            int256(uint256(quote.transferConfirmations))
        );

        uint256 lowAmountWei = 0.9 ether;

        vm.prank(pegOutLp);
        vm.expectRevert(
            abi.encodeWithSelector(
                Flyover.InsufficientAmount.selector,
                lowAmountWei,
                originalValue
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

    function test_RefundPegOut_RevertsIfBtcTxNotDirectedToUserAddress() public {
        Quotes.PegOutQuote memory quote = createAndDepositQuote();
        bytes32 quoteHash = pegOutContract.hashPegOutQuote(quote);

        // Generate BTC tx with WRONG address
        Quotes.PegOutQuote memory wrongAddressQuote = quote;
        wrongAddressQuote.depositAddress = new bytes(21); // Different address!
        wrongAddressQuote.depositAddress[0] = 0x00; // Set version byte
        bytes memory btcTx = generateBtcTx(wrongAddressQuote, quoteHash);

        // Setup headers
        bytes memory header = createBtcBlockHeader(
            uint32(block.timestamp + 100)
        );
        bridgeMock.setHeaderByHash(BLOCK_HEADER_HASH, header);
        bridgeMock.setConfirmations(
            int256(uint256(quote.transferConfirmations))
        );

        vm.prank(pegOutLp);
        vm.expectRevert(); // InvalidDestination
        pegOutContract.refundPegOut(
            quoteHash,
            btcTx,
            BLOCK_HEADER_HASH,
            PARTIAL_MERKLE_TREE,
            merkleHashes
        );
    }

    function test_RefundPegOut_PenalizesLPForBeingExpiredByTime() public {
        Quotes.PegOutQuote memory quote = createAndDepositQuote();
        bytes32 quoteHash = pegOutContract.hashPegOutQuote(quote);

        // Warp to after expireDate
        vm.warp(quote.expireDate + 1);

        // Setup block header with late timestamp
        bytes memory header = createBtcBlockHeader(
            uint32(quote.expireDate + 1)
        );
        bridgeMock.setHeaderByHash(BLOCK_HEADER_HASH, header);
        bridgeMock.setConfirmations(
            int256(uint256(quote.transferConfirmations))
        );

        bytes memory btcTx = generateBtcTx(quote, quoteHash);

        // Calculate expected penalty and reward
        uint256 penalty = quote.penaltyFee;
        uint256 reward = (penalty * TEST_REWARD_PERCENTAGE) / 10000;

        // Refund should succeed but emit penalization
        vm.prank(pegOutLp);
        vm.expectEmit(true, false, false, true);
        emit IPegOut.PegOutRefunded(quoteHash);
        vm.expectEmit(true, true, true, true);
        emit ICollateralManagement.Penalized(
            pegOutLp,
            pegOutLp,
            quoteHash,
            Flyover.ProviderType.PegOut,
            penalty,
            reward
        );
        pegOutContract.refundPegOut(
            quoteHash,
            btcTx,
            BLOCK_HEADER_HASH,
            PARTIAL_MERKLE_TREE,
            merkleHashes
        );
    }

    function test_RefundPegOut_PenalizesLPForBeingExpiredByBlocks() public {
        Quotes.PegOutQuote memory quote = createAndDepositQuote();
        bytes32 quoteHash = pegOutContract.hashPegOutQuote(quote);

        // Mine past expireBlock
        vm.roll(quote.expireBlock + 1);

        // Setup block header
        bytes memory header = createBtcBlockHeader(
            uint32(block.timestamp + 100)
        );
        bridgeMock.setHeaderByHash(BLOCK_HEADER_HASH, header);
        bridgeMock.setConfirmations(
            int256(uint256(quote.transferConfirmations))
        );

        bytes memory btcTx = generateBtcTx(quote, quoteHash);

        // Calculate expected penalty and reward
        uint256 penalty = quote.penaltyFee;
        uint256 reward = (penalty * TEST_REWARD_PERCENTAGE) / 10000;

        // Refund should succeed but emit penalization
        vm.prank(pegOutLp);
        vm.expectEmit(true, false, false, true);
        emit IPegOut.PegOutRefunded(quoteHash);
        vm.expectEmit(true, true, true, true);
        emit ICollateralManagement.Penalized(
            pegOutLp,
            pegOutLp,
            quoteHash,
            Flyover.ProviderType.PegOut,
            penalty,
            reward
        );
        pegOutContract.refundPegOut(
            quoteHash,
            btcTx,
            BLOCK_HEADER_HASH,
            PARTIAL_MERKLE_TREE,
            merkleHashes
        );
    }

    function test_RefundPegOut_PenalizesLPForSendingBtcAfterExpectedFirstConfirmation()
        public
    {
        Quotes.PegOutQuote memory quote = createAndDepositQuote();
        bytes32 quoteHash = pegOutContract.hashPegOutQuote(quote);

        // Setup header with late timestamp (after transferTime + btcBlockTime)
        uint32 lateTime = uint32(
            quote.agreementTimestamp +
                quote.transferTime +
                TEST_BTC_BLOCK_TIME +
                500
        );
        bytes memory header = createBtcBlockHeader(lateTime);
        bridgeMock.setHeaderByHash(BLOCK_HEADER_HASH, header);
        bridgeMock.setConfirmations(
            int256(uint256(quote.transferConfirmations))
        );

        bytes memory btcTx = generateBtcTx(quote, quoteHash);

        // Calculate expected penalty and reward
        uint256 penalty = quote.penaltyFee;
        uint256 reward = (penalty * TEST_REWARD_PERCENTAGE) / 10000;

        // Refund should succeed but emit penalization
        vm.prank(pegOutLp);
        vm.expectEmit(true, false, false, true);
        emit IPegOut.PegOutRefunded(quoteHash);
        vm.expectEmit(true, true, true, true);
        emit ICollateralManagement.Penalized(
            pegOutLp,
            pegOutLp,
            quoteHash,
            Flyover.ProviderType.PegOut,
            penalty,
            reward
        );
        pegOutContract.refundPegOut(
            quoteHash,
            btcTx,
            BLOCK_HEADER_HASH,
            PARTIAL_MERKLE_TREE,
            merkleHashes
        );
    }

    function test_RefundPegOut_RevertsIfCantExtractFirstConfirmationHeader()
        public
    {
        Quotes.PegOutQuote memory quote = createAndDepositQuote();
        bytes32 quoteHash = pegOutContract.hashPegOutQuote(quote);

        // Set empty header
        bridgeMock.setHeaderByHash(BLOCK_HEADER_HASH, hex"");
        bridgeMock.setConfirmations(2);

        bytes memory btcTx = generateBtcTx(quote, quoteHash);

        vm.prank(pegOutLp);
        vm.expectRevert(
            abi.encodeWithSelector(
                Flyover.EmptyBlockHeader.selector,
                BLOCK_HEADER_HASH
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

    // Note: The TypeScript test suite includes 100+ additional parameterized tests:
    // - forEach with 5 BTC address types (P2PKH, P2SH, P2WPKH, P2WSH, P2TR)
    // - forEach with 10 amount precisions
    // - 2 test scenarios per combination (normal + truncated)
    // = 5 × 10 × 2 = 100 tests
    //
    // These require full BTC transaction generation with proper scripts and
    // amount encoding, which is extensively covered in the TypeScript integration tests.

    // ============ Helper Functions ============

    /// @notice Generates a BTC transaction for PegOut refund
    /// @param quote The PegOut quote
    /// @param quoteHash The hash of the quote
    /// @return btcTx The raw BTC transaction bytes
    function generateBtcTx(
        Quotes.PegOutQuote memory quote,
        bytes32 quoteHash
    ) internal pure returns (bytes memory) {
        // BTC transaction structure:
        // - Version (4 bytes)
        // - Input count (1 byte)
        // - Input (previous tx + script + sequence)
        // - Output count (1 byte)
        // - Output 1: Payment to user (amount + script)
        // - Output 2: OP_RETURN with quote hash
        // - Locktime (4 bytes)

        // Convert quote value from WEI to SAT (divide by 10^10)
        uint64 satAmount = uint64(quote.value / 1e10);

        // Extract the 20-byte hash160 from the 21-byte address (skip version byte at index 0)
        bytes memory hash160 = new bytes(20);
        for (uint i = 0; i < 20; i++) {
            hash160[i] = quote.depositAddress[i + 1];
        }

        // Create P2PKH output script: OP_DUP OP_HASH160 <20 bytes> OP_EQUALVERIFY OP_CHECKSIG
        bytes memory outputScript = abi.encodePacked(
            hex"76a914", // OP_DUP OP_HASH160 PUSH20
            hash160, // 20 bytes hash160 (without version byte)
            hex"88ac" // OP_EQUALVERIFY OP_CHECKSIG
        );

        // Build the transaction
        bytes memory btcTx = abi.encodePacked(
            hex"01000000", // Version
            hex"01", // 1 input
            // Input: previous tx hash (32) + output index (4) + script length + script + sequence (4)
            hex"013503c427ba46058d2d8ac9221a2f6fd50734a69f19dae65420191e3ada2d40",
            hex"00000000",
            hex"6a",
            hex"47304402205d047dbd8c49aea5bd0400b85a57b2da7e139cec632fb138b7bee1d382fd70ca02201aa529f59b4f66fdf86b0728937a91a40962aedd3f6e30bce5208fec0464d54901210255507b238c6f14735a7abe96a635058da47b05b61737a610bef757f009eea2a4",
            hex"ffffffff",
            hex"02", // 2 outputs
            // Output 1: amount (8 bytes LE) + script
            toLittleEndian64(satAmount),
            uint8(outputScript.length),
            outputScript,
            // Output 2: OP_RETURN with quote hash
            hex"0000000000000000", // 0 amount
            hex"22", // script length (34 bytes)
            hex"6a20", // OP_RETURN PUSH32
            quoteHash,
            hex"00000000" // Locktime
        );

        return btcTx;
    }

    /// @notice Converts uint64 to 8-byte little-endian
    function toLittleEndian64(
        uint64 value
    ) internal pure returns (bytes memory) {
        bytes memory result = new bytes(8);
        result[0] = bytes1(uint8(value));
        result[1] = bytes1(uint8(value >> 8));
        result[2] = bytes1(uint8(value >> 16));
        result[3] = bytes1(uint8(value >> 24));
        result[4] = bytes1(uint8(value >> 32));
        result[5] = bytes1(uint8(value >> 40));
        result[6] = bytes1(uint8(value >> 48));
        result[7] = bytes1(uint8(value >> 56));
        return result;
    }

    /// @notice Creates a BTC block header with a specific timestamp (little-endian encoded)
    /// @param timestamp The Unix timestamp for the block
    /// @return header The 80-byte BTC block header
    function createBtcBlockHeader(
        uint32 timestamp
    ) internal pure returns (bytes memory) {
        bytes memory header = new bytes(80);

        // Convert timestamp to little-endian and place at offset 68
        header[68] = bytes1(uint8(timestamp));
        header[69] = bytes1(uint8(timestamp >> 8));
        header[70] = bytes1(uint8(timestamp >> 16));
        header[71] = bytes1(uint8(timestamp >> 24));

        return header;
    }

    function createAndDepositQuote()
        internal
        returns (Quotes.PegOutQuote memory)
    {
        Quotes.PegOutQuote memory quote = createTestPegOutQuote(
            1 ether,
            pegOutLp
        );
        bytes32 quoteHash = pegOutContract.hashPegOutQuote(quote);
        bytes memory signature = signQuote(pegOutLp, quoteHash);

        vm.prank(user);
        pegOutContract.depositPegOut{value: getTotalValue(quote)}(
            quote,
            signature
        );

        return quote;
    }

    function createTestPegOutQuote(
        uint256 value,
        address lp
    ) internal view returns (Quotes.PegOutQuote memory) {
        // Create a valid Bitcoin testnet P2PKH address (version byte 0x6f + 20 bytes hash160)
        // Using a non-zero hash to ensure it's a valid address for testing
        bytes memory testBtcAddress = abi.encodePacked(
            hex"6f", // Testnet version byte
            hex"89abcdefabbaabbaabbaabbaabbaabbaabbaabba" // 20 bytes hash160
        );
        uint32 currentTime = uint32(block.timestamp);

        return
            Quotes.PegOutQuote({
                callFee: 100000000000000,
                penaltyFee: 10000000000000,
                value: value,
                productFeeAmount: (value * 2) / 100,
                gasFee: 100,
                lbcAddress: address(pegOutContract),
                lpRskAddress: lp,
                rskRefundAddress: user,
                nonce: int64(uint64(block.timestamp)),
                agreementTimestamp: currentTime,
                depositDateLimit: currentTime + 600,
                transferTime: 3600,
                depositConfirmations: 10,
                transferConfirmations: 2,
                expireBlock: uint32(block.number + 4000),
                expireDate: currentTime + 7200,
                depositAddress: testBtcAddress,
                btcRefundAddress: testBtcAddress,
                lpBtcAddress: testBtcAddress
            });
    }

    function getTotalValue(
        Quotes.PegOutQuote memory quote
    ) internal pure returns (uint256) {
        return
            quote.value + quote.callFee + quote.productFeeAmount + quote.gasFee;
    }

    function signQuote(
        address signer,
        bytes32 quoteHash
    ) internal view returns (bytes memory) {
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
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            privateKey,
            ethSignedMessageHash
        );
        return abi.encodePacked(r, s, v);
    }
}
