// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import "lib/forge-std/src/Script.sol";
import "lib/forge-std/src/console.sol";
import {Quotes} from "src/libraries/Quotes.sol";
import {BtcAddressParser} from "../helpers/BtcAddressParser.sol";

interface IPegIn {
    function hashPegInQuote(Quotes.PegInQuote calldata quote) external view returns (bytes32);
}

interface IPegOut {
    function hashPegOutQuote(Quotes.PegOutQuote calldata quote) external view returns (bytes32);
}

/**
 * @title HashQuote
 * @notice Foundry script to hash PegIn and PegOut quotes for the new Flyover contracts
 * @dev Uses FFI to parse Bitcoin addresses via Node.js helper script
 *
 * ## Prerequisites
 * - FFI must be enabled in foundry.toml (ffi = true)
 * - Node.js and npm packages must be installed (bs58check, bech32, bitcoinjs-lib)
 * - Contract addresses must be provided via environment variables or addresses.json
 *
 * ## Usage
 *
 *   # Hash PegIn quote:
 *   forge script script/tasks/HashQuote.s.sol:HashQuote \
 *     --sig "hashPeginQuote(string)" <json-file-path> \
 *     --rpc-url <rpc-url> \
 *     --ffi
 *
 *   # Hash PegOut quote:
 *   forge script script/tasks/HashQuote.s.sol:HashQuote \
 *     --sig "hashPegoutQuote(string)" <json-file-path> \
 *     --rpc-url <rpc-url> \
 *     --ffi
 *
 * ## Environment Variables
 * - PEGIN_CONTRACT_ADDRESS: Address of PegInContract
 * - PEGOUT_CONTRACT_ADDRESS: Address of PegOutContract
 * - NETWORK: Network name for addresses.json (default: rskRegtest)
 */
contract HashQuote is Script, BtcAddressParser {

    /**
     * @notice Get contract address from environment or addresses.json
     */
    function getContractAddress(
        string memory envVarName,
        string memory jsonKey
    ) internal view returns (address) {
        try vm.envAddress(envVarName) returns (address addr) {
            if (addr != address(0)) {
                return addr;
            }
        } catch {}

        try vm.readFile("addresses.json") returns (string memory json) {
            string memory network = vm.envOr("NETWORK", string("rskRegtest"));
            string memory key = string.concat(".", network, ".", jsonKey, ".address");

            try vm.parseJsonAddress(json, key) returns (address addr) {
                if (addr != address(0)) {
                    return addr;
                }
            } catch {}
        } catch {}

        revert(string.concat("Failed to find ", jsonKey, " address. Set ", envVarName, " env var."));
    }

    /**
     * @notice Hash a PegIn quote from JSON file
     * @param jsonFilePath Path to the JSON file containing the quote
     */
    function hashPeginQuote(string memory jsonFilePath) public {
        string memory json = vm.readFile(jsonFilePath);

        Quotes.PegInQuote memory quote;

        // Parse Bitcoin addresses using FFI
        string memory fedBTCAddr = vm.parseJsonString(json, ".fedBTCAddr");
        quote.fedBtcAddress = parseFedBtcAddress(fedBTCAddr);

        // Parse RSK/EVM addresses
        quote.lbcAddress = vm.parseJsonAddress(json, ".lbcAddr");
        quote.liquidityProviderRskAddress = vm.parseJsonAddress(json, ".lpRSKAddr");

        string memory btcRefundAddr = vm.parseJsonString(json, ".btcRefundAddr");
        quote.btcRefundAddress = parseBtcAddress(btcRefundAddr);

        quote.rskRefundAddress = payable(vm.parseJsonAddress(json, ".rskRefundAddr"));

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
        quote.agreementTimestamp = uint32(vm.parseJsonUint(json, ".agreementTimestamp"));
        quote.timeForDeposit = uint32(vm.parseJsonUint(json, ".timeForDeposit"));
        quote.callTime = uint32(vm.parseJsonUint(json, ".lpCallTime"));
        quote.depositConfirmations = uint16(vm.parseJsonUint(json, ".confirmations"));
        quote.callOnRegister = vm.parseJsonBool(json, ".callOnRegister");
        quote.gasFee = vm.parseJsonUint(json, ".gasFee");
        quote.productFeeAmount = vm.parseJsonUint(json, ".productFeeAmount");

        // Get PegIn contract and hash the quote
        address pegInAddress = getContractAddress("PEGIN_CONTRACT_ADDRESS", "PegInContract");
        IPegIn pegIn = IPegIn(pegInAddress);

        bytes32 hash = pegIn.hashPegInQuote(quote);

        console.log("Hash of the provided PegIn quote:");
        console.logBytes32(hash);
    }

    /**
     * @notice Hash a PegOut quote from JSON file
     * @param jsonFilePath Path to the JSON file containing the quote
     */
    function hashPegoutQuote(string memory jsonFilePath) public {
        string memory json = vm.readFile(jsonFilePath);

        Quotes.PegOutQuote memory quote;

        // Parse addresses
        quote.lbcAddress = vm.parseJsonAddress(json, ".lbcAddress");
        quote.lpRskAddress = vm.parseJsonAddress(json, ".liquidityProviderRskAddress");

        string memory btcRefundAddr = vm.parseJsonString(json, ".btcRefundAddress");
        quote.btcRefundAddress = parseBtcAddress(btcRefundAddr);

        quote.rskRefundAddress = vm.parseJsonAddress(json, ".rskRefundAddress");

        string memory lpBtcAddr = vm.parseJsonString(json, ".lpBtcAddr");
        quote.lpBtcAddress = parseBtcAddress(lpBtcAddr);

        // Parse numeric fields
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

        // Get PegOut contract and hash the quote
        address pegOutAddress = getContractAddress("PEGOUT_CONTRACT_ADDRESS", "PegOutContract");
        IPegOut pegOut = IPegOut(pegOutAddress);

        bytes32 hash = pegOut.hashPegOutQuote(quote);

        console.log("Hash of the provided PegOut quote:");
        console.logBytes32(hash);
    }
}
