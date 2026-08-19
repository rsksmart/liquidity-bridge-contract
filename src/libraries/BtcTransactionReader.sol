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
library BtcTransactionReader {
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
    /// deposit — the name says `First` so no caller mistakes this for the amount paid. The rule is
    /// inherited from the registry, where the value is only a minimum-deposit gate and
    /// undercounting is conservative. `PegInContract.requestPegIn` uses it as the peg-in AMOUNT,
    /// where undercounting silently drops the user's remaining outputs, so summing is the likely
    /// correct rule there; it is not applied yet because the two call sites must move together and
    /// because the reconciling side (`resolvePegIn`, and whether the RSK bridge sums outputs to the
    /// derivation address) is not implemented. Revisit with settlement.
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
}
