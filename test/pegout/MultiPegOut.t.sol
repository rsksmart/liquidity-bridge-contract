// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {PegOutTestBase} from "./PegOutTestBase.sol";
import {IPegOut} from "../../src/interfaces/IPegOut.sol";
import {Quotes} from "../../src/libraries/Quotes.sol";
import {MultiPegOutPayer} from "../../src/test-contracts/MultiPegOutPayer.sol";

contract MultiPegOutTest is PegOutTestBase {
    MultiPegOutPayer public multiPayer;
    address public user;

    function setUp() public {
        deployPegOutContract();
        setupProviders();
        initBtcMocks();
        user = makeAddr("user");
        multiPayer = new MultiPegOutPayer(payable(address(pegOutContract)));
        vm.deal(address(multiPayer), 100 ether);
    }

    function test_MultiPegOut_EmitsNDepositEvents() public {
        Quotes.PegOutQuote memory quote1 = createTestPegOutQuote(
            0.5 ether,
            fullLp,
            1
        );
        Quotes.PegOutQuote memory quote2 = createTestPegOutQuote(
            0.5 ether,
            fullLp,
            2
        );

        bytes32 quoteHash1 = pegOutContract.hashPegOutQuote(quote1);
        bytes32 quoteHash2 = pegOutContract.hashPegOutQuote(quote2);

        bytes memory sig1 = signQuote(fullLp, quote1);
        bytes memory sig2 = signQuote(fullLp, quote2);

        MultiPegOutPayer.PegOutPayment[]
            memory payments = new MultiPegOutPayer.PegOutPayment[](2);
        payments[0] = MultiPegOutPayer.PegOutPayment({
            quote: quote1,
            signature: sig1
        });
        payments[1] = MultiPegOutPayer.PegOutPayment({
            quote: quote2,
            signature: sig2
        });

        vm.expectEmit(true, true, false, false);
        emit IPegOut.PegOutDeposit(
            quoteHash1,
            address(multiPayer),
            0,
            getTotalValue(quote1)
        );
        vm.expectEmit(true, true, false, false);
        emit IPegOut.PegOutDeposit(
            quoteHash2,
            address(multiPayer),
            0,
            getTotalValue(quote2)
        );

        multiPayer.executeMultiplePegOuts(payments);

        assertFalse(pegOutContract.isQuoteCompleted(quoteHash1));
        assertFalse(pegOutContract.isQuoteCompleted(quoteHash2));
    }

    function test_MultiPegOut_RevertsIfBalanceInsufficient() public {
        Quotes.PegOutQuote memory quote1 = createTestPegOutQuote(
            0.5 ether,
            fullLp,
            1
        );
        Quotes.PegOutQuote memory quote2 = createTestPegOutQuote(
            0.5 ether,
            fullLp,
            2
        );

        bytes memory sig1 = signQuote(fullLp, quote1);
        bytes memory sig2 = signQuote(fullLp, quote2);

        MultiPegOutPayer.PegOutPayment[]
            memory payments = new MultiPegOutPayer.PegOutPayment[](2);
        payments[0] = MultiPegOutPayer.PegOutPayment({
            quote: quote1,
            signature: sig1
        });
        payments[1] = MultiPegOutPayer.PegOutPayment({
            quote: quote2,
            signature: sig2
        });

        // Give multiPayer only enough for the first payment; after it is sent the balance is 0.
        vm.deal(address(multiPayer), getTotalValue(quote1));

        vm.expectRevert(
            abi.encodeWithSelector(
                MultiPegOutPayer.InsufficientBalance.selector,
                uint256(0),
                getTotalValue(quote2)
            )
        );
        multiPayer.executeMultiplePegOuts(payments);
    }

    // ============ Helper Functions ============

    function createTestPegOutQuote(
        uint256 value,
        address lp,
        int64 nonce
    ) internal view returns (Quotes.PegOutQuote memory) {
        bytes memory testBtcAddress = abi.encodePacked(
            hex"6f",
            hex"89abcdefabbaabbaabbaabbaabbaabbaabbaabba"
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
                nonce: nonce,
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
        uint256 privateKey;
        if (signer == fullLp) {
            privateKey = fullLpKey;
        } else if (signer == pegInLp) {
            privateKey = pegInLpKey;
        } else {
            privateKey = pegOutLpKey;
        }
        bytes32 eip712Hash = pegOutContract.hashPegOutQuoteEIP712(quote);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, eip712Hash);
        return abi.encodePacked(r, s, v);
    }
}
