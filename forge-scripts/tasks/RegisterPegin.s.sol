// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import "lib/forge-std/src/Script.sol";
import "lib/forge-std/src/console.sol";
import {QuotesV2} from "contracts/legacy/QuotesV2.sol";

interface ILiquidityBridgeContract {
    function registerPegIn(
        QuotesV2.PeginQuote memory quote,
        bytes memory signature,
        bytes memory rawTx,
        bytes memory pmt,
        uint256 height
    ) external returns (int256);

    function hashQuote(
        QuotesV2.PeginQuote memory quote
    ) external view returns (bytes32);
}

/**
 * @title RegisterPegin
 * @notice Foundry script to register a PegIn bitcoin transaction within the Liquidity Bridge Contract
 * @dev This script uses FFI to fetch Bitcoin transaction data from mempool.space
 *
 * ## Prerequisites
 * - FFI must be enabled in foundry.toml (ffi = true)
 * - Node.js and npm packages must be installed (mempool.js, bitcoinjs-lib, pmt-builder)
 * - LBC contract address must be provided via LBC_ADDRESS env var or addresses.json
 * - Bitcoin transaction must be confirmed on the network
 *
 * ## Usage
 *
 * ### Method 1: Using the wrapper script (recommended)
 *   # Simulate registration (dry-run with gas estimation)
 *   ./forge-scripts/tasks/register-pegin.sh \
 *     --file forge-scripts/tasks/hash-quote.example.json \
 *     --signature <lp-signature> \
 *     --txid <bitcoin-txid> \
 *     --network rskTestnet
 *
 *   # Execute registration (broadcast transaction)
 *   ./forge-scripts/tasks/register-pegin.sh \
 *     --file forge-scripts/tasks/hash-quote.example.json \
 *     --signature <lp-signature> \
 *     --txid <bitcoin-txid> \
 *     --network rskTestnet \
 *     --broadcast \
 *     --private-key <key>
 *
 * ### Method 2: Direct forge script invocation
 *   # Simulation
 *   forge script forge-scripts/tasks/RegisterPegin.s.sol:RegisterPegin \
 *     --sig "registerPegin(string,string,string)" \
 *     <quote-json-file> <signature> <bitcoin-txid> \
 *     --rpc-url <rpc-url> \
 *     --ffi
 *
 *   # Broadcast
 *   forge script forge-scripts/tasks/RegisterPegin.s.sol:RegisterPegin \
 *     --sig "registerPegin(string,string,string)" \
 *     <quote-json-file> <signature> <bitcoin-txid> \
 *     --rpc-url <rpc-url> \
 *     --ffi \
 *     --broadcast \
 *     --private-key <private-key>
 *
 * ## Environment Variables
 * - LBC_ADDRESS: Address of the LiquidityBridgeContract (optional if addresses.json is configured)
 * - NETWORK: Network name to use when reading from addresses.json (default: rskRegtest)
 * - BTC_NETWORK: Bitcoin network (mainnet or testnet, auto-detected from NETWORK if not set)
 *
 * ## Examples
 *   ./forge-scripts/tasks/register-pegin.sh \
 *     --file forge-scripts/tasks/hash-quote.example.json \
 *     --signature 0xabcd1234... \
 *     --txid a1b2c3d4... \
 *     --network rskTestnet \
 *     --broadcast \
 *     --private-key $TESTNET_PRIVATE_KEY
 */
import {BtcAddressParser} from "../helpers/BtcAddressParser.sol";

contract RegisterPegin is Script, BtcAddressParser {
    string constant HELPER_SCRIPT_FETCH_TX =
        "forge-scripts/helpers/fetch-btc-tx-data.ts";

    /**
     * @notice Fetch Bitcoin transaction data using FFI helper script
     * @param txId The Bitcoin transaction ID
     * @param btcNetwork The Bitcoin network (mainnet or testnet)
     * @return rawTx The raw transaction hex
     * @return pmt The partial merkle tree hex
     * @return height The block height
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

        // Parse JSON response
        rawTx = vm.parseJsonBytes(json, ".rawTx");
        pmt = vm.parseJsonBytes(json, ".pmt");
        height = vm.parseJsonUint(json, ".height");

        console.log("Bitcoin transaction data fetched:");
        console.log("  Block height:", height);
        console.log("  Raw TX length:", rawTx.length);
        console.log("  PMT length:", pmt.length);
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
     * @notice Determine Bitcoin network based on RSK network
     * @return Bitcoin network name (mainnet or testnet)
     */
    function getBtcNetwork() internal view returns (string memory) {
        // Check if explicitly set
        try vm.envString("BTC_NETWORK") returns (string memory btcNet) {
            if (bytes(btcNet).length > 0) {
                return btcNet;
            }
        } catch {}

        // Auto-detect from RSK network
        string memory network = vm.envOr("NETWORK", string("rskRegtest"));

        if (keccak256(bytes(network)) == keccak256(bytes("rskMainnet"))) {
            return "mainnet";
        }

        // Default to testnet for all other networks (rskTestnet, rskRegtest, etc.)
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

        // Read and parse quote file
        console.log("Reading quote from file:", quoteFilePath);
        string memory json = vm.readFile(quoteFilePath);
        QuotesV2.PeginQuote memory quote = parsePeginQuote(json);

        // Get LBC contract
        address lbcAddress = getLbcAddress();
        console.log("LBC Contract Address:", lbcAddress);
        ILiquidityBridgeContract lbc = ILiquidityBridgeContract(lbcAddress);

        // Hash the quote
        bytes32 quoteHash = lbc.hashQuote(quote);
        console.log("\nQuote Hash:");
        console.logBytes32(quoteHash);

        // Parse signature (remove 0x if present)
        bytes memory signature = parseSignature(signatureHex);
        console.log("Signature length:", signature.length);

        // Fetch Bitcoin transaction data
        console.log("\nFetching Bitcoin transaction data...");
        console.log("  TX ID:", txId);
        string memory btcNetwork = getBtcNetwork();
        console.log("  BTC Network:", btcNetwork);

        (bytes memory rawTx, bytes memory pmt, uint256 height) = fetchBtcTxData(
            txId,
            btcNetwork
        );

        // Estimate gas
        console.log("\nEstimating gas...");
        uint256 gasStart = gasleft();

        try lbc.registerPegIn(quote, signature, rawTx, pmt, height) returns (
            int256 result
        ) {
            uint256 gasUsed = gasStart - gasleft();
            console.log("Gas estimation (approximate):", gasUsed);
            console.log("Expected result:", vm.toString(result));
        } catch Error(string memory reason) {
            console.log("\n[ERROR] Transaction simulation failed:");
            console.log(reason);
            console.log("\nAborting transaction.");
            revert(reason);
        } catch (bytes memory lowLevelError) {
            console.log(
                "\n[ERROR] Transaction simulation failed with low-level error"
            );
            console.logBytes(lowLevelError);
            revert("Transaction simulation failed");
        }

        // Execute registration
        console.log("\n--- Executing registration transaction ---\n");

        vm.startBroadcast();

        try lbc.registerPegIn(quote, signature, rawTx, pmt, height) returns (
            int256 result
        ) {
            console.log("[SUCCESS] PegIn registered successfully!");
            console.log("\nResult code:", vm.toString(result));
            console.log("Quote hash:");
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

        console.log("\n=== REGISTRATION COMPLETED ===\n");
    }

    /**
     * @notice Register a PegIn transaction (test version without broadcast)
     * @param quoteFilePath Path to the JSON file containing the PegIn quote
     * @param signatureHex The signature from the LP
     * @param rawTxHex The raw Bitcoin transaction hex
     * @param pmtHex The partial merkle tree hex
     * @param height The block height
     */
    function registerPeginTest(
        string memory quoteFilePath,
        string memory signatureHex,
        string memory rawTxHex,
        string memory pmtHex,
        uint256 height
    ) public {
        console.log("\n=== REGISTER PEGIN (TEST) ===\n");

        // Read and parse quote file
        console.log("Reading quote from file:", quoteFilePath);
        string memory json = vm.readFile(quoteFilePath);
        QuotesV2.PeginQuote memory quote = parsePeginQuote(json);

        // Get LBC contract
        address lbcAddress = getLbcAddress();
        console.log("LBC Contract Address:", lbcAddress);
        ILiquidityBridgeContract lbc = ILiquidityBridgeContract(lbcAddress);

        // Hash the quote
        bytes32 quoteHash = lbc.hashQuote(quote);
        console.log("\nQuote Hash:");
        console.logBytes32(quoteHash);

        // Parse inputs
        bytes memory signature = parseSignature(signatureHex);
        bytes memory rawTx = vm.parseBytes(rawTxHex);
        bytes memory pmt = vm.parseBytes(pmtHex);

        console.log("Signature length:", signature.length);
        console.log("Raw TX length:", rawTx.length);
        console.log("PMT length:", pmt.length);
        console.log("Block height:", height);

        // Execute registration (without broadcast for testing)
        console.log("\n--- Executing registration ---\n");

        try lbc.registerPegIn(quote, signature, rawTx, pmt, height) returns (
            int256 result
        ) {
            console.log("[SUCCESS] PegIn registered successfully!");
            console.log("Result code:", vm.toString(result));
            console.log("Quote hash:");
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

        console.log("\n=== REGISTRATION COMPLETED ===\n");
    }

    /**
     * @notice Parse signature from hex string
     * @param sigHex Signature hex string (with or without 0x prefix)
     * @return The signature as bytes
     */
    function parseSignature(
        string memory sigHex
    ) public pure returns (bytes memory) {
        bytes memory sigBytes = bytes(sigHex);

        // Remove 0x prefix if present
        uint startIndex = 0;
        if (
            sigBytes.length >= 2 &&
            sigBytes[0] == "0" &&
            (sigBytes[1] == "x" || sigBytes[1] == "X")
        ) {
            startIndex = 2;
        }

        uint hexLength = sigBytes.length - startIndex;
        require(hexLength % 2 == 0, "Invalid signature hex length");

        bytes memory result = new bytes(hexLength / 2);
        for (uint i = 0; i < hexLength / 2; i++) {
            uint8 high = hexCharToByte(sigBytes[startIndex + i * 2]);
            uint8 low = hexCharToByte(sigBytes[startIndex + i * 2 + 1]);
            result[i] = bytes1(high * 16 + low);
        }

        return result;
    }

    /**
     * @notice Parse PegIn quote from JSON
     * @param json The JSON string containing the quote
     * @return The parsed PegIn quote
     */
    function parsePeginQuote(
        string memory json
    ) public returns (QuotesV2.PeginQuote memory) {
        QuotesV2.PeginQuote memory quote;

        // Parse Bitcoin addresses using FFI
        string memory fedBTCAddr = vm.parseJsonString(json, ".fedBTCAddr");
        quote.fedBtcAddress = parseFedBtcAddress(fedBTCAddr);

        // Parse RSK/EVM addresses
        quote.lbcAddress = vm.parseJsonAddress(json, ".lbcAddr");
        quote.liquidityProviderRskAddress = vm.parseJsonAddress(
            json,
            ".lpRSKAddr"
        );

        string memory btcRefundAddr = vm.parseJsonString(
            json,
            ".btcRefundAddr"
        );
        quote.btcRefundAddress = parseBtcAddress(btcRefundAddr);

        quote.rskRefundAddress = payable(
            vm.parseJsonAddress(json, ".rskRefundAddr")
        );

        string memory lpBTCAddr = vm.parseJsonString(json, ".lpBTCAddr");
        quote.liquidityProviderBtcAddress = parseBtcAddress(lpBTCAddr);

        // Parse numeric fields
        quote.callFee = vm.parseJsonUint(json, ".callFee");
        quote.penaltyFee = vm.parseJsonUint(json, ".penaltyFee");

        quote.contractAddress = vm.parseJsonAddress(json, ".contractAddr");
        quote.data = vm.parseJsonBytes(json, ".data");

        quote.gasLimit = uint32(vm.parseJsonUint(json, ".gasLimit"));

        // Parse nonce - handle both string and number formats
        try vm.parseJsonInt(json, ".nonce") returns (int256 nonceInt) {
            quote.nonce = int64(nonceInt);
        } catch {
            string memory nonceStr = vm.parseJsonString(json, ".nonce");
            quote.nonce = int64(uint64(vm.parseUint(nonceStr)));
        }

        quote.value = vm.parseJsonUint(json, ".value");

        quote.agreementTimestamp = uint32(
            vm.parseJsonUint(json, ".agreementTimestamp")
        );
        quote.timeForDeposit = uint32(
            vm.parseJsonUint(json, ".timeForDeposit")
        );
        quote.callTime = uint32(vm.parseJsonUint(json, ".lpCallTime"));
        quote.depositConfirmations = uint16(
            vm.parseJsonUint(json, ".confirmations")
        );
        quote.callOnRegister = vm.parseJsonBool(json, ".callOnRegister");

        quote.gasFee = vm.parseJsonUint(json, ".gasFee");
        quote.productFeeAmount = vm.parseJsonUint(json, ".productFeeAmount");

        return quote;
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
}
