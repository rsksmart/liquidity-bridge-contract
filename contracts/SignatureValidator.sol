// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

library SignatureValidator {
    /**
        @dev Verfies signature against address
        @param addr The signing address
        @param quoteHash The hash of the signed data
        @param signature The signature containing v, r and s
        @return True if the signature is valid, false otherwise.
     */
    function verify(address addr, bytes32 quoteHash, bytes memory signature) public pure returns (bool) {
        bytes32 r;
        bytes32 s;
        uint8 v;
     
        assembly {
            r := mload(add(signature, 0x20))
            s := mload(add(signature, 0x40))
            v := byte(0, mload(add(signature, 0x60)))
        }
        // TODO use EIP712 compatible format instead
        bytes memory prefix = "\x19Ethereum Signed Message:\n32";
        bytes32 prefixedHash = keccak256(abi.encodePacked(prefix, quoteHash));
        return ecrecover(prefixedHash, v, r, s) == addr;
    }
}
