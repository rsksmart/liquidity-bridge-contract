// SPDX-License-Identifier: MIT
pragma solidity ^0.7.4;

import './Bridge.sol';

contract LiquidityBridgeContract {

    Bridge bridge;
    mapping(address => uint256) private balances;
    mapping(address => uint256) private deposits;
    mapping(bytes32 => address) private callRegistry;

    constructor(address bridgeAddress) {
        bridge = Bridge(bridgeAddress);
    }

    function register() external payable {
        deposits[msg.sender] += msg.value;
    }

    function transfer() external payable {
        balances[msg.sender] += msg.value;
    }

    function getDeposit(address lp) external view returns (uint256 qty) {
        return deposits[lp];
    }

    function getBalance(address lp) external view returns (uint256 qty) {
        return balances[lp];
    }

    function callForUser(
        bytes memory fedBtcAddress,
        address liquidityProviderRskAddress,
        address contractAddress,
        bytes memory data,
        uint penaltyFee,
        uint successFee,
        uint gasLimit,
        uint nonce,
        uint value
    ) external payable {
        require(msg.sender == liquidityProviderRskAddress, "Unauthorized");

        balances[liquidityProviderRskAddress] += msg.value;
        require(balances[liquidityProviderRskAddress] >= value, "Insufficient funds");

        bytes32 derivationHash = hash(
            fedBtcAddress,
            liquidityProviderRskAddress,
            contractAddress,
            data,
            penaltyFee,
            successFee,
            gasLimit,
            nonce,
            value);

        (bool success, bytes memory ret) = contractAddress.call{gas:gasLimit, value: value}(data);

        callRegistry[derivationHash] = liquidityProviderRskAddress;

        if (success) {
            balances[liquidityProviderRskAddress] -= value;
        }
    }

    function registerFastBridgeBtcTransaction(
        bytes memory btcRawTransaction, 
        bytes memory partialMerkleTree, 
        uint256 height, 
        bytes memory userBtcRefundAddress, 
        bytes memory liquidityProviderBtcAddress, 
        bytes32 preHash
    ) public returns (int256 result) {
        address liquidityProviderRskAddress = callRegistry[preHash];
        bool callPerformed = false;

        if (liquidityProviderRskAddress != address(0x0)) {
            callPerformed = true;
        }

        int256 transferredAmount = bridge.registerFastBridgeBtcTransaction(
            btcRawTransaction, 
            height, 
            partialMerkleTree, 
            preHash, 
            userBtcRefundAddress, 
            address(this),
            liquidityProviderBtcAddress, 
            callPerformed
        );

        if (transferredAmount >= 0 && callPerformed) {
            balances[liquidityProviderRskAddress] += uint256(transferredAmount);
            callRegistry[preHash] = address(0x0);
        }
        return transferredAmount;
    }

    function hash(
        bytes memory fedBtcAddress, 
        address liquidityProviderRskAddress,
        address callContract, 
        bytes memory callContractArguments, 
        uint penaltyFee,
        uint successFee,
        uint gasLimit,
        uint nonce ,
        uint valueToTransfer
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
}
