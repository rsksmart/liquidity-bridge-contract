// SPDX-License-Identifier: MIT
pragma solidity ^0.8.3;

import './SignatureValidator.sol';

contract SignatureValidatorMock is SignatureValidator {
    function verify(address , bytes32 , bytes memory) public pure override returns (bool) {
        return true;
    }
}