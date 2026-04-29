// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {PegOutTestBase} from "./PegOutTestBase.sol";
import {IPegOut} from "../../src/interfaces/IPegOut.sol";
import {Quotes} from "../../src/libraries/Quotes.sol";
import {Flyover} from "../../src/libraries/Flyover.sol";
import {PegOutChangeReceiver} from "../../src/test-contracts/PegOutChangeReceiver.sol";

/// @title Withdraw and getBalance tests for PegOut
/// @notice Tests for withdraw, getBalance, and balance-credit-on-failed-refund behavior
contract WithdrawTest is PegOutTestBase {
    address public user;
    uint256 constant BLOCKS_UNTIL_EXPIRATION = 50;
    uint256 constant SECONDS_UNTIL_EXPIRATION = 20000;

    string constant HELPER_SCRIPT_GET_BTC_ADDRESS_BYTES =
        "script/helpers/get-btc-address-bytes.ts";

    function setUp() public {
        deployPegOutContract();
        setupProviders();

        user = makeAddr("user");
        vm.deal(user, 100 ether);

        initBtcMocks();
    }

    // ============ getBalance tests ============

    function test_GetBalance_ReturnsZeroForAddressWithNoBalance() public view {
        assertEq(
            pegOutContract.getBalance(user),
            0,
            "User should have zero balance"
        );
        assertEq(
            pegOutContract.getBalance(fullLp),
            0,
            "LP should have zero balance"
        );
        assertEq(
            pegOutContract.getBalance(address(pegOutContract)),
            0,
            "Contract should report zero for itself"
        );
    }

    function test_GetBalance_ReturnsCreditedBalanceAfterFailedUserRefund()
        public
    {
        PegOutChangeReceiver changeReceiver = new PegOutChangeReceiver();
        Quotes.PegOutQuote memory quote = createTestPegOutQuote(
            1 ether,
            fullLp
        );
        quote.rskRefundAddress = address(changeReceiver);
        quote.expireDate = uint32(
            uint256(block.timestamp) + SECONDS_UNTIL_EXPIRATION
        );
        quote.expireBlock = uint32(
            uint256(block.number) + BLOCKS_UNTIL_EXPIRATION
        );

        bytes32 quoteHash = pegOutContract.hashPegOutQuote(quote);
        bytes memory signature = signQuote(fullLp, quote);
        changeReceiver.setFail(true);

        vm.prank(user);
        pegOutContract.depositPegOut{value: getTotalValue(quote)}(
            quote,
            signature
        );

        vm.roll(block.number + BLOCKS_UNTIL_EXPIRATION + 1);
        vm.warp(block.timestamp + SECONDS_UNTIL_EXPIRATION + 1);

        assertEq(
            pegOutContract.getBalance(address(changeReceiver)),
            0,
            "Balance should be zero before refund"
        );

        vm.prank(user);
        pegOutContract.refundUserPegOut(quoteHash);

        uint256 expectedBalance = getTotalValue(quote);
        assertEq(
            pegOutContract.getBalance(address(changeReceiver)),
            expectedBalance,
            "Balance should equal refund amount after failed transfer"
        );
    }

    // ============ withdraw tests ============

    function test_Withdraw_Success() public {
        PegOutChangeReceiver receiverWithBalance = new PegOutChangeReceiver();
        uint256 amount = _creditBalanceToReceiver(receiverWithBalance, 1 ether);

        // Allow the contract to accept ETH without reentering (receive() would otherwise call depositPegOut)
        receiverWithBalance.setAcceptFunds(true);

        uint256 receiverBalanceBefore = address(receiverWithBalance).balance;

        // Withdraw to self (same address as balance owner)
        vm.prank(address(receiverWithBalance));
        pegOutContract.withdraw(payable(address(receiverWithBalance)), amount);

        assertEq(
            pegOutContract.getBalance(address(receiverWithBalance)),
            0,
            "Internal balance should be zero"
        );
        assertEq(
            address(receiverWithBalance).balance,
            receiverBalanceBefore + amount,
            "Receiver should receive the amount to itself"
        );
    }

    function test_Withdraw_RevertsWithNoBalanceWhenInsufficientBalance()
        public
    {
        address someone = makeAddr("someone");
        vm.prank(someone);
        vm.expectRevert(
            abi.encodeWithSelector(Flyover.NoBalance.selector, 1 ether, 0)
        );
        pegOutContract.withdraw(payable(someone), 1 ether);
    }

    function test_Withdraw_RevertsWithInvalidAddressWhenRecipientIsZeroAddress()
        public
    {
        PegOutChangeReceiver receiverWithBalance = new PegOutChangeReceiver();
        uint256 amount = _creditBalanceToReceiver(receiverWithBalance, 1 ether);

        vm.prank(address(receiverWithBalance));
        vm.expectRevert(
            abi.encodeWithSelector(Flyover.InvalidAddress.selector, address(0))
        );
        pegOutContract.withdraw(payable(address(0)), amount);

        // Balance should be unchanged
        assertEq(
            pegOutContract.getBalance(address(receiverWithBalance)),
            amount,
            "Balance should remain"
        );
    }

    function test_Withdraw_RevertsWithPaymentFailedWhenRecipientRejects()
        public
    {
        PegOutChangeReceiver receiverWithBalance = new PegOutChangeReceiver();
        PegOutChangeReceiver rejectingRecipient = new PegOutChangeReceiver();
        rejectingRecipient.setFail(true);

        uint256 amount = _creditBalanceToReceiver(receiverWithBalance, 1 ether);

        vm.prank(address(receiverWithBalance));
        vm.expectRevert(); // PaymentFailed when recipient's receive reverts
        pegOutContract.withdraw(payable(address(rejectingRecipient)), amount);

        // Balance should be unchanged (whole tx reverted)
        assertEq(
            pegOutContract.getBalance(address(receiverWithBalance)),
            amount,
            "Balance should remain"
        );
    }

    function test_Withdraw_CanSendToDifferentAddress() public {
        (address recipient, ) = makeAddrAndKey("recipient");
        PegOutChangeReceiver receiverWithBalance = new PegOutChangeReceiver();
        uint256 amount = _creditBalanceToReceiver(receiverWithBalance, 1 ether);

        vm.deal(recipient, 0);

        vm.prank(address(receiverWithBalance));
        pegOutContract.withdraw(payable(recipient), amount);

        assertEq(
            recipient.balance,
            amount,
            "Recipient should receive the amount"
        );
        assertEq(
            pegOutContract.getBalance(address(receiverWithBalance)),
            0,
            "Sender balance should be zero"
        );
    }

    function test_Withdraw_PartialWithdraw() public {
        (address recipient, ) = makeAddrAndKey("recipient");
        PegOutChangeReceiver receiverWithBalance = new PegOutChangeReceiver();
        uint256 totalCredited = _creditBalanceToReceiver(
            receiverWithBalance,
            3 ether
        );
        uint256 withdrawAmount = 1 ether;

        vm.prank(address(receiverWithBalance));
        pegOutContract.withdraw(payable(recipient), withdrawAmount);

        assertEq(
            pegOutContract.getBalance(address(receiverWithBalance)),
            totalCredited - withdrawAmount,
            "Remaining balance"
        );
        assertEq(
            recipient.balance,
            withdrawAmount,
            "Recipient should receive partial amount"
        );
    }

    // ============ Helpers ============

    /// Credits internal balance to the given receiver by doing a user refund where the receiver rejects the transfer.
    function _creditBalanceToReceiver(
        PegOutChangeReceiver receiver,
        uint256 quoteValue
    ) internal returns (uint256) {
        Quotes.PegOutQuote memory quote = createTestPegOutQuote(
            quoteValue,
            fullLp
        );
        quote.rskRefundAddress = address(receiver);
        quote.expireDate = uint32(
            uint256(block.timestamp) + SECONDS_UNTIL_EXPIRATION
        );
        quote.expireBlock = uint32(
            uint256(block.number) + BLOCKS_UNTIL_EXPIRATION
        );

        bytes32 quoteHash = pegOutContract.hashPegOutQuote(quote);
        bytes memory signature = signQuote(fullLp, quote);
        receiver.setFail(true);

        vm.prank(user);
        pegOutContract.depositPegOut{value: getTotalValue(quote)}(
            quote,
            signature
        );

        vm.roll(block.number + BLOCKS_UNTIL_EXPIRATION + 1);
        vm.warp(block.timestamp + SECONDS_UNTIL_EXPIRATION + 1);

        vm.prank(user);
        pegOutContract.refundUserPegOut(quoteHash);

        return getTotalValue(quote);
    }

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
                chainId: block.chainid,
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
        return quote.value + quote.callFee + quote.gasFee;
    }

    function signQuote(
        address signer,
        Quotes.PegOutQuote memory quote
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

        bytes32 eip712Hash = pegOutContract.hashPegOutQuoteEIP712(quote);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, eip712Hash);
        return abi.encodePacked(r, s, v);
    }
}
