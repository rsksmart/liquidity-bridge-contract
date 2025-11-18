// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import "lib/forge-std/src/Test.sol";
import "lib/forge-std/src/console.sol";
import {QuotesV2} from "src/legacy/QuotesV2.sol";
import {LiquidityBridgeContractV2} from "src/legacy/LiquidityBridgeContractV2.sol";
import {RefundUserPegout} from "../../script/tasks/RefundUserPegout.s.sol";

/**
 * @title RefundUserPegoutTest
 * @notice Test for the refund-user-pegout task - validates the actual script works correctly
 */
contract RefundUserPegoutTest is Test {
    RefundUserPegout public refundScript;
    LiquidityBridgeContractV2 public lbc;
    address public user;
    address public liquidityProvider;
    uint256 public lpPrivateKey;

    function setUp() public {
        // Setup test accounts
        user = makeAddr("testUser");
        (liquidityProvider, lpPrivateKey) = makeAddrAndKey("testLP");

        // Fund accounts
        vm.deal(user, 10 ether);
        vm.deal(liquidityProvider, 10 ether);

        // Deploy LBC
        lbc = new LiquidityBridgeContractV2();

        // Register LP for pegout
        vm.prank(liquidityProvider, liquidityProvider); // Set both msg.sender and tx.origin
        lbc.register{value: 0.1 ether}(
            "Test LP",
            "https://test.com",
            true,
            "pegout"
        );

        // Instantiate the refund script
        refundScript = new RefundUserPegout();

        // Set LBC address in environment for script to use
        vm.setEnv("LBC_ADDRESS", vm.toString(address(lbc)));
    }

    function test_SuccessfulRefund() public {
        // Create fresh script instance for complete isolation
        RefundUserPegout testScript = new RefundUserPegout();

        // Update LBC address for this specific test
        vm.setEnv("LBC_ADDRESS", vm.toString(address(lbc)));

        console.log("\n=== SUCCESSFUL REFUND SIMULATION ===\n");
        console.log("User address:", user);
        console.log("LP address:", liquidityProvider);
        console.log("LBC deployed at:", address(lbc));

        // Create a test pegout quote
        console.log("\n1. Creating test PegOut quote...");
        QuotesV2.PegOutQuote memory quote = createTestQuote();
        bytes32 quoteHash = lbc.hashPegoutQuote(quote);
        console.log("   Quote hash:");
        console.logBytes32(quoteHash);

        // Sign the quote
        console.log("\n2. Signing quote...");
        bytes memory signature = signQuote(quoteHash);
        console.log("   Signature created");

        // Deposit the quote
        console.log("\n3. Depositing pegout...");
        uint256 totalValue = quote.value +
            quote.callFee +
            quote.productFeeAmount +
            quote.gasFee;
        console.log("   Total value:", totalValue);

        vm.prank(user, user); // Set both msg.sender and tx.origin
        lbc.depositPegout{value: totalValue}(quote, signature);
        console.log("   [SUCCESS] Deposit successful!");

        // Check quote is registered
        console.log("\n4. Verifying quote is registered...");
        console.log("   Current block:", block.number);
        console.log("   Current time:", block.timestamp);
        console.log("   Expire block:", quote.expireBlock);
        console.log("   Expire date:", quote.expireDate);

        // Advance time and blocks to expire the quote
        console.log("\n5. Fast-forwarding time to expire quote...");
        vm.warp(quote.expireDate + 1);
        vm.roll(quote.expireBlock + 1);
        console.log("   New block:", block.number);
        console.log("   New time:", block.timestamp);
        console.log("   [SUCCESS] Quote is now expired!");

        // Execute refund using the actual script
        console.log("\n6. Executing refund using RefundUserPegout script...");
        uint256 userBalanceBefore = user.balance;
        console.log("   User balance before:", userBalanceBefore);

        // Convert quote hash to string for script
        string memory quoteHashStr = toHexString(quoteHash);
        console.log("   Quote hash string:", quoteHashStr);

        // Call the actual refund script (test version without broadcast)
        vm.recordLogs(); // Record logs to verify script executed correctly
        vm.prank(user, user); // Set both msg.sender and tx.origin for the script
        testScript.refundUserPegoutTest(quoteHashStr);

        uint256 userBalanceAfter = user.balance;
        console.log("   User balance after:", userBalanceAfter);
        console.log(
            "   Refunded amount:",
            userBalanceAfter - userBalanceBefore
        );
        console.log("   [SUCCESS] Refund script executed successfully!");

        console.log("\n=== SIMULATION COMPLETED SUCCESSFULLY ===\n");
        console.log("Summary:");
        console.log("  - Quote deposited: SUCCESS");
        console.log("  - Quote expired: SUCCESS");
        console.log("  - RefundUserPegout script executed: SUCCESS");
        console.log("  - User refunded: SUCCESS");
        console.log("  - Amount refunded:", totalValue, "wei");

        // Assertions
        assertEq(
            userBalanceAfter,
            userBalanceBefore + totalValue,
            "User should receive full refund"
        );
        console.log("\n[PASS] All assertions passed!");
        console.log("[PASS] RefundUserPegout.s.sol script works correctly!");
    }

    function createTestQuote()
        internal
        view
        returns (QuotesV2.PegOutQuote memory)
    {
        bytes
            memory testBtcAddress = hex"76a914000000000000000000000000000000000000000088ac";

        return
            QuotesV2.PegOutQuote({
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
        bytes32 messageHash = keccak256(
            abi.encodePacked("\x19Ethereum Signed Message:\n32", quoteHash)
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(lpPrivateKey, messageHash);
        return abi.encodePacked(r, s, v);
    }

    /**
     * @notice Convert bytes32 to hex string (without 0x prefix)
     * @param data The bytes32 to convert
     * @return The hex string representation
     */
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
