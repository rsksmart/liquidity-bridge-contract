// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import "lib/forge-std/src/Script.sol";
import "lib/forge-std/src/console.sol";
import {Quotes} from "src/libraries/Quotes.sol";
import {BtcAddressParser} from "../helpers/BtcAddressParser.sol";

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
contract RegisterPegin is Script, BtcAddressParser {
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
     * @notice Get PegIn contract address from environment or addresses.json
     */
    function getPegInAddress() internal view returns (address) {
        try vm.envAddress("PEGIN_CONTRACT_ADDRESS") returns (address addr) {
            if (addr != address(0)) {
                return addr;
            }
        } catch {}

        try vm.readFile("addresses.json") returns (string memory json) {
            string memory network = vm.envOr("NETWORK", string("rskRegtest"));
            string memory key = string.concat(".", network, ".PegInContract.address");

            try vm.parseJsonAddress(json, key) returns (address addr) {
                if (addr != address(0)) {
                    return addr;
                }
            } catch {}
        } catch {}

        revert("Failed to find PegInContract address. Set PEGIN_CONTRACT_ADDRESS env var.");
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
        Quotes.PegInQuote memory quote = parsePeginQuote(json);

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
     */
    function parseSignature(string memory sigHex) public pure returns (bytes memory) {
        bytes memory sigBytes = bytes(sigHex);

        uint startIndex = 0;
        if (sigBytes.length >= 2 && sigBytes[0] == "0" && (sigBytes[1] == "x" || sigBytes[1] == "X")) {
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
     */
    function parsePeginQuote(string memory json) public returns (Quotes.PegInQuote memory) {
        Quotes.PegInQuote memory quote;

        string memory fedBTCAddr = vm.parseJsonString(json, ".fedBTCAddr");
        quote.fedBtcAddress = parseFedBtcAddress(fedBTCAddr);

        quote.lbcAddress = vm.parseJsonAddress(json, ".lbcAddr");
        quote.liquidityProviderRskAddress = vm.parseJsonAddress(json, ".lpRSKAddr");

        string memory btcRefundAddr = vm.parseJsonString(json, ".btcRefundAddr");
        quote.btcRefundAddress = parseBtcAddress(btcRefundAddr);

        quote.rskRefundAddress = payable(vm.parseJsonAddress(json, ".rskRefundAddr"));

        string memory lpBTCAddr = vm.parseJsonString(json, ".lpBTCAddr");
        quote.liquidityProviderBtcAddress = parseBtcAddress(lpBTCAddr);

        quote.callFee = vm.parseJsonUint(json, ".callFee");
        quote.penaltyFee = vm.parseJsonUint(json, ".penaltyFee");
        quote.contractAddress = vm.parseJsonAddress(json, ".contractAddr");
        quote.data = vm.parseJsonBytes(json, ".data");
        quote.gasLimit = uint32(vm.parseJsonUint(json, ".gasLimit"));

        try vm.parseJsonInt(json, ".nonce") returns (int256 nonceInt) {
            quote.nonce = int64(nonceInt);
        } catch {
            string memory nonceStr = vm.parseJsonString(json, ".nonce");
            quote.nonce = int64(uint64(vm.parseUint(nonceStr)));
        }

        quote.value = vm.parseJsonUint(json, ".value");
        quote.agreementTimestamp = uint32(vm.parseJsonUint(json, ".agreementTimestamp"));
        quote.timeForDeposit = uint32(vm.parseJsonUint(json, ".timeForDeposit"));
        quote.callTime = uint32(vm.parseJsonUint(json, ".lpCallTime"));
        quote.depositConfirmations = uint16(vm.parseJsonUint(json, ".confirmations"));
        quote.callOnRegister = vm.parseJsonBool(json, ".callOnRegister");
        quote.gasFee = vm.parseJsonUint(json, ".gasFee");
        quote.productFeeAmount = vm.parseJsonUint(json, ".productFeeAmount");

        return quote;
    }

    function hexCharToByte(bytes1 char) internal pure returns (uint8) {
        uint8 c = uint8(char);
        if (c >= 48 && c <= 57) return c - 48;
        if (c >= 65 && c <= 70) return c - 55;
        if (c >= 97 && c <= 102) return c - 87;
        revert("Invalid hex character");
    }
}
