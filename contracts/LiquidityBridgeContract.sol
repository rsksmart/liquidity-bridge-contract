// SPDX-License-Identifier: MIT
pragma solidity ^0.7.4;

import './Bridge.sol';

contract LiquidityBridgeContract {

    Bridge bridge;
    mapping(address => uint256) private balances;
    mapping(address => uint256) private deposits;
    mapping(bytes32 => address) private callRegistry;
    mapping(bytes32 => bool) private callSuccess;

    constructor(address bridgeAddress) {
        bridge = Bridge(bridgeAddress);
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

    function callForUser(
        bytes memory fedBtcAddress,
        address liquidityProviderRskAddress,
        address payable rskRefundAddress,
        address contractAddress,
        bytes memory data,
        uint penaltyFee,
        uint successFee,
        uint gasLimit,
        uint nonce,
        uint value
    ) external payable {
        require(msg.sender == liquidityProviderRskAddress, "Unauthorized");
        require(deposits[liquidityProviderRskAddress] >= penaltyFee, "Insufficient collateral");

        balances[liquidityProviderRskAddress] += msg.value;

        require(balances[liquidityProviderRskAddress] >= value, "Insufficient funds");

        bytes32 derivationHash = hash(
            fedBtcAddress,
            liquidityProviderRskAddress,
            rskRefundAddress,
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
            callSuccess[derivationHash] = true;
        }
    }

    function registerFastBridgeBtcTransaction(
        bytes memory btcRawTransaction, 
        bytes memory partialMerkleTree, 
        uint256 height, 
        bytes memory userBtcRefundAddress, 
        bytes memory liquidityProviderBtcAddress,
        address payable rskRefundAddress,
        bytes32 preHash,
        uint256 successFee,
        uint256 penaltyFee
    ) public returns (int256) {
        address liquidityProviderRskAddress = callRegistry[preHash];

        int256 transferredAmount = bridge.registerFastBridgeBtcTransaction(
            btcRawTransaction, 
            height, 
            partialMerkleTree, 
            preHash, 
            userBtcRefundAddress, 
            address(this),
            liquidityProviderBtcAddress,
            liquidityProviderRskAddress != address(0x0)
        );

        if (transferredAmount > 0 && liquidityProviderRskAddress != address(0x0)) {
            if (callSuccess[preHash]) {
                balances[liquidityProviderRskAddress] += uint256(transferredAmount);
                callSuccess[preHash] = false;
            } else {
                balances[liquidityProviderRskAddress] += successFee;
                (bool success, ) = rskRefundAddress.call{value : uint256(transferredAmount) - successFee}("");
            }
            callRegistry[preHash] = address(0x0);
        } else if (transferredAmount > 0) {
            deposits[liquidityProviderRskAddress] -= penaltyFee;
            (bool success, ) = rskRefundAddress.call{value : uint256(transferredAmount) + penaltyFee}("");
        }
        return transferredAmount;
    }

    function hash(
        bytes memory fedBtcAddress, 
        address liquidityProviderRskAddress,
        address rskRefundAddress,
        address callContract, 
        bytes memory callContractArguments, 
        uint penaltyFee,
        uint successFee,
        uint gasLimit,
        uint nonce ,
        uint valueToTransfer
    ) public pure returns (bytes32) {
        
        return keccak256(abi.encode(
            fedBtcAddress, 
            liquidityProviderRskAddress,
            rskRefundAddress,
            callContract, 
            callContractArguments, 
            penaltyFee, 
            successFee, 
            gasLimit,
            nonce,
            valueToTransfer
        ));
    }
}
