// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {BtcUtils} from "@rsksmart/btc-transaction-solidity-helper/contracts/BtcUtils.sol";
import {OpCodes} from "@rsksmart/btc-transaction-solidity-helper/contracts/OpCodes.sol";

/// @title PegInDerivation
/// @notice SINGLE SOURCE OF TRUTH for the commit-first peg-in deposit-address derivation.
/// Both `PegInAddressRegistry` (address issuance and deposit-gated registration)
/// and the peg-in settlement path MUST derive through this library, so the address the
/// user pays is byte-for-byte the address the Bridge re-derives at settlement.
///
/// @dev The native fast bridge (`registerFastBridgeBtcTransaction`) is never told the deposit
/// address: it re-derives it from the call's arguments plus the active powpeg redeem script, then
/// scans the SPV-proven transaction for an output paying it. The derivation below was validated
/// end-to-end on a live regtest against the UNMODIFIED powpeg bridge (rskj 9.0.2, 2026-06-30,
/// settle tx 0x174ab0df7cc86648a40d9b36da95fd4dacf2f18c135606141d532b7d1363c7de):
///
///   derivationArgumentsHash = keccak256(DERIVATION_DOMAIN ++ rskAddr)                    (step 1)
///   derivationValue         = keccak256(
///       derivationArgumentsHash
///       ++ REFUND_PLACEHOLDER_BTC        // userRefundBtcAddress (FIXED 21-byte constant)
///       ++ bytes20(pegInContract)        // lbcAddress = the contract that CALLS the bridge
///       ++ LP_PLACEHOLDER_BTC            // liquidityProviderBtcAddress (FIXED 21-byte constant)
///   )                                                                                    (step 2)
///   flyoverRedeemScript = OP_PUSHBYTES_32 ++ derivationValue ++ OP_DROP
///                         ++ activePowpegRedeemScript                                    (step 3)
///   flyoverScriptHash   = HASH160(flyoverRedeemScript)                                   (step 4)
///   depositAddress      = base58check(version ++ flyoverScriptHash)   // PLAIN P2SH      (step 5)
///
/// Each step is a separate function taking the previous step's output, so every consumer enters
/// the pipeline at the step it needs and none re-implements any script math.
///
/// The pipeline does not stop at the address. Every consumer that reads a VALUE out of a deposit
/// transaction — the registry gating registration, `PegInContract.requestPegIn` computing the
/// peg-in amount — must match outputs against the SAME script this library derives, so
/// {expectedDepositPkScript} and {matchedDepositValue} live here too. A caller-supplied amount is
/// never an input to either path: the amount is a value the contract computes.
///
/// Two known pitfalls, both proven on-chain and both encoded as negative tests:
///   1. Keying the redeem-script tag with `derivationArgumentsHash` directly (skipping step 2's
///      address mixing) makes the bridge re-derive a DIFFERENT address and fail with -900
///      (FAST_BRIDGE_GENERIC_ERROR).
///   2. Wrapping the redeem script as a segwit P2SH-of-P2WSH instead of a PLAIN P2SH settles as
///      -304 (VALUE_ZERO): the bridge derives the plain form and attributes zero value.
///
/// SEGWIT / FEDERATION-FORMAT NOTE: the bridge wraps the flyover redeem script as a PLAIN P2SH
/// for every currently deployed federation format. Newer rskj versions add a segwit federation
/// format (`P2SH_P2WSH_ERP_FEDERATION`) for which `PegUtils.getFlyoverFederationOutputScript`
/// switches to a P2SH-P2WSH wrapping. A powpeg migration to that format rotates every derived
/// address (as any federation change does) AND requires this library to gain a matching wrapping
/// path first — same drain-then-rotate rule as a federation change.
library PegInDerivation {
    /// @notice Versioned scheme tag mixed into every derivation. Bumping it deterministically
    /// rotates every derived address (the same rotation path as a federation change).
    bytes internal constant DERIVATION_DOMAIN = "FLYOVER_PEGIN_V1";

    /// @notice FIXED protocol-wide placeholder for the bridge's `userRefundBtcAddress` argument,
    /// mixed into the deposit address AND passed to the bridge at settlement. It MUST be identical
    /// at address issuance and settlement, and it MUST be a real, well-formed 21-byte
    /// (version ++ HASH160) BTC address — NEVER empty (the bridge rejects an empty address with
    /// -900) and NEVER the serving LP's address (the deposit address stays LP-agnostic).
    ///
    /// PRODUCTION (OPEN treasury-sink decision, walkthrough): replace this regtest placeholder
    /// with a SINGLE, protocol-owned, MONITORED BTC address (e.g. a Flyover-treasury multisig).
    /// The bridge's FAILURE-REFUND path (taken only when a fast-bridge peg-in is rejected after
    /// the BTC is locked) sends the locked BTC to THIS address — not to the depositing user and
    /// not to the LP — so it must be a recoverable, monitored sink, never an EOA whose key can be
    /// lost. Current value: `mfujgzmRixnsDfxN9u9yck1k3xtx9qCf2F`.
    /// @return The 21-byte (version ++ HASH160) refund placeholder
    function refundPlaceholderBtc() internal pure returns (bytes memory) {
        return hex"6f044f0ba3d3a2bd0724db5e6d59a0bb62f4ef0cc2";
    }

    /// @notice FIXED protocol-wide placeholder for the bridge's `liquidityProviderBtcAddress`
    /// argument. Same constraints and same production guidance as {refundPlaceholderBtc}; it is
    /// NOT the serving LP's address. Kept as a separate accessor so production can point the two
    /// roles at distinct addresses if desired.
    /// @return The 21-byte (version ++ HASH160) liquidity-provider placeholder
    function lpPlaceholderBtc() internal pure returns (bytes memory) {
        return hex"6f044f0ba3d3a2bd0724db5e6d59a0bb62f4ef0cc2";
    }

    /// @notice Step 1: the 32-byte `derivationArgumentsHash` passed to the bridge as the FIRST
    /// member of its own mix. The only value of the five steps that Flyover designs: the bridge
    /// ABI gives the caller exactly one 32-byte free slot, so the protocol version and the
    /// destination address compress into it.
    /// @param rskAddr The RSK destination address the deposit address is derived for
    /// @return The keccak256 hash of DERIVATION_DOMAIN ++ rskAddr
    function derivationArgumentsHash(address rskAddr) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(DERIVATION_DOMAIN, rskAddr));
    }

    /// @notice Step 2: the 32-byte derivation value the bridge bakes into the flyover redeem
    /// script — the argsHash mixed with the two placeholders and the calling LBC (PegInContract)
    /// address. Replicated byte-for-byte from the bridge, never designed: keying the redeem
    /// script with step 1's hash directly is pitfall #1 (-900).
    /// @param rskAddr The RSK destination address
    /// @param pegInContract The PegInContract PROXY address (the lbcAddress that calls the bridge;
    /// stable across implementation upgrades, rotates only on a redeploy)
    /// @return The keccak256 hash the bridge embeds in the flyover redeem script
    function derivationValue(address rskAddr, address pegInContract) internal pure returns (bytes32) {
        return keccak256(
            bytes.concat(
                derivationArgumentsHash(rskAddr), refundPlaceholderBtc(), bytes20(pegInContract), lpPlaceholderBtc()
            )
        );
    }

    /// @notice Step 3: the flyover redeem script the bridge wraps as a PLAIN P2SH:
    /// OP_PUSHBYTES_32 <derivationValue> OP_DROP <activePowpegRedeemScript>. The push-then-drop
    /// prefix embeds the 32 bytes without changing the spending condition, so the powpeg keys
    /// still spend the output while every distinct value yields a distinct address.
    /// @param derivationValue_ Step 2's output
    /// @param activePowpegRedeemScript The live powpeg redeem script, read from the bridge at
    /// call time (`getActivePowpegRedeemScript()`), never stored — the only input that changes
    /// on a federation change
    /// @return The flyover redeem script
    function flyoverRedeemScript(bytes32 derivationValue_, bytes memory activePowpegRedeemScript)
        internal
        pure
        returns (bytes memory)
    {
        return bytes.concat(OpCodes.OP_PUSHBYTES_32, derivationValue_, OpCodes.OP_DROP, activePowpegRedeemScript);
    }

    /// @notice Step 4: HASH160 (ripemd160 of sha256) of the flyover redeem script — the 20-byte
    /// hash a P2SH output commits to. Bitcoin's standard recipe; no design freedom.
    /// @param redeemScript Step 3's output
    /// @return The 20-byte P2SH script hash
    function flyoverScriptHash(bytes memory redeemScript) internal pure returns (bytes20) {
        return ripemd160(abi.encodePacked(sha256(redeemScript)));
    }

    /// @notice Step 5 (output-script form): the on-chain P2SH scriptPubkey a deposit output must
    /// carry: OP_HASH160 <scriptHash> OP_EQUAL. This is the raw pkScript a parsed transaction
    /// output exposes, so deposit-gating compares it directly against outputs.
    /// @param scriptHash Step 4's output
    /// @return The 23-byte P2SH scriptPubkey
    function p2shScriptPubkey(bytes20 scriptHash) internal pure returns (bytes memory) {
        return bytes.concat(OpCodes.OP_HASH160, bytes1(uint8(20)), scriptHash, OpCodes.OP_EQUAL);
    }

    /// @notice Step 5 (address form): the base58check payload of the PLAIN P2SH deposit address:
    /// version (0x05 mainnet / 0xC4 testnet) ++ scriptHash ++ 4-byte double-sha256 checksum.
    /// Returned as the raw 25 bytes — the caller (SDK/LPS) base58-ENCODEs them to the address
    /// string shown to the user. MUST stay a plain P2SH: the segwit-wrapped form is pitfall #2
    /// (-304).
    /// @param scriptHash Step 4's output
    /// @param mainnet True for the mainnet version byte (0x05), false for testnet/regtest (0xC4)
    /// @return The 25-byte base58check payload of the deposit address
    function depositAddressPayload(bytes20 scriptHash, bool mainnet) internal pure returns (bytes memory) {
        bytes1 version = mainnet ? bytes1(0x05) : bytes1(0xC4);
        bytes memory versionedHash = bytes.concat(version, scriptHash);
        bytes32 checksum = sha256(abi.encodePacked(sha256(versionedHash)));
        return bytes.concat(versionedHash, checksum[0], checksum[1], checksum[2], checksum[3]);
    }

    /// @notice Steps 2-5 composed: the on-chain P2SH scriptPubkey a deposit output must carry to
    /// count as a deposit for `rskAddr`. The single entry point for deposit matching — the
    /// registry and the peg-in claim path both call this rather than re-composing the steps, so
    /// the script that gates registration and the script that fixes the peg-in amount cannot
    /// drift apart.
    /// @param rskAddr The RSK destination address the deposit address is derived for
    /// @param pegInContract The PegInContract PROXY address mixed into step 2
    /// @param activePowpegRedeemScript The live powpeg redeem script, read from the bridge at
    /// call time — never stored
    /// @return The 23-byte P2SH scriptPubkey of the deposit address
    function expectedDepositPkScript(
        address rskAddr,
        address pegInContract,
        bytes memory activePowpegRedeemScript
    ) internal pure returns (bytes memory) {
        bytes32 derivationValue_ = derivationValue(rskAddr, pegInContract);
        bytes memory redeemScript = flyoverRedeemScript(derivationValue_, activePowpegRedeemScript);
        return p2shScriptPubkey(flyoverScriptHash(redeemScript));
    }

    /// @notice The satoshi value of the FIRST output of `btcTxSerialized` paying `expectedPkScript`.
    /// @dev First match, not the sum of every matching output. A deposit split across several
    /// outputs to the same derived address therefore counts only its first output, which
    /// UNDERSTATES the deposit. That direction is the safe one — the claimer fronts less than the
    /// bridge will release and settlement covers the claim — and it is the rule the registry has
    /// always applied, so the value that gates registration and the value that fixes the peg-in
    /// amount stay identical. Summing would have to change both call sites at once.
    ///
    /// Returns a found flag rather than reverting: the two call sites revert with their own named
    /// errors, and a library revert would flatten them into one.
    /// @param btcTxSerialized The witness-stripped raw deposit transaction
    /// @param expectedPkScript The scriptPubkey from {expectedDepositPkScript}
    /// @return value The matched output's value in satoshis, 0 when no output matched
    /// @return found Whether any output paid `expectedPkScript`
    function matchedDepositValue(bytes calldata btcTxSerialized, bytes memory expectedPkScript)
        internal
        pure
        returns (uint64 value, bool found)
    {
        BtcUtils.TxRawOutput[] memory outputs = BtcUtils.getOutputs(btcTxSerialized);
        bytes32 expectedHash = keccak256(expectedPkScript);
        uint256 outputCount = outputs.length;
        for (uint256 i = 0; i < outputCount; ++i) {
            if (keccak256(outputs[i].pkScript) == expectedHash) {
                return (outputs[i].value, true);
            }
        }
        return (0, false);
    }
}
