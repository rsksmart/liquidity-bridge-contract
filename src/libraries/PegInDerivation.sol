// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {OpCodes} from "@rsksmart/btc-transaction-solidity-helper/contracts/OpCodes.sol";

/// @title PegInDerivation
/// @notice SINGLE SOURCE OF TRUTH for the commit-first peg-in deposit-address derivation.
/// Both `PegInAddressRegistry` (address issuance and deposit-gated registration)
/// and the peg-in settlement path MUST derive through this library, so the address the
/// user pays is byte-for-byte the address the Bridge re-derives at settlement.
///
/// @dev The native fast bridge (`registerFastBridgeBtcTransaction`) is never told the deposit
/// address: it re-derives it from the call's arguments plus the active powpeg redeem script, then
/// scans the SPV-proven transaction for an output paying it. The SHAPE of the derivation below was
/// validated end-to-end on a live regtest against the UNMODIFIED powpeg bridge (rskj 9.0.2,
/// 2026-06-30, settle tx 0x174ab0df7cc86648a40d9b36da95fd4dacf2f18c135606141d532b7d1363c7de). That
/// run used a real regtest p2pkh as the two BTC placeholders; they are now the per-network ZERO
/// address (see {getRefundPlaceholderBtcAddress}). The zero-address form is well-formed and
/// non-empty, but no end-to-end run has yet settled with it — the settlement path does not exist on
/// this branch (`PegInContract.resolvePegIn` reverts `ResolvePegInNotImplemented`). Proving the
/// bridge accepts a zero-hash address is owed by the settlement work, and is a merge gate for
/// production, not a property this library may assume:
///
///   derivationArgumentsHash = keccak256(DERIVATION_DOMAIN ++ rskAddr)                    (step 1)
///   derivationValue         = keccak256(
///       derivationArgumentsHash
///       ++ getRefundPlaceholderBtcAddress(isMainnet) // userRefundBtcAddress (21-byte constant)
///       ++ bytes20(pegInContract)                    // lbcAddress = the contract CALLING the bridge
///       ++ getLpPlaceholderBtcAddress(isMainnet)     // liquidityProviderBtcAddress (same constant)
///   )                                                                                    (step 2)
///   flyoverRedeemScript = OP_PUSHBYTES_32 ++ derivationValue ++ OP_DROP
///                         ++ activePowpegRedeemScript                                    (step 3)
///   flyoverScriptHash   = HASH160(flyoverRedeemScript)                                   (step 4)
///   depositAddress      = base58check(version ++ flyoverScriptHash)   // PLAIN P2SH      (step 5)
///
/// Each step is a separate function taking the previous step's output, so every consumer enters
/// the pipeline at the step it needs and none re-implements any script math.
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

    /// @notice Base58check version byte of a mainnet P2SH address — the leading byte of the
    /// deposit-address payload built in {depositAddressPayload}.
    bytes1 internal constant P2SH_VERSION_MAINNET = 0x05;

    /// @notice Base58check version byte of a testnet/regtest P2SH address. Differing from
    /// {P2SH_VERSION_MAINNET} is what keeps the two networks' deposit addresses disjoint.
    bytes1 internal constant P2SH_VERSION_TESTNET = 0xC4;

    /// @notice The P2PKH zero address payload for mainnet: version byte `0x00` followed by a
    /// 20-byte zero HASH160. Well-formed and non-empty, but provably unspendable.
    bytes internal constant BITCOIN_ZERO_ADDRESS_MAINNET = hex"000000000000000000000000000000000000000000";

    /// @notice The P2PKH zero address payload for testnet/regtest: version byte `0x6f` followed by
    /// a 20-byte zero HASH160. Differs from {BITCOIN_ZERO_ADDRESS_MAINNET} ONLY in the version
    /// byte, which is enough to make every address derived from it a different address.
    bytes internal constant BITCOIN_ZERO_ADDRESS_TESTNET = hex"6f0000000000000000000000000000000000000000";

    // ---------------------------------------------------------------------------------------------
    // WHERE THE FAILURE-REFUND MONEY GOES (applies to BOTH accessors below)
    //
    // The two BTC placeholders are FIXED protocol-wide values, mixed into the deposit address AND
    // passed to the bridge at settlement. Each MUST be identical at address issuance and settlement,
    // is NEVER empty (the bridge rejects an empty address with -900) and is NEVER the serving LP's
    // address (the deposit address stays LP-agnostic).
    //
    // Both are the per-network P2PKH ZERO ADDRESS — `version ++ 20 zero bytes`. The value is
    // network-dependent because the version byte is, so the two networks derive disjoint address
    // sets. Once the first address is issued on a network the value is frozen: changing it rotates
    // every derived address and requires the full drain-then-rotate procedure.
    //
    // The bridge's FAILURE-REFUND path — taken only when a fast-bridge peg-in is rejected after the
    // BTC is locked — pays the refund placeholder, not the depositing user and not the LP. A
    // zero-hash address has no spending key, so any BTC that goes down that path is BURNED.
    //
    // A future version may point these placeholders at a monitored, recoverable, protocol-owned
    // treasury address instead (one per network, e.g. a Flyover-treasury multisig), which would give
    // the failure-refund path a recoverable destination. The two accessors are kept separate so such
    // a change can point the refund and LP roles at distinct addresses. Repointing either value
    // rotates every derived address, so it carries the same drain-then-rotate cost as a federation
    // change.
    // ---------------------------------------------------------------------------------------------

    /// @notice The protocol-wide placeholder for the bridge's `userRefundBtcAddress` argument.
    /// See the failure-refund comment above for what this address receives and why it is frozen.
    /// @param isMainnet True for the mainnet zero address, false for testnet/regtest
    /// @return The 21-byte (version ++ HASH160) refund placeholder for the target network
    function getRefundPlaceholderBtcAddress(bool isMainnet) internal pure returns (bytes memory) {
        return isMainnet ? BITCOIN_ZERO_ADDRESS_MAINNET : BITCOIN_ZERO_ADDRESS_TESTNET;
    }

    /// @notice The protocol-wide placeholder for the bridge's `liquidityProviderBtcAddress`
    /// argument. Same value and same constraints as {getRefundPlaceholderBtcAddress} — see the
    /// failure-refund comment above; it is NOT the serving LP's address.
    /// @param isMainnet True for the mainnet zero address, false for testnet/regtest
    /// @return The 21-byte (version ++ HASH160) liquidity-provider placeholder for the network
    function getLpPlaceholderBtcAddress(bool isMainnet) internal pure returns (bytes memory) {
        return isMainnet ? BITCOIN_ZERO_ADDRESS_MAINNET : BITCOIN_ZERO_ADDRESS_TESTNET;
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
    /// @param isMainnet True to mix the mainnet placeholders, false for testnet/regtest. The
    /// placeholders are network-dependent (see {getRefundPlaceholderBtcAddress}), so this flag
    /// changes the derived value — and therefore the deposit address — on every network.
    /// @return The keccak256 hash the bridge embeds in the flyover redeem script
    function derivationValue(address rskAddr, address pegInContract, bool isMainnet) internal pure returns (bytes32) {
        return keccak256(
            bytes.concat(
                derivationArgumentsHash(rskAddr),
                getRefundPlaceholderBtcAddress(isMainnet),
                bytes20(pegInContract),
                getLpPlaceholderBtcAddress(isMainnet)
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
    /// version ({P2SH_VERSION_MAINNET} / {P2SH_VERSION_TESTNET}) ++ scriptHash ++ 4-byte
    /// double-sha256 checksum.
    /// Returned as the raw 25 bytes — the caller (SDK/LPS) base58-ENCODEs them to the address
    /// string shown to the user. MUST stay a plain P2SH: the segwit-wrapped form is pitfall #2
    /// (-304).
    /// @param scriptHash Step 4's output
    /// @param isMainnet True for {P2SH_VERSION_MAINNET}, false for {P2SH_VERSION_TESTNET}
    /// @return The 25-byte base58check payload of the deposit address
    function depositAddressPayload(bytes20 scriptHash, bool isMainnet) internal pure returns (bytes memory) {
        bytes1 version = isMainnet ? P2SH_VERSION_MAINNET : P2SH_VERSION_TESTNET;
        bytes memory versionedHash = bytes.concat(version, scriptHash);
        bytes32 checksum = sha256(abi.encodePacked(sha256(versionedHash)));
        return bytes.concat(versionedHash, checksum[0], checksum[1], checksum[2], checksum[3]);
    }
}
