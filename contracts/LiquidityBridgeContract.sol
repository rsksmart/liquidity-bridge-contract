// SPDX-License-Identifier: MIT
pragma solidity ^0.8.3;
pragma experimental ABIEncoderV2;

import './Bridge.sol';

contract LiquidityBridgeContract {

    struct DerivationParams {
        bytes20 fedBtcAddress;
        address lbcAddress;
        address liquidityProviderRskAddress;
        bytes20 btcRefundAddress;
        address rskRefundAddress;
        bytes20 liquidityProviderBtcAddress;
        uint callFee;
        address contractAddress;
        bytes data;        
        uint gasLimit;
        uint nonce;
        uint value;
    }

    struct Quote {
        DerivationParams params;
        uint agreementTimestamp;
        uint timeForDeposit;
        uint callTime;
        uint depositConfirmations;
    }

    struct Registry {
        uint256 timestamp;  
        bool success;
    }

    Bridge bridge;
    mapping(address => uint256) private balances;
    mapping(address => uint256) private collateral;
    mapping(bytes32 => Registry) private callRegistry;  

    uint private minCol;    // minimum collateral
    uint private penaltyR;  // misbehavior penalty ratio
    uint private rewardR;   // reward ratio

    constructor(address bridgeAddress, uint minCollateral, uint penaltyRatio, uint rewardRatio) {
        bridge = Bridge(bridgeAddress);
        minCol = minCollateral;
        penaltyR = penaltyRatio;
        rewardR = rewardRatio;
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

        bytes32 derivationHash = hashParams(params);

        balances[params.liquidityProviderRskAddress] += msg.value - params.value;

        require(gasleft() >= params.gasLimit, "Insufficient gas");
        (bool success, bytes memory ret) = params.contractAddress.call{gas:params.gasLimit, value: params.value}(params.data);
        
        callRegistry[derivationHash].timestamp = block.timestamp;

        if (success) {            
            callRegistry[derivationHash].success = true;
        } else {
            balances[params.liquidityProviderRskAddress] += params.value;
        }
        return success;
    }

    function registerPegIn(
        Quote memory quote,
        bytes memory signature,
        bytes memory btcRawTransaction, 
        bytes memory partialMerkleTree, 
        uint256 height
    ) public returns (int256) {
        require(verify(quote.params.liquidityProviderRskAddress, hashQuote(quote), signature), "Invalid signature");

        bytes32 derivationHash = hashParams(quote.params);

        int256 transferredAmount = registerBridge(quote, btcRawTransaction, partialMerkleTree, height, derivationHash);

        require(transferredAmount != -303, "Failed to validate BTC transaction");
        require(transferredAmount != -302, "Transaction already processed");
        require(transferredAmount != -304, "Invalid transaction value");

        if (shouldPenalize(quote, callRegistry[derivationHash].timestamp, height)) {
            uint256 penalty = collateral[quote.params.liquidityProviderRskAddress] / penaltyR;
            collateral[quote.params.liquidityProviderRskAddress] -= penalty;
            
            // pay reward to sender
            uint256 reward = penalty / rewardR;            
            balances[msg.sender] += reward;
            
            // burn the rest of the penalty
            payable(0x00).call{value : penalty - reward}("");
        }

        if (transferredAmount == -200 || transferredAmount == -100) {
            // Bridge cap surpassed
            callRegistry[derivationHash].timestamp = 0;
            callRegistry[derivationHash].success = false;
            return transferredAmount;
        } 

        if (transferredAmount > 0 && callRegistry[derivationHash].timestamp > 0) {
            if (callRegistry[derivationHash].success) {
                balances[quote.params.liquidityProviderRskAddress] += quote.params.value + quote.params.callFee;
                uint256 remainingAmount = uint256(transferredAmount) - (quote.params.value + quote.params.callFee);
                
                if (remainingAmount > 0) {
                    (bool success, ) = quote.params.rskRefundAddress.call{value : remainingAmount}("");
                }
                callRegistry[derivationHash].success = false;
            } else {
                balances[quote.params.liquidityProviderRskAddress] += quote.params.callFee;
                (bool success, ) = quote.params.rskRefundAddress.call{value : uint256(transferredAmount) - quote.params.callFee}("");
            }
            callRegistry[derivationHash].timestamp = 0;
        } else if (transferredAmount > 0) {
            (bool success, ) = quote.params.rskRefundAddress.call{value : uint256(transferredAmount)}("");
        }
        return transferredAmount;
    }

    function registerBridge (
        Quote memory quote,
        bytes memory btcRawTransaction, 
        bytes memory partialMerkleTree, 
        uint256 height,
        bytes32 derivationHash
    ) private returns (int256) {
        return bridge.registerFastBridgeBtcTransaction(
            btcRawTransaction, 
            height, 
            partialMerkleTree, 
            derivationHash, 
            quote.params.btcRefundAddress, 
            payable(this),
            quote.params.liquidityProviderBtcAddress,
            callRegistry[derivationHash].timestamp > 0
        );
    }

    function shouldPenalize(Quote memory quote, uint256 callTimestamp, uint256 height) private view returns (bool) {
        bytes memory firstConfirmationHeader = bridge.getBitcoinHeaderByHeight(height);
        uint256 firstConfirmationTimestamp = getBtcBlockTimestamp(firstConfirmationHeader);        

        // do not penalize if deposit was not made on time
        if (firstConfirmationTimestamp > quote.agreementTimestamp + quote.timeForDeposit) {
            return false;
        }
        // penalize if call was not made
        if (callTimestamp <= 0) {
            return true;
        }
        bytes memory nConfirmationsHeader = bridge.getBitcoinHeaderByHeight(height + quote.depositConfirmations - 1);
        uint256 nConfirmationsTimestamp = getBtcBlockTimestamp(nConfirmationsHeader);

        // penalize if the call was not made on time
        if (callTimestamp > nConfirmationsTimestamp + quote.callTime) {
            return true;
        }
        return false;
    }
    
    function getBtcBlockTimestamp(bytes memory header) public pure returns (uint256) {
        // bitcoin header is 80 bytes and timestamp is 4 bytes from byte 68 to byte 71 (both inclusive) 
        return (uint256)(shiftLeft(header[68], 24) | shiftLeft(header[69], 16) | shiftLeft(header[70], 8) | shiftLeft(header[71], 0));
    }

    function shiftLeft(bytes1 b, uint nBits) public pure returns (bytes32){
        return (bytes32)(uint8(b) * 2 ** nBits);
    }
    
    function verify(address addr, bytes32 hash, bytes memory signature) public pure returns (bool) {
        bytes32 r;
        bytes32 s;
        uint8 v;
     
        assembly {
            r := mload(add(signature, 0x20))
            s := mload(add(signature, 0x40))
            v := byte(0, mload(add(signature, 0x60)))
        }
        bytes memory prefix = "\x19Ethereum Signed Message:\n32";
        bytes32 prefixedHash = keccak256(abi.encodePacked(prefix, hash));
        return ecrecover(prefixedHash, v, r, s) == addr;
    }

    function hashParams(DerivationParams memory params) public pure returns (bytes32) {        
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

    function hashQuote(Quote memory quote) public pure returns (bytes32) { 
        return keccak256(encodeQuote(quote));        
    }

    function encodeQuote(Quote memory quote) public pure returns (bytes memory) {
        // Encode in two parts because abi.encode cannot take more than 12 parameters due to stack depth limits.
        // Then modify the offset of the params.data parameter (at byte 286) because encoding in two parts gets it wrong.
        // This is awful but I do not know another way of encoding more than 12 parameters that include dynamic types.
        bytes memory encoding = abi.encodePacked(encodePart1(quote.params), encodePart2(quote));
        encoding[286] = 0x02;
        return encoding;
    }

    function encodePart1(DerivationParams memory params) private pure returns (bytes memory) {
        return abi.encode(params.fedBtcAddress, 
            params.lbcAddress,
            params.liquidityProviderRskAddress,
            params.btcRefundAddress,    
            params.rskRefundAddress,
            params.liquidityProviderBtcAddress,
            params.callFee, 
            params.contractAddress);
    }

    function encodePart2(Quote memory quote) private pure returns (bytes memory) {
        return abi.encode(quote.params.data, 
            quote.params.gasLimit,            
            quote.params.nonce,
            quote.params.value,
            quote.agreementTimestamp,
            quote.timeForDeposit,
            quote.callTime,
            quote.depositConfirmations);
    }
}
