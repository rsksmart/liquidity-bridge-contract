// SPDX-License-Identifier: MIT
pragma solidity ^0.7.4;

import "./LiquidityBridgeContract.sol";

contract LiquidityBridgeContractImpl is LiquidityBridgeContract {

    mapping(bytes32 => uint256) public balances;

    constructor(address bridgeAddress) public {
        bridge = Bridge(bridgeAddress);
    }

    function validateData(bytes32 derivationHash) internal override returns (uint remainder) {
        return balances[derivationHash];
    }

    function updateTransferredAmount(bytes32 derivationHash, uint256 transferredAmount) internal override {
        balances[derivationHash] = transferredAmount;
    }
}
