// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import { ECDSA } from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

library SignatureValidator {

    using ECDSA for bytes32;

    error IncorrectSignature(address expectedAddress, bytes32 usedHash, bytes signature);
    error SignatureCheckError(uint8 errorType, bytes32 errorArg);
    error ZeroAddress();
    /**
        @dev Verifies signature against address
        @param addr The signing address
        @param messageHash The hash of the signed message, the SignatureValidator won't perform any
        modification on the message. If this is used for EIP712, this contract expects it to be the
        final hash (domain hash + hashStruct)
        @param signature The signature containing v, r and s
        @return True if the signature is valid, false otherwise.
     */
    function verify(address addr, bytes32 messageHash, bytes memory signature) public pure returns (bool) {

        if (addr == address(0)) {
            revert ZeroAddress();
        }

        if (signature.length != 65) {
            revert IncorrectSignature(addr, messageHash, signature);
        }
        (address recovered, ECDSA.RecoverError err, bytes32 errorArg) = messageHash.tryRecover(signature);
        if (err != ECDSA.RecoverError.NoError) {
            revert SignatureCheckError(uint8(err), errorArg);
        }
        return recovered == addr;
    }
}
