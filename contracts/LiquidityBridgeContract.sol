// SPDX-License-Identifier: MIT
pragma solidity ^0.7.4;
pragma experimental ABIEncoderV2;

import './BridgeMock.sol';

contract LiquidityBridgeContract {

    struct DerivationParams {
        bytes fedBtcAddress;
        address liquidityProviderRskAddress;
        address rskRefundAddress;
        address contractAddress;
        bytes data;
        uint penaltyFee;
        uint successFee;
        uint gasLimit;
        uint nonce;
        uint value;
    }

    BridgeMock bridge;
    mapping(address => uint256) private balances;
    mapping(address => uint256) private deposits;
    mapping(bytes32 => bool) private callRegistry;
    mapping(bytes32 => bool) private callSuccess;

    constructor(address bridgeAddress) {
        bridge = BridgeMock(bridgeAddress);
    }

    receive() external payable { }

    function register() external payable {
        deposits[msg.sender] += msg.value;
    }

    function transfer() external payable {
        balances[msg.sender] += msg.value;
    }

    function getDeposit(address lp) external view returns (uint256) {
        return deposits[lp];
    }

    function getBalance(address lp) external view returns (uint256) {
        return balances[lp];
    }

    function callForUser(DerivationParams memory params) external payable returns (bool) {
        require(msg.sender == params.liquidityProviderRskAddress, "Unauthorized");
        require(deposits[params.liquidityProviderRskAddress] >= params.penaltyFee, "Insufficient collateral");
        require(balances[params.liquidityProviderRskAddress] + msg.value >= params.value, "Insufficient funds");

        bytes32 derivationHash = hash(params);

        (bool success, bytes memory ret) = params.contractAddress.call{gas:params.gasLimit, value: params.value}(params.data);

        balances[params.liquidityProviderRskAddress] += msg.value;
        callRegistry[derivationHash] = true;

        if (success) {
            balances[params.liquidityProviderRskAddress] -= params.value;
            callSuccess[derivationHash] = true;
        } 
        return success;
    }

    function registerFastBridgeBtcTransaction(
        DerivationParams memory params,
        bytes memory btcRawTransaction, 
        bytes memory partialMerkleTree, 
        uint256 height, 
        bytes memory userBtcRefundAddress, 
        bytes memory liquidityProviderBtcAddress
    ) public returns (int256) {
        bytes32 derivationHash = hash(params);

        int256 transferredAmount = bridge.registerFastBridgeBtcTransaction(
            btcRawTransaction, 
            height, 
            partialMerkleTree, 
            derivationHash, 
            userBtcRefundAddress, 
            address(this),
            liquidityProviderBtcAddress,
            callRegistry[derivationHash]
        );

        if (transferredAmount > 0 && callRegistry[derivationHash]) {
            if (callSuccess[derivationHash]) {
                balances[params.liquidityProviderRskAddress] += params.value + params.successFee;
                uint256 remainingAmount = uint256(transferredAmount) - (params.value + params.successFee);

                if (remainingAmount > 0) {
                    (bool success, ) = params.rskRefundAddress.call{value : remainingAmount}("");
                }
                callSuccess[derivationHash] = false;
            } else {
                balances[params.liquidityProviderRskAddress] += params.successFee;
                (bool success, ) = params.rskRefundAddress.call{value : uint256(transferredAmount) - params.successFee}("");
            }
            callRegistry[derivationHash] = false;
        } else if (transferredAmount > 0) {
            deposits[params.liquidityProviderRskAddress] -= params.penaltyFee;
            (bool success, ) = params.rskRefundAddress.call{value : uint256(transferredAmount) + params.penaltyFee}("");
        }
        return transferredAmount;
    }

    function hash(DerivationParams memory params) public pure returns (bytes32) {        
        return keccak256(abi.encode(
            params.fedBtcAddress, 
            params.liquidityProviderRskAddress,
            params.rskRefundAddress,
            params.contractAddress, 
            params.data, 
            params.penaltyFee, 
            params.successFee, 
            params.gasLimit,
            params.nonce,
            params.value
        ));
    }
}
