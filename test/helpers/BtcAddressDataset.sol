// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Test} from "forge-std/Test.sol";
import {BtcAddressParser} from "../../script/helpers/BtcAddressParser.sol";

/// @title Helper for loading BTC addresses from test/datasets/*.json
/// @dev Each dataset file has "testnet" and "mainnet" arrays of {script, address} entries.
abstract contract BtcAddressDataset is Test, BtcAddressParser {
    enum BtcAddressType {
        P2PKH,
        P2SH,
        P2WPKH,
        P2WSH,
        P2TR
    }

    string internal constant DATASETS_DIR = "test/datasets/";
    uint256 internal constant DATASET_ENTRY_COUNT = 5;

    /// @notice Loads parsed addresses for a single script type and network
    function loadAddresses(
        BtcAddressType addrType,
        string memory networkKey
    ) internal returns (bytes[] memory addresses) {
        return
            parseDatasetAddresses(
                loadDatasetAddressStrings(_datasetPath(addrType), networkKey)
            );
    }

    /// @notice Loads and concatenates addresses for two script types
    function loadAddresses(
        BtcAddressType addrTypeA,
        BtcAddressType addrTypeB,
        string memory networkKey
    ) internal returns (bytes[] memory addresses) {
        return
            concatAddressBytes(
                loadAddresses(addrTypeA, networkKey),
                loadAddresses(addrTypeB, networkKey)
            );
    }

    /// @notice Loads and concatenates addresses for three script types
    function loadAddresses(
        BtcAddressType addrTypeA,
        BtcAddressType addrTypeB,
        BtcAddressType addrTypeC,
        string memory networkKey
    ) internal returns (bytes[] memory addresses) {
        return
            concatAddressBytes(
                loadAddresses(addrTypeA, networkKey),
                loadAddresses(addrTypeB, networkKey),
                loadAddresses(addrTypeC, networkKey)
            );
    }

    /// @notice Non-P2PKH/P2SH types that must revert on testnet quote hashing
    function loadInvalidTestnetQuoteAddresses()
        internal
        returns (bytes[] memory)
    {
        return
            loadAddresses(
                BtcAddressType.P2WPKH,
                BtcAddressType.P2WSH,
                BtcAddressType.P2TR,
                "testnet"
            );
    }

    /// @notice P2PKH/P2SH types accepted on testnet
    function loadValidTestnetQuoteAddresses()
        internal
        returns (bytes[] memory)
    {
        return
            loadAddresses(BtcAddressType.P2PKH, BtcAddressType.P2SH, "testnet");
    }

    /// @notice P2PKH/P2SH types accepted when PegIn is deployed with mainnet=true
    function loadValidMainnetQuoteAddresses()
        internal
        returns (bytes[] memory)
    {
        return
            loadAddresses(BtcAddressType.P2PKH, BtcAddressType.P2SH, "mainnet");
    }

    /// @notice P2WSH/P2TR types that revert on mainnet; P2WPKH shares the P2PKH prefix so is not included
    function loadInvalidMainnetQuoteAddresses()
        internal
        returns (bytes[] memory)
    {
        return
            loadAddresses(
                //BtcAddressType.P2WPKH,
                BtcAddressType.P2WSH,
                BtcAddressType.P2TR,
                "mainnet"
            );
    }

    /// @dev Flat index layout for loadInvalidTestnetQuoteAddresses: [0..4] p2wpkh, [5..9] p2wsh, [10..14] p2tr
    function assertInvalidTestnetScriptType(
        bytes memory addressBytes,
        uint8 addressIndex
    ) internal pure {
        if (addressIndex < DATASET_ENTRY_COUNT) {
            assertEq(addressBytes.length, 21, "expected P2WPKH length");
            assertEq(addressBytes[0], bytes1(0x00), "expected P2WPKH prefix");
        } else if (addressIndex < 2 * DATASET_ENTRY_COUNT) {
            assertEq(addressBytes.length, 33, "expected P2WSH length");
            assertEq(addressBytes[0], bytes1(0x00), "expected P2WSH prefix");
        } else {
            assertEq(addressBytes.length, 33, "expected P2TR length");
            assertEq(addressBytes[0], bytes1(0x01), "expected P2TR prefix");
        }
    }

    function _datasetPath(
        BtcAddressType addrType
    ) internal pure returns (string memory path) {
        if (addrType == BtcAddressType.P2PKH) {
            return string.concat(DATASETS_DIR, "p2pkh.json");
        }
        if (addrType == BtcAddressType.P2SH) {
            return string.concat(DATASETS_DIR, "p2sh.json");
        }
        if (addrType == BtcAddressType.P2WPKH) {
            return string.concat(DATASETS_DIR, "p2wpkh.json");
        }
        if (addrType == BtcAddressType.P2WSH) {
            return string.concat(DATASETS_DIR, "p2wsh.json");
        }
        return string.concat(DATASETS_DIR, "p2tr.json");
    }

    function loadDatasetAddressStrings(
        string memory path,
        string memory networkKey
    ) internal view returns (string[] memory addresses) {
        string memory json = vm.readFile(path);
        addresses = new string[](DATASET_ENTRY_COUNT);
        for (uint256 i = 0; i < DATASET_ENTRY_COUNT; i++) {
            string memory key = string(
                abi.encodePacked(
                    ".",
                    networkKey,
                    "[",
                    vm.toString(i),
                    "].address"
                )
            );
            addresses[i] = vm.parseJsonString(json, key);
        }
    }

    function parseDatasetAddresses(
        string[] memory addressStrings
    ) internal returns (bytes[] memory addresses) {
        addresses = new bytes[](addressStrings.length);
        for (uint256 i = 0; i < addressStrings.length; i++) {
            addresses[i] = parseBtcAddress(addressStrings[i]);
        }
    }

    function concatAddressBytes(
        bytes[] memory a,
        bytes[] memory b,
        bytes[] memory c
    ) internal pure returns (bytes[] memory combined) {
        combined = new bytes[](a.length + b.length + c.length);
        uint256 offset;
        for (uint256 i = 0; i < a.length; i++) {
            combined[offset++] = a[i];
        }
        for (uint256 i = 0; i < b.length; i++) {
            combined[offset++] = b[i];
        }
        for (uint256 i = 0; i < c.length; i++) {
            combined[offset++] = c[i];
        }
    }

    function concatAddressBytes(
        bytes[] memory a,
        bytes[] memory b
    ) internal pure returns (bytes[] memory combined) {
        combined = new bytes[](a.length + b.length);
        for (uint256 i = 0; i < a.length; i++) {
            combined[i] = a[i];
        }
        for (uint256 i = 0; i < b.length; i++) {
            combined[a.length + i] = b[i];
        }
    }
}
