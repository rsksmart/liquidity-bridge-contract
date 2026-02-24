// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {PegOutTestBase} from "./PegOutTestBase.sol";
import {IPegOut} from "../../src/interfaces/IPegOut.sol";
import {Quotes} from "../../src/libraries/Quotes.sol";
import {Flyover} from "../../src/libraries/Flyover.sol";
import {SignatureValidator} from "../../src/libraries/SignatureValidator.sol";
import {PegOutChangeReceiver} from "../../src/test-contracts/PegOutChangeReceiver.sol";

contract DepositTest is PegOutTestBase {
    address public user;
    address public notLp;

    function setUp() public {
        deployPegOutContract();
        setupProviders();

        user = makeAddr("user");
        notLp = makeAddr("notLp");

        vm.deal(user, 100 ether);
        vm.deal(notLp, 100 ether);

        initBtcMocks(); // Initialize shared BTC mock data
    }

    // ============ depositPegOut function tests ============

    function test_DepositPegOut_RevertsIfLPDoesNotHaveCollateral() public {
        Quotes.PegOutQuote memory quote = createTestPegOutQuote(
            1.03 ether,
            notLp
        );
        bytes memory signature = signQuote(notLp, quote);

        vm.prank(user);
        vm.expectRevert(
            abi.encodeWithSelector(
                Flyover.ProviderNotRegistered.selector,
                notLp
            )
        );
        pegOutContract.depositPegOut{value: getTotalValue(quote)}(
            quote,
            signature
        );
    }

    function test_DepositPegOut_RevertsIfLPDoesNotSupportPegOut() public {
        Quotes.PegOutQuote memory quote = createTestPegOutQuote(
            1.03 ether,
            pegInLp
        );
        bytes memory signature = signQuote(pegInLp, quote);

        vm.prank(user);
        vm.expectRevert(
            abi.encodeWithSelector(
                Flyover.ProviderNotRegistered.selector,
                pegInLp
            )
        );
        pegOutContract.depositPegOut{value: getTotalValue(quote)}(
            quote,
            signature
        );
    }

    function test_DepositPegOut_RevertsIfAmountIsNotEnough() public {
        Quotes.PegOutQuote memory quote = createTestPegOutQuote(
            1.03 ether,
            fullLp
        );
        uint256 totalVal = getTotalValue(quote);
        uint256 sentAmount = totalVal - 1;

        bytes memory signature = signQuote(fullLp, quote);

        vm.prank(user);
        vm.expectRevert(
            abi.encodeWithSelector(
                Flyover.InsufficientAmount.selector,
                sentAmount,
                totalVal
            )
        );
        pegOutContract.depositPegOut{value: sentAmount}(quote, signature);
    }

    function test_DepositPegOut_RevertsIfDepositDateLimitExpired() public {
        Quotes.PegOutQuote memory quote = createTestPegOutQuote(
            1 ether,
            fullLp
        );

        // Warp time forward
        vm.warp(2000000);

        // Only depositDateLimit is expired, expireDate is still valid
        quote.depositDateLimit = 1000000; // EXPIRED (< current time)
        quote.expireDate = 3000000; // Still valid (> current time)

        bytes memory signature = signQuote(fullLp, quote);

        vm.prank(user);
        vm.expectRevert(
            abi.encodeWithSelector(
                IPegOut.QuoteExpiredByTime.selector,
                quote.depositDateLimit,
                quote.expireDate
            )
        );
        pegOutContract.depositPegOut{value: getTotalValue(quote)}(
            quote,
            signature
        );
    }

    function test_DepositPegOut_RevertsIfExpireDateExpired() public {
        Quotes.PegOutQuote memory quote = createTestPegOutQuote(
            1 ether,
            fullLp
        );

        // Warp time forward
        vm.warp(2000000);

        // Only expireDate is expired, depositDateLimit is still valid
        quote.depositDateLimit = 3000000; // Still valid (> current time)
        quote.expireDate = 1000000; // EXPIRED (< current time)

        bytes memory signature = signQuote(fullLp, quote);

        vm.prank(user);
        vm.expectRevert(
            abi.encodeWithSelector(
                IPegOut.QuoteExpiredByTime.selector,
                quote.depositDateLimit,
                quote.expireDate
            )
        );
        pegOutContract.depositPegOut{value: getTotalValue(quote)}(
            quote,
            signature
        );
    }

    function test_DepositPegOut_RevertsIfQuoteIsExpiredByBlocks() public {
        Quotes.PegOutQuote memory quote = createTestPegOutQuote(
            1.03 ether,
            fullLp
        );

        uint256 currentBlock = block.number;
        quote.expireBlock = uint32(currentBlock + 3);
        quote.expireDate = uint32(block.timestamp + 20000);

        bytes memory signature = signQuote(fullLp, quote);

        // Mine blocks to expire the quote
        vm.roll(currentBlock + 4);

        vm.prank(user);
        vm.expectRevert(
            abi.encodeWithSelector(
                IPegOut.QuoteExpiredByBlocks.selector,
                quote.expireBlock
            )
        );
        pegOutContract.depositPegOut{value: getTotalValue(quote)}(
            quote,
            signature
        );
    }

    function test_DepositPegOut_RevertsIfSignatureIsInvalid() public {
        Quotes.PegOutQuote memory quote = createTestPegOutQuote(
            1.03 ether,
            pegOutLp
        );

        bytes32 eip712Hash = pegOutContract.hashPegOutQuoteEIP712(quote);
        bytes memory wrongSignature = signQuote(fullLp, quote);

        vm.prank(user);
        vm.expectRevert(
            abi.encodeWithSelector(
                SignatureValidator.IncorrectSignature.selector,
                pegOutLp,
                eip712Hash,
                wrongSignature
            )
        );
        pegOutContract.depositPegOut{value: getTotalValue(quote)}(
            quote,
            wrongSignature
        );
    }

    function test_DepositPegOut_RevertsIfQuoteAlreadyCompleted() public {
        // Deposit → LP Refund (completes quote) → Try to deposit again
        Quotes.PegOutQuote memory quote = createTestPegOutQuote(
            1.03 ether,
            pegOutLp
        );
        bytes32 quoteHash = pegOutContract.hashPegOutQuote(quote);
        bytes memory signature = signQuote(pegOutLp, quote);
        uint256 totalVal = getTotalValue(quote);

        // Step 1: Deposit the quote
        vm.prank(user);
        pegOutContract.depositPegOut{value: totalVal}(quote, signature);

        // Step 2: LP completes the quote by refunding with BTC proof (mocked)
        // Generate mock BTC transaction
        bytes memory btcTx = generateMockBtcTx(quote, quoteHash);

        // Setup mock bridge responses
        bytes memory header = createBtcBlockHeader(
            uint32(block.timestamp + 100)
        );
        bridgeMock.setHeaderByHash(BLOCK_HEADER_HASH, header);
        bridgeMock.setConfirmations(
            int256(uint256(quote.transferConfirmations))
        );

        vm.prank(pegOutLp);
        pegOutContract.refundPegOut(
            quoteHash,
            btcTx,
            BLOCK_HEADER_HASH,
            PARTIAL_MERKLE_TREE,
            merkleHashes
        );

        // Step 3: Try to deposit the same quote again - should fail as already completed
        vm.prank(user);
        vm.expectRevert(
            abi.encodeWithSelector(
                IPegOut.QuoteAlreadyCompleted.selector,
                quoteHash
            )
        );
        pegOutContract.depositPegOut{value: totalVal}(quote, signature);
    }

    function test_DepositPegOut_RevertsIfQuoteAlreadyPaid() public {
        Quotes.PegOutQuote memory quote = createTestPegOutQuote(
            1.03 ether,
            pegOutLp
        );
        bytes32 quoteHash = pegOutContract.hashPegOutQuote(quote);
        bytes memory signature = signQuote(pegOutLp, quote);
        uint256 totalVal = getTotalValue(quote);

        // First deposit succeeds
        vm.prank(user);
        pegOutContract.depositPegOut{value: totalVal}(quote, signature);

        // Second deposit should fail - quote already registered
        vm.prank(user);
        vm.expectRevert(
            abi.encodeWithSelector(
                IPegOut.QuoteAlreadyRegistered.selector,
                quoteHash
            )
        );
        pegOutContract.depositPegOut{value: totalVal}(quote, signature);
    }

    function test_DepositPegOut_ReceivesDepositSuccessfullyWithoutPayingChange()
        public
    {
        Quotes.PegOutQuote memory quote = createTestPegOutQuote(
            1.03 ether,
            pegOutLp
        );

        uint256 totalVal = getTotalValue(quote);
        // Pay slightly more but less than dust threshold
        uint256 paidAmount = totalVal + 0.00000009 ether;

        bytes32 quoteHash = pegOutContract.hashPegOutQuote(quote);
        bytes memory signature = signQuote(pegOutLp, quote);

        uint256 userBalanceBefore = user.balance;
        uint256 contractBalanceBefore = address(pegOutContract).balance;

        vm.prank(user);
        vm.expectEmit(true, true, false, false);
        emit IPegOut.PegOutDeposit(quoteHash, user, 0, paidAmount);
        pegOutContract.depositPegOut{value: paidAmount}(quote, signature);

        // Verify balances (no change paid back due to dust threshold)
        assertEq(
            user.balance,
            userBalanceBefore - paidAmount,
            "User should pay full amount"
        );
        assertEq(
            address(pegOutContract).balance,
            contractBalanceBefore + paidAmount,
            "Contract should receive full amount"
        );

        // Verify quote is not yet completed
        assertFalse(
            pegOutContract.isQuoteCompleted(quoteHash),
            "Quote should not be completed yet"
        );
    }

    function test_DepositPegOut_ReceivesDepositSuccessfullyPayingChange()
        public
    {
        Quotes.PegOutQuote memory quote = createTestPegOutQuote(
            1.03 ether,
            pegOutLp
        );

        uint256 totalVal = getTotalValue(quote);
        uint256 paidAmount = totalVal + TEST_DUST_THRESHOLD;
        uint256 changeAmount = paidAmount - totalVal;

        bytes32 quoteHash = pegOutContract.hashPegOutQuote(quote);
        bytes memory signature = signQuote(pegOutLp, quote);

        uint256 userBalanceBefore = user.balance;

        vm.prank(user);
        vm.expectEmit(true, false, false, false);
        emit IPegOut.PegOutDeposit(quoteHash, user, 0, paidAmount);
        vm.expectEmit(true, true, false, true);
        emit IPegOut.PegOutChangePaid(quoteHash, user, changeAmount);
        pegOutContract.depositPegOut{value: paidAmount}(quote, signature);

        // Verify net payment (change was returned)
        assertEq(
            user.balance,
            userBalanceBefore - totalVal,
            "User should pay only total value (change returned)"
        );

        // Verify quote is not yet completed
        assertFalse(
            pegOutContract.isQuoteCompleted(quoteHash),
            "Quote should not be completed yet"
        );
    }

    function test_DepositPegOut_RevertsIfChangePaymentFails() public {
        // Create quote with refund address that will reject payments
        Quotes.PegOutQuote memory quote = createTestPegOutQuote(
            1 ether,
            fullLp
        );

        // Deploy mock contract that rejects payments
        PegOutChangeReceiver changeReceiver = new PegOutChangeReceiver();
        vm.prank(address(this));
        changeReceiver.setFail(true);
        quote.rskRefundAddress = address(changeReceiver);

        uint256 totalVal = getTotalValue(quote);
        uint256 paidAmount = totalVal + 0.5 ether; // Overpay significantly

        bytes memory signature = signQuote(fullLp, quote);

        // Deposit should revert when trying to pay change
        vm.prank(user);
        vm.expectRevert(); // PaymentFailed error
        pegOutContract.depositPegOut{value: paidAmount}(quote, signature);
    }

    function test_DepositPegOut_RevertsIfChangePaymentHasReentrancy() public {
        // Create quote with receiver that attempts reentrancy
        Quotes.PegOutQuote memory quote = createTestPegOutQuote(
            1 ether,
            fullLp
        );

        // Deploy receiver that will attempt reentrancy during change payment
        PegOutChangeReceiver changeReceiver = new PegOutChangeReceiver();
        bytes memory signature = signQuote(fullLp, quote);

        // Set up receiver to attempt reentrancy by calling depositPegOut again
        vm.prank(address(this));
        changeReceiver.setPegOut(quote, signature);
        quote.rskRefundAddress = address(changeReceiver);

        uint256 totalVal = getTotalValue(quote);
        uint256 paidAmount = totalVal + 0.5 ether;

        // Deposit should revert due to reentrancy guard
        vm.prank(user);
        vm.expectRevert(); // PaymentFailed with ReentrancyGuard error
        pegOutContract.depositPegOut{value: paidAmount}(quote, signature);
    }

    // ============ Helper Functions ============

    function createTestPegOutQuote(
        uint256 value,
        address lp
    ) internal view returns (Quotes.PegOutQuote memory) {
        // Create a valid Bitcoin testnet P2PKH address (version byte 0x6f + 20 bytes hash160)
        bytes memory testBtcAddress = abi.encodePacked(
            hex"6f", // Testnet version byte
            hex"89abcdefabbaabbaabbaabbaabbaabbaabbaabba" // 20 bytes hash160
        );
        uint32 currentTime = uint32(block.timestamp);

        return
            Quotes.PegOutQuote({
                chainId: block.chainid,
                callFee: 100000000000000,
                penaltyFee: 10000000000000,
                value: value,
                gasFee: 100,
                lbcAddress: address(pegOutContract),
                lpRskAddress: lp,
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

    function getTotalValue(
        Quotes.PegOutQuote memory quote
    ) internal pure returns (uint256) {
        return quote.value + quote.callFee + quote.gasFee;
    }

    function signQuote(
        address signer,
        Quotes.PegOutQuote memory quote
    ) internal returns (bytes memory) {
        // Get private key for the signer
        uint256 privateKey;
        if (signer == fullLp) {
            privateKey = fullLpKey;
        } else if (signer == pegInLp) {
            privateKey = pegInLpKey;
        } else if (signer == pegOutLp) {
            privateKey = pegOutLpKey;
        } else {
            // For other signers (like notLp), create a temporary key
            (, privateKey) = makeAddrAndKey("tempSigner");
        }

        bytes32 eip712Hash = pegOutContract.hashPegOutQuoteEIP712(quote);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, eip712Hash);
        return abi.encodePacked(r, s, v);
    }
}
