// SPDX-License-Identifier: MIT
pragma solidity ^0.7.4;

import './Bridge.sol';

abstract contract LiquidityBridgeContract {

    Bridge bridge;

    constructor(address bridgeAddress) {
        bridge = Bridge(bridgeAddress);
    }

    function registerFastBridgeBtcTransaction(
        bytes memory btcRawTransaction, 
        bytes memory partialMerkleTree, 
        uint256 height, 
        bytes memory userBtcRefundAddress, 
        bytes memory liquidityProviderBtcAddress, 
        bytes32 preHash
    ) public returns (int256 result) {
        
        bytes32 derivationHash = hash(preHash, userBtcRefundAddress, liquidityProviderBtcAddress);
        bool shouldTransferToContract = validateData(derivationHash);

        int256 transferredAmount = bridge.registerFastBridgeBtcTransaction(
            btcRawTransaction, 
            height, 
            partialMerkleTree, 
            preHash, 
            userBtcRefundAddress, 
            address(this),
            liquidityProviderBtcAddress, 
            shouldTransferToContract
        );

        if (transferredAmount > 0) {
            updateTransferredAmount(derivationHash, uint(transferredAmount));
        }

        return transferredAmount;
    }

    function hash(
        bytes memory fedBtcAddress, 
        address liquidityProviderRskAddress,
        address callContract, 
        bytes memory callContractArguments, 
        int penaltyFee, 
        int successFee, 
        int gasLimit, 
        int nonce ,
        int valueToTransfer
    ) public pure returns (bytes32 derivationHash) {
        
        return keccak256(abi.encode(
            fedBtcAddress, 
            liquidityProviderRskAddress, 
            callContract, 
            callContractArguments, 
            penaltyFee, 
            successFee, 
            gasLimit,
            nonce,
            valueToTransfer
        ));
    }

    function hash(
        bytes32 preHash,
        bytes memory userBtcRefundAddress, 
        bytes memory liquidityProviderBtcAddress
    ) internal view returns (bytes32 derivationHash) {
        return keccak256(abi.encodePacked(
            preHash,
            userBtcRefundAddress,
            address(this),
            liquidityProviderBtcAddress
        ));
    }

    function validateData(bytes32 derivationHash) internal virtual returns (bool shouldTransferToContract);

    function updateTransferredAmount(bytes32 derivationHash, uint256 transferredAmount) internal virtual;
}
