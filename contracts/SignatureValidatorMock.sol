// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

library SignatureValidatorMock {
    function verify(address , bytes32 , bytes memory) public pure returns (bool) {
        // This is mocked due to an issue with truffle evm that makes the
        // ecrecover function to return address 0x000...0 as the signer
        // when executing against RSK the issue doesn't happen, so the actual implementation
        // uses the class and not this mock
        return true;
    }
}
