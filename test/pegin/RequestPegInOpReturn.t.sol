// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {RequestPegInTestBase} from "./RequestPegInTestBase.sol";
import {BtcTransactionReader} from "../../src/libraries/BtcTransactionReader.sol";
import {IPegInCommitFirst} from "../../src/interfaces/IPegInCommitFirst.sol";
import {Flyover} from "../../src/libraries/Flyover.sol";

/// @title requestPegIn validation of the deposit's first OP_RETURN output
contract RequestPegInOpReturnTest is RequestPegInTestBase {
    address internal destination;

    function setUp() public override {
        super.setUp();
        destination = makeAddr("destination");
    }

    // ---- helpers ----

    function _net(uint256 amount) internal pure returns (uint256) {
        return amount - _expectedFee(amount);
    }

    function _expectInvalid(
        bytes memory depositTx,
        BtcTransactionReader.OpReturnFault fault
    ) internal {
        vm.expectRevert(
            abi.encodeWithSelector(
                IPegInCommitFirst.InvalidOpReturn.selector,
                fault
            )
        );
        _requestPegInTx(claimer, rskUser, depositTx, _net(DEFAULT_AMOUNT));
    }

    function _expectGasOutOfRange(
        uint32 maxGasLimit,
        uint256 maxCallGas
    ) internal {
        bytes memory depositTx = _depositTxWithCall(
            rskUser,
            DEFAULT_AMOUNT,
            destination,
            maxGasLimit,
            ""
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                IPegInCommitFirst.CallGasOutOfRange.selector,
                uint256(maxGasLimit),
                maxCallGas
            )
        );
        _requestPegInTx(claimer, rskUser, depositTx, _net(DEFAULT_AMOUNT));
    }

    function _assertClaimed(bytes memory depositTx) internal {
        bytes32 pegInId = _pegInIdForTx(rskUser, depositTx);
        _requestPegInTx(claimer, rskUser, depositTx, _net(DEFAULT_AMOUNT));
        (address claimerAddr, , , ) = _readClaim(pegInId);
        assertEq(claimerAddr, claimer, "claim must be recorded");
    }

    // ---- invalid payload ----

    function test_bareOpReturn_revertsBadPush() public {
        _expectInvalid(
            _depositTxWithScript(rskUser, DEFAULT_AMOUNT, hex"6a"),
            BtcTransactionReader.OpReturnFault.BadPush
        );
    }

    function test_pushData2_revertsBadPush() public {
        bytes memory payload = _callPayload(destination, 100_000, "");
        _expectInvalid(
            _depositTxWithScript(
                rskUser,
                DEFAULT_AMOUNT,
                abi.encodePacked(
                    hex"6a4d",
                    uint16(uint8(payload.length)),
                    payload
                )
            ),
            BtcTransactionReader.OpReturnFault.BadPush
        );
    }

    function test_payloadOf25Bytes_revertsTooShort() public {
        bytes memory payload = _callPayload(destination, 100_000, "");
        bytes memory shortPayload = new bytes(25);
        for (uint256 i = 0; i < 25; ++i) shortPayload[i] = payload[i];
        _expectInvalid(
            _depositTxWithScript(
                rskUser,
                DEFAULT_AMOUNT,
                _opReturnScript(shortPayload)
            ),
            BtcTransactionReader.OpReturnFault.TooShort
        );
    }

    function test_wrongMagic_revertsWrongMagic() public {
        bytes memory payload = _callPayload(destination, 100_000, "");
        payload[0] = 0xF1;
        _expectInvalid(
            _depositTxWithScript(
                rskUser,
                DEFAULT_AMOUNT,
                _opReturnScript(payload)
            ),
            BtcTransactionReader.OpReturnFault.WrongMagic
        );
    }

    /// @notice An OP_RETURN from another protocol counts as a Flyover OP_RETURN, so it reverts.
    /// The bridge's own peg-in OP_RETURN starts with "RSKT".
    function test_otherProtocolOpReturn_revertsWrongMagic() public {
        bytes memory payload = abi.encodePacked(
            "RSKT",
            uint8(1),
            rskUser,
            bytes1(0x00)
        );
        _expectInvalid(
            _depositTxWithScript(
                rskUser,
                DEFAULT_AMOUNT,
                _opReturnScript(payload)
            ),
            BtcTransactionReader.OpReturnFault.WrongMagic
        );
    }

    function test_wrongVersion_revertsWrongVersion() public {
        bytes memory payload = _callPayload(destination, 100_000, "");
        payload[1] = 0x02;
        _expectInvalid(
            _depositTxWithScript(
                rskUser,
                DEFAULT_AMOUNT,
                _opReturnScript(payload)
            ),
            BtcTransactionReader.OpReturnFault.WrongVersion
        );
    }

    function test_zeroDestination_revertsZeroDestination() public {
        _expectInvalid(
            _depositTxWithCall(
                rskUser,
                DEFAULT_AMOUNT,
                address(0),
                100_000,
                ""
            ),
            BtcTransactionReader.OpReturnFault.ZeroDestination
        );
    }

    // ---- maxGasLimit range ----

    function test_zeroMaxGasLimit_revertsCallGasOutOfRange() public {
        _expectGasOutOfRange(0, DEFAULT_MAX_CALL_GAS);
    }

    function test_maxGasLimitAboveMaxCallGas_revertsCallGasOutOfRange() public {
        _expectGasOutOfRange(
            uint32(DEFAULT_MAX_CALL_GAS + 1),
            DEFAULT_MAX_CALL_GAS
        );
    }

    function test_maxCallGasZero_rejectsEveryCall() public {
        configurations.setMaxCallGas(0);
        _expectGasOutOfRange(1, 0);
    }

    function test_maxGasLimitOfOne_isAccepted() public {
        _assertClaimed(
            _depositTxWithCall(rskUser, DEFAULT_AMOUNT, destination, 1, "")
        );
    }

    function test_maxGasLimitEqualToMaxCallGas_isAccepted() public {
        _assertClaimed(
            _depositTxWithCall(
                rskUser,
                DEFAULT_AMOUNT,
                destination,
                uint32(DEFAULT_MAX_CALL_GAS),
                ""
            )
        );
    }

    /// @notice maxGasLimit is big-endian: 0x01000000 must read as 16,777,216, not as 1
    function test_maxGasLimit_isReadBigEndian() public {
        configurations.setMaxCallGas(0x00FFFFFF);
        _expectGasOutOfRange(0x01000000, 0x00FFFFFF);

        configurations.setMaxCallGas(0x01000000);
        _assertClaimed(
            _depositTxWithCall(
                rskUser,
                DEFAULT_AMOUNT,
                destination,
                0x01000000,
                ""
            )
        );
    }

    // ---- order and identity ----

    function test_noOpReturn_isStillAccepted() public {
        _assertClaimed(_defaultTx());
    }

    /// @notice The amount rules run first, so an invalid OP_RETURN on a deposit below the minimum
    /// reports the amount
    function test_amountRulesRunBeforeTheOpReturn() public {
        uint256 amount = TEST_MIN_PEGIN - Flyover.SAT_TO_WEI_CONVERSION;
        bytes memory depositTx = _depositTxWithScript(rskUser, amount, hex"6a");
        vm.expectRevert(
            abi.encodeWithSelector(
                IPegInCommitFirst.PegInBelowMinimum.selector,
                amount,
                TEST_MIN_PEGIN
            )
        );
        _requestPegInTx(claimer, rskUser, depositTx, 0);
    }

    /// @notice Only the first OP_RETURN is read: a valid second one does not rescue an invalid first
    function test_onlyTheFirstOpReturnIsRead() public {
        bytes[] memory pkScripts = new bytes[](3);
        pkScripts[0] = _depositPkScript(rskUser);
        pkScripts[1] = hex"6a";
        pkScripts[2] = _opReturnScript(_callPayload(destination, 100_000, ""));
        uint64[] memory valuesSats = new uint64[](3);
        valuesSats[0] = _toSats(DEFAULT_AMOUNT);
        _expectInvalid(
            _buildTx(pkScripts, valuesSats, DEFAULT_TX_NONCE),
            BtcTransactionReader.OpReturnFault.BadPush
        );
    }

    /// @notice The LP cannot change the OP_RETURN: a different OP_RETURN is a different
    /// transaction, so it has a different txid and pegInId, and the bridge proof is for the
    /// original transaction
    function test_changedOpReturn_givesAnotherPegInId() public view {
        bytes memory original = _depositTxWithCall(
            rskUser,
            DEFAULT_AMOUNT,
            destination,
            100_000,
            hex"deadbeef"
        );
        bytes memory changed = _depositTxWithCall(
            rskUser,
            DEFAULT_AMOUNT,
            address(0xBEEF),
            100_000,
            hex"deadbeef"
        );
        assertTrue(
            _pegInIdForTx(rskUser, original) != _pegInIdForTx(rskUser, changed)
        );
    }
}
