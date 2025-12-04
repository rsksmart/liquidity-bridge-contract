// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Quotes} from "../../src/libraries/Quotes.sol";
import {HexUtils} from "../../script/helpers/HexUtils.sol";

/**
 * @title TestUtils
 * @notice Shared utility functions for tests
 * @dev Provides consistent test helpers across all test files
 */
library TestUtils {
    /// @notice Convert bytes32 to hex string (without 0x prefix)
    function toHexString(bytes32 data) internal pure returns (string memory) {
        return HexUtils.toHexString(data);
    }

    /// @notice Convert bytes to hex string (without 0x prefix)
    function toHexString(bytes memory data) internal pure returns (string memory) {
        return HexUtils.toHexString(data);
    }

    /// @notice Create a standard test BTC address (P2PKH format)
    function createTestBtcAddress() internal pure returns (bytes memory) {
        return hex"76a914000000000000000000000000000000000000000088ac";
    }

    /// @notice Create a testnet BTC address
    function createTestnetBtcAddress() internal pure returns (bytes memory) {
        return hex"6f0000000000000000000000000000000000000000";
    }

    /// @notice Create a test federation BTC address
    function createTestFedAddress() internal pure returns (bytes20) {
        return bytes20(hex"0000000000000000000000000000000000000000");
    }
}
