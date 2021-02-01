// SPDX-License-Identifier: MIT
pragma solidity ^0.7.4;

interface Bridge {
    function registerFastBridgeBtcTransaction(
        bytes calldata btcTxSerialized, 
        uint256 height, 
        bytes calldata pmtSerialized, 
        bytes32 derivationArgumentsHash, 
        bytes calldata userRefundBtcAddress, 
        address payable liquidityBridgeContractAddress,
        bytes calldata liquidityProviderBtcAddress, 
        bool shouldTransferToContract
    ) external returns (int256);
}
