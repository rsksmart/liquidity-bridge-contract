// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {OpCodes} from "@rsksmart/btc-transaction-solidity-helper/contracts/OpCodes.sol";

/// @title PegInDerivation
/// @notice Step-composed peg-in deposit-address derivation helpers.
/// @dev Each derivation step is a separate function so callers (e.g. {PegInAddressRegistry})
/// compose the flyover redeem script and P2SH payload without duplicating script math.
library PegInDerivation {
    /// @notice Versioned scheme tag mixed into every derivation.
    bytes internal constant DERIVATION_DOMAIN = "FLYOVER_PEGIN_V1";

    /// @notice FIXED protocol-wide placeholder for `userRefundBtcAddress`.
    function refundPlaceholderBtc() internal pure returns (bytes memory) {
        return hex"6f044f0ba3d3a2bd0724db5e6d59a0bb62f4ef0cc2";
    }

    /// @notice FIXED protocol-wide placeholder for `liquidityProviderBtcAddress`.
    function lpPlaceholderBtc() internal pure returns (bytes memory) {
        return hex"6f044f0ba3d3a2bd0724db5e6d59a0bb62f4ef0cc2";
    }

    /// @notice The derivation-arguments hash for `rskAddr`.
    function derivationArgumentsHash(address rskAddr) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(DERIVATION_DOMAIN, rskAddr));
    }

    /// @notice The 32-byte derivation value mixed with placeholders and the PegInContract address.
    function derivationValue(address rskAddr, address pegInContract) internal pure returns (bytes32) {
        return keccak256(
            bytes.concat(
                derivationArgumentsHash(rskAddr), refundPlaceholderBtc(), bytes20(pegInContract), lpPlaceholderBtc()
            )
        );
    }

    /// @notice Flyover redeem script: OP_PUSHBYTES_32 <derivationValue> OP_DROP <activePowpegRedeemScript>.
    function flyoverRedeemScript(bytes32 derivationValue_, bytes memory activePowpegRedeemScript)
        internal
        pure
        returns (bytes memory)
    {
        return bytes.concat(OpCodes.OP_PUSHBYTES_32, derivationValue_, OpCodes.OP_DROP, activePowpegRedeemScript);
    }

    /// @notice HASH160 of the flyover redeem script.
    function flyoverScriptHash(bytes memory redeemScript) internal pure returns (bytes20) {
        return ripemd160(abi.encodePacked(sha256(redeemScript)));
    }

    /// @notice On-chain P2SH scriptPubkey: OP_HASH160 <hash160> OP_EQUAL.
    function p2shScriptPubkey(bytes20 scriptHash) internal pure returns (bytes memory) {
        return bytes.concat(OpCodes.OP_HASH160, bytes1(uint8(20)), scriptHash, OpCodes.OP_EQUAL);
    }

    /// @notice Base58check payload of the PLAIN P2SH deposit address.
    function depositAddressPayload(bytes20 scriptHash, bool mainnet) internal pure returns (bytes memory) {
        bytes1 version = mainnet ? bytes1(0x05) : bytes1(0xC4);
        bytes memory versionedHash = bytes.concat(version, scriptHash);
        bytes32 checksum = sha256(abi.encodePacked(sha256(versionedHash)));
        return bytes.concat(versionedHash, checksum[0], checksum[1], checksum[2], checksum[3]);
    }
}
