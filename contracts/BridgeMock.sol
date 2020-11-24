// SPDX-License-Identifier: MIT
pragma solidity ^0.7.4;

import "./Bridge.sol";

contract BridgeMock is Bridge {

    mapping(bytes32 => int256) private returnStatus;

    function registerBtcTransfer(
        bytes calldata btcTxSerialized, 
        uint256 height, 
        bytes calldata pmtSerialized, 
        bytes32 derivationArgumentsHash, 
        bytes calldata userRefundBtcAddress, 
        address liquidityBridgeContractAddress,
        bytes calldata liquidityProviderBtcAddress, 
        uint amountToTransfer
    ) external override returns (int256 executionStatus) {
        return returnStatus[derivationArgumentsHash];
    }

    function setReturnStatus(bytes32 derivationArgumentsHash, int256 status) public {
        returnStatus[derivationArgumentsHash] = status;
    }
}
