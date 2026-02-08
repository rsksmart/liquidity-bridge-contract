// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import { ECDSA } from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

library SignatureValidator {

    using ECDSA for bytes32;

    error IncorrectSignature(address expectedAddress, bytes32 usedHash, bytes signature);
    error ZeroAddress();
    /**
        @dev Verfies signature against address
        @param addr The signing address
        @param eip712Hash The EIP712 hash of the signed data, this contract expects
        it to be already prefixed with the EIP712 domain separator
        @param signature The signature containing v, r and s
        @return True if the signature is valid, false otherwise.
     */
    function verify(address addr, bytes32 eip712Hash, bytes memory signature) public pure returns (bool) {

        if (addr == address(0)) {
            revert ZeroAddress();
        }

        if (signature.length != 65) {
            revert IncorrectSignature(addr, eip712Hash, signature);
        }
        return  eip712Hash.recover(signature) == addr;
    }
}
