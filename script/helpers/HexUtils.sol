// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

/**
 * @title HexUtils
 * @notice Shared utility for hex string parsing and conversion
 * @dev Provides consistent hex handling across all task scripts
 */
library HexUtils {
    error InvalidHexCharacter(bytes1 char);
    error InvalidHexLength(uint256 expected, uint256 actual);

    /// @notice Convert a single hex character to its byte value
    /// @param char The hex character (0-9, a-f, A-F)
    /// @return The byte value (0-15)
    function hexCharToByte(bytes1 char) internal pure returns (uint8) {
        uint8 c = uint8(char);
        if (c >= 48 && c <= 57) return c - 48; // '0' - '9'
        if (c >= 65 && c <= 70) return c - 55; // 'A' - 'F'
        if (c >= 97 && c <= 102) return c - 87; // 'a' - 'f'
        revert InvalidHexCharacter(char);
    }

    /// @notice Parse a hex string to bytes32 (quote hash)
    /// @param hexStr The hex string (with or without 0x prefix)
    /// @return The parsed bytes32 value
    function parseBytes32(
        string memory hexStr
    ) internal pure returns (bytes32) {
        bytes memory hexBytes = bytes(hexStr);

        uint256 startIndex = 0;
        if (
            hexBytes.length >= 2 &&
            hexBytes[0] == "0" &&
            (hexBytes[1] == "x" || hexBytes[1] == "X")
        ) {
            startIndex = 2;
        }

        uint256 hexLength = hexBytes.length - startIndex;
        if (hexLength != 64) {
            revert InvalidHexLength(64, hexLength);
        }

        bytes32 result;
        for (uint256 i = 0; i < 32; i++) {
            uint8 high = hexCharToByte(hexBytes[startIndex + i * 2]);
            uint8 low = hexCharToByte(hexBytes[startIndex + i * 2 + 1]);
            result |= bytes32(uint256(high * 16 + low)) << (248 - i * 8);
        }

        return result;
    }

    /// @notice Parse a hex string to bytes (for signatures, etc.)
    /// @param hexStr The hex string (with or without 0x prefix)
    /// @return The parsed bytes
    function parseBytes(
        string memory hexStr
    ) internal pure returns (bytes memory) {
        bytes memory hexBytes = bytes(hexStr);

        uint256 startIndex = 0;
        if (
            hexBytes.length >= 2 &&
            hexBytes[0] == "0" &&
            (hexBytes[1] == "x" || hexBytes[1] == "X")
        ) {
            startIndex = 2;
        }

        uint256 hexLength = hexBytes.length - startIndex;
        if (hexLength % 2 != 0) {
            revert InvalidHexLength(hexLength + 1, hexLength);
        }

        bytes memory result = new bytes(hexLength / 2);
        for (uint256 i = 0; i < hexLength / 2; i++) {
            uint8 high = hexCharToByte(hexBytes[startIndex + i * 2]);
            uint8 low = hexCharToByte(hexBytes[startIndex + i * 2 + 1]);
            result[i] = bytes1(high * 16 + low);
        }

        return result;
    }

    /// @notice Convert bytes32 to hex string (without 0x prefix)
    /// @param data The bytes32 value
    /// @return The hex string representation
    function toHexString(bytes32 data) internal pure returns (string memory) {
        bytes memory hexChars = "0123456789abcdef";
        bytes memory result = new bytes(64);
        for (uint256 i = 0; i < 32; i++) {
            result[i * 2] = hexChars[uint8(data[i] >> 4)];
            result[i * 2 + 1] = hexChars[uint8(data[i] & 0x0f)];
        }
        return string(result);
    }

    /// @notice Convert bytes to hex string (without 0x prefix)
    /// @param data The bytes value
    /// @return The hex string representation
    function toHexString(
        bytes memory data
    ) internal pure returns (string memory) {
        bytes memory hexChars = "0123456789abcdef";
        bytes memory result = new bytes(data.length * 2);
        for (uint256 i = 0; i < data.length; i++) {
            result[i * 2] = hexChars[uint8(data[i] >> 4)];
            result[i * 2 + 1] = hexChars[uint8(data[i] & 0x0f)];
        }
        return string(result);
    }
}
