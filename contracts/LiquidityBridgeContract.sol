// SPDX-License-Identifier: MIT
pragma solidity ^0.8.3;
pragma experimental ABIEncoderV2;

import './Bridge.sol';

/**
    @title Contract that assists with the Flyover protocol
 */
contract LiquidityBridgeContract {

    struct Quote {
        bytes20 fedBtcAddress;
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
        uint agreementTimestamp;
        uint timeForDeposit;
        uint callTime;
        uint depositConfirmations;
    }

    struct Registry {
        uint256 timestamp;  
        bool success;
    }

    struct Unregister {
        uint256 blockNumber;
        uint256 amount;
    }

    Bridge bridge;
    mapping(address => uint256) private balances;
    mapping(address => uint256) private collateral;
    mapping(bytes32 => Registry) private callRegistry;  
    mapping(address => uint256) private resignations;

    uint private minCol;      
    uint private penaltyR;    
    uint private rewardR;     
    uint private resignBlocks;  

    modifier onlyRegistered() {
        require(isRegistered(msg.sender), "Not registered");
        _;
    }

    /**
        @param bridgeAddress The address of the bridge contract
        @param minCollateral The minimum required collateral for liquidity providers
        @param penaltyRatio The penalty to apply to a liquidity provider in case of misbehavior is computed by dividing the collateral by penaltyRatio
        @param rewardRatio The reward that an honest party receives when calling registerPegIn in case of a liquidity provider misbehaving is the penalty divided by rewardRatio
        @param resignationBlocks The number of block confirmations that a liquidity provider needs to wait before it can withdraw its collateral
     */
    constructor(address bridgeAddress, uint minCollateral, uint penaltyRatio, uint rewardRatio, uint resignationBlocks) {
        bridge = Bridge(bridgeAddress);
        minCol = minCollateral;
        penaltyR = penaltyRatio;
        rewardR = rewardRatio;
        resignBlocks = resignationBlocks;
    }

    receive() external payable { 
        require(msg.sender == address(bridge), "Not allowed");
    }

    function getBridgeAddress() external view returns (address) {
        return address(bridge);
    }

    function getMinCollateral() external view returns (uint) {
        return minCol;
    }

    function getPenaltyRatio() external view returns (uint) {
        return penaltyR;
    }

    function getRewardRatio() external view returns (uint) {
        return rewardR;
    }

    function getResignationBlocks() external view returns (uint) {
        return resignBlocks;
    }    

    /**
        @dev Checks whether a liquidity provider can deliver a service
        @return Whether the liquidity provider is registered and has enough locked collateral
     */
    function isOperational(address addr) external view returns (bool) {
        return isRegistered(addr) && collateral[addr] >= minCol;
    }

    /**
        @dev Registers msg.sender as a liquidity provider with msg.value as collateral
     */
    function register() external payable {
        require(collateral[msg.sender] == 0, "Already registered");
        require(msg.value >= minCol, "Not enough collateral");
        require(resignations[msg.sender] == 0, "Withdraw collateral first");
        collateral[msg.sender] = msg.value;
    }

    /**
        @dev Increases the amount of collateral of the sender
     */
    function addCollateral() external payable onlyRegistered {
        collateral[msg.sender] += msg.value;
    }

    /**
        @dev Increases the balance of the sender
     */
    function deposit() external payable onlyRegistered {
        balances[msg.sender] += msg.value;    
    }

    /**
        @dev Used to withdraw funds
        @param amount The amount to withdraw
     */
    function withdraw(uint256 amount) external {
        require(balances[msg.sender] >= amount, "Insufficient funds");
        balances[msg.sender] -= amount;
        (bool success, ) = msg.sender.call{value : amount}("");
        require(success, "Sending funds failed");
    }

    /**
        @dev Used to withdraw the locked collateral
     */
    function withdrawCollateral() external {
        require(resignations[msg.sender] > 0, "Need to resign first");
        require(block.number - resignations[msg.sender] >= resignBlocks, "Not enough blocks");
        uint amount = collateral[msg.sender];
        collateral[msg.sender] = 0;   
        resignations[msg.sender] = 0;
        (bool success, ) = msg.sender.call{value : amount}("");
        require(success, "Sending funds failed");
    }

    /**
        @dev Used to resign as a liquidity provider
     */
    function resign() external onlyRegistered {
        require(resignations[msg.sender] == 0, "Already resigned");
        resignations[msg.sender] = block.number;
    }    

    /**
        @dev Returns the amount of collateral of a liquidity provider
        @param addr The address of the liquidity provider
        @return The amount of locked collateral
     */
    function getCollateral(address addr) external view returns (uint256) {
        return collateral[addr];
    }

    /**
        @dev Returns the amount of funds of a liquidity provider
        @param addr The address of the liquidity provider
        @return The balance of the liquidity provider
     */
    function getBalance(address addr) external view returns (uint256) {
        return balances[addr];
    }

    /**
        @dev Performs a call on behalf of a user
        @param quote The quote that identifies the service
        @return Boolean indicating whether the call was successful
     */
    function callForUser(Quote memory quote) external payable onlyRegistered returns (bool) {
        require(msg.sender == quote.liquidityProviderRskAddress, "Unauthorized");
        require(balances[quote.liquidityProviderRskAddress] + msg.value >= quote.value, "Insufficient funds");   
        require(address(this) == quote.lbcAddress, "Wrong LBC address");  
        require(collateral[msg.sender] >= minCol, "Insufficient collateral");   

        bytes32 derivationHash = hashParams(quote);

        balances[quote.liquidityProviderRskAddress] += msg.value - quote.value;

        require(gasleft() >= quote.gasLimit, "Insufficient gas");
        (bool success, ) = quote.contractAddress.call{gas:quote.gasLimit, value: quote.value}(quote.data);
        
        callRegistry[derivationHash].timestamp = block.timestamp;

        if (success) {            
            callRegistry[derivationHash].success = true;
        } else {
            balances[quote.liquidityProviderRskAddress] += quote.value;
        }
        return success;
    }

    /**
        @dev Registers a peg-in transaction with the bridge and pays to the involved parties
        @param quote The quote of the service
        @param signature The signature of the quote
        @param btcRawTransaction The peg-in transaction
        @param partialMerkleTree The merkle tree path that proves transaction inclusion
        @param height The block that contains the peg-in transaction
        @return The total peg-in amount received from the bridge contract or an error code
     */
    function registerPegIn(
        Quote memory quote,
        bytes memory signature,
        bytes memory btcRawTransaction, 
        bytes memory partialMerkleTree, 
        uint256 height
    ) public returns (int256) {
        require(verify(quote.liquidityProviderRskAddress, hashQuote(quote), signature), "Invalid signature");

        bytes32 derivationHash = hashParams(quote);

        int256 transferredAmount = registerBridge(quote, btcRawTransaction, partialMerkleTree, height, derivationHash);

        require(transferredAmount != -303, "Failed to validate BTC transaction");
        require(transferredAmount != -302, "Transaction already processed");
        require(transferredAmount != -304, "Invalid transaction value");

        if (shouldPenalize(quote, transferredAmount, callRegistry[derivationHash].timestamp, height)) {
            uint256 penalty = collateral[quote.liquidityProviderRskAddress] / penaltyR;
            collateral[quote.liquidityProviderRskAddress] -= penalty;
            
            // pay reward to sender
            uint256 reward = penalty / rewardR;            
            balances[msg.sender] += reward;
            
            // burn the rest of the penalty
            (bool success, ) = payable(0x00).call{value : penalty - reward}("");
            require(success, "Could not burn penalty");
        }

        if (transferredAmount == -200 || transferredAmount == -100) {
            // Bridge cap surpassed
            callRegistry[derivationHash].timestamp = 0;
            callRegistry[derivationHash].success = false;
            return transferredAmount;
        }

        if (transferredAmount > 0 && callRegistry[derivationHash].timestamp > 0) {
            uint refundAmount;

            if (callRegistry[derivationHash].success) {
                refundAmount = min(uint(transferredAmount), quote.value + quote.callFee);
                callRegistry[derivationHash].success = false;
            } else {
                refundAmount = min(uint(transferredAmount), quote.callFee);
            }
            balances[quote.liquidityProviderRskAddress] += refundAmount;
            int256 remainingAmount = transferredAmount - int(refundAmount);
            
            if (remainingAmount > 0) {
                (bool success, ) = quote.rskRefundAddress.call{value : uint(remainingAmount)}("");
                require(success, "Refund failed");
            }            
            callRegistry[derivationHash].timestamp = 0;
        } else if (transferredAmount > 0) {
            (bool success, ) = quote.rskRefundAddress.call{value : uint256(transferredAmount)}("");
            require(success, "Refund failed");
        }
        return transferredAmount;
    }

    function hashParams(Quote memory quote) public pure returns (bytes32) {        
        return keccak256(abi.encode(
            quote.fedBtcAddress, 
            quote.lbcAddress,
            quote.liquidityProviderRskAddress,
            quote.btcRefundAddress,    
            quote.rskRefundAddress,
            quote.liquidityProviderBtcAddress,
            quote.callFee, 
            quote.contractAddress, 
            quote.data, 
            quote.gasLimit,            
            quote.nonce,
            quote.value                  
        ));
    }

    function hashQuote(Quote memory quote) public pure returns (bytes32) { 
        return keccak256(encodeQuote(quote));        
    }

    function min(uint a, uint b) private pure returns (uint) {
        return a < b ? a : b;
    }

    /**
        @dev Checks if a liquidity provider is registered
        @param addr The address of the liquidity provider
        @return Boolean indicating whether the liquidity provider is registered
     */
    function isRegistered(address addr) private view returns (bool) {
        return collateral[addr] > 0 && resignations[addr] == 0;
    }

    /**
        @dev Registers a transaction with the bridge contract
        @param quote The quote of the service
        @param btcRawTransaction The peg-in transaction
        @param partialMerkleTree The merkle tree path that proves transaction inclusion
        @param height The block that contains the transaction
        @return The total peg-in amount received from the bridge contract or an error code
     */
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
            quote.btcRefundAddress, 
            payable(this),
            quote.liquidityProviderBtcAddress,
            callRegistry[derivationHash].timestamp > 0
        );
    }

    /**
        @dev Checks if a liquidity provider should be penalized
        @param quote The quote of the service
        @param callTimestamp The time that the liquidity provider called callForUser
        @param height The block height where the peg-in transaction is included
        @return Boolean indicating whether the penalty applies
     */
    function shouldPenalize(Quote memory quote, int256 amount, uint256 callTimestamp, uint256 height) private view returns (bool) {
        // do not penalize if deposit amount is insufficient
        if (amount < int(quote.value + quote.callFee) && amount > 0) {
            return false;
        }
        bytes memory firstConfirmationHeader = bridge.getBtcBlockchainBlockHeaderByHeight(height);
        uint256 firstConfirmationTimestamp = getBtcBlockTimestamp(firstConfirmationHeader);        

        // do not penalize if deposit was not made on time
        if (firstConfirmationTimestamp > quote.agreementTimestamp + quote.timeForDeposit) {
            return false;
        }
        // penalize if call was not made
        if (callTimestamp <= 0) {
            return true;
        }
        bytes memory nConfirmationsHeader = bridge.getBtcBlockchainBlockHeaderByHeight(height + quote.depositConfirmations - 1);
        uint256 nConfirmationsTimestamp = getBtcBlockTimestamp(nConfirmationsHeader);

        // penalize if the call was not made on time
        if (callTimestamp > nConfirmationsTimestamp + quote.callTime) {
            return true;
        }
        return false;
    }
    
    /**
        @dev Gets the timestamp of a Bitcoin block header
        @param header The block header
        @return The timestamp of the block header
     */
    function getBtcBlockTimestamp(bytes memory header) private pure returns (uint256) {
        // bitcoin header is 80 bytes and timestamp is 4 bytes from byte 68 to byte 71 (both inclusive) 
        return (uint256)(shiftLeft(header[68], 24) | shiftLeft(header[69], 16) | shiftLeft(header[70], 8) | shiftLeft(header[71], 0));
    }

    /**
        @dev Performs a left shift of a byte
        @param b The byte
        @param nBits The number of bits to shift
        @return The shifted byte
     */
    function shiftLeft(bytes1 b, uint nBits) private pure returns (bytes32){
        return (bytes32)(uint8(b) * 2 ** nBits);
    }
    
    /**
        @dev Verfies signature agains address
        @param addr The signing address
        @param hash The hash of the signed data
        @param signature The signature containing v, r and s
        @return True if the signature is valid, false otherwise.
     */
    function verify(address addr, bytes32 hash, bytes memory signature) private pure returns (bool) {
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

    function encodeQuote(Quote memory quote) private pure returns (bytes memory) {
        // Encode in two parts because abi.encode cannot take more than 12 parameters due to stack depth limits.
        return abi.encode(encodePart1(quote), encodePart2(quote));
    }

    function encodePart1(Quote memory quote) private pure returns (bytes memory) {
        return abi.encode(
            quote.fedBtcAddress, 
            quote.lbcAddress,
            quote.liquidityProviderRskAddress,
            quote.btcRefundAddress,    
            quote.rskRefundAddress,
            quote.liquidityProviderBtcAddress,
            quote.callFee, 
            quote.contractAddress);
    }

    function encodePart2(Quote memory quote) private pure returns (bytes memory) {
        return abi.encode(
            quote.data, 
            quote.gasLimit,            
            quote.nonce,
            quote.value,
            quote.agreementTimestamp,
            quote.timeForDeposit,
            quote.callTime,
            quote.depositConfirmations);
    }
}
