// SPDX-License-Identifier: MIT
pragma solidity ^0.8.3;

interface Bridge {

    function registerFastBridgeBtcTransaction(
        bytes memory btcTxSerialized, 
        uint256 height, 
        bytes memory pmtSerialized, 
        bytes32 derivationArgumentsHash, 
        bytes21 userRefundBtcAddress, 
        address payable liquidityBridgeContractAddress,
        bytes21 liquidityProviderBtcAddress, 
        bool shouldTransferToContract
    ) external returns (int256);

    function getBtcBlockchainBlockHeaderByHeight(uint256 height) external view returns (bytes memory);
}