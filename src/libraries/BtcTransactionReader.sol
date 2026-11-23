// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {BtcUtils} from "@rsksmart/btc-transaction-solidity-helper/contracts/BtcUtils.sol";

/// @title BtcTransactionReader
/// @notice Reads serialized Bitcoin transactions — the values inside them, and which serialization
/// they are. No derivation, no script math: every function here takes bytes that already exist and
/// inspects them.
/// @dev Separate from {PegInDerivation} on purpose. That library answers "which script should a
/// deposit carry", which is a formula; this one answers "what does this transaction actually pay",
/// which is a lookup. The two change for different reasons — a derivation change rotates every
/// issued address, an output-matching change does not — and keeping them apart means neither
/// reads as the other.
///
/// It stays a library rather than a private function on each consumer because both
/// `PegInAddressRegistry` (gating registration on a minimum deposit) and
/// `PegInContract.requestPegIn` (fixing the peg-in amount) must apply the SAME matching rule. Two
/// copies of the loop could drift, and a drift there means an address registers against one value
/// and settles against another.
///
/// It also decodes the Flyover payload of a deposit's OP_RETURN output ({readFlyoverOpReturn}).
/// That payload is a value inside the transaction, so reading it is a lookup like the others: it
/// builds nothing. docs/PEGIN_OP_RETURN.md describes the layout.
library BtcTransactionReader {
    /// @notice Why a deposit's first OP_RETURN output is not a valid Flyover contract call
    /// @dev Layout: `magic:1 (0xF0) | version:1 (1) | destContract:20 | maxGasLimit:4 (big-endian) |
    /// callData`
    /// - None: no fault; the payload is valid, or there is no OP_RETURN
    /// - BadPush: the script is not OP_RETURN followed by one direct push or one OP_PUSHDATA1 push
    /// - TooShort: the pushed data is shorter than the 26-byte fixed part
    /// - WrongMagic: the first byte is not 0xF0
    /// - WrongVersion: the second byte is not 1
    /// - ZeroDestination: destContract is the zero address
    enum OpReturnFault {
        None,
        BadPush,
        TooShort,
        WrongMagic,
        WrongVersion,
        ZeroDestination
    }

    /// @notice Offset of callData inside a Flyover OP_RETURN payload; also the payload's minimum length
    uint256 internal constant FLYOVER_CALL_DATA_OFFSET = 26;

    bytes1 private constant _OP_RETURN = 0x6a;
    uint8 private constant _OP_PUSHDATA1 = 0x4c;
    bytes1 private constant _FLYOVER_MAGIC = 0xF0;
    uint8 private constant _FLYOVER_VERSION = 1;
    uint256 private constant _FLYOVER_DESTINATION_OFFSET = 2;
    uint256 private constant _FLYOVER_GAS_OFFSET = 22;

    /// @notice Thrown when raw transaction bytes are too short to classify as a transaction at all.
    /// @dev Guards the marker+flag read in {requireWitnessStripped} so malformed input reverts with
    /// a reason instead of panicking out of bounds.
    error InvalidBtcTransaction();

    /// @notice Thrown when a caller supplies the BIP144 (witness-included) serialization of a
    /// transaction where the witness-stripped form is required.
    /// @dev DELIBERATE and CURRENTLY TOTAL: Flyover registers peg-ins witness-stripped, because the
    /// LPS reads deposits with `GetRawTransaction`, which returns the non-witness form. Both
    /// serializations of one segwit transaction carry the same outputs but hash differently (txid vs
    /// wtxid), so accepting both would let one deposit present under two identities.
    ///
    /// Supporting the witness form is not a matter of relaxing this check: it needs
    /// `registerBtcCoinbaseTransaction` and the witness merkle root. Whoever does that work must
    /// revisit this guard rather than delete it.
    error WitnessSerializedTxNotAccepted();

    /// @notice Reverts unless `btcTxSerialized` is the witness-stripped serialization.
    /// @dev MUST be called before hashing caller-supplied transaction bytes. `BtcUtils.hashBtcTx`
    /// double-sha256s whatever it is handed, so it returns a wtxid for the witness form; every
    /// identity Flyover derives from a transaction hash (`pegInId`, the SPV proof) assumes a txid.
    /// `BtcUtils.getOutputs` skips the marker+flag and reads the same outputs from both forms, so
    /// nothing downstream notices the difference on its own.
    ///
    /// The discrimination is exact in both directions. A BIP144 transaction always carries
    /// `00 01` at offsets 4 and 5, so no witness serialization slips through. In the legacy
    /// encoding offset 4 is the input-count compactSize, which is never `0x00` because a
    /// transaction with no inputs is invalid — that is why BIP144 chose `0x00` as the marker — so
    /// no valid witness-stripped transaction is rejected.
    /// @param btcTxSerialized The raw transaction bytes to classify
    function requireWitnessStripped(bytes calldata btcTxSerialized) internal pure {
        if (btcTxSerialized.length < 6) revert InvalidBtcTransaction();
        if (btcTxSerialized[4] == 0x00 && btcTxSerialized[5] == 0x01) {
            revert WitnessSerializedTxNotAccepted();
        }
    }

    /// @notice Searches the outputs of `btcTxSerialized` for the FIRST one locked by `pkScript`
    /// and returns its satoshi value.
    /// @dev A search, not an accessor: the `found` flag is the failure mode, and both call sites
    /// turn it into their own named error (a library revert would flatten the two into one).
    ///
    /// FIRST match, not the sum of every matching output. A deposit split across several outputs
    /// to the same derived address therefore counts only its first output, which UNDERSTATES the
    /// deposit — the name says `First` so no caller mistakes this for the amount paid. The
    /// registry uses the value only as a minimum-deposit gate, where undercounting is
    /// conservative. `PegInContract.requestPegIn` reads the same first output through
    /// {findOutputsPaying}. docs/PEGIN_DEPOSIT_OUTPUTS.md records why the amount is the first
    /// output and not the sum.
    /// @param btcTxSerialized The witness-stripped raw transaction
    /// @param pkScript The scriptPubkey to search for, from {PegInDerivation-depositPkScript}
    /// @return value The matched output's value in satoshis, 0 when no output matched
    /// @return found Whether any output was locked by `pkScript`
    function findFirstOutputPaying(bytes calldata btcTxSerialized, bytes memory pkScript)
        internal
        pure
        returns (uint64 value, bool found)
    {
        BtcUtils.TxRawOutput[] memory outputs = BtcUtils.getOutputs(btcTxSerialized);
        bytes32 pkScriptHash = keccak256(pkScript);
        uint256 outputCount = outputs.length;
        for (uint256 i = 0; i < outputCount; ++i) {
            if (keccak256(outputs[i].pkScript) == pkScriptHash) {
                return (outputs[i].value, true);
            }
        }
        return (0, false);
    }

    /// @notice Searches every output locked by `pkScript` and returns the first one's value and the
    /// smallest value among them.
    /// @dev The first value is the one {findFirstOutputPaying} returns. The smallest value exists
    /// for the bridge minimum: the RSK bridge refuses a flyover deposit when ANY output paying the
    /// deposit address is below its minimum, not only the first. See
    /// docs/PEGIN_DEPOSIT_OUTPUTS.md.
    ///
    /// Takes the parsed outputs, not the raw transaction, so a caller that reads more than one
    /// thing from the same transaction parses it once. `BtcUtils.getOutputs` copies every output
    /// script into memory, so each extra parse costs gas in proportion to the transaction size.
    /// @param outputs The outputs of the witness-stripped raw transaction, from
    /// `BtcUtils.getOutputs`
    /// @param pkScript The scriptPubkey to search for, from {PegInDerivation-depositPkScript}
    /// @return firstValue The first matched output's value in satoshis, 0 when no output matched
    /// @return smallestValue The smallest matched output's value in satoshis, 0 when no output
    /// matched
    /// @return found Whether any output was locked by `pkScript`
    function findOutputsPaying(BtcUtils.TxRawOutput[] memory outputs, bytes memory pkScript)
        internal
        pure
        returns (uint64 firstValue, uint64 smallestValue, bool found)
    {
        bytes32 pkScriptHash = keccak256(pkScript);
        uint256 outputCount = outputs.length;
        smallestValue = type(uint64).max;
        for (uint256 i = 0; i < outputCount; ++i) {
            if (keccak256(outputs[i].pkScript) == pkScriptHash) {
                uint64 value = outputs[i].value;
                if (!found) {
                    firstValue = value;
                    found = true;
                }
                if (value < smallestValue) {
                    smallestValue = value;
                }
            }
        }
        if (!found) {
            smallestValue = 0;
        }
    }

    /// @notice Finds the FIRST output whose script starts with OP_RETURN and returns the data it
    /// pushes.
    /// @dev Only the first OP_RETURN output is read. Any later one is ignored.
    ///
    /// `found` and `wellFormed` are separate so the caller decides what each case means. An
    /// OP_RETURN output is well formed when its script is exactly OP_RETURN, one push opcode, and
    /// the pushed bytes:
    /// - a direct push (`0x01`–`0x4b`), where the opcode is the data length; or
    /// - `OP_PUSHDATA1` (`0x4c`), followed by a 1-byte data length.
    /// The pushed length must end exactly at the end of the script. Any other script, such as a
    /// bare OP_RETURN, `OP_0`, `OP_PUSHDATA2`, `OP_PUSHDATA4`, a second push, or a length that
    /// does not match, is not well formed. Data longer than 255 bytes needs `OP_PUSHDATA2`, so it
    /// is not well formed either.
    ///
    /// `BtcUtils.parseNullDataScript` is not used: it removes only the OP_RETURN byte and returns
    /// the push opcode as the first data byte.
    /// @param outputs The outputs of the witness-stripped raw transaction, from
    /// `BtcUtils.getOutputs`
    /// @return found Whether any output script starts with OP_RETURN
    /// @return wellFormed Whether the first such script has the form above; false when not found
    /// @return data The pushed bytes; empty unless wellFormed
    function findFirstOpReturn(BtcUtils.TxRawOutput[] memory outputs)
        internal
        pure
        returns (bool found, bool wellFormed, bytes memory data)
    {
        uint256 outputCount = outputs.length;
        for (uint256 i = 0; i < outputCount; ++i) {
            bytes memory script = outputs[i].pkScript;
            if (script.length > 0 && script[0] == _OP_RETURN) {
                (wellFormed, data) = _readSinglePush(script);
                return (true, wellFormed, data);
            }
        }
        return (false, false, data);
    }

    /// @notice Reads the first OP_RETURN output as a Flyover contract call
    /// @dev Finds the output with {findFirstOpReturn}, then decodes its payload. Any first
    /// OP_RETURN counts as a Flyover OP_RETURN, so one from another protocol returns a fault,
    /// usually WrongMagic. The caller decides what a fault means; this function only reads.
    ///
    /// maxGasLimit is returned as read. Its allowed range is a contract rule, not part of the
    /// format, so this function does not check it.
    /// @param outputs The outputs of the witness-stripped raw transaction, from
    /// `BtcUtils.getOutputs`
    /// @return found Whether any output script starts with OP_RETURN
    /// @return fault The first check the OP_RETURN fails; None when it is valid or not found
    /// @return destination The contract to call; zero unless found and fault is None
    /// @return maxGasLimit The gas the call requests; 0 unless found and fault is None
    /// @return data The whole payload; callData starts at {FLYOVER_CALL_DATA_OFFSET}. Empty unless
    /// found and fault is None
    function readFlyoverOpReturn(BtcUtils.TxRawOutput[] memory outputs)
        internal
        pure
        returns (bool found, OpReturnFault fault, address destination, uint256 maxGasLimit, bytes memory data)
    {
        bool wellFormed;
        bytes memory payload;
        (found, wellFormed, payload) = findFirstOpReturn(outputs);
        if (!found) return (false, OpReturnFault.None, address(0), 0, data);
        if (!wellFormed) return (true, OpReturnFault.BadPush, address(0), 0, data);

        fault = _checkFlyoverPayload(payload);
        if (fault != OpReturnFault.None) return (true, fault, address(0), 0, data);

        destination = address(uint160(_readBigEndian(payload, _FLYOVER_DESTINATION_OFFSET, _FLYOVER_GAS_OFFSET)));
        if (destination == address(0)) return (true, OpReturnFault.ZeroDestination, address(0), 0, data);
        maxGasLimit = _readBigEndian(payload, _FLYOVER_GAS_OFFSET, FLYOVER_CALL_DATA_OFFSET);
        return (true, OpReturnFault.None, destination, maxGasLimit, payload);
    }

    /// @dev Checks the fixed header of a Flyover payload: its length, the magic byte and the version
    function _checkFlyoverPayload(bytes memory payload) private pure returns (OpReturnFault) {
        if (payload.length < FLYOVER_CALL_DATA_OFFSET) return OpReturnFault.TooShort;
        if (payload[0] != _FLYOVER_MAGIC) return OpReturnFault.WrongMagic;
        if (uint8(payload[1]) != _FLYOVER_VERSION) return OpReturnFault.WrongVersion;
        return OpReturnFault.None;
    }

    /// @dev Reads data[start:end] as a big-endian unsigned integer. end - start is at most 20.
    function _readBigEndian(bytes memory data, uint256 start, uint256 end) private pure returns (uint256 value) {
        for (uint256 i = start; i < end; ++i) {
            value = (value << 8) | uint8(data[i]);
        }
    }

    /// @dev Reads the one push that follows the OP_RETURN byte. See {findFirstOpReturn}.
    function _readSinglePush(bytes memory script) private pure returns (bool wellFormed, bytes memory data) {
        if (script.length < 2) return (false, data);
        uint8 opcode = uint8(script[1]);
        uint256 dataStart;
        uint256 dataLength;
        // A direct push is 0x01-0x4b: the opcode is the data length
        if (opcode > 0 && opcode < _OP_PUSHDATA1) {
            dataStart = 2;
            dataLength = opcode;
        } else if (opcode == _OP_PUSHDATA1) {
            if (script.length < 3) return (false, data);
            dataStart = 3;
            dataLength = uint8(script[2]);
        } else {
            return (false, data);
        }
        if (script.length != dataStart + dataLength) return (false, data);
        data = new bytes(dataLength);
        for (uint256 j = 0; j < dataLength; ++j) {
            data[j] = script[dataStart + j];
        }
        return (true, data);
    }
}
