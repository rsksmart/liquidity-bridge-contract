// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {OpCodes} from "@rsksmart/btc-transaction-solidity-helper/contracts/OpCodes.sol";

/// @title PegInDerivation
/// @notice SINGLE SOURCE OF TRUTH for the commit-first peg-in deposit-address derivation. Both
/// `PegInAddressRegistry` (which shows the deposit address and gates registration) and
/// `PegInContract` (which settles via the native fast bridge) MUST use these helpers so the
/// address the user pays is byte-for-byte the address the bridge re-derives at settlement.
///
/// @dev The native fast bridge (`registerFastBridgeBtcTransaction`) re-derives the flyover deposit
/// address from the arguments passed to it. The proven formula (EB.1 spike, validated end-to-end on
/// a live regtest against the UNMODIFIED powpeg bridge — see
/// EPICS/FOUNDATION/EB-settlement-address-derivation) is:
///
///   derivationArgumentsHash = keccak256(DERIVATION_DOMAIN, rskAddr)
///   derivationValue         = keccak256(
///       derivationArgumentsHash
///       ++ REFUND_PLACEHOLDER_BTC          // userRefundBtcAddress  (FIXED 21-byte protocol constant)
///       ++ bytes20(pegInContract)          // lbcAddress = the contract that CALLS the bridge
///       ++ LP_PLACEHOLDER_BTC              // liquidityProviderBtcAddress (FIXED 21-byte constant)
///   )
///   flyoverRedeemScript     = OP_PUSHBYTES_32 ++ derivationValue ++ OP_DROP ++ activePowpegRedeemScript
///   depositP2SH             = base58check( version ++ HASH160(flyoverRedeemScript) )   // PLAIN P2SH
///
/// Two corrections vs. the original E2 design were required (both proven):
///   1. The address-mixing above (the original used `keccak256(DOMAIN, rskAddr)` directly as the
///      redeem-script tag, while the bridge re-hashed it with the three addresses → -900).
///   2. A PLAIN P2SH of the flyover redeem script — NOT the segwit-wrapped P2SH-of-P2WSH the original
///      built (the wrapped form settled as -304 VALUE_ZERO).
library PegInDerivation {
    /// @notice Versioned scheme tag mixed into every derivation. Bumping it deterministically
    /// changes every derived address (the same path the system handles for a federation change).
    bytes internal constant DERIVATION_DOMAIN = "FLYOVER_PEGIN_V1";

    /// @notice FIXED protocol-wide placeholder for `userRefundBtcAddress`, mixed into the deposit
    /// address AND passed to the bridge at settlement. It MUST be identical in the registry and in
    /// the settlement path, and it MUST be a real, well-formed 21-byte (version || HASH160) BTC
    /// address — NEVER empty (the bridge rejects an empty address with -900) and NEVER the serving
    /// LP's address (so the deposit address stays LP-agnostic).
    ///
    /// PRODUCTION: replace this regtest/testnet placeholder with a SINGLE, protocol-owned, MONITORED
    /// BTC address (e.g. a Flyover-treasury / multisig). The bridge's FAILURE-REFUND path (taken only
    /// when a fast-bridge peg-in is rejected after the BTC is locked) sends the locked BTC to THIS
    /// address — not back to the depositing user and not to the LP — so it must be a recoverable,
    /// monitored sink, never an EOA whose key can be lost. The current value is the spike's regtest
    /// P2PKH `mfujgzmRixnsDfxN9u9yck1k3xtx9qCf2F` (version 0x6f testnet).
    function refundPlaceholderBtc() internal pure returns (bytes memory) {
        return hex"6f044f0ba3d3a2bd0724db5e6d59a0bb62f4ef0cc2";
    }

    /// @notice FIXED protocol-wide placeholder for `liquidityProviderBtcAddress`. Same constraints
    /// and same production guidance as {refundPlaceholderBtc}; it is NOT the serving LP's address.
    /// Kept as a separate accessor so production can point the two roles at distinct addresses if
    /// desired. Currently the same regtest placeholder as the refund address.
    function lpPlaceholderBtc() internal pure returns (bytes memory) {
        return hex"6f044f0ba3d3a2bd0724db5e6d59a0bb62f4ef0cc2";
    }

    /// @notice The `derivationArgumentsHash` passed to the bridge as the FIRST member of the mix.
    /// @param rskAddr The RSK address the deposit address is derived for
    function derivationArgumentsHash(address rskAddr) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(DERIVATION_DOMAIN, rskAddr));
    }

    /// @notice The 32-byte derivation value the bridge bakes into the flyover redeem script: the
    /// argsHash mixed with the two placeholders and the calling LBC (PegInContract) address.
    /// @param rskAddr The RSK address
    /// @param pegInContract The PegInContract address (the lbcAddress that calls the bridge)
    function derivationValue(address rskAddr, address pegInContract) internal pure returns (bytes32) {
        return keccak256(
            bytes.concat(
                derivationArgumentsHash(rskAddr),
                refundPlaceholderBtc(),
                bytes20(pegInContract),
                lpPlaceholderBtc()
            )
        );
    }

    /// @notice The flyover redeem script the bridge wraps as a PLAIN P2SH:
    /// OP_PUSHBYTES_32 <derivationValue> OP_DROP <activePowpegRedeemScript>.
    /// @param rskAddr The RSK address
    /// @param pegInContract The PegInContract (lbcAddress)
    /// @param activePowpegRedeemScript The live powpeg redeem script (read from the bridge)
    function flyoverRedeemScript(
        address rskAddr,
        address pegInContract,
        bytes memory activePowpegRedeemScript
    ) internal pure returns (bytes memory) {
        return bytes.concat(
            OpCodes.OP_PUSHBYTES_32,
            derivationValue(rskAddr, pegInContract),
            OpCodes.OP_DROP,
            activePowpegRedeemScript
        );
    }

    /// @notice HASH160 (ripemd160 of sha256) of the flyover redeem script: the 20-byte P2SH hash.
    function flyoverScriptHash(
        address rskAddr,
        address pegInContract,
        bytes memory activePowpegRedeemScript
    ) internal pure returns (bytes20) {
        return ripemd160(
            abi.encodePacked(
                sha256(flyoverRedeemScript(rskAddr, pegInContract, activePowpegRedeemScript))
            )
        );
    }

    /// @notice The on-chain P2SH scriptPubkey a deposit must carry: OP_HASH160 <hash160> OP_EQUAL.
    /// This is the raw pkScript form a parsed tx output exposes, so deposit-gating compares it directly.
    function p2shScriptPubkey(
        address rskAddr,
        address pegInContract,
        bytes memory activePowpegRedeemScript
    ) internal pure returns (bytes memory) {
        return bytes.concat(
            OpCodes.OP_HASH160,
            bytes1(uint8(20)),
            flyoverScriptHash(rskAddr, pegInContract, activePowpegRedeemScript),
            OpCodes.OP_EQUAL
        );
    }

    /// @notice The base58check payload of the PLAIN P2SH deposit address:
    /// version(0x05 mainnet / 0xC4 testnet) || HASH160(flyoverRedeemScript) || 4-byte checksum.
    /// Returned as raw bytes (the caller base58-ENCODEs them to the address string), matching the
    /// shape the registry's getters return.
    function depositAddressPayload(
        address rskAddr,
        address pegInContract,
        bytes memory activePowpegRedeemScript,
        bool mainnet
    ) internal pure returns (bytes memory) {
        bytes1 version = mainnet ? bytes1(0x05) : bytes1(0xC4);
        bytes memory versionedHash = bytes.concat(
            version,
            flyoverScriptHash(rskAddr, pegInContract, activePowpegRedeemScript)
        );
        bytes32 checksum = sha256(abi.encodePacked(sha256(versionedHash)));
        return bytes.concat(versionedHash, checksum[0], checksum[1], checksum[2], checksum[3]);
    }
}
