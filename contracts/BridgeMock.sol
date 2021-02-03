// SPDX-License-Identifier: MIT
pragma solidity ^0.7.4;

contract BridgeMock {

    mapping(bytes32 => uint256) private amounts;

    function registerFastBridgeBtcTransaction(
        bytes calldata btcTxSerialized, 
        uint256 height, 
        bytes calldata pmtSerialized, 
        bytes32 derivationArgumentsHash, 
        bytes calldata userRefundBtcAddress, 
        address payable liquidityBridgeContractAddress,
        bytes calldata liquidityProviderBtcAddress, 
        bool shouldTransferToContract
    ) external returns (int256) {
        uint256 amount = amounts[derivationArgumentsHash];
        amounts[derivationArgumentsHash] = 0;
        (bool success, ) = liquidityBridgeContractAddress.call{value: amount}("");
        return int(amount);
    }

    function setPegin(bytes32 derivationArgumentsHash) public payable {
        amounts[derivationArgumentsHash] = msg.value;
    }
}
