// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import "lib/forge-std/src/Script.sol";
import "lib/forge-std/src/console.sol";
import {Quotes} from "src/libraries/Quotes.sol";
import {BtcAddressParser} from "../helpers/BtcAddressParser.sol";

interface IPegOut {
    function refundUserPegOut(bytes32 quoteHash) external;
    function hashPegOutQuote(Quotes.PegOutQuote calldata quote) external view returns (bytes32);
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
contract RefundUserPegout is Script, BtcAddressParser {

    /**
     * @notice Get PegOut contract address from environment or addresses.json
     */
    function getPegOutAddress() internal view returns (address) {
        try vm.envAddress("PEGOUT_CONTRACT_ADDRESS") returns (address addr) {
            if (addr != address(0)) {
                return addr;
            }
        } catch {}

        try vm.readFile("addresses.json") returns (string memory json) {
            string memory network = vm.envOr("NETWORK", string("rskRegtest"));
            string memory key = string.concat(".", network, ".PegOutContract.address");

            try vm.parseJsonAddress(json, key) returns (address addr) {
                if (addr != address(0)) {
                    return addr;
                }
            } catch {}
        } catch {}

        revert("Failed to find PegOutContract address. Set PEGOUT_CONTRACT_ADDRESS env var.");
    }

    /**
     * @notice Parse quote hash from string (with or without 0x prefix)
     */
    function parseQuoteHash(string memory quoteHashStr) internal pure returns (bytes32) {
        bytes memory hashBytes = bytes(quoteHashStr);

        uint startIndex = 0;
        if (hashBytes.length >= 2 && hashBytes[0] == "0" && (hashBytes[1] == "x" || hashBytes[1] == "X")) {
            startIndex = 2;
        }

        uint hexLength = hashBytes.length - startIndex;
        require(hexLength == 64, "Invalid quote hash length. Expected 64 hex characters.");

        bytes32 result;
        for (uint i = 0; i < 32; i++) {
            uint8 high = hexCharToByte(hashBytes[startIndex + i * 2]);
            uint8 low = hexCharToByte(hashBytes[startIndex + i * 2 + 1]);
            result |= bytes32(uint256(high * 16 + low)) << (248 - i * 8);
        }

        return result;
    }

    function hexCharToByte(bytes1 char) internal pure returns (uint8) {
        uint8 c = uint8(char);
        if (c >= 48 && c <= 57) return c - 48;
        if (c >= 65 && c <= 70) return c - 55;
        if (c >= 97 && c <= 102) return c - 87;
        revert("Invalid hex character");
    }

    /**
     * @notice Refund a user PegOut transaction
     * @param quoteHashStr The hash of the accepted PegOut quote (hex string)
     */
    function refundUserPegout(string memory quoteHashStr) public {
        console.log("\n=== REFUND USER PEGOUT ===\n");

        bytes32 quoteHash = parseQuoteHash(quoteHashStr);
        console.log("Quote Hash:");
        console.logBytes32(quoteHash);

        address pegOutAddress = getPegOutAddress();
        console.log("\nPegOut Contract Address:");
        console.log(pegOutAddress);

        IPegOut pegOut = IPegOut(pegOutAddress);

        // Estimate gas
        console.log("\nEstimating gas...");

        try pegOut.refundUserPegOut(quoteHash) {
            console.log("Gas estimation successful");
        } catch Error(string memory reason) {
            console.log("\n[ERROR] Transaction simulation failed:");
            console.log(reason);
            console.log("\nPossible reasons:");
            console.log("  - Quote does not exist");
            console.log("  - Quote has not expired yet");
            console.log("  - Quote has already been refunded");
            revert(reason);
        }

        // Execute transaction
        console.log("\n--- Executing refund transaction ---\n");

        vm.startBroadcast();

        try pegOut.refundUserPegOut(quoteHash) {
            console.log("[SUCCESS] User PegOut refunded successfully!");
            console.log("\nRefunded quote:");
            console.logBytes32(quoteHash);
        } catch Error(string memory reason) {
            console.log("\n[FAILED] Transaction failed:");
            console.log(reason);
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

        Quotes.PegOutQuote memory quote;

        quote.lbcAddress = vm.parseJsonAddress(json, ".lbcAddress");
        quote.lpRskAddress = vm.parseJsonAddress(json, ".liquidityProviderRskAddress");

        string memory btcRefundAddr = vm.parseJsonString(json, ".btcRefundAddress");
        quote.btcRefundAddress = parseBtcAddress(btcRefundAddr);

        quote.rskRefundAddress = vm.parseJsonAddress(json, ".rskRefundAddress");

        string memory lpBtcAddr = vm.parseJsonString(json, ".lpBtcAddr");
        quote.lpBtcAddress = parseBtcAddress(lpBtcAddr);

        quote.callFee = vm.parseJsonUint(json, ".callFee");
        quote.penaltyFee = vm.parseJsonUint(json, ".penaltyFee");

        try vm.parseJsonInt(json, ".nonce") returns (int256 nonceInt) {
            quote.nonce = int64(nonceInt);
        } catch {
            string memory nonceStr = vm.parseJsonString(json, ".nonce");
            quote.nonce = int64(uint64(vm.parseUint(nonceStr)));
        }

        string memory depositAddr = vm.parseJsonString(json, ".depositAddr");
        quote.depositAddress = parseBtcAddress(depositAddr);

        quote.value = vm.parseJsonUint(json, ".value");
        quote.agreementTimestamp = uint32(vm.parseJsonUint(json, ".agreementTimestamp"));
        quote.depositDateLimit = uint32(vm.parseJsonUint(json, ".depositDateLimit"));
        quote.transferTime = uint32(vm.parseJsonUint(json, ".transferTime"));
        quote.depositConfirmations = uint16(vm.parseJsonUint(json, ".depositConfirmations"));
        quote.transferConfirmations = uint16(vm.parseJsonUint(json, ".transferConfirmations"));
        quote.productFeeAmount = vm.parseJsonUint(json, ".productFeeAmount");
        quote.gasFee = vm.parseJsonUint(json, ".gasFee");
        quote.expireBlock = uint32(vm.parseJsonUint(json, ".expireBlocks"));
        quote.expireDate = uint32(vm.parseJsonUint(json, ".expireDate"));

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
