// SPDX-License-Identifier: MIT
pragma solidity ^0.7.4;

import './LiquidityBridgeContract.sol';

contract LiquidityBridgeContractImpl is LiquidityBridgeContract {

    mapping(bytes32 => uint256) private balances;

    constructor(address bridgeAddress) LiquidityBridgeContract(bridgeAddress) {}

    function validateData(bytes32 derivationHash) internal override returns (uint remainder) {
        return balances[derivationHash];
    }

    function updateTransferredAmount(bytes32 derivationHash, uint256 transferredAmount) internal override {
        balances[derivationHash] -= transferredAmount;
    }

    function getDerivationHashBalance(bytes32 derivationHash) external view returns (uint256 balance) {
        return balances[derivationHash];
    }

    function setDerivationHashBalance(bytes32 derivationHash, uint256 amount) external {
        balances[derivationHash] = amount;
    }

    function getDerivationHash(
        bytes32 preHash,
        bytes memory userBtcRefundAddress, 
        bytes memory liquidityProviderBtcAddress
    ) external view returns (bytes32 derivationHash) {
        return hash(preHash, userBtcRefundAddress, liquidityProviderBtcAddress);
    }
}
