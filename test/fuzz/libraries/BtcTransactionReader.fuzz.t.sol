// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {BtcUtils} from "@rsksmart/btc-transaction-solidity-helper/contracts/BtcUtils.sol";
import {BtcTransactionReader} from "../../../src/libraries/BtcTransactionReader.sol";
import {BtcTransactionReaderTestBase} from "../../libraries/BtcTransactionReaderTestBase.sol";

contract BtcTransactionReaderFuzzTest is BtcTransactionReaderTestBase {
    // ---------------------------------------------------------------- findFirstOpReturn

    /// @notice Any script after OP_RETURN is well formed exactly when it is one direct push or one
    /// OP_PUSHDATA1 push whose length ends at the end of the script, and the data is the pushed bytes.
    function testFuzz_findFirstOpReturn_matchesTheSinglePushRule(
        bytes memory afterOpReturn
    ) public pure {
        vm.assume(afterOpReturn.length <= 250);
        bytes memory script = abi.encodePacked(hex"6a", afterOpReturn);

        (bool expectedWellFormed, bytes memory expectedData) = _expectedPush(
            afterOpReturn
        );
        (bool found, bool wellFormed, bytes memory data) = BtcTransactionReader
            .findFirstOpReturn(BtcUtils.getOutputs(_tx1(script)));

        assertTrue(found);
        assertEq(wellFormed, expectedWellFormed);
        assertEq(data, expectedData);
    }

    function testFuzz_findFirstOpReturn_wellFormedDirectPush_roundTrips(
        bytes memory payload
    ) public pure {
        vm.assume(payload.length >= 1 && payload.length <= 75);
        (, bool wellFormed, bytes memory data) = BtcTransactionReader
            .findFirstOpReturn(
                BtcUtils.getOutputs(_tx2(P2PKH, _directPushScript(payload)))
            );
        assertTrue(wellFormed);
        assertEq(data, payload);
    }

    // ---------------------------------------------------------------- readFlyoverOpReturn

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
            : _pushData1Script(payload);

        BtcTransactionReader.FlyoverOpReturn memory r = _read(script);

        assertTrue(r.found);
        assertEq(
            uint8(r.fault),
            uint8(BtcTransactionReader.OpReturnFault.None)
        );
        assertEq(r.destination, destination);
        assertEq(r.maxGasLimit, maxGasLimit);
        assertEq(r.data, payload);
    }

    /// @notice Any pushed bytes get the fault an independent statement of the layout expects
    function testFuzz_readFlyoverOpReturn_matchesTheLayoutRule(
        bytes memory payload
    ) public pure {
        vm.assume(payload.length >= 1 && payload.length <= 75);
        BtcTransactionReader.OpReturnFault expected = _expectedFault(payload);

        BtcTransactionReader.FlyoverOpReturn memory r = _read(
            _directPushScript(payload)
        );

        assertTrue(r.found);
        assertEq(uint8(r.fault), uint8(expected));
    }

    // ---------------------------------------------------------------- helpers

    /// @dev Independent statement of the single-push rule
    function _expectedPush(
        bytes memory s
    ) private pure returns (bool, bytes memory) {
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

    /// @dev Independent statement of the layout checks
    function _expectedFault(
        bytes memory p
    ) private pure returns (BtcTransactionReader.OpReturnFault) {
        if (p.length < 26) return BtcTransactionReader.OpReturnFault.TooShort;
        if (p[0] != 0xF0) return BtcTransactionReader.OpReturnFault.WrongMagic;
        if (p[1] != 0x01)
            return BtcTransactionReader.OpReturnFault.WrongVersion;
        bool zero = true;
        for (uint256 i = 2; i < 22; ++i) {
            if (p[i] != 0) zero = false;
        }
        if (zero) return BtcTransactionReader.OpReturnFault.ZeroDestination;
        return BtcTransactionReader.OpReturnFault.None;
    }
}
