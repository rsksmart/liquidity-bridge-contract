// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Test} from "forge-std/Test.sol";
import {BtcUtils} from "@rsksmart/btc-transaction-solidity-helper/contracts/BtcUtils.sol";
import {BtcTransactionReader} from "../../src/libraries/BtcTransactionReader.sol";

contract BtcTransactionReaderTest is Test {
    bytes private constant P2PKH = hex"76a914000000000000000000000000000000000000dead88ac";

    // ---------------------------------------------------------------- findFirstOpReturn

    function test_findFirstOpReturn_noOpReturn_returnsNotFound() public pure {
        (bool found, bool wellFormed, bytes memory data) =
            BtcTransactionReader.findFirstOpReturn(BtcUtils.getOutputs(_tx1(P2PKH)));
        assertFalse(found);
        assertFalse(wellFormed);
        assertEq(data.length, 0);
    }

    function test_findFirstOpReturn_directPush_returnsData() public pure {
        bytes memory payload = _payload(26);
        (bool found, bool wellFormed, bytes memory data) =
            BtcTransactionReader.findFirstOpReturn(BtcUtils.getOutputs(_tx2(P2PKH, _directPushScript(payload))));
        assertTrue(found);
        assertTrue(wellFormed);
        assertEq(data, payload);
    }

    function test_findFirstOpReturn_largestDirectPush_returnsData() public pure {
        bytes memory payload = _payload(75);
        (, bool wellFormed, bytes memory data) =
            BtcTransactionReader.findFirstOpReturn(BtcUtils.getOutputs(_tx1(_directPushScript(payload))));
        assertTrue(wellFormed);
        assertEq(data, payload);
    }

    function test_findFirstOpReturn_pushData1_returnsData() public pure {
        bytes memory payload = _payload(80);
        (bool found, bool wellFormed, bytes memory data) = BtcTransactionReader.findFirstOpReturn(
            BtcUtils.getOutputs(_tx1(abi.encodePacked(hex"6a4c", uint8(80), payload)))
        );
        assertTrue(found);
        assertTrue(wellFormed);
        assertEq(data, payload);
    }

    function test_findFirstOpReturn_readsOnlyTheFirstOpReturn() public pure {
        bytes memory first = _payload(26);
        bytes memory second = abi.encodePacked(hex"ff", _payload(25));
        (, bool wellFormed, bytes memory data) = BtcTransactionReader.findFirstOpReturn(
            BtcUtils.getOutputs(_tx2(_directPushScript(first), _directPushScript(second)))
        );
        assertTrue(wellFormed);
        assertEq(data, first);
    }

    function test_findFirstOpReturn_malformedFirst_isNotRescuedByAWellFormedSecond() public pure {
        (bool found, bool wellFormed,) =
            BtcTransactionReader.findFirstOpReturn(BtcUtils.getOutputs(_tx2(hex"6a", _directPushScript(_payload(26)))));
        assertTrue(found);
        assertFalse(wellFormed);
    }

    function test_findFirstOpReturn_bareOpReturn_isNotWellFormed() public pure {
        _assertMalformed(hex"6a");
    }

    function test_findFirstOpReturn_op0_isNotWellFormed() public pure {
        _assertMalformed(hex"6a00");
    }

    function test_findFirstOpReturn_pushData1WithoutLength_isNotWellFormed() public pure {
        _assertMalformed(hex"6a4c");
    }

    function test_findFirstOpReturn_pushData2_isNotWellFormed() public pure {
        _assertMalformed(abi.encodePacked(hex"6a4d1a00", _payload(26)));
    }

    function test_findFirstOpReturn_pushData4_isNotWellFormed() public pure {
        _assertMalformed(abi.encodePacked(hex"6a4e1a000000", _payload(26)));
    }

    function test_findFirstOpReturn_lengthLongerThanScript_isNotWellFormed() public pure {
        _assertMalformed(abi.encodePacked(hex"6a1b", _payload(26)));
    }

    function test_findFirstOpReturn_lengthShorterThanScript_isNotWellFormed() public pure {
        _assertMalformed(abi.encodePacked(hex"6a19", _payload(26)));
    }

    function test_findFirstOpReturn_secondPush_isNotWellFormed() public pure {
        _assertMalformed(abi.encodePacked(_directPushScript(_payload(26)), hex"0101"));
    }

    function test_findFirstOpReturn_pushData1LengthMismatch_isNotWellFormed() public pure {
        _assertMalformed(abi.encodePacked(hex"6a4c51", _payload(80)));
    }

    /// @notice Any script after OP_RETURN is well formed exactly when it is one direct push or one
    /// OP_PUSHDATA1 push whose length ends at the end of the script, and the data is the pushed bytes.
    function testFuzz_findFirstOpReturn_matchesTheSinglePushRule(bytes memory afterOpReturn) public pure {
        vm.assume(afterOpReturn.length <= 250);
        bytes memory script = abi.encodePacked(hex"6a", afterOpReturn);

        (bool expectedWellFormed, bytes memory expectedData) = _expectedPush(afterOpReturn);
        (bool found, bool wellFormed, bytes memory data) =
            BtcTransactionReader.findFirstOpReturn(BtcUtils.getOutputs(_tx1(script)));

        assertTrue(found);
        assertEq(wellFormed, expectedWellFormed);
        assertEq(data, expectedData);
    }

    function testFuzz_findFirstOpReturn_wellFormedDirectPush_roundTrips(bytes memory payload) public pure {
        vm.assume(payload.length >= 1 && payload.length <= 75);
        (, bool wellFormed, bytes memory data) =
            BtcTransactionReader.findFirstOpReturn(BtcUtils.getOutputs(_tx2(P2PKH, _directPushScript(payload))));
        assertTrue(wellFormed);
        assertEq(data, payload);
    }

    // ---------------------------------------------------------------- readFlyoverOpReturn

    address private constant DESTINATION = 0x0102030405060708090a0B0c0d0e0f1011121314;

    function test_readFlyoverOpReturn_noOpReturn_returnsNotFound() public pure {
        (
            bool found,
            BtcTransactionReader.OpReturnFault fault,
            address destination,
            uint256 maxGasLimit,
            bytes memory data
        ) = _read(P2PKH);
        assertFalse(found);
        assertEq(uint8(fault), uint8(BtcTransactionReader.OpReturnFault.None));
        assertEq(destination, address(0));
        assertEq(maxGasLimit, 0);
        assertEq(data.length, 0);
    }

    function test_readFlyoverOpReturn_validPayload_returnsTheCall() public pure {
        bytes memory payload = _callPayload(DESTINATION, 100_000, "");
        (
            bool found,
            BtcTransactionReader.OpReturnFault fault,
            address destination,
            uint256 maxGasLimit,
            bytes memory data
        ) = _read(_directPushScript(payload));
        assertTrue(found);
        assertEq(uint8(fault), uint8(BtcTransactionReader.OpReturnFault.None));
        assertEq(destination, DESTINATION);
        assertEq(maxGasLimit, 100_000);
        assertEq(data, payload);
    }

    function test_readFlyoverOpReturn_callDataStartsAtTheOffset() public pure {
        bytes memory callData = abi.encodeWithSignature("deposit(uint256)", 7);
        bytes memory payload = _callPayload(DESTINATION, 100_000, callData);
        (bool found,,,, bytes memory data) = _read(_directPushScript(payload));
        assertTrue(found);
        assertEq(data.length, BtcTransactionReader.FLYOVER_CALL_DATA_OFFSET + callData.length);
        for (uint256 i = 0; i < callData.length; ++i) {
            assertEq(data[BtcTransactionReader.FLYOVER_CALL_DATA_OFFSET + i], callData[i]);
        }
    }

    function test_readFlyoverOpReturn_pushData1Payload_returnsTheCall() public pure {
        bytes memory payload = _callPayload(DESTINATION, 100_000, _payload(54));
        assertEq(payload.length, 80);
        (bool found, BtcTransactionReader.OpReturnFault fault, address destination,, bytes memory data) =
            _read(abi.encodePacked(hex"6a4c", uint8(80), payload));
        assertTrue(found);
        assertEq(uint8(fault), uint8(BtcTransactionReader.OpReturnFault.None));
        assertEq(destination, DESTINATION);
        assertEq(data, payload);
    }

    function test_readFlyoverOpReturn_badPush() public pure {
        _assertFault(hex"6a", BtcTransactionReader.OpReturnFault.BadPush);
    }

    function test_readFlyoverOpReturn_payloadOf25Bytes_isTooShort() public pure {
        bytes memory payload = _callPayload(DESTINATION, 100_000, "");
        bytes memory shortPayload = new bytes(25);
        for (uint256 i = 0; i < 25; ++i) {
            shortPayload[i] = payload[i];
        }
        _assertFault(_directPushScript(shortPayload), BtcTransactionReader.OpReturnFault.TooShort);
    }

    function test_readFlyoverOpReturn_wrongMagic() public pure {
        bytes memory payload = _callPayload(DESTINATION, 100_000, "");
        payload[0] = 0xF1;
        _assertFault(_directPushScript(payload), BtcTransactionReader.OpReturnFault.WrongMagic);
    }

    /// @notice An OP_RETURN from another protocol is read as a Flyover OP_RETURN. The bridge's
    /// own peg-in OP_RETURN starts with "RSKT".
    function test_readFlyoverOpReturn_otherProtocol_isWrongMagic() public pure {
        bytes memory payload = abi.encodePacked("RSKT", uint8(1), DESTINATION, bytes1(0x00));
        _assertFault(_directPushScript(payload), BtcTransactionReader.OpReturnFault.WrongMagic);
    }

    function test_readFlyoverOpReturn_wrongVersion() public pure {
        bytes memory payload = _callPayload(DESTINATION, 100_000, "");
        payload[1] = 0x02;
        _assertFault(_directPushScript(payload), BtcTransactionReader.OpReturnFault.WrongVersion);
    }

    function test_readFlyoverOpReturn_zeroDestination() public pure {
        _assertFault(
            _directPushScript(_callPayload(address(0), 100_000, "")), BtcTransactionReader.OpReturnFault.ZeroDestination
        );
    }

    /// @notice The range of maxGasLimit is a contract rule, so 0 is returned as read
    function test_readFlyoverOpReturn_zeroMaxGasLimit_isReturnedAsRead() public pure {
        (bool found, BtcTransactionReader.OpReturnFault fault, address destination, uint256 maxGasLimit,) =
            _read(_directPushScript(_callPayload(DESTINATION, 0, "")));
        assertTrue(found);
        assertEq(destination, DESTINATION);
        assertEq(uint8(fault), uint8(BtcTransactionReader.OpReturnFault.None));
        assertEq(maxGasLimit, 0);
    }

    /// @notice maxGasLimit is big-endian: 0x01000000 reads as 16,777,216, not as 1
    function test_readFlyoverOpReturn_maxGasLimit_isBigEndian() public pure {
        (,,, uint256 high,) = _read(_directPushScript(_callPayload(DESTINATION, 0x01000000, "")));
        (,,, uint256 low,) = _read(_directPushScript(_callPayload(DESTINATION, 0x00000001, "")));
        (,,, uint256 max,) = _read(_directPushScript(_callPayload(DESTINATION, 0xFFFFFFFF, "")));
        assertEq(high, 16_777_216);
        assertEq(low, 1);
        assertEq(max, type(uint32).max);
    }

    function test_readFlyoverOpReturn_readsOnlyTheFirstOpReturn() public pure {
        bytes memory valid = _directPushScript(_callPayload(DESTINATION, 100_000, ""));
        (bool found, BtcTransactionReader.OpReturnFault fault,,,) =
            BtcTransactionReader.readFlyoverOpReturn(BtcUtils.getOutputs(_tx2(hex"6a", valid)));
        assertTrue(found);
        assertEq(uint8(fault), uint8(BtcTransactionReader.OpReturnFault.BadPush));
    }

    function testFuzz_readFlyoverOpReturn_validPayload_roundTrips(
        address destination,
        uint32 maxGasLimit,
        bytes memory callData
    ) public pure {
        vm.assume(destination != address(0));
        vm.assume(callData.length <= 200);
        bytes memory payload = _callPayload(destination, maxGasLimit, callData);
        bytes memory script = payload.length <= 75
            ? _directPushScript(payload)
            : abi.encodePacked(hex"6a4c", uint8(payload.length), payload);

        (
            bool found,
            BtcTransactionReader.OpReturnFault fault,
            address readDestination,
            uint256 readGas,
            bytes memory data
        ) = _read(script);

        assertTrue(found);
        assertEq(uint8(fault), uint8(BtcTransactionReader.OpReturnFault.None));
        assertEq(readDestination, destination);
        assertEq(readGas, maxGasLimit);
        assertEq(data, payload);
    }

    /// @notice Any pushed bytes get the fault an independent statement of the layout expects
    function testFuzz_readFlyoverOpReturn_matchesTheLayoutRule(bytes memory payload) public pure {
        vm.assume(payload.length >= 1 && payload.length <= 75);
        BtcTransactionReader.OpReturnFault expected = _expectedFault(payload);

        (bool found, BtcTransactionReader.OpReturnFault fault,,,) = _read(_directPushScript(payload));

        assertTrue(found);
        assertEq(uint8(fault), uint8(expected));
    }

    // ---------------------------------------------------------------- findOutputsPaying

    function test_findOutputsPaying_readsTheParsedOutputs() public pure {
        bytes memory pkScript = hex"a914000000000000000000000000000000000000beef87";
        bytes[] memory scripts = new bytes[](3);
        scripts[0] = pkScript;
        scripts[1] = _directPushScript(_payload(26));
        scripts[2] = pkScript;
        uint64[] memory values = new uint64[](3);
        values[0] = 70_000;
        values[1] = 0;
        values[2] = 50_000;

        (uint64 firstValue, uint64 smallestValue, bool found) =
            BtcTransactionReader.findOutputsPaying(BtcUtils.getOutputs(_buildTx(scripts, values)), pkScript);

        assertTrue(found);
        assertEq(firstValue, 70_000);
        assertEq(smallestValue, 50_000);
    }

    // ---------------------------------------------------------------- helpers

    function _read(bytes memory script)
        private
        pure
        returns (bool, BtcTransactionReader.OpReturnFault, address, uint256, bytes memory)
    {
        return BtcTransactionReader.readFlyoverOpReturn(BtcUtils.getOutputs(_tx2(P2PKH, script)));
    }

    function _assertFault(bytes memory script, BtcTransactionReader.OpReturnFault expected) private pure {
        (
            bool found,
            BtcTransactionReader.OpReturnFault fault,
            address destination,
            uint256 maxGasLimit,
            bytes memory data
        ) = _read(script);
        assertTrue(found);
        assertEq(uint8(fault), uint8(expected));
        assertEq(destination, address(0));
        assertEq(maxGasLimit, 0);
        assertEq(data.length, 0);
    }

    function _callPayload(address destination, uint32 maxGasLimit, bytes memory callData)
        private
        pure
        returns (bytes memory)
    {
        return abi.encodePacked(bytes1(0xF0), uint8(1), destination, maxGasLimit, callData);
    }

    /// @dev Independent statement of the layout checks, for the fuzz test
    function _expectedFault(bytes memory p) private pure returns (BtcTransactionReader.OpReturnFault) {
        if (p.length < 26) return BtcTransactionReader.OpReturnFault.TooShort;
        if (p[0] != 0xF0) return BtcTransactionReader.OpReturnFault.WrongMagic;
        if (p[1] != 0x01) return BtcTransactionReader.OpReturnFault.WrongVersion;
        bool zero = true;
        for (uint256 i = 2; i < 22; ++i) {
            if (p[i] != 0) zero = false;
        }
        if (zero) return BtcTransactionReader.OpReturnFault.ZeroDestination;
        return BtcTransactionReader.OpReturnFault.None;
    }

    function _assertMalformed(bytes memory script) private pure {
        (bool found, bool wellFormed, bytes memory data) =
            BtcTransactionReader.findFirstOpReturn(BtcUtils.getOutputs(_tx1(script)));
        assertTrue(found);
        assertFalse(wellFormed);
        assertEq(data.length, 0);
    }

    /// @dev Independent statement of the rule, for the fuzz test
    function _expectedPush(bytes memory s) private pure returns (bool, bytes memory) {
        if (s.length == 0) return (false, "");
        uint8 op = uint8(s[0]);
        uint256 start;
        uint256 len;
        if (op >= 0x01 && op <= 0x4b) {
            start = 1;
            len = op;
        } else if (op == 0x4c && s.length >= 2) {
            start = 2;
            len = uint8(s[1]);
        } else {
            return (false, "");
        }
        if (s.length != start + len) return (false, "");
        bytes memory out = new bytes(len);
        for (uint256 i = 0; i < len; ++i) {
            out[i] = s[start + i];
        }
        return (true, out);
    }

    function _directPushScript(bytes memory payload) private pure returns (bytes memory) {
        return abi.encodePacked(hex"6a", uint8(payload.length), payload);
    }

    function _payload(uint256 length) private pure returns (bytes memory p) {
        p = new bytes(length);
        for (uint256 i = 0; i < length; ++i) {
            p[i] = bytes1(uint8(i + 1));
        }
    }

    function _tx1(bytes memory script) private pure returns (bytes memory) {
        bytes[] memory scripts = new bytes[](1);
        scripts[0] = script;
        uint64[] memory values = new uint64[](1);
        values[0] = 0;
        return _buildTx(scripts, values);
    }

    function _tx2(bytes memory first, bytes memory second) private pure returns (bytes memory) {
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
    function _buildTx(bytes[] memory scripts, uint64[] memory values) private pure returns (bytes memory) {
        bytes memory outputs;
        for (uint256 i = 0; i < scripts.length; ++i) {
            require(scripts[i].length < 253, "script too long for this fixture");
            bytes memory valueLe = new bytes(8);
            uint64 v = values[i];
            for (uint256 j = 0; j < 8; ++j) {
                valueLe[j] = bytes1(uint8(v & 0xFF));
                v >>= 8;
            }
            outputs = abi.encodePacked(outputs, valueLe, uint8(scripts[i].length), scripts[i]);
        }
        return abi.encodePacked(
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
