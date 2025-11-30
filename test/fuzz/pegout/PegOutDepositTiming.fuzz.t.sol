// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {PegOutTestBase} from "../../pegout/PegOutTestBase.sol";
import {Quotes} from "../../../src/libraries/Quotes.sol";
import {IPegOut} from "../../../src/interfaces/IPegOut.sol";

/// @title PegOutDepositTiming Fuzz Tests
/// @notice Fuzz tests for time-based validation in PegOut deposits
contract PegOutDepositTimingFuzzTest is PegOutTestBase {
    address public user;

    function setUp() public {
        deployPegOutContract();
        setupProviders();

        user = makeAddr("user");
        vm.deal(user, 1000 ether);
    }

    /// @notice Fuzz test: Deposit should succeed before depositDateLimit
    function testFuzz_DepositPegOut_SucceedsBeforeDepositDateLimit(
        uint32 currentTime,
        uint32 timeUntilLimit
    ) public {
        currentTime = uint32(bound(currentTime, 1000000, type(uint32).max - 1000000));
        timeUntilLimit = uint32(bound(timeUntilLimit, 100, 1000000));

        vm.warp(currentTime);

        Quotes.PegOutQuote memory quote = createTestQuote();
        quote.agreementTimestamp = currentTime;
        quote.depositDateLimit = currentTime + timeUntilLimit;
        quote.expireDate = currentTime + timeUntilLimit + 10000;

        uint256 totalValue = getTotalValue(quote);
        bytes32 quoteHash = pegOutContract.hashPegOutQuote(quote);
        bytes memory signature = signQuote(pegOutLp, quoteHash);

        // Should succeed
        vm.prank(user);
        pegOutContract.depositPegOut{value: totalValue}(quote, signature);
    }

    /// @notice Fuzz test: Deposit should revert after depositDateLimit
    function testFuzz_DepositPegOut_RevertsAfterDepositDateLimit(
        uint32 currentTime,
        uint32 depositDateLimit,
        uint32 lateness
    ) public {
        currentTime = uint32(bound(currentTime, 1000000, type(uint32).max - 2000000));
        depositDateLimit = uint32(bound(depositDateLimit, currentTime, currentTime + 100000));
        lateness = uint32(bound(lateness, 1, 100000));

        uint32 expireDate = depositDateLimit + lateness + 10000;
        vm.warp(depositDateLimit + lateness);

        Quotes.PegOutQuote memory quote = createTestQuote();
        quote.agreementTimestamp = currentTime;
        quote.depositDateLimit = depositDateLimit;
        quote.expireDate = expireDate;

        uint256 totalValue = getTotalValue(quote);
        bytes32 quoteHash = pegOutContract.hashPegOutQuote(quote);
        bytes memory signature = signQuote(pegOutLp, quoteHash);

        vm.prank(user);
        vm.expectRevert(
            abi.encodeWithSelector(
                IPegOut.QuoteExpiredByTime.selector,
                depositDateLimit,
                expireDate
            )
        );
        pegOutContract.depositPegOut{value: totalValue}(quote, signature);
    }

    /// @notice Fuzz test: Deposit should revert after expireDate
    function testFuzz_DepositPegOut_RevertsAfterExpireDate(
        uint32 currentTime,
        uint32 expireDate,
        uint32 lateness
    ) public {
        currentTime = uint32(bound(currentTime, 1000000, type(uint32).max - 2000000));
        expireDate = uint32(bound(expireDate, currentTime + 1000, currentTime + 100000));
        lateness = uint32(bound(lateness, 1, 100000));

        vm.warp(expireDate + lateness);

        Quotes.PegOutQuote memory quote = createTestQuote();
        quote.agreementTimestamp = currentTime;
        quote.depositDateLimit = expireDate - 1000;
        quote.expireDate = expireDate;

        uint256 totalValue = getTotalValue(quote);
        bytes32 quoteHash = pegOutContract.hashPegOutQuote(quote);
        bytes memory signature = signQuote(pegOutLp, quoteHash);

        vm.prank(user);
        vm.expectRevert(
            abi.encodeWithSelector(
                IPegOut.QuoteExpiredByTime.selector,
                quote.depositDateLimit,
                expireDate
            )
        );
        pegOutContract.depositPegOut{value: totalValue}(quote, signature);
    }

    /// @notice Fuzz test: Deposit should revert after expireBlock
    function testFuzz_DepositPegOut_RevertsAfterExpireBlock(
        uint32 currentBlock,
        uint32 blocksUntilExpiry,
        uint16 extraBlocks
    ) public {
        currentBlock = uint32(bound(currentBlock, 1000, type(uint32).max - 1000000));
        blocksUntilExpiry = uint32(bound(blocksUntilExpiry, 10, 10000));
        extraBlocks = uint16(bound(extraBlocks, 1, 1000));

        vm.roll(currentBlock);

        Quotes.PegOutQuote memory quote = createTestQuote();
        quote.expireBlock = currentBlock + blocksUntilExpiry;

        // Mine past expiry
        vm.roll(quote.expireBlock + extraBlocks);

        uint256 totalValue = getTotalValue(quote);
        bytes32 quoteHash = pegOutContract.hashPegOutQuote(quote);
        bytes memory signature = signQuote(pegOutLp, quoteHash);

        vm.prank(user);
        vm.expectRevert(
            abi.encodeWithSelector(
                IPegOut.QuoteExpiredByBlocks.selector,
                quote.expireBlock
            )
        );
        pegOutContract.depositPegOut{value: totalValue}(quote, signature);
    }

    /// @notice Fuzz test: Deposit should succeed exactly at depositDateLimit
    function testFuzz_DepositPegOut_SucceedsAtExactDepositDateLimit(
        uint32 currentTime,
        uint32 timeUntilLimit
    ) public {
        currentTime = uint32(bound(currentTime, 1000000, type(uint32).max - 1000000));
        timeUntilLimit = uint32(bound(timeUntilLimit, 100, 100000));

        vm.warp(currentTime);

        Quotes.PegOutQuote memory quote = createTestQuote();
        quote.agreementTimestamp = currentTime;
        quote.depositDateLimit = currentTime + timeUntilLimit;
        quote.expireDate = currentTime + timeUntilLimit + 10000;

        // Warp to exactly the limit
        vm.warp(quote.depositDateLimit);

        uint256 totalValue = getTotalValue(quote);
        bytes32 quoteHash = pegOutContract.hashPegOutQuote(quote);
        bytes memory signature = signQuote(pegOutLp, quoteHash);

        // Should succeed (boundary check: <= not <)
        vm.prank(user);
        pegOutContract.depositPegOut{value: totalValue}(quote, signature);
    }

    /// @notice Fuzz test: Deposit should succeed exactly at expireBlock - 1
    function testFuzz_DepositPegOut_SucceedsBeforeExpireBlock(
        uint32 currentBlock,
        uint32 blocksUntilExpiry
    ) public {
        currentBlock = uint32(bound(currentBlock, 1000, type(uint32).max - 100000));
        blocksUntilExpiry = uint32(bound(blocksUntilExpiry, 10, 10000));

        vm.roll(currentBlock);

        Quotes.PegOutQuote memory quote = createTestQuote();
        quote.expireBlock = currentBlock + blocksUntilExpiry;

        // Mine to exactly expireBlock - 1
        vm.roll(quote.expireBlock - 1);

        uint256 totalValue = getTotalValue(quote);
        bytes32 quoteHash = pegOutContract.hashPegOutQuote(quote);
        bytes memory signature = signQuote(pegOutLp, quoteHash);

        vm.prank(user);
        pegOutContract.depositPegOut{value: totalValue}(quote, signature);
    }

    /// @notice Fuzz test: agreementTimestamp, depositDateLimit, and expireDate relationships
    function testFuzz_DepositPegOut_ValidatesTimestampRelationships(
        uint32 agreementTimestamp,
        uint32 depositWindow,
        uint32 expiryWindow
    ) public {
        agreementTimestamp = uint32(bound(agreementTimestamp, 1000000, type(uint32).max - 2000000));
        depositWindow = uint32(bound(depositWindow, 100, 100000));
        expiryWindow = uint32(bound(expiryWindow, 100, 100000));

        vm.warp(agreementTimestamp);

        Quotes.PegOutQuote memory quote = createTestQuote();
        quote.agreementTimestamp = agreementTimestamp;
        quote.depositDateLimit = agreementTimestamp + depositWindow;
        quote.expireDate = agreementTimestamp + depositWindow + expiryWindow;

        uint256 totalValue = getTotalValue(quote);
        bytes32 quoteHash = pegOutContract.hashPegOutQuote(quote);
        bytes memory signature = signQuote(pegOutLp, quoteHash);

        // Should succeed with properly ordered timestamps
        vm.prank(user);
        pegOutContract.depositPegOut{value: totalValue}(quote, signature);
    }

    /// @notice Fuzz test: Edge case with maximum timestamp values
    function testFuzz_DepositPegOut_HandlesMaxTimestamps(
        uint32 timeBeforeMax
    ) public {
        timeBeforeMax = uint32(bound(timeBeforeMax, 100000, 1000000));

        uint32 maxTime = type(uint32).max;
        uint32 currentTime = maxTime - timeBeforeMax;

        vm.warp(currentTime);

        Quotes.PegOutQuote memory quote = createTestQuote();
        quote.agreementTimestamp = currentTime;
        quote.depositDateLimit = currentTime + 1000;
        quote.expireDate = currentTime + 2000;

        uint256 totalValue = getTotalValue(quote);
        bytes32 quoteHash = pegOutContract.hashPegOutQuote(quote);
        bytes memory signature = signQuote(pegOutLp, quoteHash);

        vm.prank(user);
        pegOutContract.depositPegOut{value: totalValue}(quote, signature);
    }

    // ============ Helper Functions ============

    function createTestQuote() internal view returns (Quotes.PegOutQuote memory) {
        bytes memory testBtcAddress = abi.encodePacked(
            hex"6f",
            hex"89abcdefabbaabbaabbaabbaabbaabbaabbaabba"
        );
        uint32 currentTime = uint32(block.timestamp);

        return Quotes.PegOutQuote({
            callFee: 100000000000000,
            penaltyFee: 10000000000000,
            value: 1 ether,
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
