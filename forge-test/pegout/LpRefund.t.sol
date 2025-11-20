// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {PegOutTestBase} from "./PegOutTestBase.sol";
import {IPegOut} from "../../contracts/interfaces/IPegOut.sol";
import {ICollateralManagement} from "../../contracts/interfaces/ICollateralManagement.sol";
import {Quotes} from "../../contracts/libraries/Quotes.sol";
import {Flyover} from "../../contracts/libraries/Flyover.sol";

/// @title LpRefund Tests
/// @notice Tests for the refundPegOut function - LP proves BTC payment
/// @dev Includes comprehensive testing of all 5 BTC address types using FFI

/// FFI Integration:
/// - Uses TypeScript utilities via FFI for BTC transaction generation
/// - Ensures compatibility with existing TypeScript BTC address handling
/// - Supports easy migration from TypeScript to Foundry tests
contract LpRefundTest is PegOutTestBase {
    address public user;

    function setUp() public {
        deployPegOutContract();
        setupProviders();
        initBtcMocks(); // Initialize shared BTC mock data

        user = makeAddr("user");
        vm.deal(user, 100 ether);
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

    function test_RefundPegOut_RevertsIfBtcTxMalformed() public {
        Quotes.PegOutQuote memory quote = createAndDepositQuote();
        bytes32 quoteHash = pegOutContract.hashPegOutQuote(quote);

        // Test that a malformed Bitcoin transaction (too short) reverts
        // Using a minimal invalid tx that can't be parsed
        vm.prank(pegOutLp);
        vm.expectRevert(); // Will revert during BtcUtils.getOutputs parsing
        pegOutContract.refundPegOut(
            quoteHash,
            hex"010203",
            BLOCK_HEADER_HASH,
            PARTIAL_MERKLE_TREE,
            merkleHashes
        );
    }

    function test_RefundPegOut_RevertsIfNullDataScriptHasWrongSize() public {
        Quotes.PegOutQuote memory quote = createAndDepositQuote();
        bytes32 quoteHash = pegOutContract.hashPegOutQuote(quote);

        // Generate a valid BTC tx but manually create one with wrong OP_RETURN size
        // The null data script should be: 0x6a20 (OP_RETURN PUSH32) + 32 bytes hash
        // But we'll make it shorter: 0x6a10 (OP_RETURN PUSH16) + 16 bytes
        bytes memory btcTx = abi.encodePacked(
            hex"01000000", // Version
            hex"01", // 1 input
            hex"013503c427ba46058d2d8ac9221a2f6fd50734a69f19dae65420191e3ada2d40",
            hex"00000000",
            hex"6a",
            hex"47304402205d047dbd8c49aea5bd0400b85a57b2da7e139cec632fb138b7bee1d382fd70ca02201aa529f59b4f66fdf86b0728937a91a40962aedd3f6e30bce5208fec0464d54901210255507b238c6f14735a7abe96a635058da47b05b61737a610bef757f009eea2a4",
            hex"ffffffff",
            hex"02", // 2 outputs
            // Output 1: Payment
            hex"00e1f50500000000",
            hex"19", // script length
            hex"76a91489abcdefabbaabbaabbaabbaabbaabbaabbaabba88ac",
            // Output 2: OP_RETURN with WRONG SIZE (16 bytes instead of 32)
            hex"0000000000000000", // 0 amount
            hex"12", // Wrong script length! (18 bytes instead of 34)
            hex"6a10", // OP_RETURN PUSH16 (wrong! should be 0x20 for 32 bytes)
            bytes16(quoteHash), // Only 16 bytes instead of 32!
            hex"00000000" // Locktime
        );

        // Setup headers
        bytes memory header = createBtcBlockHeader(
            uint32(block.timestamp + 100)
        );
        bridgeMock.setHeaderByHash(BLOCK_HEADER_HASH, header);
        bridgeMock.setConfirmations(
            int256(uint256(quote.transferConfirmations))
        );

        // Extract what the malformed script content will be
        // Script content after parsing will be: 0x10 + 16 bytes (total 17 bytes, not 33)
        bytes memory expectedScriptContent = abi.encodePacked(
            hex"10", // Size byte (16, not 32)
            bytes16(quoteHash) // Only 16 bytes
        );

        vm.prank(pegOutLp);
        vm.expectRevert(
            abi.encodeWithSelector(
                IPegOut.MalformedTransaction.selector,
                expectedScriptContent
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

    // ============ BTC Address Type Tests ============

    /// @notice Test refund with P2PKH (Pay-to-PubKey-Hash) address - Legacy Bitcoin addresses
    function test_RefundPegOut_WorksWithP2PKH() public {
        Quotes.PegOutQuote memory quote = createTestPegOutQuoteWithAddressType(
            1 ether,
            pegOutLp,
            "p2pkh"
        );
        bytes32 quoteHash = pegOutContract.hashPegOutQuote(quote);
        bytes memory signature = signQuote(pegOutLp, quoteHash);

        vm.prank(user);
        pegOutContract.depositPegOut{value: getTotalValue(quote)}(
            quote,
            signature
        );

        // Setup block header
        bytes memory header = createBtcBlockHeader(
            uint32(block.timestamp + 100)
        );
        bridgeMock.setHeaderByHash(BLOCK_HEADER_HASH, header);
        bridgeMock.setConfirmations(
            int256(uint256(quote.transferConfirmations))
        );

        // Generate P2PKH transaction
        bytes memory btcTx = generateBtcTx(quote, quoteHash);

        vm.prank(pegOutLp);
        pegOutContract.refundPegOut(
            quoteHash,
            btcTx,
            BLOCK_HEADER_HASH,
            PARTIAL_MERKLE_TREE,
            merkleHashes
        );
    }

    /// @notice Test refund with P2SH (Pay-to-Script-Hash) address
    function test_RefundPegOut_WorksWithP2SH() public {
        Quotes.PegOutQuote memory quote = createTestPegOutQuoteWithAddressType(
            1 ether,
            pegOutLp,
            "p2sh"
        );
        bytes32 quoteHash = pegOutContract.hashPegOutQuote(quote);
        bytes memory signature = signQuote(pegOutLp, quoteHash);

        vm.prank(user);
        pegOutContract.depositPegOut{value: getTotalValue(quote)}(
            quote,
            signature
        );

        // Setup block header
        bytes memory header = createBtcBlockHeader(
            uint32(block.timestamp + 100)
        );
        bridgeMock.setHeaderByHash(BLOCK_HEADER_HASH, header);
        bridgeMock.setConfirmations(
            int256(uint256(quote.transferConfirmations))
        );

        // Generate P2SH transaction
        bytes memory btcTx = generateBtcTxWithType(quote, quoteHash, "p2sh");

        vm.prank(pegOutLp);
        pegOutContract.refundPegOut(
            quoteHash,
            btcTx,
            BLOCK_HEADER_HASH,
            PARTIAL_MERKLE_TREE,
            merkleHashes
        );
    }

    /// @notice Test refund with P2WPKH (SegWit v0 Pay-to-Witness-PubKey-Hash) address
    function test_RefundPegOut_WorksWithP2WPKH() public {
        Quotes.PegOutQuote memory quote = createTestPegOutQuoteWithAddressType(
            1 ether,
            pegOutLp,
            "p2wpkh"
        );
        bytes32 quoteHash = pegOutContract.hashPegOutQuote(quote);
        bytes memory signature = signQuote(pegOutLp, quoteHash);

        vm.prank(user);
        pegOutContract.depositPegOut{value: getTotalValue(quote)}(
            quote,
            signature
        );

        // Setup block header
        bytes memory header = createBtcBlockHeader(
            uint32(block.timestamp + 100)
        );
        bridgeMock.setHeaderByHash(BLOCK_HEADER_HASH, header);
        bridgeMock.setConfirmations(
            int256(uint256(quote.transferConfirmations))
        );

        // Generate P2WPKH transaction
        bytes memory btcTx = generateBtcTxWithType(quote, quoteHash, "p2wpkh");

        vm.prank(pegOutLp);
        pegOutContract.refundPegOut(
            quoteHash,
            btcTx,
            BLOCK_HEADER_HASH,
            PARTIAL_MERKLE_TREE,
            merkleHashes
        );
    }

    /// @notice Test refund with P2WSH (SegWit v0 Pay-to-Witness-Script-Hash) address
    function test_RefundPegOut_WorksWithP2WSH() public {
        Quotes.PegOutQuote memory quote = createTestPegOutQuoteWithAddressType(
            1 ether,
            pegOutLp,
            "p2wsh"
        );
        bytes32 quoteHash = pegOutContract.hashPegOutQuote(quote);
        bytes memory signature = signQuote(pegOutLp, quoteHash);

        vm.prank(user);
        pegOutContract.depositPegOut{value: getTotalValue(quote)}(
            quote,
            signature
        );

        // Setup block header
        bytes memory header = createBtcBlockHeader(
            uint32(block.timestamp + 100)
        );
        bridgeMock.setHeaderByHash(BLOCK_HEADER_HASH, header);
        bridgeMock.setConfirmations(
            int256(uint256(quote.transferConfirmations))
        );

        // Generate P2WSH transaction
        bytes memory btcTx = generateBtcTxWithType(quote, quoteHash, "p2wsh");

        vm.prank(pegOutLp);
        pegOutContract.refundPegOut(
            quoteHash,
            btcTx,
            BLOCK_HEADER_HASH,
            PARTIAL_MERKLE_TREE,
            merkleHashes
        );
    }

    /// @notice Test refund with P2TR (Taproot / SegWit v1) address
    function test_RefundPegOut_WorksWithP2TR() public {
        Quotes.PegOutQuote memory quote = createTestPegOutQuoteWithAddressType(
            1 ether,
            pegOutLp,
            "p2tr"
        );
        bytes32 quoteHash = pegOutContract.hashPegOutQuote(quote);
        bytes memory signature = signQuote(pegOutLp, quoteHash);

        vm.prank(user);
        pegOutContract.depositPegOut{value: getTotalValue(quote)}(
            quote,
            signature
        );

        // Setup block header
        bytes memory header = createBtcBlockHeader(
            uint32(block.timestamp + 100)
        );
        bridgeMock.setHeaderByHash(BLOCK_HEADER_HASH, header);
        bridgeMock.setConfirmations(
            int256(uint256(quote.transferConfirmations))
        );

        // Generate P2TR transaction
        bytes memory btcTx = generateBtcTxWithType(quote, quoteHash, "p2tr");

        vm.prank(pegOutLp);
        pegOutContract.refundPegOut(
            quoteHash,
            btcTx,
            BLOCK_HEADER_HASH,
            PARTIAL_MERKLE_TREE,
            merkleHashes
        );
    }

    // ============ Helper Functions ============

    string constant HELPER_SCRIPT_GET_BTC_ADDRESS_BYTES =
        "forge-scripts/helpers/get-btc-address-bytes.ts";

    /// @notice Generates a BTC transaction for PegOut refund using FFI
    /// @param quote The PegOut quote
    /// @param quoteHash The hash of the quote
    /// @return btcTx The raw BTC transaction bytes
    function generateBtcTx(
        Quotes.PegOutQuote memory quote,
        bytes32 quoteHash
    ) internal returns (bytes memory) {
        return generateBtcTxWithType(quote, quoteHash, "p2pkh");
    }

    /// @notice Generates a BTC transaction for a specific script type
    /// @param quote The PegOut quote
    /// @param quoteHash The hash of the quote
    /// @param scriptType The script type (p2pkh, p2sh, p2wpkh, p2wsh, p2tr)
    /// @return btcTx The raw BTC transaction bytes
    function generateBtcTxWithType(
        Quotes.PegOutQuote memory quote,
        bytes32 quoteHash,
        string memory scriptType
    ) internal returns (bytes memory) {
        // Call FFI helper script to generate BTC transaction
        string[] memory inputs = new string[](7);
        inputs[0] = "npx";
        inputs[1] = "ts-node";
        inputs[2] = HELPER_SCRIPT_GENERATE_BTC_TX;
        inputs[3] = vm.toString(quoteHash);
        inputs[4] = vm.toString(quote.depositAddress);
        inputs[5] = vm.toString(quote.value);
        inputs[6] = scriptType;

        bytes memory result = vm.ffi(inputs);
        return result;
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
    ) internal returns (Quotes.PegOutQuote memory) {
        return createTestPegOutQuoteWithAddressType(value, lp, "p2pkh");
    }

    /// @notice Creates a test PegOut quote with a specific BTC address type
    function createTestPegOutQuoteWithAddressType(
        uint256 value,
        address lp,
        string memory addressType
    ) internal returns (Quotes.PegOutQuote memory) {
        bytes memory testBtcAddress = getBtcAddressForType(addressType);
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

    /// @notice Returns a test Bitcoin address for the given type using FFI
    /// @dev For SegWit addresses, returns witness version + 5-bit words (bech32 format)
    ///      For legacy addresses, returns version byte + raw hash
    function getBtcAddressForType(
        string memory addressType
    ) internal returns (bytes memory) {
        string[] memory inputs = new string[](4);
        inputs[0] = "npx";
        inputs[1] = "ts-node";
        inputs[2] = HELPER_SCRIPT_GET_BTC_ADDRESS_BYTES;
        inputs[3] = addressType;

        bytes memory result = vm.ffi(inputs);
        return result;
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
