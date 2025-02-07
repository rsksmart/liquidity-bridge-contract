// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity >=0.7.0 <0.9.0;

contract Encoder {
    function getCallDataSetProviderStatus(uint _index, bool _status) external pure returns (bytes memory) {
        return abi.encodeWithSignature(
            "setProviderStatus(uint256,bool)",
            _index,
            _status
        );
    }

    function getCallDataForUpgrade(address proxy, address implementation) external pure returns (bytes memory) {
        return abi.encodeWithSignature(
            "upgrade(address,address)",
            proxy,
            implementation
        );
    }
}
