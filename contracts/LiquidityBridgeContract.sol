// SPDX-License-Identifier: MIT
pragma solidity ^0.7.4;
pragma experimental ABIEncoderV2;

import './BridgeMock.sol';

contract LiquidityBridgeContract {

    struct DerivationParams {
        bytes fedBtcAddress;
        address lbcAddress;
        address liquidityProviderRskAddress;
        bytes btcRefundAddress;
        address rskRefundAddress;
        bytes liquidityProviderBtcAddress;
        uint callFee;
        address contractAddress;
        bytes data;        
        uint gasLimit;
        uint nonce;
        uint value;
    }

    struct Registry {
        bool performed;  
        bool success;
    }

    BridgeMock bridge;
    mapping(address => uint256) private balances;
    mapping(address => uint256) private collateral;
    mapping(bytes32 => Registry) private callRegistry;  
    uint private minCol;

    constructor(address bridgeAddress, uint minCollateral) {
        bridge = BridgeMock(bridgeAddress);
        minCol = minCollateral;
    }

    receive() external payable { }

    function register() external payable {
        require(collateral[msg.sender] == 0, "Already registered");
        require(msg.value >= minCol, "Not enough collateral");
        collateral[msg.sender] = msg.value;
    }

    function addCollateral() external payable {
        require(collateral[msg.sender] > 0, "Not registered");
        collateral[msg.sender] += msg.value;
    }

    function deposit() external payable {
        require(collateral[msg.sender] > 0, "Not registered");
        balances[msg.sender] += msg.value;
    }

    function getCollateral(address lp) external view returns (uint256) {
        return collateral[lp];
    }

    function getBalance(address lp) external view returns (uint256) {
        return balances[lp];
    }

    function callForUser(DerivationParams memory params) external payable returns (bool) {
        require(msg.sender == params.liquidityProviderRskAddress, "Unauthorized");
        require(balances[params.liquidityProviderRskAddress] + msg.value >= params.value, "Insufficient funds");   
        require(address(this) == params.lbcAddress, "Wrong LBC address");  
        require(collateral[msg.sender] > 0, "Not registered");
        require(collateral[msg.sender] >= minCol, "Insufficient collateral");   

        bytes32 derivationHash = hash(params);

        require(gasleft() >= params.gasLimit, "Insufficient gas");
        (bool success, bytes memory ret) = params.contractAddress.call{gas:params.gasLimit, value: params.value}(params.data);

        balances[params.liquidityProviderRskAddress] += msg.value;
        callRegistry[derivationHash].performed = true;

        if (success) {
            balances[params.liquidityProviderRskAddress] -= params.value;
            callRegistry[derivationHash].success = true;
        } 
        return success;
    }

    function registerPegIn(
        DerivationParams memory params,
        bytes memory btcRawTransaction, 
        bytes memory partialMerkleTree, 
        uint256 height
    ) public returns (int256) {
        bytes32 derivationHash = hash(params);

        int256 transferredAmount = bridge.registerFastBridgeBtcTransaction(
            btcRawTransaction, 
            height, 
            partialMerkleTree, 
            derivationHash, 
            params.btcRefundAddress, 
            address(this),
            params.liquidityProviderBtcAddress,
            callRegistry[derivationHash].performed
        );

        require(transferredAmount != -303, "Not enough BTC validations");
        
        if (transferredAmount == -200 || transferredAmount == -100) {
            // Bridge cap surpassed
            callRegistry[derivationHash].performed = false;
            callRegistry[derivationHash].success = false;
            return transferredAmount;
        }

        if (transferredAmount > 0 && callRegistry[derivationHash].performed) {
            if (callRegistry[derivationHash].success) {
                balances[params.liquidityProviderRskAddress] += params.value + params.callFee;
                uint256 remainingAmount = uint256(transferredAmount) - (params.value + params.callFee);
                
                if (remainingAmount > 0) {
                    (bool success, ) = params.rskRefundAddress.call{value : remainingAmount}("");
                }
                callRegistry[derivationHash].success = false;
            } else {
                balances[params.liquidityProviderRskAddress] += params.callFee;
                (bool success, ) = params.rskRefundAddress.call{value : uint256(transferredAmount) - params.callFee}("");
            }
            callRegistry[derivationHash].performed = false;
        } else if (transferredAmount > 0) {
            (bool success, ) = params.rskRefundAddress.call{value : uint256(transferredAmount)}("");
        }
        return transferredAmount;
    }

    function hash(DerivationParams memory params) public pure returns (bytes32) {        
        return keccak256(abi.encode(
            params.fedBtcAddress, 
            params.lbcAddress,
            params.liquidityProviderRskAddress,
            params.btcRefundAddress,    
            params.rskRefundAddress,
            params.liquidityProviderBtcAddress,
            params.callFee, 
            params.contractAddress, 
            params.data, 
            params.gasLimit,            
            params.nonce,
            params.value                    
        ));
    }
}
