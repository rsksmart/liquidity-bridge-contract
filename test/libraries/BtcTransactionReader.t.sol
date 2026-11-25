// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {BtcUtils} from "@rsksmart/btc-transaction-solidity-helper/contracts/BtcUtils.sol";
import {BtcTransactionReader} from "../../src/libraries/BtcTransactionReader.sol";
import {BtcTransactionReaderTestBase} from "./BtcTransactionReaderTestBase.sol";

contract BtcTransactionReaderTest is BtcTransactionReaderTestBase {
    // ---------------------------------------------------------------- findFirstOpReturn

    function test_findFirstOpReturn_noOpReturn_returnsNotFound() public pure {
        (bool found, bool wellFormed, bytes memory data) = BtcTransactionReader
            .findFirstOpReturn(BtcUtils.getOutputs(_tx1(P2PKH)));
        assertFalse(found);
        assertFalse(wellFormed);
        assertEq(data.length, 0);
    }

    function test_findFirstOpReturn_directPush_returnsData() public pure {
        bytes memory payload = _payload(26);
        (bool found, bool wellFormed, bytes memory data) = BtcTransactionReader
            .findFirstOpReturn(
                BtcUtils.getOutputs(_tx2(P2PKH, _directPushScript(payload)))
            );
        assertTrue(found);
        assertTrue(wellFormed);
        assertEq(data, payload);
    }

    function test_findFirstOpReturn_largestDirectPush_returnsData()
        public
        pure
    {
        bytes memory payload = _payload(75);
        (, bool wellFormed, bytes memory data) = BtcTransactionReader
            .findFirstOpReturn(
                BtcUtils.getOutputs(_tx1(_directPushScript(payload)))
            );
        assertTrue(wellFormed);
        assertEq(data, payload);
    }

    function test_findFirstOpReturn_pushData1_returnsData() public pure {
        bytes memory payload = _payload(80);
        (bool found, bool wellFormed, bytes memory data) = BtcTransactionReader
            .findFirstOpReturn(
                BtcUtils.getOutputs(_tx1(_pushData1Script(payload)))
            );
        assertTrue(found);
        assertTrue(wellFormed);
        assertEq(data, payload);
    }

    function test_findFirstOpReturn_readsOnlyTheFirstOpReturn() public pure {
        bytes memory first = _payload(26);
        bytes memory second = abi.encodePacked(hex"ff", _payload(25));
        (, bool wellFormed, bytes memory data) = BtcTransactionReader
            .findFirstOpReturn(
                BtcUtils.getOutputs(
                    _tx2(_directPushScript(first), _directPushScript(second))
                )
            );
        assertTrue(wellFormed);
        assertEq(data, first);
    }

    function test_findFirstOpReturn_malformedFirst_isNotRescuedByAWellFormedSecond()
        public
        pure
    {
        (bool found, bool wellFormed, ) = BtcTransactionReader
            .findFirstOpReturn(
                BtcUtils.getOutputs(
                    _tx2(hex"6a", _directPushScript(_payload(26)))
                )
            );
        assertTrue(found);
        assertFalse(wellFormed);
    }

    function test_findFirstOpReturn_bareOpReturn_isNotWellFormed() public pure {
        _assertMalformed(hex"6a");
    }

    function test_findFirstOpReturn_op0_isNotWellFormed() public pure {
        _assertMalformed(hex"6a00");
    }

    function test_findFirstOpReturn_pushData1WithoutLength_isNotWellFormed()
        public
        pure
    {
        _assertMalformed(hex"6a4c");
    }

    function test_findFirstOpReturn_pushData2_isNotWellFormed() public pure {
        _assertMalformed(abi.encodePacked(hex"6a4d1a00", _payload(26)));
    }

    function test_findFirstOpReturn_pushData4_isNotWellFormed() public pure {
        _assertMalformed(abi.encodePacked(hex"6a4e1a000000", _payload(26)));
    }

    function test_findFirstOpReturn_lengthLongerThanScript_isNotWellFormed()
        public
        pure
    {
        _assertMalformed(abi.encodePacked(hex"6a1b", _payload(26)));
    }

    function test_findFirstOpReturn_lengthShorterThanScript_isNotWellFormed()
        public
        pure
    {
        _assertMalformed(abi.encodePacked(hex"6a19", _payload(26)));
    }

    function test_findFirstOpReturn_secondPush_isNotWellFormed() public pure {
        _assertMalformed(
            abi.encodePacked(_directPushScript(_payload(26)), hex"0101")
        );
    }

    function test_findFirstOpReturn_pushData1LengthMismatch_isNotWellFormed()
        public
        pure
    {
        _assertMalformed(abi.encodePacked(hex"6a4c51", _payload(80)));
    }

    // ---------------------------------------------------------------- readFlyoverOpReturn

    function test_readFlyoverOpReturn_noOpReturn_returnsNotFound() public pure {
        BtcTransactionReader.FlyoverOpReturn memory r = _read(P2PKH);
        assertFalse(r.found);
        assertEq(
            uint8(r.fault),
            uint8(BtcTransactionReader.OpReturnFault.None)
        );
        assertEq(r.destination, address(0));
        assertEq(r.maxGasLimit, 0);
        assertEq(r.data.length, 0);
    }

    function test_readFlyoverOpReturn_validPayload_returnsTheCall()
        public
        pure
    {
        bytes memory payload = _callPayload(DESTINATION, 100_000, "");
        BtcTransactionReader.FlyoverOpReturn memory r = _read(
            _directPushScript(payload)
        );
        assertTrue(r.found);
        assertEq(
            uint8(r.fault),
            uint8(BtcTransactionReader.OpReturnFault.None)
        );
        assertEq(r.destination, DESTINATION);
        assertEq(r.maxGasLimit, 100_000);
        assertEq(r.data, payload);
    }

    function test_readFlyoverOpReturn_callDataStartsAtTheOffset() public pure {
        bytes memory callData = abi.encodeWithSignature("deposit(uint256)", 7);
        bytes memory payload = _callPayload(DESTINATION, 100_000, callData);
        BtcTransactionReader.FlyoverOpReturn memory r = _read(
            _directPushScript(payload)
        );
        assertTrue(r.found);
        assertEq(
            r.data.length,
            BtcTransactionReader.FLYOVER_CALL_DATA_OFFSET + callData.length
        );
        for (uint256 i = 0; i < callData.length; ++i) {
            assertEq(
                r.data[BtcTransactionReader.FLYOVER_CALL_DATA_OFFSET + i],
                callData[i]
            );
        }
    }

    function test_readFlyoverOpReturn_pushData1Payload_returnsTheCall()
        public
        pure
    {
        bytes memory payload = _callPayload(DESTINATION, 100_000, _payload(54));
        assertEq(payload.length, 80);
        BtcTransactionReader.FlyoverOpReturn memory r = _read(
            _pushData1Script(payload)
        );
        assertTrue(r.found);
        assertEq(
            uint8(r.fault),
            uint8(BtcTransactionReader.OpReturnFault.None)
        );
        assertEq(r.destination, DESTINATION);
        assertEq(r.data, payload);
    }

    function test_readFlyoverOpReturn_badPush() public pure {
        _assertFault(hex"6a", BtcTransactionReader.OpReturnFault.BadPush);
    }

    function test_readFlyoverOpReturn_payloadOf25Bytes_isTooShort()
        public
        pure
    {
        bytes memory payload = _callPayload(DESTINATION, 100_000, "");
        bytes memory shortPayload = new bytes(25);
        for (uint256 i = 0; i < 25; ++i) {
            shortPayload[i] = payload[i];
        }
        _assertFault(
            _directPushScript(shortPayload),
            BtcTransactionReader.OpReturnFault.TooShort
        );
    }

    function test_readFlyoverOpReturn_wrongMagic() public pure {
        bytes memory payload = _callPayload(DESTINATION, 100_000, "");
        payload[0] = 0xF1;
        _assertFault(
            _directPushScript(payload),
            BtcTransactionReader.OpReturnFault.WrongMagic
        );
    }

    /// @notice An OP_RETURN from another protocol is read as a Flyover OP_RETURN. The bridge's
    /// own peg-in OP_RETURN starts with "RSKT".
    function test_readFlyoverOpReturn_otherProtocol_isWrongMagic() public pure {
        bytes memory payload = abi.encodePacked(
            "RSKT",
            uint8(1),
            DESTINATION,
            bytes1(0x00)
        );
        _assertFault(
            _directPushScript(payload),
            BtcTransactionReader.OpReturnFault.WrongMagic
        );
    }

    function test_readFlyoverOpReturn_wrongVersion() public pure {
        bytes memory payload = _callPayload(DESTINATION, 100_000, "");
        payload[1] = 0x02;
        _assertFault(
            _directPushScript(payload),
            BtcTransactionReader.OpReturnFault.WrongVersion
        );
    }

    function test_readFlyoverOpReturn_zeroDestination() public pure {
        _assertFault(
            _directPushScript(_callPayload(address(0), 100_000, "")),
            BtcTransactionReader.OpReturnFault.ZeroDestination
        );
    }

    /// @notice The range of maxGasLimit is a contract rule, so 0 is returned as read
    function test_readFlyoverOpReturn_zeroMaxGasLimit_isReturnedAsRead()
        public
        pure
    {
        BtcTransactionReader.FlyoverOpReturn memory r = _read(
            _directPushScript(_callPayload(DESTINATION, 0, ""))
        );
        assertTrue(r.found);
        assertEq(r.destination, DESTINATION);
        assertEq(
            uint8(r.fault),
            uint8(BtcTransactionReader.OpReturnFault.None)
        );
        assertEq(r.maxGasLimit, 0);
    }

    /// @notice maxGasLimit is big-endian: 0x01000000 reads as 16,777,216, not as 1
    function test_readFlyoverOpReturn_maxGasLimit_isBigEndian() public pure {
        uint256 high = _read(
            _directPushScript(_callPayload(DESTINATION, 0x01000000, ""))
        ).maxGasLimit;
        uint256 low = _read(
            _directPushScript(_callPayload(DESTINATION, 0x00000001, ""))
        ).maxGasLimit;
        uint256 max = _read(
            _directPushScript(_callPayload(DESTINATION, 0xFFFFFFFF, ""))
        ).maxGasLimit;
        assertEq(high, 16_777_216);
        assertEq(low, 1);
        assertEq(max, type(uint32).max);
    }

    function test_readFlyoverOpReturn_readsOnlyTheFirstOpReturn() public pure {
        bytes memory valid = _directPushScript(
            _callPayload(DESTINATION, 100_000, "")
        );
        BtcTransactionReader.FlyoverOpReturn memory r = BtcTransactionReader
            .readFlyoverOpReturn(BtcUtils.getOutputs(_tx2(hex"6a", valid)));
        assertTrue(r.found);
        assertEq(
            uint8(r.fault),
            uint8(BtcTransactionReader.OpReturnFault.BadPush)
        );
    }

    // ---------------------------------------------------------------- findOutputsPaying

    function test_findOutputsPaying_readsTheParsedOutputs() public pure {
        bytes
            memory pkScript = hex"a914000000000000000000000000000000000000beef87";
        bytes[] memory scripts = new bytes[](3);
        scripts[0] = pkScript;
        scripts[1] = _directPushScript(_payload(26));
        scripts[2] = pkScript;
        uint64[] memory values = new uint64[](3);
        values[0] = 70_000;
        values[1] = 0;
        values[2] = 50_000;

        (
            uint64 firstValue,
            uint64 smallestValue,
            bool found
        ) = BtcTransactionReader.findOutputsPaying(
                BtcUtils.getOutputs(_buildTx(scripts, values)),
                pkScript
            );

        assertTrue(found);
        assertEq(firstValue, 70_000);
        assertEq(smallestValue, 50_000);
    }

    // ---------------------------------------------------------------- helpers

    function _assertFault(
        bytes memory script,
        BtcTransactionReader.OpReturnFault expected
    ) private pure {
        BtcTransactionReader.FlyoverOpReturn memory r = _read(script);
        assertTrue(r.found);
        assertEq(uint8(r.fault), uint8(expected));
        assertEq(r.destination, address(0));
        assertEq(r.maxGasLimit, 0);
        assertEq(r.data.length, 0);
    }

    function _assertMalformed(bytes memory script) private pure {
        (bool found, bool wellFormed, bytes memory data) = BtcTransactionReader
            .findFirstOpReturn(BtcUtils.getOutputs(_tx1(script)));
        assertTrue(found);
        assertFalse(wellFormed);
        assertEq(data.length, 0);
    }
}
