// SPDX-License-Identifier: MIT
pragma solidity ^0.8.3;
pragma experimental ABIEncoderV2;

import './Bridge.sol';
import './SafeMath.sol';
/**
    @title Contract that assists with the Flyover protocol
 */
contract LiquidityBridgeContract {
    using SafeMath for uint;
    using SafeMath for uint32;

    uint16 constant MAX_CALL_GAS_COST = 35000;

    uint8 constant UNPROCESSED_QUOTE_CODE = 0;
    uint8 constant CALL_DONE_CODE = 1;
    uint8 constant PROCESSED_QUOTE_CODE = 2;

    uint32 constant MAX_INT32 = 2147483647;
    uint32 constant MAX_UINT32 = 4294967295;

    int16 constant BRIDGE_REFUNDED_USER_ERROR_CODE = -100;
    int16 constant BRIDGE_REFUNDED_LP_ERROR_CODE = -200;
    int16 constant BRIDGE_UNPROCESSABLE_TX_NOT_CONTRACT_ERROR_CODE = -300;
    int16 constant BRIDGE_UNPROCESSABLE_TX_INVALID_SENDER_ERROR_CODE = -301;
    int16 constant BRIDGE_UNPROCESSABLE_TX_ALREADY_PROCESSED_ERROR_CODE = -302;
    int16 constant BRIDGE_UNPROCESSABLE_TX_VALIDATIONS_ERROR = -303;
    int16 constant BRIDGE_UNPROCESSABLE_TX_VALUE_ZERO_ERROR = -304;
    int16 constant BRIDGE_GENERIC_ERROR = -900;
    uint constant MAX_UINT = 2**256 - 1;

    struct Quote {
 
        bytes20 fedBtcAddress;
        address lbcAddress;
        address liquidityProviderRskAddress;
        bytes btcRefundAddress;
        address payable rskRefundAddress;
        bytes liquidityProviderBtcAddress;
        uint64 callFee; 
        uint64 penaltyFee; 
        address contractAddress;
        bytes data;        
        uint32 gasLimit; 
        int64 nonce; 
        uint64 value;
        uint32 agreementTimestamp; 
        uint32 timeForDeposit;
        uint32 callTime; 
        uint16 depositConfirmations; 
        bool callOnRegister;
    }

    struct Registry {
        uint32 timestamp;  
        bool success;
    }

    event Register(address from, uint256 amount);
    event Deposit(address from, uint256 amount);
    event CollateralIncrease(address from, uint256 amount);
    event Withdrawal(address from, uint256 amount);
    event WithdrawCollateral(address from, uint256 amount);
    event Resigned(address from);
    event CallForUser(address from, address dest, uint gasLimit, uint value, bytes data, bool success, bytes32 quoteHash);
    event Penalized(address liquidityProvider, uint penalty, bytes32 quoteHash);
    event BridgeCapExceeded(bytes32 quoteHash, int256 errorCode);
    event BalanceIncrease(address dest, uint amount);
    event BalanceDecrease(address dest, uint amount);
    event BridgeError(bytes32 quoteHash, int256 errorCode);
    event Refund(address dest, uint amount, bytes32 quoteHash);

    Bridge bridge;
    mapping(address => uint256) private balances;
    mapping(address => uint256) private collateral;
    mapping(bytes32 => Registry) private callRegistry;  
    mapping(address => uint256) private resignationBlockNum;

    uint64 private minCollateral;        
    uint32 private rewardP;     
    uint32 private resignDelayInBlocks;  
    uint private dust;

    bool private locked;

    mapping(bytes32 => uint8) private processedQuotes;

    modifier onlyRegistered() {
        require(isRegistered(msg.sender), "Not registered");
        _;
    }

    modifier noReentrancy() {
        require(!locked, "Reentrant call");
        locked = true;
        _;
        locked = false;
    }

    /**
        @param bridgeAddress The address of the bridge contract
        @param minimumCollateral The minimum required collateral for liquidity providers
        @param rewardPercentage The percentage of the penalty fee that an honest party receives when calling registerPegIn in case of a liquidity provider misbehaving
        @param resignDelayBlocks The number of block confirmations that a liquidity provider needs to wait before it can withdraw its collateral
        @param dustThreshold Amount that is considered dust
     */
    constructor(address bridgeAddress, uint64 minimumCollateral, uint32 rewardPercentage, uint32 resignDelayBlocks, uint dustThreshold) {
        bridge = Bridge(bridgeAddress);
        minCollateral = minimumCollateral;
        rewardP = rewardPercentage;
        resignDelayInBlocks = resignDelayBlocks;
        dust = dustThreshold;
    }

    receive() external payable { 
        require(msg.sender == address(bridge), "Not allowed");
    }

    function getBridgeAddress() external view returns (address) {
        return address(bridge);
    }

    function getMinCollateral() external view returns (uint) {
        return minCollateral;
    }

    function getRewardPercentage() external view returns (uint) {
        return rewardP;
    }

    function getResignDelayBlocks() external view returns (uint) {
        return resignDelayInBlocks;
    }    

    function getDustThreshold() external view returns (uint) {
        return dust;
    }

    /**
        @dev Checks whether a liquidity provider can deliver a service
        @return Whether the liquidity provider is registered and has enough locked collateral
     */
    function isOperational(address addr) external view returns (bool) {
        return isRegistered(addr) && collateral[addr] >= minCollateral;
    }

    /**
        @dev Registers msg.sender as a liquidity provider with msg.value as collateral
     */
    function register() external payable {
        require(collateral[msg.sender] == 0, "Already registered");
        require(msg.value >= minCollateral, "Not enough collateral");
        require(resignationBlockNum[msg.sender] == 0, "Withdraw collateral first");
        collateral[msg.sender] = msg.value;
        emit Register(msg.sender, msg.value);
    }

    /**
        @dev Increases the amount of collateral of the sender
     */
    function addCollateral() external payable onlyRegistered {
        collateral[msg.sender] += msg.value;
        emit CollateralIncrease(msg.sender, msg.value);
    }

    /**
        @dev Increases the balance of the sender
     */
    function deposit() external payable onlyRegistered {
        increaseBalance(msg.sender, msg.value); 
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
        emit Withdrawal(msg.sender, amount);
    }

    /**
        @dev Used to withdraw the locked collateral
     */
    function withdrawCollateral() external {
        require(resignationBlockNum[msg.sender] > 0, "Need to resign first");
        require(block.number - resignationBlockNum[msg.sender] >= resignDelayInBlocks, "Not enough blocks");
        uint amount = collateral[msg.sender];
        collateral[msg.sender] = 0;   
        resignationBlockNum[msg.sender] = 0;
        (bool success, ) = msg.sender.call{value : amount}("");
        require(success, "Sending funds failed");
        emit WithdrawCollateral(msg.sender, amount);
    }

    /**
        @dev Used to resign as a liquidity provider
     */
    function resign() external onlyRegistered {
        require(resignationBlockNum[msg.sender] == 0, "Already resigned");
        resignationBlockNum[msg.sender] = block.number;
        emit Resigned(msg.sender);
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
    function callForUser(Quote memory quote) external payable onlyRegistered noReentrancy returns (bool) {
        require(msg.sender == quote.liquidityProviderRskAddress, "Unauthorized");
        require(balances[quote.liquidityProviderRskAddress] + msg.value >= quote.value, "Insufficient funds");   
        require(address(this) == quote.lbcAddress, "Wrong LBC address");  

        bytes32 quoteHash = hashQuote(quote);
        require(processedQuotes[quoteHash] == UNPROCESSED_QUOTE_CODE, "Quote already processed");

        increaseBalance(quote.liquidityProviderRskAddress, msg.value);

        // This check ensures that the call cannot be performed with less gas than the agreed amount
        require(gasleft() >= quote.gasLimit + MAX_CALL_GAS_COST, "Insufficient gas");
        (bool success, ) = quote.contractAddress.call{gas:quote.gasLimit, value: quote.value}(quote.data);
        
        require(block.timestamp <= MAX_UINT32, "Block timestamp overflow");
        callRegistry[quoteHash].timestamp = uint32(block.timestamp);

        if (success) {            
            callRegistry[quoteHash].success = true;
            decreaseBalance(quote.liquidityProviderRskAddress, quote.value);
        }
        emit CallForUser(msg.sender, quote.contractAddress, quote.gasLimit, quote.value, quote.data, success, quoteHash);
        processedQuotes[quoteHash] = CALL_DONE_CODE;
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
    ) public noReentrancy returns (int256) {
        bytes32 quoteHash = hashQuote(quote);

        require(quote.btcRefundAddress.length == 21, "BTC refund address must be 21 bytes long");
        require(quote.liquidityProviderBtcAddress.length == 21, "BTC LP address must be 21 bytes long");

        // TODO: allow multiple registerPegIns for the same quote with different transactions
        require(processedQuotes[quoteHash] <= CALL_DONE_CODE, "Quote already registered");
        require(verify(quote.liquidityProviderRskAddress, quoteHash, signature), "Invalid signature");
        require(height < uint256(MAX_INT32), "Height must be lower than 2^31");
		
        int256 transferredAmountOrErrorCode = registerBridge(quote, btcRawTransaction, partialMerkleTree, height, quoteHash);

        require(transferredAmountOrErrorCode != BRIDGE_UNPROCESSABLE_TX_VALIDATIONS_ERROR, "Error -303: Failed to validate BTC transaction");
        require(transferredAmountOrErrorCode != BRIDGE_UNPROCESSABLE_TX_ALREADY_PROCESSED_ERROR_CODE, "Error -302: Transaction already processed");
        require(transferredAmountOrErrorCode != BRIDGE_UNPROCESSABLE_TX_VALUE_ZERO_ERROR, "Error -304: Transaction value is zero");
        require(transferredAmountOrErrorCode != BRIDGE_GENERIC_ERROR, "Error -900: Bridge error");
        require(transferredAmountOrErrorCode > 0 || transferredAmountOrErrorCode == BRIDGE_REFUNDED_LP_ERROR_CODE || transferredAmountOrErrorCode == BRIDGE_REFUNDED_USER_ERROR_CODE, "Unknown Bridge error");
		
        if (shouldPenalizeLP(quote, transferredAmountOrErrorCode, callRegistry[quoteHash].timestamp, height)) {
            uint penalizationAmount = min(quote.penaltyFee, collateral[quote.liquidityProviderRskAddress]); // prevent undeflow when collateral is less than penalty fee.
            collateral[quote.liquidityProviderRskAddress] -= penalizationAmount;
            emit Penalized(quote.liquidityProviderRskAddress, penalizationAmount, quoteHash);
            
            // pay reward to sender
            uint256 punisherReward = quote.penaltyFee * rewardP / 100;    
            increaseBalance(msg.sender, punisherReward);           
        }
				
        if (transferredAmountOrErrorCode == BRIDGE_REFUNDED_LP_ERROR_CODE || transferredAmountOrErrorCode == BRIDGE_REFUNDED_USER_ERROR_CODE) {
            // Bridge cap exceeded
            processedQuotes[quoteHash] = PROCESSED_QUOTE_CODE;
            delete callRegistry[quoteHash];
            emit BridgeCapExceeded(quoteHash, transferredAmountOrErrorCode);
            return transferredAmountOrErrorCode;
        }

        // the amount is safely assumed positive because it's already been validated in lines 287/298 there's no (negative) error code being returned by the bridge.
        uint transferredAmount = uint(transferredAmountOrErrorCode);        
	
        if (callRegistry[quoteHash].timestamp > 0) {
            uint refundAmount;

            if (callRegistry[quoteHash].success) {
                refundAmount = min(transferredAmount, quote.value + quote.callFee);
            } else {
                refundAmount = min(transferredAmount, quote.callFee);
            }
            increaseBalance(quote.liquidityProviderRskAddress, refundAmount);
            uint remainingAmount = transferredAmount - refundAmount;
            
            if (remainingAmount > dust) {
                quote.rskRefundAddress.transfer(uint(remainingAmount));
                emit Refund(quote.rskRefundAddress, remainingAmount, quoteHash);
            }            
        } else {
            uint refundAmount = transferredAmount;

            if (quote.callOnRegister && refundAmount >= quote.value) {
                (bool callSuccess, ) = quote.contractAddress.call{gas:quote.gasLimit, value: quote.value}(quote.data);
                emit CallForUser(msg.sender, quote.contractAddress, quote.gasLimit, quote.value, quote.data, callSuccess, quoteHash);

                if (callSuccess) {
                    refundAmount -= quote.value;
                }
            }
            if (refundAmount > dust) {
                quote.rskRefundAddress.transfer(uint256(refundAmount));
                emit Refund(quote.rskRefundAddress, refundAmount, quoteHash);
            }
        } 
        processedQuotes[quoteHash] = PROCESSED_QUOTE_CODE;
        delete callRegistry[quoteHash];
        return transferredAmountOrErrorCode;
    }

    function hashQuote(Quote memory quote) public pure returns (bytes32) { 
        return keccak256(encodeQuote(quote));        
    }

    function min(uint a, uint b) private pure returns (uint) {
        return a < b ? a : b;
    }

    // IMPORTANT: These methods should remain private at all costs
    function increaseBalance(address dest, uint amount) private {
        balances[dest] += amount;
        emit BalanceIncrease(dest, amount);
    }

    function decreaseBalance(address dest, uint amount) private {
        balances[dest] -= amount;
        emit BalanceDecrease(dest, amount);
    }

    /**
        @dev Checks if a liquidity provider is registered
        @param addr The address of the liquidity provider
        @return Boolean indicating whether the liquidity provider is registered
     */
    function isRegistered(address addr) private view returns (bool) {
        return collateral[addr] > 0 && resignationBlockNum[addr] == 0;
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
        @param amount The transferred amount or an error code
        @param callTimestamp The time that the liquidity provider called callForUser
        @param height The block height where the peg-in transaction is included
        @return Boolean indicating whether the penalty applies
     */
    function shouldPenalizeLP(Quote memory quote, int256 amount, uint256 callTimestamp, uint256 height) private view returns (bool) {

        // do not penalize if deposit amount is insufficient
        if (amount > 0 && amount < int64(quote.value + quote.callFee)) {
            return false;
        }
		
        bytes memory firstConfirmationHeader = bridge.getBtcBlockchainBlockHeaderByHeight(height);
        require(firstConfirmationHeader.length > 0, "Invalid block height");
		
        uint256 firstConfirmationTimestamp = getBtcBlockTimestamp(firstConfirmationHeader);        

        // do not penalize if deposit was not made on time
        uint timeLimit = quote.agreementTimestamp.tryAdd(quote.timeForDeposit); // prevent overflow when collateral is less than penalty fee.
        if (firstConfirmationTimestamp > timeLimit) {
            return false;
        }

        // penalize if call was not made
        if (callTimestamp == 0) {
            return true;
        }
	
        bytes memory nConfirmationsHeader = bridge.getBtcBlockchainBlockHeaderByHeight(height + quote.depositConfirmations - 1);
        require(nConfirmationsHeader.length > 0, "Invalid block height");

        uint256 nConfirmationsTimestamp = getBtcBlockTimestamp(nConfirmationsHeader);

        // penalize if the call was not made on time
        if (callTimestamp > nConfirmationsTimestamp.tryAdd(quote.callTime)) {
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
        return sliceUint32FromLSB(header, 68);
    }

	// bytes must have at least 28 bytes before the uint32
	function sliceUint32FromLSB(bytes memory bs, uint start)
    internal pure
    returns (uint32)
	{
		require(bs.length >= start + 4, "slicing out of range");
		require(bs.length >= 32, "slicing out of range");
		start -=28;
		uint x;
		assembly {
			x := mload(add(bs, add(0x20, start)))
		}
		return uint32(x);
		//return (uint32) (x & (1<<32-1));
	}
    
    /**
        @dev Verfies signature against address
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
	
        // TODO use EIP712 compatible format instead
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
            quote.penaltyFee, 
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
            quote.depositConfirmations,
            quote.callOnRegister);
    }
}
