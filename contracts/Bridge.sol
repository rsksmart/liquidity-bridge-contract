// SPDX-License-Identifier: MIT
pragma solidity ^0.8.3;

interface Bridge {

    function registerFastBridgeBtcTransaction(
        bytes memory btcTxSerialized, 
        uint256 height, 
        bytes memory pmtSerialized, 
        bytes32 derivationArgumentsHash, 
        bytes memory userRefundBtcAddress, 
        address payable liquidityBridgeContractAddress,
        bytes memory liquidityProviderBtcAddress, 
        bool shouldTransferToContract
    ) external returns (int256);

    function getBtcBlockchainBlockHeaderByHeight(uint256 height) external view returns (bytes memory);
}