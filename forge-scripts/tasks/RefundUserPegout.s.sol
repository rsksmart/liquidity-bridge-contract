// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import "lib/forge-std/src/Script.sol";
import "lib/forge-std/src/console.sol";
import {QuotesV2} from "contracts/legacy/QuotesV2.sol";

interface ILiquidityBridgeContract {
    function refundUserPegOut(bytes32 quoteHash) external;

    function hashPegoutQuote(
        QuotesV2.PegOutQuote memory quote
    ) external view returns (bytes32);
}

/**
 * @title RefundUserPegout
 * @notice Foundry script to refund a user that didn't receive their PegOut in the agreed time
 * @dev This script calls refundUserPegOut on the LiquidityBridgeContract
 *
 * ## Prerequisites
 * - LBC contract address must be provided via LBC_ADDRESS env var or addresses.json
 * - Quote must be expired (both by timestamp and block number)
 * - Quote must exist and not be already completed
 *
 * ## Usage
 *
 * ### Method 1: Using the wrapper script (recommended)
 *   # Simulate refund (check gas estimation and validation)
 *   ./forge-scripts/tasks/refund-user-pegout.sh --quote-hash <hash> --network rskTestnet
 *
 *   # Execute refund (broadcast transaction)
 *   ./forge-scripts/tasks/refund-user-pegout.sh --quote-hash <hash> --network rskTestnet --broadcast --private-key <key>
 *
 * ### Method 2: Direct forge script invocation
 *   # Simulation (dry-run with gas estimation)
 *   forge script forge-scripts/tasks/RefundUserPegout.s.sol:RefundUserPegout \
 *     --sig "refundUserPegout(string)" <quote-hash-without-0x> \
 *     --rpc-url <rpc-url>
 *
 *   # Broadcast (execute transaction)
 *   forge script forge-scripts/tasks/RefundUserPegout.s.sol:RefundUserPegout \
 *     --sig "refundUserPegout(string)" <quote-hash-without-0x> \
 *     --rpc-url <rpc-url> \
 *     --broadcast \
 *     --private-key <private-key>
 *
 * ## Environment Variables
 * - LBC_ADDRESS: Address of the LiquidityBridgeContract (optional if addresses.json is configured)
 * - NETWORK: Network name to use when reading from addresses.json (default: rskRegtest)
 *
 * ## Private Key Options (in order of precedence)
 * 1. --private-key <key>: Direct private key
 * 2. --ledger: Use hardware wallet
 * 3. --interactive: Interactive keystore
 *
 * ## Examples
 *   # Simulate refund on testnet
 *   ./forge-scripts/tasks/refund-user-pegout.sh \
 *     --quote-hash abc123... \
 *     --network rskTestnet
 *
 *   # Execute refund on testnet with private key
 *   ./forge-scripts/tasks/refund-user-pegout.sh \
 *     --quote-hash abc123... \
 *     --network rskTestnet \
 *     --broadcast \
 *     --private-key $TESTNET_PRIVATE_KEY
 *
 *   # Execute refund on mainnet with ledger (most secure)
 *   ./forge-scripts/tasks/refund-user-pegout.sh \
 *     --quote-hash abc123... \
 *     --network rskMainnet \
 *     --broadcast \
 *     --ledger
 */
contract RefundUserPegout is Script {
    string constant HELPER_SCRIPT =
        "forge-scripts/helpers/parse-btc-address.js";

    /**
     * @notice Parse Bitcoin address using FFI helper script
     * @param btcAddress The Bitcoin address string to parse
     * @return The decoded address as bytes
     */
    function parseBtcAddress(
        string memory btcAddress
    ) internal returns (bytes memory) {
        string[] memory inputs = new string[](3);
        inputs[0] = "node";
        inputs[1] = HELPER_SCRIPT;
        inputs[2] = btcAddress;

        bytes memory result = vm.ffi(inputs);
        return result;
    }

    /**
     * @notice Get LBC address from deployment config or environment variable
     * @return The LBC contract address
     */
    function getLbcAddress() internal view returns (address) {
        // First try environment variable
        try vm.envAddress("LBC_ADDRESS") returns (address addr) {
            if (addr != address(0)) {
                return addr;
            }
        } catch {}

        // Try to read from addresses.json
        try vm.readFile("addresses.json") returns (string memory json) {
            // Get network from environment or default to rskRegtest
            string memory network = vm.envOr("NETWORK", string("rskRegtest"));
            string memory key = string.concat(
                ".",
                network,
                ".LiquidityBridgeContract.address"
            );

            try vm.parseJsonAddress(json, key) returns (address addr) {
                if (addr != address(0)) {
                    return addr;
                }
            } catch {}

            // Try proxy address as fallback
            string memory proxyKey = string.concat(
                ".",
                network,
                ".LiquidityBridgeContractProxy.address"
            );
            try vm.parseJsonAddress(json, proxyKey) returns (
                address proxyAddr
            ) {
                if (proxyAddr != address(0)) {
                    return proxyAddr;
                }
            } catch {}
        } catch {}

        revert(
            "Failed to find LBC address. Set LBC_ADDRESS env var or ensure addresses.json is configured."
        );
    }

    /**
     * @notice Parse quote hash from string (with or without 0x prefix)
     * @param quoteHashStr The quote hash as a string
     * @return The quote hash as bytes32
     */
    function parseQuoteHash(
        string memory quoteHashStr
    ) internal pure returns (bytes32) {
        bytes memory hashBytes = bytes(quoteHashStr);

        // Check if string starts with "0x" and remove it
        uint startIndex = 0;
        if (
            hashBytes.length >= 2 &&
            hashBytes[0] == "0" &&
            (hashBytes[1] == "x" || hashBytes[1] == "X")
        ) {
            startIndex = 2;
        }

        // Calculate expected length (64 hex chars = 32 bytes)
        uint hexLength = hashBytes.length - startIndex;
        require(
            hexLength == 64,
            "Invalid quote hash length. Expected 64 hex characters (32 bytes)."
        );

        // Convert hex string to bytes32
        bytes32 result;
        for (uint i = 0; i < 32; i++) {
            uint8 high = hexCharToByte(hashBytes[startIndex + i * 2]);
            uint8 low = hexCharToByte(hashBytes[startIndex + i * 2 + 1]);
            result |= bytes32(uint256(high * 16 + low)) << (248 - i * 8);
        }

        return result;
    }

    /**
     * @notice Convert a hex character to its byte value
     * @param char The hex character
     * @return The byte value (0-15)
     */
    function hexCharToByte(bytes1 char) internal pure returns (uint8) {
        uint8 c = uint8(char);
        if (c >= 48 && c <= 57) return c - 48; // 0-9
        if (c >= 65 && c <= 70) return c - 55; // A-F
        if (c >= 97 && c <= 102) return c - 87; // a-f
        revert("Invalid hex character");
    }

    /**
     * @notice Refund a user PegOut transaction
     * @param quoteHashStr The hash of the accepted PegOut quote (as hex string, with or without 0x prefix)
     */
    function refundUserPegout(string memory quoteHashStr) public {
        console.log("\n=== REFUND USER PEGOUT ===\n");

        // Parse quote hash
        bytes32 quoteHash = parseQuoteHash(quoteHashStr);
        console.log("Quote Hash:");
        console.logBytes32(quoteHash);

        // Get LBC contract address
        address lbcAddress = getLbcAddress();
        console.log("\nLBC Contract Address:");
        console.log(lbcAddress);

        ILiquidityBridgeContract lbc = ILiquidityBridgeContract(lbcAddress);

        // Estimate gas
        console.log("\nEstimating gas...");
        uint256 gasEstimate = 0;

        // Get the sender address for gas estimation
        address sender = msg.sender;
        if (vm.envOr("BROADCAST", false)) {
            try vm.envAddress("SENDER") returns (address envSender) {
                sender = envSender;
            } catch {
                // Use default from private key if available
                sender = vm.addr(vm.envUint("PRIVATE_KEY"));
            }
        }

        // Estimate gas by simulating the call
        vm.prank(sender);
        try lbc.refundUserPegOut(quoteHash) {
            // If we get here in simulation, estimate around 100k gas as a safe estimate
            gasEstimate = 100000;
            console.log("Gas estimation (approximate):", gasEstimate);
        } catch Error(string memory reason) {
            console.log("\n[ERROR] Transaction simulation failed:");
            console.log(reason);
            console.log("\nPossible reasons:");
            console.log("  - Quote does not exist (LBC042)");
            console.log("  - Quote has not expired yet (LBC041)");
            console.log("  - Quote has already been refunded");
            console.log("\nAborting transaction.");
            revert(reason);
        } catch (bytes memory lowLevelError) {
            console.log(
                "\n[ERROR] Transaction simulation failed with low-level error"
            );
            console.logBytes(lowLevelError);
            revert("Transaction simulation failed");
        }

        // Execute transaction if not in view mode
        console.log("\n--- Executing refund transaction ---\n");

        vm.startBroadcast();

        try lbc.refundUserPegOut(quoteHash) {
            console.log("[SUCCESS] User PegOut refunded successfully!");
            console.log("\nTransaction will refund the user for quote:");
            console.logBytes32(quoteHash);
        } catch Error(string memory reason) {
            console.log("\n[FAILED] Transaction failed:");
            console.log(reason);
            revert(reason);
        } catch (bytes memory lowLevelError) {
            console.log("\n[FAILED] Transaction failed with low-level error");
            console.logBytes(lowLevelError);
            revert("Transaction failed");
        }

        vm.stopBroadcast();

        console.log("\n=== REFUND COMPLETED ===\n");
    }

    /**
     * @notice Refund a user PegOut transaction by reading quote from JSON file
     * @param jsonFilePath Path to the JSON file containing the pegout quote
     */
    function refundUserPegoutFromFile(string memory jsonFilePath) public {
        console.log("\n=== REFUND USER PEGOUT FROM FILE ===\n");
        console.log("Reading quote from file:", jsonFilePath);

        // Read JSON file
        string memory json = vm.readFile(jsonFilePath);

        // Parse PegOut quote fields from JSON
        QuotesV2.PegOutQuote memory quote;

        // Parse addresses
        quote.lbcAddress = vm.parseJsonAddress(json, ".lbcAddress");
        quote.lpRskAddress = vm.parseJsonAddress(
            json,
            ".liquidityProviderRskAddress"
        );

        string memory btcRefundAddr = vm.parseJsonString(
            json,
            ".btcRefundAddress"
        );
        quote.btcRefundAddress = parseBtcAddress(btcRefundAddr);

        quote.rskRefundAddress = vm.parseJsonAddress(json, ".rskRefundAddress");

        string memory lpBtcAddr = vm.parseJsonString(json, ".lpBtcAddr");
        quote.lpBtcAddress = parseBtcAddress(lpBtcAddr);

        // Parse numeric fields
        quote.callFee = vm.parseJsonUint(json, ".callFee");
        quote.penaltyFee = vm.parseJsonUint(json, ".penaltyFee");

        // Parse nonce - handle both string and number formats
        try vm.parseJsonInt(json, ".nonce") returns (int256 nonceInt) {
            quote.nonce = int64(nonceInt);
        } catch {
            string memory nonceStr = vm.parseJsonString(json, ".nonce");
            quote.nonce = int64(uint64(vm.parseUint(nonceStr)));
        }

        string memory depositAddr = vm.parseJsonString(json, ".depositAddr");
        quote.deposityAddress = parseBtcAddress(depositAddr);

        quote.value = vm.parseJsonUint(json, ".value");
        quote.agreementTimestamp = uint32(
            vm.parseJsonUint(json, ".agreementTimestamp")
        );
        quote.depositDateLimit = uint32(
            vm.parseJsonUint(json, ".depositDateLimit")
        );
        quote.transferTime = uint32(vm.parseJsonUint(json, ".transferTime"));
        quote.depositConfirmations = uint16(
            vm.parseJsonUint(json, ".depositConfirmations")
        );
        quote.transferConfirmations = uint16(
            vm.parseJsonUint(json, ".transferConfirmations")
        );
        quote.productFeeAmount = vm.parseJsonUint(json, ".productFeeAmount");
        quote.gasFee = vm.parseJsonUint(json, ".gasFee");
        quote.expireBlock = uint32(vm.parseJsonUint(json, ".expireBlocks"));
        quote.expireDate = uint32(vm.parseJsonUint(json, ".expireDate"));

        // Get LBC contract and hash the quote
        address lbcAddress = getLbcAddress();
        ILiquidityBridgeContract lbc = ILiquidityBridgeContract(lbcAddress);

        bytes32 quoteHash = lbc.hashPegoutQuote(quote);

        console.log("\nComputed Quote Hash:");
        console.logBytes32(quoteHash);
        console.log("\nLBC Contract Address:");
        console.log(lbcAddress);

        // Estimate gas
        console.log("\nEstimating gas...");
        uint256 gasEstimate = 0;

        // Get the sender address for gas estimation
        address sender = msg.sender;
        if (vm.envOr("BROADCAST", false)) {
            try vm.envAddress("SENDER") returns (address envSender) {
                sender = envSender;
            } catch {
                // Use default from private key if available
                sender = vm.addr(vm.envUint("PRIVATE_KEY"));
            }
        }

        // Estimate gas by simulating the call
        vm.prank(sender);
        try lbc.refundUserPegOut(quoteHash) {
            gasEstimate = 100000;
            console.log("Gas estimation (approximate):", gasEstimate);
        } catch Error(string memory reason) {
            console.log("\n[ERROR] Transaction simulation failed:");
            console.log(reason);
            console.log("\nPossible reasons:");
            console.log("  - Quote does not exist (LBC042)");
            console.log("  - Quote has not expired yet (LBC041)");
            console.log("  - Quote has already been refunded");
            console.log("\nAborting transaction.");
            revert(reason);
        } catch (bytes memory lowLevelError) {
            console.log(
                "\n[ERROR] Transaction simulation failed with low-level error"
            );
            console.logBytes(lowLevelError);
            revert("Transaction simulation failed");
        }

        // Execute transaction if not in view mode
        console.log("\n--- Executing refund transaction ---\n");

        vm.startBroadcast();

        try lbc.refundUserPegOut(quoteHash) {
            console.log("[SUCCESS] User PegOut refunded successfully!");
            console.log("\nTransaction will refund the user for quote:");
            console.logBytes32(quoteHash);
        } catch Error(string memory reason) {
            console.log("\n[FAILED] Transaction failed:");
            console.log(reason);
            revert(reason);
        } catch (bytes memory lowLevelError) {
            console.log("\n[FAILED] Transaction failed with low-level error");
            console.logBytes(lowLevelError);
            revert("Transaction failed");
        }

        vm.stopBroadcast();

        console.log("\n=== REFUND COMPLETED ===\n");
    }

    /**
     * @notice Refund a user PegOut transaction (test-friendly version without broadcast)
     * @param quoteHashStr The hash of the accepted PegOut quote (as hex string, with or without 0x prefix)
     * @dev This version is meant for testing - it doesn't use vm.startBroadcast
     */
    function refundUserPegoutTest(string memory quoteHashStr) public {
        console.log("\n=== REFUND USER PEGOUT (TEST) ===\n");

        // Parse quote hash
        bytes32 quoteHash = parseQuoteHash(quoteHashStr);
        console.log("Quote Hash:");
        console.logBytes32(quoteHash);

        // Get LBC contract address
        address lbcAddress = getLbcAddress();
        console.log("\nLBC Contract Address:");
        console.log(lbcAddress);

        ILiquidityBridgeContract lbc = ILiquidityBridgeContract(lbcAddress);

        // Estimate gas
        console.log("\nEstimating gas...");

        // Execute refund directly (without broadcast for testing)
        try lbc.refundUserPegOut(quoteHash) {
            console.log("[SUCCESS] User PegOut refunded successfully!");
            console.log("\nTransaction refunded the user for quote:");
            console.logBytes32(quoteHash);
        } catch Error(string memory reason) {
            console.log("\n[FAILED] Transaction failed:");
            console.log(reason);
            revert(reason);
        } catch (bytes memory lowLevelError) {
            console.log("\n[FAILED] Transaction failed with low-level error");
            console.logBytes(lowLevelError);
            revert("Transaction failed");
        }

        console.log("\n=== REFUND COMPLETED ===\n");
    }
}
