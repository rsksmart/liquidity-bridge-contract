// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import "lib/forge-std/src/Script.sol";
import "lib/forge-std/src/console.sol";
import {QuotesV2} from "contracts/legacy/QuotesV2.sol";
import {Quotes} from "contracts/libraries/Quotes.sol";

interface ILiquidityBridgeContract {
    function hashQuote(
        QuotesV2.PeginQuote memory quote
    ) external view returns (bytes32);

    function hashPegoutQuote(
        QuotesV2.PegOutQuote memory quote
    ) external view returns (bytes32);
}

/**
 * @title HashQuote
 * @notice Foundry script to hash PegIn and PegOut quotes from JSON files
 * @dev This script uses FFI to parse Bitcoin addresses via Node.js helper script
 *
 * ## Prerequisites
 * - FFI must be enabled in foundry.toml (ffi = true)
 * - Node.js and npm packages must be installed (bs58check, bech32, bitcoinjs-lib)
 * - LBC contract address must be provided via LBC_ADDRESS env var or addresses.json
 *
 * ## Usage
 *
 * ### Method 1: Using the wrapper script (recommended)
 *   ./forge-scripts/tasks/hash-quote.sh --type pegin --file quote.json
 *   ./forge-scripts/tasks/hash-quote.sh --type pegout --file quote.json --rpc-url http://localhost:4444
 *
 * ### Method 2: Direct forge script invocation
 *   For PegIn:
 *     forge script forge-scripts/tasks/HashQuote.s.sol:HashQuote \
 *       --sig "hashPeginQuote(string)" <json-file-path> \
 *       --rpc-url <rpc-url> \
 *       --ffi
 *
 *   For PegOut:
 *     forge script forge-scripts/tasks/HashQuote.s.sol:HashQuote \
 *       --sig "hashPegoutQuote(string)" <json-file-path> \
 *       --rpc-url <rpc-url> \
 *       --ffi
 *
 * ## Environment Variables
 * - LBC_ADDRESS: Address of the LiquidityBridgeContract (optional if addresses.json is configured)
 * - NETWORK: Network name to use when reading from addresses.json (default: rskRegtest)
 * - RPC_URL: RPC endpoint URL
 *
 * ## Examples
 *   # Using wrapper script with environment variables
 *   LBC_ADDRESS=0x1234... ./forge-scripts/tasks/hash-quote.sh --type pegin --file tasks/hash-quote.example.json
 *
 *   # Using forge directly
 *   forge script forge-scripts/tasks/HashQuote.s.sol:HashQuote \
 *     --sig "hashPeginQuote(string)" "tasks/hash-quote.example.json" \
 *     --rpc-url http://localhost:4444 \
 *     --ffi
 */
contract HashQuote is Script {
    // LBC contract address - should be loaded from deployment config
    address constant LBC_ADDRESS = address(0); // TODO: Load from addresses.json

    string constant HELPER_SCRIPT =
        "forge-scripts/helpers/parse-btc-address.ts";

    /**
     * @notice Parse Bitcoin address using FFI helper script
     * @param btcAddress The Bitcoin address string to parse
     * @return The decoded address as bytes
     */
    function parseBtcAddress(
        string memory btcAddress
    ) internal returns (bytes memory) {
        string[] memory inputs = new string[](4);
        inputs[0] = "npx";
        inputs[1] = "ts-node";
        inputs[2] = HELPER_SCRIPT;
        inputs[3] = btcAddress;

        bytes memory result = vm.ffi(inputs);
        return result;
    }

    /**
     * @notice Parse fedBtcAddress (removes first byte after base58check decode)
     * @param btcAddress The Bitcoin address string to parse
     * @return The decoded address as bytes20 (without first byte)
     */
    function parseFedBtcAddress(
        string memory btcAddress
    ) internal returns (bytes20) {
        bytes memory decoded = parseBtcAddress(btcAddress);
        require(decoded.length >= 21, "Invalid fedBtcAddress length");

        // Skip first byte (network prefix)
        bytes memory sliced = new bytes(20);
        for (uint i = 0; i < 20; i++) {
            sliced[i] = decoded[i + 1];
        }

        return bytes20(sliced);
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
     * @notice Hash a PegIn quote from JSON file
     * @param jsonFilePath Path to the JSON file containing the quote
     */
    function hashPeginQuote(string memory jsonFilePath) public {
        // Read JSON file
        string memory json = vm.readFile(jsonFilePath);

        // Parse PegIn quote fields from JSON
        QuotesV2.PeginQuote memory quote;

        // Parse Bitcoin addresses using FFI
        string memory fedBTCAddr = vm.parseJsonString(json, ".fedBTCAddr");
        quote.fedBtcAddress = parseFedBtcAddress(fedBTCAddr);

        // Parse RSK/EVM addresses (convert to lowercase and checksum)
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
            // Try parsing as string if direct parse fails
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

        // Get LBC contract and hash the quote
        address lbcAddress = getLbcAddress();
        ILiquidityBridgeContract lbc = ILiquidityBridgeContract(lbcAddress);

        bytes32 hash = lbc.hashQuote(quote);

        // Print result (without 0x prefix, with green color)
        console.log("Hash of the provided PegIn quote:");
        console.logBytes32(hash);
    }

    /**
     * @notice Hash a PegOut quote from JSON file
     * @param jsonFilePath Path to the JSON file containing the quote
     */
    function hashPegoutQuote(string memory jsonFilePath) public {
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

        bytes32 hash = lbc.hashPegoutQuote(quote);

        // Print result (without 0x prefix, with green color)
        console.log("Hash of the provided PegOut quote:");
        console.logBytes32(hash);
    }
}
