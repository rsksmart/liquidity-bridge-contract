// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {PegOutTestBase} from "./PegOutTestBase.sol";
import {IPegOut} from "../../src/interfaces/IPegOut.sol";
import {Quotes} from "../../src/libraries/Quotes.sol";
import {Flyover} from "../../src/libraries/Flyover.sol";
import {ICollateralManagement} from "../../src/interfaces/ICollateralManagement.sol";
import {PegOutChangeReceiver} from "../../src/test-contracts/PegOutChangeReceiver.sol";

/// @title UserRefund Tests for PegOut
/// @notice Tests for the refundUserPegOut function
contract UserRefundTest is PegOutTestBase {
    address public user;
    uint256 constant BLOCKS_UNTIL_EXPIRATION = 50;
    uint256 constant SECONDS_UNTIL_EXPIRATION = 20000;

    function setUp() public {
        deployPegOutContract();
        setupProviders();

        user = makeAddr("user");
        vm.deal(user, 100 ether);

        initBtcMocks(); // Initialize shared BTC mock data
    }

    // ============ refundUserPegOut function tests ============

    function test_RefundUserPegOut_RevertsIfQuoteWasNotPaid() public {
        Quotes.PegOutQuote memory quote = createTestPegOutQuote(
            1 ether,
            fullLp
        );
        bytes32 quoteHash = pegOutContract.hashPegOutQuote(quote);

        vm.expectRevert(
            abi.encodeWithSelector(Flyover.QuoteNotFound.selector, quoteHash)
        );
        pegOutContract.refundUserPegOut(quoteHash);
    }

    function test_RefundUserPegOut_RevertsIfQuoteNotExpiredByBlocks() public {
        Quotes.PegOutQuote memory quote = createTestPegOutQuote(
            1 ether,
            fullLp
        );

        // Set expiration in the future
        quote.expireDate = uint32(
            uint256(block.timestamp) + SECONDS_UNTIL_EXPIRATION
        );
        quote.expireBlock = uint32(
            uint256(block.number) + BLOCKS_UNTIL_EXPIRATION
        );

        bytes32 quoteHash = pegOutContract.hashPegOutQuote(quote);
        bytes memory signature = signQuote(fullLp, quoteHash);

        // Deposit the quote
        vm.prank(user);
        pegOutContract.depositPegOut{value: getTotalValue(quote)}(
            quote,
            signature
        );

        // Advance time past expireDate but not past expireBlock
        vm.roll(block.number + 2);
        vm.warp(block.timestamp + SECONDS_UNTIL_EXPIRATION + 1);

        // Should revert because block number hasn't reached expireBlock
        vm.expectRevert(
            abi.encodeWithSelector(IPegOut.QuoteNotExpired.selector, quoteHash)
        );
        pegOutContract.refundUserPegOut(quoteHash);
    }

    function test_RefundUserPegOut_RevertsIfQuoteNotExpiredByDate() public {
        Quotes.PegOutQuote memory quote = createTestPegOutQuote(
            1 ether,
            fullLp
        );

        // Set expiration in the future
        quote.expireBlock = uint32(
            uint256(block.number) + BLOCKS_UNTIL_EXPIRATION
        );
        quote.expireDate = uint32(
            uint256(block.timestamp) + SECONDS_UNTIL_EXPIRATION
        );

        bytes32 quoteHash = pegOutContract.hashPegOutQuote(quote);
        bytes memory signature = signQuote(fullLp, quoteHash);

        // Deposit the quote
        vm.prank(user);
        pegOutContract.depositPegOut{value: getTotalValue(quote)}(
            quote,
            signature
        );

        // Advance blocks past expireBlock but not time past expireDate
        vm.roll(block.number + BLOCKS_UNTIL_EXPIRATION + 3);
        vm.warp(block.timestamp + 1);

        // Should revert because timestamp hasn't reached expireDate
        vm.expectRevert(
            abi.encodeWithSelector(IPegOut.QuoteNotExpired.selector, quoteHash)
        );
        pegOutContract.refundUserPegOut(quoteHash);
    }

    function test_RefundUserPegOut_RevertsIfPaymentToUserFails() public {
        // Deploy a contract that will reject payments
        PegOutChangeReceiver changeReceiver = new PegOutChangeReceiver();

        Quotes.PegOutQuote memory quote = createTestPegOutQuote(
            1 ether,
            fullLp
        );
        quote.rskRefundAddress = address(changeReceiver);

        // Set expiration in the future
        quote.expireDate = uint32(
            uint256(block.timestamp) + SECONDS_UNTIL_EXPIRATION
        );
        quote.expireBlock = uint32(
            uint256(block.number) + BLOCKS_UNTIL_EXPIRATION
        );

        bytes32 quoteHash = pegOutContract.hashPegOutQuote(quote);
        bytes memory signature = signQuote(fullLp, quoteHash);

        // Make the receiver fail on payment
        changeReceiver.setFail(true);

        // Deposit the quote
        vm.prank(user);
        pegOutContract.depositPegOut{value: getTotalValue(quote)}(
            quote,
            signature
        );

        // Advance past expiration - both block number and timestamp must be past expiration
        vm.roll(block.number + BLOCKS_UNTIL_EXPIRATION + 1);
        vm.warp(block.timestamp + SECONDS_UNTIL_EXPIRATION + 1);

        // Should revert with PaymentFailed
        vm.prank(user);
        vm.expectRevert(
            abi.encodeWithSelector(
                Flyover.PaymentFailed.selector,
                quote.rskRefundAddress,
                getTotalValue(quote),
                abi.encodeWithSelector(PegOutChangeReceiver.SomeError.selector)
            )
        );
        pegOutContract.refundUserPegOut(quoteHash);
    }

    function test_RefundUserPegOut_NotAllowReentrancy() public {
        // Deploy a contract that will attempt reentrancy
        PegOutChangeReceiver changeReceiver = new PegOutChangeReceiver();

        Quotes.PegOutQuote memory quote = createTestPegOutQuote(
            1 ether,
            fullLp
        );
        quote.rskRefundAddress = address(changeReceiver);

        // Set short expiration
        quote.expireDate = uint32(block.timestamp) + 20;
        quote.expireBlock = uint32(block.number) + 5;

        bytes32 quoteHash = pegOutContract.hashPegOutQuote(quote);
        bytes memory signature = signQuote(fullLp, quoteHash);

        // Don't make it fail, but set up reentrancy attack
        changeReceiver.setFail(false);
        changeReceiver.setPegOut(quote, signature);

        // Deposit the quote
        vm.prank(user);
        pegOutContract.depositPegOut{value: getTotalValue(quote)}(
            quote,
            signature
        );

        // Advance past expiration - both block number and timestamp must be past expiration
        vm.roll(block.number + 6); // Must be > expireBlock (which is block.number + 5)
        vm.warp(block.timestamp + 21); // Must be > expireDate (which is block.timestamp + 20)

        // The reentrancy attempt should fail
        vm.prank(user);
        vm.expectRevert(
            abi.encodeWithSelector(
                Flyover.PaymentFailed.selector,
                quote.rskRefundAddress,
                getTotalValue(quote),
                abi.encodeWithSelector(
                    bytes4(keccak256("ReentrancyGuardReentrantCall()"))
                )
            )
        );
        pegOutContract.refundUserPegOut(quoteHash);
    }

    function test_RefundUserPegOut_ExecutesRefundAndSlashesLP() public {
        Quotes.PegOutQuote memory quote = createTestPegOutQuote(
            1 ether,
            fullLp
        );
        uint256 totalQuoteValue = getTotalValue(quote);

        // Set expiration in the future
        quote.expireDate = uint32(
            uint256(block.timestamp) + SECONDS_UNTIL_EXPIRATION
        );
        quote.expireBlock = uint32(
            uint256(block.number) + BLOCKS_UNTIL_EXPIRATION
        );

        bytes32 quoteHash = pegOutContract.hashPegOutQuote(quote);
        bytes memory signature = signQuote(fullLp, quoteHash);

        // Deposit the quote
        vm.prank(user);
        pegOutContract.depositPegOut{value: totalQuoteValue}(quote, signature);

        // Get initial balances
        uint256 contractBalanceBefore = address(pegOutContract).balance;
        uint256 userBalanceBefore = user.balance;

        // Advance past expiration - both block number and timestamp must be past expiration
        vm.roll(block.number + BLOCKS_UNTIL_EXPIRATION + 1);
        vm.warp(block.timestamp + SECONDS_UNTIL_EXPIRATION + 1);

        // Calculate expected reward
        uint256 rewardPercentage = collateralManagement.getRewardPercentage();
        uint256 expectedReward = (uint256(quote.penaltyFee) *
            rewardPercentage) / 10000;

        // Execute refund
        vm.prank(user);
        vm.expectEmit(true, true, true, true);
        emit IPegOut.PegOutUserRefunded(
            quoteHash,
            quote.rskRefundAddress,
            totalQuoteValue
        );
        vm.expectEmit(true, true, true, true);
        emit ICollateralManagement.Penalized(
            fullLp,
            user,
            quoteHash,
            Flyover.ProviderType.PegOut,
            quote.penaltyFee,
            expectedReward
        );
        pegOutContract.refundUserPegOut(quoteHash);

        // Verify balances changed correctly
        assertEq(
            address(pegOutContract).balance,
            contractBalanceBefore - totalQuoteValue,
            "Contract balance should decrease by total quote value"
        );
        assertEq(
            user.balance,
            userBalanceBefore + totalQuoteValue,
            "User balance should increase by total quote value"
        );

        // Verify quote is marked as completed
        assertTrue(
            pegOutContract.isQuoteCompleted(quoteHash),
            "Quote should be marked as completed"
        );

        // Verify cannot refund again
        vm.prank(user);
        vm.expectRevert(
            abi.encodeWithSelector(Flyover.QuoteNotFound.selector, quoteHash)
        );
        pegOutContract.refundUserPegOut(quoteHash);
    }

    // ============ Helper Functions ============

    string constant HELPER_SCRIPT_GET_BTC_ADDRESS_BYTES =
        "script/helpers/get-btc-address-bytes.ts";

    function createTestPegOutQuote(
        uint256 value,
        address lp
    ) internal returns (Quotes.PegOutQuote memory) {
        bytes memory testBtcAddress = getBtcAddressForType("p2pkh");
        uint32 currentTime = uint32(block.timestamp);

        return
            Quotes.PegOutQuote({
                callFee: 100000000000000,
                penaltyFee: 10000000000000,
                value: value,
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
            quote.value + quote.callFee + quote.gasFee;
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
