// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {OpCodes} from "@rsksmart/btc-transaction-solidity-helper/contracts/OpCodes.sol";
import {Base58} from "@openzeppelin/contracts/utils/Base58.sol";

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
/// Two known pitfalls, both proven on-chain and both encoded as negative tests:
///   1. Keying the redeem-script tag with `derivationArgumentsHash` directly (skipping step 2's
///      address mixing) makes the bridge re-derive a DIFFERENT address and fail with -900
///      (FAST_BRIDGE_GENERIC_ERROR).
///   2. Wrapping the redeem script as a segwit P2SH-of-P2WSH instead of a PLAIN P2SH settles as
///      -304 (VALUE_ZERO): the bridge derives the plain form and attributes zero value.
///
/// SEGWIT / FEDERATION-FORMAT NOTE: rskj selects plain P2SH vs P2SH-P2WSH wrapping via
/// `PegUtils.getFlyoverFederationOutputScript` (legacy federation formats vs
/// `P2SH_P2WSH_ERP_FEDERATION` = 4000). Live mainnet/testnet powpegs use the segwit branch.
/// {inferFederationFormat} reads `IBridge.getFederationAddress()` at derivation time and
/// compares the decoded script hash against both wrapping candidates — see
/// `docs/pegin/federation-format-detection.md`.
library PegInDerivation {
    /// @notice Powpeg federation output wrapping variants replicated from rskj.
    enum FederationFormat {
        PlainP2SH,
        SegwitP2SHP2WSH
    }

    /// @notice Federation address payload is not a valid base58check P2SH encoding.
    error InvalidFederationAddress();

    /// @notice Decoded federation script hash matches neither plain nor segwit candidate.
    error UnrecognizedFederationFormat();
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
    function derivationArgumentsHash(
        address rskAddr
    ) internal pure returns (bytes32) {
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
    function derivationValue(
        address rskAddr,
        address pegInContract
    ) internal pure returns (bytes32) {
        return
            keccak256(
                bytes.concat(
                    derivationArgumentsHash(rskAddr),
                    refundPlaceholderBtc(),
                    bytes20(pegInContract),
                    lpPlaceholderBtc()
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
    function flyoverRedeemScript(
        bytes32 derivationValue_,
        bytes memory activePowpegRedeemScript
    ) internal pure returns (bytes memory) {
        return
            bytes.concat(
                OpCodes.OP_PUSHBYTES_32,
                derivationValue_,
                OpCodes.OP_DROP,
                activePowpegRedeemScript
            );
    }

    /// @notice Step 4 (plain path): HASH160 of the flyover redeem script — the 20-byte hash a
    /// legacy-federation P2SH output commits to.
    /// @param redeemScript Step 3's output
    /// @return The 20-byte P2SH script hash
    function flyoverScriptHash(
        bytes memory redeemScript
    ) internal pure returns (bytes20) {
        return ripemd160(abi.encodePacked(sha256(redeemScript)));
    }

    /// @notice Segwit step 4 witness program: OP_0 OP_PUSHBYTES_32 sha256(redeemScript).
    /// @param redeemScript Step 3's flyover redeem script
    /// @return The 34-byte witness program committed to by P2SH-P2WSH federation outputs
    function witnessProgram(
        bytes memory redeemScript
    ) internal pure returns (bytes memory) {
        return
            bytes.concat(
                OpCodes.OP_0,
                OpCodes.OP_PUSHBYTES_32,
                sha256(redeemScript)
            );
    }

    /// @notice Segwit step 4: HASH160 of the witness program (P2SH-P2WSH federation form).
    /// @param redeemScript Step 3's flyover redeem script
    /// @return The 20-byte P2SH script hash for segwit federation wrapping
    function witnessProgramHash(
        bytes memory redeemScript
    ) internal pure returns (bytes20) {
        return flyoverScriptHash(witnessProgram(redeemScript));
    }

    /// @notice Step 4 parameterized by federation format — plain HASH160(redeem) or segwit
    /// HASH160(OP_0‖sha256(redeem)), byte-matched to rskj `getFlyoverFederationOutputScript`.
    /// @param redeemScript Step 3's flyover redeem script
    /// @param format Active powpeg federation wrapping
    /// @return The 20-byte script hash fed to step 5
    function scriptHashForFormat(
        bytes memory redeemScript,
        FederationFormat format
    ) internal pure returns (bytes20) {
        if (format == FederationFormat.SegwitP2SHP2WSH) {
            return witnessProgramHash(redeemScript);
        }
        return flyoverScriptHash(redeemScript);
    }

    /// @notice Infers federation wrapping from the live federation P2SH address and powpeg script.
    /// @dev Decodes `federationAddressBase58` (base58check) and byte-matches its script hash
    /// against plain HASH160(powpegRedeemScript) and segwit HASH160(OP_0‖sha256(powpeg)).
    /// @param powpegRedeemScript Active powpeg redeem script from the bridge
    /// @param federationAddressBase58 Federation address string from `IBridge.getFederationAddress()`
    /// @return The inferred wrapping format
    function inferFederationFormat(
        bytes memory powpegRedeemScript,
        string memory federationAddressBase58,
        bool /* mainnet */
    ) internal pure returns (FederationFormat) {
        bytes20 federationScriptHash = _scriptHashFromBase58check(
            federationAddressBase58
        );
        bytes20 plainCandidate = flyoverScriptHash(powpegRedeemScript);
        bytes20 segwitCandidate = witnessProgramHash(powpegRedeemScript);
        if (federationScriptHash == segwitCandidate) {
            return FederationFormat.SegwitP2SHP2WSH;
        }
        if (federationScriptHash == plainCandidate) {
            return FederationFormat.PlainP2SH;
        }
        revert UnrecognizedFederationFormat();
    }

    /// @notice Extracts the 20-byte script hash from a base58check-encoded P2SH address.
    function _scriptHashFromBase58check(
        string memory addressBase58
    ) private pure returns (bytes20) {
        bytes memory payload = Base58.decode(addressBase58);
        if (payload.length != 25) {
            revert InvalidFederationAddress();
        }

        bytes memory versionAndHash = new bytes(21);
        for (uint256 i = 0; i < 21; ++i) {
            versionAndHash[i] = payload[i];
        }

        bytes4 expectedChecksum = bytes4(
            sha256(abi.encodePacked(sha256(versionAndHash)))
        );
        if (
            payload[21] != expectedChecksum[0] ||
            payload[22] != expectedChecksum[1] ||
            payload[23] != expectedChecksum[2] ||
            payload[24] != expectedChecksum[3]
        ) {
            revert InvalidFederationAddress();
        }
        bytes20 scriptHash;
        assembly {
            scriptHash := mload(add(payload, 33))
        }
        return scriptHash;
    }

    /// @notice Step 5 (output-script form): the on-chain P2SH scriptPubkey a deposit output must
    /// carry: OP_HASH160 <scriptHash> OP_EQUAL. This is the raw pkScript a parsed transaction
    /// output exposes, so deposit-gating compares it directly against outputs.
    /// @param scriptHash Step 4's output
    /// @return The 23-byte P2SH scriptPubkey
    function p2shScriptPubkey(
        bytes20 scriptHash
    ) internal pure returns (bytes memory) {
        return
            bytes.concat(
                OpCodes.OP_HASH160,
                bytes1(uint8(20)),
                scriptHash,
                OpCodes.OP_EQUAL
            );
    }

    /// @notice Step 5 (address form): the base58check payload of the PLAIN P2SH deposit address:
    /// version (0x05 mainnet / 0xC4 testnet) ++ scriptHash ++ 4-byte double-sha256 checksum.
    /// Returned as the raw 25 bytes — the caller (SDK/LPS) base58-ENCODEs them to the address
    /// string shown to the user. MUST stay a plain P2SH: the segwit-wrapped form is pitfall #2
    /// (-304).
    /// @param scriptHash Step 4's output
    /// @param mainnet True for the mainnet version byte (0x05), false for testnet/regtest (0xC4)
    /// @return The 25-byte base58check payload of the deposit address
    function depositAddressPayload(
        bytes20 scriptHash,
        bool mainnet
    ) internal pure returns (bytes memory) {
        bytes1 version = mainnet ? bytes1(0x05) : bytes1(0xC4);
        bytes memory versionedHash = bytes.concat(version, scriptHash);
        bytes32 checksum = sha256(abi.encodePacked(sha256(versionedHash)));
        return
            bytes.concat(
                versionedHash,
                checksum[0],
                checksum[1],
                checksum[2],
                checksum[3]
            );
    }
}
