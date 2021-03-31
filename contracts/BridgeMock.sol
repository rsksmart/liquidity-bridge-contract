// SPDX-License-Identifier: MIT
pragma solidity ^0.8.3;

import "./Bridge.sol";

contract BridgeMock is Bridge {

    mapping(bytes32 => uint256) private amounts;
    mapping(uint256 => bytes) private headers;

    function registerFastBridgeBtcTransaction(
        bytes memory btcTxSerialized, 
        uint256 height, 
        bytes memory pmtSerialized, 
        bytes32 derivationArgumentsHash, 
        bytes20 userRefundBtcAddress, 
        address payable liquidityBridgeContractAddress,
        bytes20 liquidityProviderBtcAddress, 
        bool shouldTransferToContract
    ) external override returns (int256) {
        uint256 amount = amounts[derivationArgumentsHash];
        amounts[derivationArgumentsHash] = 0;
        liquidityBridgeContractAddress.call{value: amount}("");
        return int(amount);
    }    

    function getBitcoinHeaderByHeight(uint256 height) external view override returns (bytes memory) {
        return headers[height];
    }

    function setPegin(bytes32 derivationArgumentsHash) public payable {
        amounts[derivationArgumentsHash] = msg.value;
    }

    function setHeader(uint256 height, bytes memory header) public {
        headers[height] = header;
    }    
}
