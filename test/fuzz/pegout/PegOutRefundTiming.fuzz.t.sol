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
        bytes memory signature = signFuzzQuote(pegOutLp, quote);

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
        bytes memory signature = signFuzzQuote(pegOutLp, quote);

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
        bytes memory signature = signFuzzQuote(pegOutLp, quote);

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
