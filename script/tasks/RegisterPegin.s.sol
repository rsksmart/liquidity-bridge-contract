// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import "lib/forge-std/src/Script.sol";
import "lib/forge-std/src/console.sol";
import {Quotes} from "src/libraries/Quotes.sol";
import {AddressResolver} from "../helpers/AddressResolver.sol";
import {HexUtils} from "../helpers/HexUtils.sol";
import {QuoteParser} from "../helpers/QuoteParser.sol";

interface IPegIn {
    function registerPegIn(
        Quotes.PegInQuote calldata quote,
        bytes calldata signature,
        bytes calldata btcRawTransaction,
        bytes calldata partialMerkleTree,
        uint256 height
    ) external returns (int256);

    function hashPegInQuote(Quotes.PegInQuote calldata quote) external view returns (bytes32);
}

/**
 * @title RegisterPegin
 * @notice Foundry script to register a PegIn bitcoin transaction with the PegInContract
 * @dev Uses FFI to fetch Bitcoin transaction data from mempool.space
 *
 * ## Prerequisites
 * - FFI must be enabled in foundry.toml (ffi = true)
 * - Node.js and npm packages must be installed
 * - PegIn contract address must be provided via PEGIN_CONTRACT_ADDRESS env var or addresses.json
 * - Bitcoin transaction must be confirmed on the network
 *
 * ## Usage
 *
 *   # Simulation
 *   forge script script/tasks/RegisterPegin.s.sol:RegisterPegin \
 *     --sig "registerPegin(string,string,string)" \
 *     <quote-json-file> <signature> <bitcoin-txid> \
 *     --rpc-url <rpc-url> \
 *     --ffi
 *
 *   # Broadcast
 *   forge script script/tasks/RegisterPegin.s.sol:RegisterPegin \
 *     --sig "registerPegin(string,string,string)" \
 *     <quote-json-file> <signature> <bitcoin-txid> \
 *     --rpc-url <rpc-url> \
 *     --ffi \
 *     --broadcast \
 *     --private-key <private-key>
 *
 * ## Environment Variables
 * - PEGIN_CONTRACT_ADDRESS: Address of PegInContract
 * - NETWORK: Network name for addresses.json (default: rskRegtest)
 * - BTC_NETWORK: Bitcoin network (mainnet or testnet)
 */
contract RegisterPegin is Script, AddressResolver, QuoteParser {
    string constant HELPER_SCRIPT_FETCH_TX = "script/helpers/fetch-btc-tx-data.ts";

    /**
     * @notice Fetch Bitcoin transaction data using FFI helper script
     */
    function fetchBtcTxData(
        string memory txId,
        string memory btcNetwork
    ) internal returns (bytes memory rawTx, bytes memory pmt, uint256 height) {
        string[] memory inputs = new string[](5);
        inputs[0] = "npx";
        inputs[1] = "ts-node";
        inputs[2] = HELPER_SCRIPT_FETCH_TX;
        inputs[3] = txId;
        inputs[4] = btcNetwork;

        bytes memory result = vm.ffi(inputs);
        string memory json = string(result);

        rawTx = vm.parseJsonBytes(json, ".rawTx");
        pmt = vm.parseJsonBytes(json, ".pmt");
        height = vm.parseJsonUint(json, ".height");

        console.log("Bitcoin transaction data fetched:");
        console.log("  Block height:", height);
        console.log("  Raw TX length:", rawTx.length);
        console.log("  PMT length:", pmt.length);
    }

    /**
     * @notice Determine Bitcoin network based on RSK network
     */
    function getBtcNetwork() internal view returns (string memory) {
        try vm.envString("BTC_NETWORK") returns (string memory btcNet) {
            if (bytes(btcNet).length > 0) {
                return btcNet;
            }
        } catch {}

        string memory network = vm.envOr("NETWORK", string("rskRegtest"));

        if (keccak256(bytes(network)) == keccak256(bytes("rskMainnet"))) {
            return "mainnet";
        }

        return "testnet";
    }

    /**
     * @notice Register a PegIn transaction
     * @param quoteFilePath Path to the JSON file containing the PegIn quote
     * @param signatureHex The signature from the LP (with or without 0x prefix)
     * @param txId The Bitcoin transaction ID
     */
    function registerPegin(
        string memory quoteFilePath,
        string memory signatureHex,
        string memory txId
    ) public {
        console.log("\n=== REGISTER PEGIN ===\n");

        console.log("Reading quote from file:", quoteFilePath);
        string memory json = vm.readFile(quoteFilePath);
        Quotes.PegInQuote memory quote = parsePegInQuote(json);

        address pegInAddress = getPegInAddress();
        console.log("PegIn Contract Address:", pegInAddress);
        IPegIn pegIn = IPegIn(pegInAddress);

        bytes32 quoteHash = pegIn.hashPegInQuote(quote);
        console.log("\nQuote Hash:");
        console.logBytes32(quoteHash);

        bytes memory signature = parseSignature(signatureHex);
        console.log("Signature length:", signature.length);

        console.log("\nFetching Bitcoin transaction data...");
        console.log("  TX ID:", txId);
        string memory btcNetwork = getBtcNetwork();
        console.log("  BTC Network:", btcNetwork);

        (bytes memory rawTx, bytes memory pmt, uint256 height) = fetchBtcTxData(txId, btcNetwork);

        console.log("\n--- Executing registration transaction ---\n");

        vm.startBroadcast();

        try pegIn.registerPegIn(quote, signature, rawTx, pmt, height) returns (int256 result) {
            console.log("[SUCCESS] PegIn registered successfully!");
            console.log("Result code:", vm.toString(result));
            console.log("Quote hash:");
            console.logBytes32(quoteHash);
        } catch Error(string memory reason) {
            console.log("\n[FAILED] Transaction failed:");
            console.log(reason);
            revert(reason);
        }

        vm.stopBroadcast();

        console.log("\n=== REGISTRATION COMPLETED ===\n");
    }

    /**
     * @notice Parse signature from hex string
     * @param sigHex The hex string (with or without 0x prefix)
     * @return The parsed signature bytes
     */
    function parseSignature(string memory sigHex) public pure returns (bytes memory) {
        return HexUtils.parseBytes(sigHex);
    }
}
