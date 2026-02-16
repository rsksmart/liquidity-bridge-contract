// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {IERC1271} from "@openzeppelin/contracts/interfaces/IERC1271.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

library SignatureValidator {

    using ECDSA for bytes32;
    bytes4 internal constant EIP1271_MAGIC_VALUE_BYTES32 = IERC1271.isValidSignature.selector;
    bytes4 internal constant EIP1271_MAGIC_VALUE_BYTES = 0x20c13b0b;

    error IncorrectSignature(address expectedAddress, bytes32 usedHash, bytes signature);
    error ZeroAddress();
    /**
        @dev Verifies signature against address.
        @dev For EOAs, validates ECDSA over the EIP-191 prefixed hash.
        @dev For contract wallets, validates EIP-1271 (bytes32 path plus bytes fallback compatibility path).
        @param addr The signing address
        @param quoteHash The hash of the signed data
        @param signature The signature payload
        @return True if the signature is valid, false otherwise.
     */
<<<<<<< HEAD
    function verify(address addr, bytes32 quoteHash, bytes memory signature) public view returns (bool) {

        if (addr == address(0)) {
            revert ZeroAddress();
        }

        // TODO use EIP712 compatible format instead
        bytes memory prefix = "\x19Ethereum Signed Message:\n32";
        bytes32 prefixedHash = keccak256(abi.encodePacked(prefix, quoteHash));

        // Contract wallets are validated through EIP-1271.
        if (addr.code.length > 0) {
            return _verifyContractSignature(addr, prefixedHash, signature);
        }

        return _verifyEcdsaSignature(addr, quoteHash, prefixedHash, signature);
    }

    function _verifyContractSignature(
        address addr,
        bytes32 prefixedHash,
        bytes memory signature
    ) private view returns (bool) {
        (bool success, bytes memory result) = addr.staticcall(
            abi.encodeCall(IERC1271.isValidSignature, (prefixedHash, signature))
        );
        if (success && result.length > 31 && abi.decode(result, (bytes4)) == EIP1271_MAGIC_VALUE_BYTES32) {
            return true;
        }

        // Compatibility fallback for contracts that implement isValidSignature(bytes,bytes).
        (success, result) = addr.staticcall(
            abi.encodeWithSelector(EIP1271_MAGIC_VALUE_BYTES, abi.encode(prefixedHash), signature)
        );
        return success && result.length > 31 && abi.decode(result, (bytes4)) == EIP1271_MAGIC_VALUE_BYTES;
    }

    function _verifyEcdsaSignature(
        address addr,
        bytes32 quoteHash,
        bytes32 prefixedHash,
        bytes memory signature
    ) private pure returns (bool) {
        if (signature.length != 65) {
            revert IncorrectSignature(addr, quoteHash, signature);
        }
        bytes32 r;
        bytes32 s;
        uint8 v;

        assembly {
            r := mload(add(signature, 0x20))
            s := mload(add(signature, 0x40))
            v := byte(0, mload(add(signature, 0x60)))
        }
        return prefixedHash.recover(v, r, s) == addr;
    }

}
