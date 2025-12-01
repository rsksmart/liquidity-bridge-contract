// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {PegOutFuzzTestBase} from "./PegOutFuzzTestBase.sol";
import {Quotes} from "../../../src/libraries/Quotes.sol";
import {IPegOut} from "../../../src/interfaces/IPegOut.sol";
import {ICollateralManagement} from "../../../src/interfaces/ICollateralManagement.sol";
import {Flyover} from "../../../src/libraries/Flyover.sol";

/// @title PegOutRefundTiming Fuzz Tests
/// @notice Fuzz tests for timing-based penalties in PegOut refunds
contract PegOutRefundTimingFuzzTest is PegOutFuzzTestBase {
    function setUp() public {
        deployPegOutContract();
        setupProviders();
        initBtcMocks();

        fuzzUser = makeAddr("user");
        vm.deal(fuzzUser, 100 ether);
    }

    /// @notice Fuzz test: On-time refund should not penalize LP
    function testFuzz_RefundPegOut_NoPenaltyWhenOnTime(
        uint32 agreementTimestamp,
        uint32 transferTime,
        uint16 depositConfirmations
    ) public {
        agreementTimestamp = uint32(
            bound(agreementTimestamp, 1000000, type(uint32).max - 1000000)
        );
        transferTime = uint32(bound(transferTime, 100, 100000));
        depositConfirmations = uint16(bound(depositConfirmations, 1, 100));

        vm.warp(agreementTimestamp);

        Quotes.PegOutQuote memory quote = createFuzzTestQuote(1 ether);
        quote.agreementTimestamp = agreementTimestamp;
        quote.transferTime = transferTime;
        quote.transferConfirmations = depositConfirmations;
        quote.depositDateLimit = agreementTimestamp + 7200;
        quote.expireDate = agreementTimestamp + 20000;
        quote.expireBlock = uint32(block.number + 1000);

        bytes32 quoteHash = pegOutContract.hashPegOutQuote(quote);
        bytes memory signature = signFuzzQuote(pegOutLp, quoteHash);

        vm.prank(fuzzUser);
        pegOutContract.depositPegOut{value: getTotalQuoteValue(quote)}(
            quote,
            signature
        );

        // Generate BTC tx with timestamp within acceptable window
        uint32 onTimeBtcTimestamp = uint32(
            agreementTimestamp + transferTime + TEST_BTC_BLOCK_TIME - 100
        );
        bytes memory btcTx = generateMockBtcTx(quote, quoteHash);

        // Setup bridge with on-time header
        bytes memory header = createBtcBlockHeader(onTimeBtcTimestamp);
        bridgeMock.setHeaderByHash(BLOCK_HEADER_HASH, header);
        bridgeMock.setConfirmations(int256(uint256(depositConfirmations)));

        // Refund should succeed without penalty
        vm.prank(pegOutLp);
        vm.expectEmit(true, false, false, true);
        emit IPegOut.PegOutRefunded(quoteHash);
        pegOutContract.refundPegOut(
            quoteHash,
            btcTx,
            BLOCK_HEADER_HASH,
            PARTIAL_MERKLE_TREE,
            merkleHashes
        );

        assertTrue(pegOutContract.isQuoteCompleted(quoteHash));
    }

    /// @notice Fuzz test: Late BTC transfer should penalize LP
    function testFuzz_RefundPegOut_PenalizesLPForLateTransfer(
        uint32 agreementTimestamp,
        uint32 transferTime,
        uint32 lateness
    ) public {
        agreementTimestamp = uint32(
            bound(agreementTimestamp, 1000000, type(uint32).max - 2000000)
        );
        transferTime = uint32(bound(transferTime, 1000, 50000));
        lateness = uint32(bound(lateness, 1, 10000));

        vm.warp(agreementTimestamp);

        Quotes.PegOutQuote memory quote = createFuzzTestQuote(1 ether);
        quote.agreementTimestamp = agreementTimestamp;
        quote.transferTime = transferTime;
        quote.depositDateLimit = agreementTimestamp + 7200;
        quote.expireDate = agreementTimestamp + 20000;
        quote.expireBlock = uint32(block.number + 1000);

        bytes32 quoteHash = pegOutContract.hashPegOutQuote(quote);
        bytes memory signature = signFuzzQuote(pegOutLp, quoteHash);

        vm.prank(fuzzUser);
        pegOutContract.depositPegOut{value: getTotalQuoteValue(quote)}(
            quote,
            signature
        );

        // Generate BTC tx with late timestamp
        uint32 lateBtcTimestamp = uint32(
            agreementTimestamp + transferTime + TEST_BTC_BLOCK_TIME + lateness
        );
        bytes memory btcTx = generateMockBtcTx(quote, quoteHash);

        // Setup bridge with late header
        bytes memory header = createBtcBlockHeader(lateBtcTimestamp);
        bridgeMock.setHeaderByHash(BLOCK_HEADER_HASH, header);
        bridgeMock.setConfirmations(
            int256(uint256(quote.transferConfirmations))
        );

        uint256 penalty = quote.penaltyFee;
        uint256 reward = (penalty * TEST_REWARD_PERCENTAGE) / 10000;

        // Refund should penalize LP
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

    /// @notice Fuzz test: Refund after expireDate should penalize
    /// @dev Verifies both PegOutRefunded and Penalized events are emitted in correct order
    function testFuzz_RefundPegOut_PenalizesAfterExpireDate(
        uint32 agreementTimestamp,
        uint32 expireDate,
        uint32 lateness
    ) public {
        agreementTimestamp = uint32(
            bound(agreementTimestamp, 1000000, type(uint32).max - 2000000)
        );
        expireDate = uint32(
            bound(
                expireDate,
                agreementTimestamp + 1000,
                agreementTimestamp + 100000
            )
        );
        lateness = uint32(bound(lateness, 1, 10000));

        vm.warp(agreementTimestamp);

        Quotes.PegOutQuote memory quote = createFuzzTestQuote(1 ether);
        quote.agreementTimestamp = agreementTimestamp;
        quote.expireDate = expireDate;
        quote.depositDateLimit = agreementTimestamp + 7200;
        quote.expireBlock = uint32(block.number + 1000);

        bytes32 quoteHash = pegOutContract.hashPegOutQuote(quote);
        bytes memory signature = signFuzzQuote(pegOutLp, quoteHash);

        vm.prank(fuzzUser);
        pegOutContract.depositPegOut{value: getTotalQuoteValue(quote)}(
            quote,
            signature
        );

        // Warp past expiration
        vm.warp(expireDate + lateness);

        bytes memory btcTx = generateMockBtcTx(quote, quoteHash);
        bytes memory header = createBtcBlockHeader(
            uint32(expireDate + lateness)
        );
        bridgeMock.setHeaderByHash(BLOCK_HEADER_HASH, header);
        bridgeMock.setConfirmations(
            int256(uint256(quote.transferConfirmations))
        );

        uint256 penalty = quote.penaltyFee;
        uint256 reward = (penalty * TEST_REWARD_PERCENTAGE) / 10000;

        vm.prank(pegOutLp);

        // Expect PegOutRefunded event first
        vm.expectEmit(true, false, false, true);
        emit IPegOut.PegOutRefunded(quoteHash);

        // Then expect Penalized event
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

    /// @notice Fuzz test: Refund after expireBlock should penalize
    /// @dev Verifies both PegOutRefunded and Penalized events are emitted in correct order
    function testFuzz_RefundPegOut_PenalizesAfterExpireBlock(
        uint32 currentBlock,
        uint32 expireBlock,
        uint16 lateBlocks
    ) public {
        currentBlock = uint32(
            bound(currentBlock, 1000, type(uint32).max - 100000)
        );
        expireBlock = uint32(
            bound(expireBlock, currentBlock + 10, currentBlock + 10000)
        );
        lateBlocks = uint16(bound(lateBlocks, 1, 1000));

        vm.roll(currentBlock);

        Quotes.PegOutQuote memory quote = createFuzzTestQuote(1 ether);
        quote.expireBlock = expireBlock;
        quote.expireDate = uint32(block.timestamp + 20000);
        quote.depositDateLimit = uint32(block.timestamp + 7200);

        bytes32 quoteHash = pegOutContract.hashPegOutQuote(quote);
        bytes memory signature = signFuzzQuote(pegOutLp, quoteHash);

        vm.prank(fuzzUser);
        pegOutContract.depositPegOut{value: getTotalQuoteValue(quote)}(
            quote,
            signature
        );

        // Roll past expiration
        vm.roll(expireBlock + lateBlocks);

        bytes memory btcTx = generateMockBtcTx(quote, quoteHash);
        bytes memory header = createBtcBlockHeader(
            uint32(block.timestamp + 100)
        );
        bridgeMock.setHeaderByHash(BLOCK_HEADER_HASH, header);
        bridgeMock.setConfirmations(
            int256(uint256(quote.transferConfirmations))
        );

        uint256 penalty = quote.penaltyFee;
        uint256 reward = (penalty * TEST_REWARD_PERCENTAGE) / 10000;

        vm.prank(pegOutLp);

        // Expect PegOutRefunded event first
        vm.expectEmit(true, false, false, true);
        emit IPegOut.PegOutRefunded(quoteHash);

        // Then expect Penalized event
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

    /// @notice Fuzz test: Boundary test - exactly at expireDate should not penalize
    function testFuzz_RefundPegOut_NoPenaltyAtExactExpireDate(
        uint32 agreementTimestamp,
        uint32 expireDate
    ) public {
        agreementTimestamp = uint32(
            bound(agreementTimestamp, 1000000, type(uint32).max - 200000)
        );
        expireDate = uint32(
            bound(
                expireDate,
                agreementTimestamp + 1000,
                agreementTimestamp + 100000
            )
        );

        vm.warp(agreementTimestamp);

        Quotes.PegOutQuote memory quote = createFuzzTestQuote(1 ether);
        quote.agreementTimestamp = agreementTimestamp;
        quote.expireDate = expireDate;
        quote.depositDateLimit = agreementTimestamp + 7200;
        quote.expireBlock = uint32(block.number + 1000);

        bytes32 quoteHash = pegOutContract.hashPegOutQuote(quote);
        bytes memory signature = signFuzzQuote(pegOutLp, quoteHash);

        vm.prank(fuzzUser);
        pegOutContract.depositPegOut{value: getTotalQuoteValue(quote)}(
            quote,
            signature
        );

        // Warp to exactly expireDate
        vm.warp(expireDate);

        bytes memory btcTx = generateMockBtcTx(quote, quoteHash);
        bytes memory header = createBtcBlockHeader(uint32(expireDate));
        bridgeMock.setHeaderByHash(BLOCK_HEADER_HASH, header);
        bridgeMock.setConfirmations(
            int256(uint256(quote.transferConfirmations))
        );

        // Should succeed without penalty (boundary condition)
        vm.prank(pegOutLp);
        vm.expectEmit(true, false, false, true);
        emit IPegOut.PegOutRefunded(quoteHash);
        pegOutContract.refundPegOut(
            quoteHash,
            btcTx,
            BLOCK_HEADER_HASH,
            PARTIAL_MERKLE_TREE,
            merkleHashes
        );
    }

    /// @notice Fuzz test: Different penalty amounts
    /// @dev Verifies exact penalty and reward amounts in emitted events
    function testFuzz_RefundPegOut_DifferentPenaltyAmounts(
        uint128 penaltyFee
    ) public {
        // Bound penalty fee to reasonable range (above dust, below max reasonable value)
        // The penalty is taken from the LP's collateral, which must be >= MIN_COLLATERAL
        penaltyFee = uint128(bound(penaltyFee, 0.001 ether, 0.5 ether));

        uint32 currentTime = uint32(block.timestamp);

        Quotes.PegOutQuote memory quote = createFuzzTestQuote(1 ether);
        quote.penaltyFee = penaltyFee;
        quote.agreementTimestamp = currentTime;
        quote.depositDateLimit = currentTime + 7200;
        quote.expireDate = currentTime + 14400;
        quote.expireBlock = uint32(block.number + 1000);

        bytes32 quoteHash = pegOutContract.hashPegOutQuote(quote);
        bytes memory signature = signFuzzQuote(pegOutLp, quoteHash);

        vm.prank(fuzzUser);
        pegOutContract.depositPegOut{value: getTotalQuoteValue(quote)}(
            quote,
            signature
        );

        // Make it late
        vm.warp(quote.expireDate + 1);

        bytes memory btcTx = generateMockBtcTx(quote, quoteHash);
        bytes memory header = createBtcBlockHeader(
            uint32(quote.expireDate + 1)
        );
        bridgeMock.setHeaderByHash(BLOCK_HEADER_HASH, header);
        bridgeMock.setConfirmations(
            int256(uint256(quote.transferConfirmations))
        );

        // Calculate expected penalty and reward amounts
        uint256 expectedPenalty = quote.penaltyFee;
        uint256 expectedReward = (expectedPenalty * TEST_REWARD_PERCENTAGE) /
            10000;

        vm.prank(pegOutLp);

        // Expect PegOutRefunded event first
        vm.expectEmit(true, false, false, true);
        emit IPegOut.PegOutRefunded(quoteHash);

        // Expect Penalized event with exact amounts (checkData: true)
        vm.expectEmit(true, true, true, true);
        emit ICollateralManagement.Penalized(
            pegOutLp,
            pegOutLp,
            quoteHash,
            Flyover.ProviderType.PegOut,
            expectedPenalty,
            expectedReward
        );

        pegOutContract.refundPegOut(
            quoteHash,
            btcTx,
            BLOCK_HEADER_HASH,
            PARTIAL_MERKLE_TREE,
            merkleHashes
        );
    }

    /// @notice Fuzz test: Confirmation count validation
    function testFuzz_RefundPegOut_ValidatesConfirmations(
        uint16 requiredConfirmations,
        uint16 actualConfirmations
    ) public {
        requiredConfirmations = uint16(bound(requiredConfirmations, 1, 100));
        actualConfirmations = uint16(bound(actualConfirmations, 0, 100));

        // Skip if confirmations are sufficient (success case)
        vm.assume(actualConfirmations < requiredConfirmations);

        Quotes.PegOutQuote memory quote = createFuzzTestQuote(1 ether);
        quote.transferConfirmations = requiredConfirmations;

        bytes32 quoteHash = pegOutContract.hashPegOutQuote(quote);
        bytes memory signature = signFuzzQuote(pegOutLp, quoteHash);

        vm.prank(fuzzUser);
        pegOutContract.depositPegOut{value: getTotalQuoteValue(quote)}(
            quote,
            signature
        );

        bytes memory btcTx = generateMockBtcTx(quote, quoteHash);
        bytes memory header = createBtcBlockHeader(
            uint32(block.timestamp + 100)
        );
        bridgeMock.setHeaderByHash(BLOCK_HEADER_HASH, header);
        bridgeMock.setConfirmations(int256(uint256(actualConfirmations)));

        vm.prank(pegOutLp);
        vm.expectRevert(
            abi.encodeWithSelector(
                IPegOut.NotEnoughConfirmations.selector,
                requiredConfirmations,
                actualConfirmations
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

    /// @notice Fuzz test: Sufficient confirmations should succeed
    function testFuzz_RefundPegOut_SucceedsWithSufficientConfirmations(
        uint16 requiredConfirmations,
        uint16 extraConfirmations
    ) public {
        requiredConfirmations = uint16(bound(requiredConfirmations, 1, 50));
        extraConfirmations = uint16(bound(extraConfirmations, 0, 50));

        uint16 actualConfirmations = requiredConfirmations + extraConfirmations;

        Quotes.PegOutQuote memory quote = createFuzzTestQuote(1 ether);
        quote.transferConfirmations = requiredConfirmations;

        bytes32 quoteHash = pegOutContract.hashPegOutQuote(quote);
        bytes memory signature = signFuzzQuote(pegOutLp, quoteHash);

        vm.prank(fuzzUser);
        pegOutContract.depositPegOut{value: getTotalQuoteValue(quote)}(
            quote,
            signature
        );

        bytes memory btcTx = generateMockBtcTx(quote, quoteHash);
        bytes memory header = createBtcBlockHeader(
            uint32(block.timestamp + 100)
        );
        bridgeMock.setHeaderByHash(BLOCK_HEADER_HASH, header);
        bridgeMock.setConfirmations(int256(uint256(actualConfirmations)));

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
}
