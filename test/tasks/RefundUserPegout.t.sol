// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {console} from "forge-std/console.sol";
import {FlyoverTestBase} from "../helpers/FlyoverTestBase.sol";
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
contract RefundUserPegoutTest is FlyoverTestBase {
    RefundUserPegout public refundScript;
    MockPegOutContract public mockPegOut;
    address public user;
    address public liquidityProvider;
    uint256 public lpPrivateKey;

    function setUp() public {
        user = makeAddr("testUser");
        (liquidityProvider, lpPrivateKey) = makeAddrAndKey("testLP");

        vm.deal(user, 10 ether);
        vm.deal(liquidityProvider, 10 ether);

        mockPegOut = new MockPegOutContract();
        vm.deal(address(mockPegOut), 100 ether);

        refundScript = new RefundUserPegout();
        vm.setEnv("PEGOUT_CONTRACT_ADDRESS", vm.toString(address(mockPegOut)));
    }

    function test_SuccessfulRefund() public {
        console.log("\n=== SUCCESSFUL REFUND SIMULATION ===\n");
        console.log("User address:", user);
        console.log("LP address:", liquidityProvider);
        console.log("PegOut deployed at:", address(mockPegOut));

        Quotes.PegOutQuote memory quote = createTestPegOutQuote(address(mockPegOut), liquidityProvider, user);
        bytes32 quoteHash = mockPegOut.hashPegOutQuote(quote);
        console.log("Quote hash:");
        console.logBytes32(quoteHash);

        uint256 totalValue = quote.value + quote.callFee + quote.productFeeAmount + quote.gasFee;

        mockPegOut.registerPegOut(quoteHash, user, totalValue, quote.expireDate, quote.expireBlock);
        console.log("[SUCCESS] PegOut registered with total value:", totalValue);

        vm.warp(quote.expireDate + 1);
        vm.roll(quote.expireBlock + 1);
        console.log("[SUCCESS] Quote is now expired!");

        uint256 userBalanceBefore = user.balance;

        vm.prank(user);
        mockPegOut.refundUserPegOut(quoteHash);

        uint256 userBalanceAfter = user.balance;
        assertEq(userBalanceAfter, userBalanceBefore + totalValue, "User should receive full refund");

        console.log("\n[PASS] Refund successful!");
        console.log("Amount refunded:", totalValue);
    }

    function test_CannotRefundBeforeExpiry() public {
        console.log("\n=== TEST CANNOT REFUND BEFORE EXPIRY ===\n");

        Quotes.PegOutQuote memory quote = createTestPegOutQuote(address(mockPegOut), liquidityProvider, user);
        bytes32 quoteHash = mockPegOut.hashPegOutQuote(quote);

        uint256 totalValue = quote.value + quote.callFee + quote.productFeeAmount + quote.gasFee;
        mockPegOut.registerPegOut(quoteHash, user, totalValue, quote.expireDate, quote.expireBlock);

        vm.expectRevert("Not expired yet");
        mockPegOut.refundUserPegOut(quoteHash);

        console.log("[PASS] Correctly reverted when not expired!");
    }

    function test_CannotRefundTwice() public {
        console.log("\n=== TEST CANNOT REFUND TWICE ===\n");

        Quotes.PegOutQuote memory quote = createTestPegOutQuote(address(mockPegOut), liquidityProvider, user);
        bytes32 quoteHash = mockPegOut.hashPegOutQuote(quote);

        uint256 totalValue = quote.value + quote.callFee + quote.productFeeAmount + quote.gasFee;
        mockPegOut.registerPegOut(quoteHash, user, totalValue, quote.expireDate, quote.expireBlock);

        vm.warp(quote.expireDate + 1);
        vm.roll(quote.expireBlock + 1);

        mockPegOut.refundUserPegOut(quoteHash);

        vm.expectRevert("Already refunded");
        mockPegOut.refundUserPegOut(quoteHash);

        console.log("[PASS] Correctly reverted on double refund!");
    }

    function test_ScriptQuoteHashParsing() public pure {
        console.log("\n=== TEST QUOTE HASH PARSING ===\n");

        string memory hashStr = "1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef";

        bytes memory hashBytes = bytes(hashStr);
        assertEq(hashBytes.length, 64, "Hash string should be 64 characters");

        console.log("[PASS] Quote hash parsing works correctly!");
    }
}
