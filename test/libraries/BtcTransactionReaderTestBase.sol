// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Test} from "forge-std/Test.sol";
import {BtcUtils} from "@rsksmart/btc-transaction-solidity-helper/contracts/BtcUtils.sol";
import {BtcTransactionReader} from "../../src/libraries/BtcTransactionReader.sol";

/// @notice Transaction and OP_RETURN builders shared by the BtcTransactionReader unit and fuzz tests
abstract contract BtcTransactionReaderTestBase is Test {
    bytes internal constant P2PKH =
        hex"76a914000000000000000000000000000000000000dead88ac";

    address internal constant DESTINATION =
        0x0102030405060708090a0B0c0d0e0f1011121314;

    /// @dev Reads `script` as the second output, after a P2PKH output
    function _read(
        bytes memory script
    ) internal pure returns (BtcTransactionReader.FlyoverOpReturn memory) {
        return
            BtcTransactionReader.readFlyoverOpReturn(
                BtcUtils.getOutputs(_tx2(P2PKH, script))
            );
    }

    function _callPayload(
        address destination,
        uint32 maxGasLimit,
        bytes memory callData
    ) internal pure returns (bytes memory) {
        return
            abi.encodePacked(
                bytes1(0xF0),
                uint8(1),
                destination,
                maxGasLimit,
                callData
            );
    }

    /// @dev OP_RETURN with a direct push: the opcode is the data length. `payload` is 1-75 bytes.
    function _directPushScript(
        bytes memory payload
    ) internal pure returns (bytes memory) {
        return abi.encodePacked(hex"6a", uint8(payload.length), payload);
    }

    /// @dev OP_RETURN with OP_PUSHDATA1 and a 1-byte data length. `payload` is at most 255 bytes.
    function _pushData1Script(
        bytes memory payload
    ) internal pure returns (bytes memory) {
        return abi.encodePacked(hex"6a4c", uint8(payload.length), payload);
    }

    function _payload(uint256 length) internal pure returns (bytes memory p) {
        p = new bytes(length);
        for (uint256 i = 0; i < length; ++i) {
            p[i] = bytes1(uint8(i + 1));
        }
    }

    function _tx1(bytes memory script) internal pure returns (bytes memory) {
        bytes[] memory scripts = new bytes[](1);
        scripts[0] = script;
        uint64[] memory values = new uint64[](1);
        values[0] = 0;
        return _buildTx(scripts, values);
    }

    function _tx2(
        bytes memory first,
        bytes memory second
    ) internal pure returns (bytes memory) {
        bytes[] memory scripts = new bytes[](2);
        scripts[0] = first;
        scripts[1] = second;
        uint64[] memory values = new uint64[](2);
        values[0] = 50_000;
        values[1] = 0;
        return _buildTx(scripts, values);
    }

    /// @dev A one-input, witness-stripped raw transaction with one output per entry. Each script
    /// must be under 253 bytes, so its length fits in a one-byte compactSize.
    function _buildTx(
        bytes[] memory scripts,
        uint64[] memory values
    ) internal pure returns (bytes memory) {
        bytes memory outputs;
        for (uint256 i = 0; i < scripts.length; ++i) {
            require(
                scripts[i].length < 253,
                "script too long for this fixture"
            );
            bytes memory valueLe = new bytes(8);
            uint64 v = values[i];
            for (uint256 j = 0; j < 8; ++j) {
                valueLe[j] = bytes1(uint8(v & 0xFF));
                v >>= 8;
            }
            outputs = abi.encodePacked(
                outputs,
                valueLe,
                uint8(scripts[i].length),
                scripts[i]
            );
        }
        return
            abi.encodePacked(
                hex"01000000", // version
                hex"01", // input count
                bytes32(uint256(1)), // prevout txid
                hex"00000000", // prevout index
                hex"00", // empty scriptSig
                hex"ffffffff", // sequence
                uint8(scripts.length), // output count
                outputs,
                hex"00000000" // locktime
            );
    }
}
