// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import "lib/forge-std/src/Script.sol";
import "lib/forge-std/src/console.sol";
import {Quotes} from "src/libraries/Quotes.sol";
import {AddressResolver} from "../helpers/AddressResolver.sol";
import {HexUtils} from "../helpers/HexUtils.sol";
import {QuoteParser} from "../helpers/QuoteParser.sol";

interface IPegOut {
    function refundUserPegOut(bytes32 quoteHash) external;

    function hashPegOutQuote(
        Quotes.PegOutQuote calldata quote
    ) external view returns (bytes32);
}

/**
 * @title RefundUserPegout
 * @notice Foundry script to refund a user that didn't receive their PegOut in the agreed time
 * @dev This script calls refundUserPegOut on the PegOutContract
 *
 * ## Prerequisites
 * - PegOut contract address must be provided via PEGOUT_CONTRACT_ADDRESS env var or addresses.json
 * - Quote must be expired (both by timestamp and block number)
 * - Quote must exist and not be already completed
 *
 * ## Usage
 *
 *   # Simulate refund (dry-run)
 *   forge script script/tasks/RefundUserPegout.s.sol:RefundUserPegout \
 *     --sig "refundUserPegout(string)" <quote-hash> \
 *     --rpc-url <rpc-url>
 *
 *   # Execute refund (broadcast)
 *   forge script script/tasks/RefundUserPegout.s.sol:RefundUserPegout \
 *     --sig "refundUserPegout(string)" <quote-hash> \
 *     --rpc-url <rpc-url> \
 *     --broadcast \
 *     --private-key <private-key>
 *
 * ## Environment Variables
 * - PEGOUT_CONTRACT_ADDRESS: Address of PegOutContract
 * - NETWORK: Network name for addresses.json (default: rskRegtest)
 */
contract RefundUserPegout is Script, AddressResolver, QuoteParser {
    /**
     * @notice Refund a user PegOut transaction
     * @param quoteHashStr The hash of the accepted PegOut quote (hex string)
     */
    function refundUserPegout(string memory quoteHashStr) public {
        console.log("\n=== REFUND USER PEGOUT ===\n");

        bytes32 quoteHash = HexUtils.parseBytes32(quoteHashStr);
        console.log("Quote Hash:");
        console.logBytes32(quoteHash);

        address pegOutAddress = getPegOutAddress();
        console.log("\nPegOut Contract Address:");
        console.log(pegOutAddress);

        IPegOut pegOut = IPegOut(pegOutAddress);

        // Execute transaction (simulation happens automatically without --broadcast)
        console.log("\n--- Executing refund transaction ---\n");

        vm.startBroadcast();

        try pegOut.refundUserPegOut(quoteHash) {
            console.log("[SUCCESS] User PegOut refunded successfully!");
            console.log("\nRefunded quote:");
            console.logBytes32(quoteHash);
        } catch Error(string memory reason) {
            console.log("\n[FAILED] Transaction failed:");
            console.log(reason);
            console.log("\nPossible reasons:");
            console.log("  - Quote does not exist");
            console.log("  - Quote has not expired yet");
            console.log("  - Quote has already been refunded");
            revert(reason);
        }

        vm.stopBroadcast();

        console.log("\n=== REFUND COMPLETED ===\n");
    }

    /**
     * @notice Refund a user PegOut by reading quote from JSON file
     * @param jsonFilePath Path to the JSON file containing the pegout quote
     */
    function refundUserPegoutFromFile(string memory jsonFilePath) public {
        console.log("\n=== REFUND USER PEGOUT FROM FILE ===\n");
        console.log("Reading quote from file:", jsonFilePath);

        string memory json = vm.readFile(jsonFilePath);
        Quotes.PegOutQuote memory quote = parsePegOutQuote(json);

        address pegOutAddress = getPegOutAddress();
        IPegOut pegOut = IPegOut(pegOutAddress);

        bytes32 quoteHash = pegOut.hashPegOutQuote(quote);

        console.log("\nComputed Quote Hash:");
        console.logBytes32(quoteHash);
        console.log("\nPegOut Contract Address:");
        console.log(pegOutAddress);

        vm.startBroadcast();

        try pegOut.refundUserPegOut(quoteHash) {
            console.log("[SUCCESS] User PegOut refunded successfully!");
        } catch Error(string memory reason) {
            console.log("\n[FAILED] Transaction failed:");
            console.log(reason);
            revert(reason);
        }

        vm.stopBroadcast();

        console.log("\n=== REFUND COMPLETED ===\n");
    }
}
