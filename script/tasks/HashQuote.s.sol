// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import "lib/forge-std/src/Script.sol";
import "lib/forge-std/src/console.sol";
import {Quotes} from "src/libraries/Quotes.sol";
import {AddressResolver} from "../helpers/AddressResolver.sol";
import {QuoteParser} from "../helpers/QuoteParser.sol";

interface IPegOut {
    function hashPegOutQuote(
        Quotes.PegOutQuote calldata quote
    ) external view returns (bytes32);
}

/**
 * @title HashQuote
 * @notice Foundry script to hash PegOut quotes for the new Flyover contracts
 * @dev Uses FFI to parse Bitcoin addresses via Node.js helper script
 *
 * ## Prerequisites
 * - FFI must be enabled in foundry.toml (ffi = true)
 * - Node.js and npm packages must be installed (bs58check, bech32, bitcoinjs-lib)
 * - Contract addresses must be provided via environment variables or addresses.json
 *
 * ## Usage
 *
 *   # Hash PegOut quote:
 *   forge script script/tasks/HashQuote.s.sol:HashQuote \
 *     --sig "hashPegoutQuote(string)" <json-file-path> \
 *     --rpc-url <rpc-url> \
 *     --ffi
 *
 * ## Environment Variables
 * - PEGOUT_CONTRACT_ADDRESS: Address of PegOutContract
 * - NETWORK: Network name for addresses.json (default: rskRegtest)
 */
contract HashQuote is Script, AddressResolver, QuoteParser {
    /**
     * @notice Hash a PegOut quote from JSON file
     * @param jsonFilePath Path to the JSON file containing the quote
     */
    function hashPegoutQuote(string memory jsonFilePath) public {
        string memory json = vm.readFile(jsonFilePath);

        Quotes.PegOutQuote memory quote = parsePegOutQuote(json);

        // Get PegOut contract and hash the quote
        address pegOutAddress = getPegOutAddress();
        IPegOut pegOut = IPegOut(pegOutAddress);

        bytes32 hash = pegOut.hashPegOutQuote(quote);

        console.log("Hash of the provided PegOut quote:");
        console.logBytes32(hash);
    }
}
