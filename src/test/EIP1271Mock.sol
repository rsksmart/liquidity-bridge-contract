// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {IERC1271} from "@openzeppelin/contracts/interfaces/IERC1271.sol";

/* solhint-disable one-contract-per-file */

contract EIP1271Bytes32Mock is IERC1271 {
    bytes4 internal constant _EIP1271_MAGIC_VALUE_BYTES32 = IERC1271.isValidSignature.selector;

    bytes32 private _expectedHash;
    bytes32 private _expectedSignatureHash;

    constructor(bytes32 expectedHash, bytes memory expectedSignature) {
        _expectedHash = expectedHash;
        _expectedSignatureHash = keccak256(expectedSignature);
    }

    function isValidSignature(bytes32 dataHash, bytes calldata signature) external view override returns (bytes4) {
        if (dataHash == _expectedHash && keccak256(signature) == _expectedSignatureHash) {
            return _EIP1271_MAGIC_VALUE_BYTES32;
        }
        return bytes4(0xffffffff);
    }
}

contract EIP1271BytesOnlyMock {
    bytes4 internal constant _EIP1271_MAGIC_VALUE_BYTES = 0x20c13b0b;

    bytes32 private _expectedDataHash;
    bytes32 private _expectedSignatureHash;

    constructor(bytes memory expectedData, bytes memory expectedSignature) {
        _expectedDataHash = keccak256(expectedData);
        _expectedSignatureHash = keccak256(expectedSignature);
    }

    // solhint-disable-next-line comprehensive-interface
    function isValidSignature(bytes memory data, bytes memory signature) public view returns (bytes4) {
        if (keccak256(data) == _expectedDataHash && keccak256(signature) == _expectedSignatureHash) {
            return _EIP1271_MAGIC_VALUE_BYTES;
        }
        return bytes4(0xffffffff);
    }
}

contract EIP1271InvalidMock is IERC1271 {
    function isValidSignature(bytes32, bytes calldata) external pure override returns (bytes4) {
        return bytes4(0xffffffff);
    }
}

contract NonEIP1271Mock {
    uint256 private _unused;
}
