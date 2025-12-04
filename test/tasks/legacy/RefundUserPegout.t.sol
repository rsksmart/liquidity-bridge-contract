// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import "lib/forge-std/src/Test.sol";
import "lib/forge-std/src/console.sol";
import {QuotesV2} from "src/legacy/QuotesV2.sol";
import {LiquidityBridgeContractV2} from "src/legacy/LiquidityBridgeContractV2.sol";
import {RefundUserPegout} from "../../../script/legacy/tasks/RefundUserPegout.s.sol";

/**
 * @title RefundUserPegoutTest
 * @notice Test for the legacy refund-user-pegout task
 */
contract RefundUserPegoutTest is Test {
    RefundUserPegout public refundScript;
    LiquidityBridgeContractV2 public lbc;
    address public user;
    address public liquidityProvider;
    uint256 public lpPrivateKey;

    function setUp() public {
        user = makeAddr("testUser");
        (liquidityProvider, lpPrivateKey) = makeAddrAndKey("testLP");

        vm.deal(user, 10 ether);
        vm.deal(liquidityProvider, 10 ether);

        lbc = new LiquidityBridgeContractV2();

        vm.prank(liquidityProvider, liquidityProvider);
        lbc.register{value: 0.1 ether}("Test LP", "https://test.com", true, "pegout");

        refundScript = new RefundUserPegout();
        vm.setEnv("LBC_ADDRESS", vm.toString(address(lbc)));
    }

    function test_SuccessfulRefund() public {
        RefundUserPegout testScript = new RefundUserPegout();
        vm.setEnv("LBC_ADDRESS", vm.toString(address(lbc)));

        console.log("\n=== SUCCESSFUL REFUND SIMULATION ===\n");

        QuotesV2.PegOutQuote memory quote = createTestQuote();
        bytes32 quoteHash = lbc.hashPegoutQuote(quote);
        bytes memory signature = signQuote(quoteHash);

        uint256 totalValue = quote.value + quote.callFee + quote.productFeeAmount + quote.gasFee;

        vm.prank(user, user);
        lbc.depositPegout{value: totalValue}(quote, signature);

        vm.warp(quote.expireDate + 1);
        vm.roll(quote.expireBlock + 1);

        uint256 userBalanceBefore = user.balance;
        string memory quoteHashStr = toHexString(quoteHash);

        vm.prank(user, user);
        testScript.refundUserPegoutTest(quoteHashStr);

        uint256 userBalanceAfter = user.balance;
        assertEq(userBalanceAfter, userBalanceBefore + totalValue, "User should receive full refund");

        console.log("\n[PASS] RefundUserPegout.s.sol script works correctly!");
    }

    function createTestQuote() internal view returns (QuotesV2.PegOutQuote memory) {
        bytes memory testBtcAddress = hex"76a914000000000000000000000000000000000000000088ac";

        return QuotesV2.PegOutQuote({
            lbcAddress: address(lbc),
            lpRskAddress: liquidityProvider,
            btcRefundAddress: testBtcAddress,
            rskRefundAddress: user,
            lpBtcAddress: testBtcAddress,
            callFee: 100000000000000,
            penaltyFee: 10000000000000,
            nonce: int64(uint64(block.timestamp)),
            deposityAddress: testBtcAddress,
            value: 0.5 ether,
            agreementTimestamp: uint32(block.timestamp),
            depositDateLimit: uint32(block.timestamp + 600),
            transferTime: 3600,
            depositConfirmations: 10,
            transferConfirmations: 2,
            productFeeAmount: 0,
            gasFee: 100,
            expireBlock: uint32(block.number + 10),
            expireDate: uint32(block.timestamp + 1000)
        });
    }

    function signQuote(bytes32 quoteHash) internal view returns (bytes memory) {
        bytes32 messageHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", quoteHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(lpPrivateKey, messageHash);
        return abi.encodePacked(r, s, v);
    }

    function toHexString(bytes32 data) internal pure returns (string memory) {
        bytes memory hexChars = "0123456789abcdef";
        bytes memory result = new bytes(64);
        for (uint256 i = 0; i < 32; i++) {
            result[i * 2] = hexChars[uint8(data[i] >> 4)];
            result[i * 2 + 1] = hexChars[uint8(data[i] & 0x0f)];
        }
        return string(result);
    }
}
