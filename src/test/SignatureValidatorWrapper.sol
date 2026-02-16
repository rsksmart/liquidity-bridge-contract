// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {SignatureValidator} from "../libraries/SignatureValidator.sol";

/**
 * @dev Wrapper contract for testing the SignatureValidator library
 * This contract exposes the library functions for testing without calling the library directly
 */
contract SignatureValidatorWrapper {

    // Re-declare the errors from the library so they can be caught in tests
    error IncorrectSignature(address expectedAddress, bytes32 usedHash, bytes signature);
    error ZeroAddress();

    /**
     * @dev Wrapper function to test SignatureValidator.verify
     * @param addr The signing address
     * @param quoteHash The hash of the signed data
     * @param signature The signature containing v, r and s
     * @return True if the signature is valid, false otherwise.
     */
    // solhint-disable-next-line comprehensive-interface
    function verify(address addr, bytes32 quoteHash, bytes calldata signature) external view returns (bool) {
        return SignatureValidator.verify(addr, quoteHash, signature);
    }
}
