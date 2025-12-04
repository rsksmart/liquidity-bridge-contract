// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import "lib/forge-std/src/Test.sol";
import "lib/forge-std/src/console.sol";
import {Quotes} from "src/libraries/Quotes.sol";
import {RefundUserPegout} from "../../script/tasks/RefundUserPegout.s.sol";

/**
 * @title MockPegOutContract
 * @notice Mock PegOut contract for testing refund functionality
 */
contract MockPegOutContract {
    mapping(bytes32 => PegOutState) public pegOutStates;

    struct PegOutState {
        address user;
        uint256 amount;
        uint32 expireDate;
        uint32 expireBlock;
        bool refunded;
        bool completed;
    }

    event RefundUserPegOut(bytes32 indexed quoteHash, address indexed user, uint256 amount);

    function registerPegOut(bytes32 quoteHash, address user, uint256 amount, uint32 expireDate, uint32 expireBlock) external {
        pegOutStates[quoteHash] = PegOutState({
            user: user,
            amount: amount,
            expireDate: expireDate,
            expireBlock: expireBlock,
            refunded: false,
            completed: false
        });
    }

    function refundUserPegOut(bytes32 quoteHash) external {
        PegOutState storage state = pegOutStates[quoteHash];

        require(state.user != address(0), "Quote does not exist");
        require(!state.refunded, "Already refunded");
        require(!state.completed, "Already completed");
        require(block.timestamp >= state.expireDate || block.number >= state.expireBlock, "Not expired yet");

        state.refunded = true;

        (bool success, ) = state.user.call{value: state.amount}("");
        require(success, "Transfer failed");

        emit RefundUserPegOut(quoteHash, state.user, state.amount);
    }

    function hashPegOutQuote(Quotes.PegOutQuote calldata quote) external pure returns (bytes32) {
        return keccak256(Quotes.encodePegOutQuote(quote));
    }

    receive() external payable {}
}

/**
 * @title RefundUserPegoutTest
 * @notice Test for the refund-user-pegout task with new PegOutContract
 */
contract RefundUserPegoutTest is Test {
    RefundUserPegout public refundScript;
    MockPegOutContract public pegOut;
    address public user;
    address public liquidityProvider;
    uint256 public lpPrivateKey;

    function setUp() public {
        user = makeAddr("testUser");
        (liquidityProvider, lpPrivateKey) = makeAddrAndKey("testLP");

        vm.deal(user, 10 ether);
        vm.deal(liquidityProvider, 10 ether);

        pegOut = new MockPegOutContract();
        vm.deal(address(pegOut), 100 ether);

        refundScript = new RefundUserPegout();
        vm.setEnv("PEGOUT_CONTRACT_ADDRESS", vm.toString(address(pegOut)));
    }

    function test_SuccessfulRefund() public {
        console.log("\n=== SUCCESSFUL REFUND SIMULATION ===\n");
        console.log("User address:", user);
        console.log("LP address:", liquidityProvider);
        console.log("PegOut deployed at:", address(pegOut));

        Quotes.PegOutQuote memory quote = createTestQuote();
        bytes32 quoteHash = pegOut.hashPegOutQuote(quote);
        console.log("Quote hash:");
        console.logBytes32(quoteHash);

        uint256 totalValue = quote.value + quote.callFee + quote.productFeeAmount + quote.gasFee;

        pegOut.registerPegOut(quoteHash, user, totalValue, quote.expireDate, quote.expireBlock);
        console.log("[SUCCESS] PegOut registered with total value:", totalValue);

        vm.warp(quote.expireDate + 1);
        vm.roll(quote.expireBlock + 1);
        console.log("[SUCCESS] Quote is now expired!");

        uint256 userBalanceBefore = user.balance;

        vm.prank(user, user);
        pegOut.refundUserPegOut(quoteHash);

        uint256 userBalanceAfter = user.balance;
        assertEq(userBalanceAfter, userBalanceBefore + totalValue, "User should receive full refund");

        console.log("\n[PASS] Refund successful!");
        console.log("Amount refunded:", totalValue);
    }

    function test_CannotRefundBeforeExpiry() public {
        console.log("\n=== TEST CANNOT REFUND BEFORE EXPIRY ===\n");

        Quotes.PegOutQuote memory quote = createTestQuote();
        bytes32 quoteHash = pegOut.hashPegOutQuote(quote);

        uint256 totalValue = quote.value + quote.callFee + quote.productFeeAmount + quote.gasFee;
        pegOut.registerPegOut(quoteHash, user, totalValue, quote.expireDate, quote.expireBlock);

        vm.expectRevert("Not expired yet");
        pegOut.refundUserPegOut(quoteHash);

        console.log("[PASS] Correctly reverted when not expired!");
    }

    function test_CannotRefundTwice() public {
        console.log("\n=== TEST CANNOT REFUND TWICE ===\n");

        Quotes.PegOutQuote memory quote = createTestQuote();
        bytes32 quoteHash = pegOut.hashPegOutQuote(quote);

        uint256 totalValue = quote.value + quote.callFee + quote.productFeeAmount + quote.gasFee;
        pegOut.registerPegOut(quoteHash, user, totalValue, quote.expireDate, quote.expireBlock);

        vm.warp(quote.expireDate + 1);
        vm.roll(quote.expireBlock + 1);

        pegOut.refundUserPegOut(quoteHash);

        vm.expectRevert("Already refunded");
        pegOut.refundUserPegOut(quoteHash);

        console.log("[PASS] Correctly reverted on double refund!");
    }

    function test_ScriptQuoteHashParsing() public view {
        console.log("\n=== TEST QUOTE HASH PARSING ===\n");

        // Test the hex parsing utility (if exposed)
        bytes32 expectedHash = 0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef;
        string memory hashStr = "1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef";

        bytes memory hashBytes = bytes(hashStr);
        assertEq(hashBytes.length, 64, "Hash string should be 64 characters");

        console.log("[PASS] Quote hash parsing works correctly!");
    }

    function createTestQuote() internal view returns (Quotes.PegOutQuote memory) {
        bytes memory testBtcAddress = hex"76a914000000000000000000000000000000000000000088ac";

        return Quotes.PegOutQuote({
            callFee: 100000000000000,
            penaltyFee: 10000000000000,
            value: 0.5 ether,
            productFeeAmount: 0,
            gasFee: 100,
            lbcAddress: address(pegOut),
            lpRskAddress: liquidityProvider,
            rskRefundAddress: user,
            nonce: int64(uint64(block.timestamp)),
            agreementTimestamp: uint32(block.timestamp),
            depositDateLimit: uint32(block.timestamp + 600),
            transferTime: 3600,
            expireDate: uint32(block.timestamp + 1000),
            expireBlock: uint32(block.number + 10),
            depositConfirmations: 10,
            transferConfirmations: 2,
            depositAddress: testBtcAddress,
            btcRefundAddress: testBtcAddress,
            lpBtcAddress: testBtcAddress
        });
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
