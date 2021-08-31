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
		// SDL: Versioning field is missing. Because no double-hash was used,
		// then now the version field would need to go here I think
        uint callFee; // SDL: Can't we re-scale to reduce field size?
        uint penaltyFee; // SDL: Can't we re-scale to reduce field size?
        address contractAddress;
        bytes data;        
        uint gasLimit; // SDL: Do we really need 2^256 range?
        uint nonce; // SDL: Why not uint32 ?
        uint value;
        uint agreementTimestamp; // SDL: Do we really need 2^256 range?
        uint timeForDeposit; // SDL: Do we really need 2^256 range?
        uint callTime; // SDL: Do we really need 2^256 range?
        uint depositConfirmations; // SDL: Do we really need 2^256 range?
    }

    struct Registry {
        uint256 timestamp;  // SDL: if we reduce range to uint32 then both fields fit into a single 256-bit cell, reducing gas cost 50%
        bool success;
    }

	// SDL: unused struct
    struct Unregister {
        uint256 blockNumber;
        uint256 amount;
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
    event Refund(address dest, int256 amount, bytes32 quoteHash);

    Bridge bridge;
    mapping(address => uint256) private balances;
    mapping(address => uint256) private collateral;
    mapping(bytes32 => Registry) private callRegistry;  
    mapping(address => uint256) private resignations; // SDL This name is incorrect: It should be named "resignationBlockNumber". Now is seems to mean the number of resignations.

    uint private minCol;        // SDL: minCollateral is better
    uint private rewardR;     
    uint private resignBlocks;  // SDL: rename resignDelayInBlocks

    modifier onlyRegistered() {
        require(isRegistered(msg.sender), "Not registered");
        _;
    }

    /**
        @param bridgeAddress The address of the bridge contract
        @param minCollateral The minimum required collateral for liquidity providers
        @param rewardRatio The reward that an honest party receives when calling registerPegIn in case of a liquidity provider misbehaving is the penalty divided by rewardRatio
        @param resignationBlocks The number of block confirmations that a liquidity provider needs to wait before it can withdraw its collateral
     */
    constructor(address bridgeAddress, uint minCollateral, uint rewardRatio, uint resignationBlocks) {
        bridge = Bridge(bridgeAddress);
        minCol = minCollateral;
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
        require(resignations[msg.sender] > 0, "Need to resign first");
        require(block.number - resignations[msg.sender] >= resignBlocks, "Not enough blocks");
        uint amount = collateral[msg.sender];
        collateral[msg.sender] = 0;   
        resignations[msg.sender] = 0;
        (bool success, ) = msg.sender.call{value : amount}("");
        require(success, "Sending funds failed");
        emit WithdrawCollateral(msg.sender, amount);
    }

    /**
        @dev Used to resign as a liquidity provider
     */
    function resign() external onlyRegistered {
        require(resignations[msg.sender] == 0, "Already resigned");
        resignations[msg.sender] = block.number;
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
	 // SDL I don't like this method to be able to be called recursively
	 // even if I can't see a vuln in the  logic. Defensive programming should
	 // be applied.
    function callForUser(Quote memory quote) external payable onlyRegistered returns (bool) {
        require(msg.sender == quote.liquidityProviderRskAddress, "Unauthorized");
        require(balances[quote.liquidityProviderRskAddress] + msg.value >= quote.value, "Insufficient funds");   
        require(address(this) == quote.lbcAddress, "Wrong LBC address");  
        require(collateral[msg.sender] >= minCol, "Insufficient collateral"); // SDL: Why this check? If the user accepted, it's already too late. Better if the LP calls callForUser() than if he is forbitten to.  
		
		// SDL: The subtraction may underflow (both args are uint). 
		// I think this version
		// of Solidity will revert on underflow.
		// Do we want this to occur?
		// I think we want to allow msg.value to be zero, and to consume
		// the pre-existent balance. In that case then this operation 
		// should be performed in ints instead of uints (unless Solidity is
		// already casting the subtraction to int, but I don't think so)
		// Is there any test case for this ?
        balances[quote.liquidityProviderRskAddress] += msg.value - quote.value;
        
		// SDL: Is this event really needed? What for ?
		emit BalanceIncrease(quote.liquidityProviderRskAddress, msg.value);

		// SDL: Shoudn't here by a "gap" added to gasLimit ?
        require(gasleft() >= quote.gasLimit, "Insufficient gas");
        (bool success, ) = quote.contractAddress.call{gas:quote.gasLimit, value: quote.value}(quote.data);
        
        bytes32 quoteHash = hashQuote(quote);
        callRegistry[quoteHash].timestamp = block.timestamp;

        if (success) {            
            callRegistry[quoteHash].success = true;
            emit BalanceDecrease(quote.liquidityProviderRskAddress, quote.value);
        } else {
            balances[quote.liquidityProviderRskAddress] += quote.value;
        }
        emit CallForUser(msg.sender, quote.contractAddress, quote.gasLimit, quote.value, quote.data, success, quoteHash);
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
	 
	 //SDL: No reentrancy guard. I see that registerBridge() does not allow
	 // reentrancy, but that not an explicit guard. Maybe it's better to 
	 // ad a guard as defensive programming.
	 
    function registerPegIn(
        Quote memory quote,
        bytes memory signature,
        bytes memory btcRawTransaction, 
        bytes memory partialMerkleTree, 
        uint256 height
    ) public returns (int256) {
        bytes32 quoteHash = hashQuote(quote);
		
		// SDL: I don't remember why this should be signed...
        require(verify(quote.liquidityProviderRskAddress, quoteHash, signature), "Invalid signature");

		// SDL: Because a bug in the bridge, only the Low significant 4 bytes
		// in height are considered. To protect from unintended vulns,
		// we should require that height < 2^64.
		
		// SDL: rename transferredAmount to transferredAmountOrErrorCode
		// Too many future checks depends on this variable being an error code
		// Do not hide this fact.
        int256 transferredAmount = registerBridge(quote, btcRawTransaction, partialMerkleTree, height, quoteHash);

		// Return codes should be stored in consts. 
        require(transferredAmount != -303, "Failed to validate BTC transaction");
        require(transferredAmount != -302, "Transaction already processed");
        require(transferredAmount != -304, "Invalid transaction value");

		
        if (shouldPenalize(quote, transferredAmount, callRegistry[quoteHash].timestamp, height)) {
            collateral[quote.liquidityProviderRskAddress] -= quote.penaltyFee;
            emit Penalized(quote.liquidityProviderRskAddress, quote.penaltyFee, quoteHash);
            
            // pay reward to sender
			// SDL: rewardR is a divisor... why not making more granual, such as 
			// multiplying penaltyFee by 10 before dividing ?
			// SDL: rename reward punisherReward or something alike.
            uint256 reward = quote.penaltyFee / rewardR;    
            increaseBalance(msg.sender, reward);        
            
            // burn the rest of the penalty
			// SDL: Why it is necessary to send it to another contract 0x00
			// for burning. Leaving it in this contract is enough.
            (bool success, ) = payable(0x00).call{value : quote.penaltyFee - reward}("");
            require(success, "Could not burn penalty");            
        }
		// SDL: -100 and -200 should be final constants defined with an
		// associated identifier. What's the difference between them?
		
		
        if (transferredAmount == -200 || transferredAmount == -100) {
            // Bridge cap exceeded
			// There is a Solidity sentence called "delete" that I think
			// it performs the clearing more efficiently.
			// It's like: delete callRegistry[quoteHash];
            callRegistry[quoteHash].timestamp = 0;
            callRegistry[quoteHash].success = false;
            emit BridgeCapExceeded(quoteHash, transferredAmount);
            return transferredAmount;
        }
		// SDL: What if there is another error code that is not considered?
		// Defensive programming would suggest adding
		// else require(transferredAmount>0,"unknown error code");
	
		// SDL: Why I see checks like transferredAmount > 0 when
		// zero value is a valid amount to transfer in Bitcoin.
		// I saw that the bridge contract doesn't like zero as peg-in amount
		// If that's the reason, I think that should be commented here because
		// it's a very obscure thing.
		// 
        if (transferredAmount > 0 && callRegistry[quoteHash].timestamp > 0) {
            uint refundAmount;

            if (callRegistry[quoteHash].success) {
                refundAmount = min(uint(transferredAmount), quote.value + quote.callFee);
                callRegistry[quoteHash].success = false;
            } else {
                refundAmount = min(uint(transferredAmount), quote.callFee);
            }
            increaseBalance(quote.liquidityProviderRskAddress, refundAmount);
            int256 remainingAmount = transferredAmount - int(refundAmount);
            
			// SDL: Should we refund ANY amount. Maybe some wallets do round 
			// the number to X decimal places and the user cannot send exactly
			// the amount he wants. If the extra amount sent is "dust", then
			// maybe we should not attempt to refund.
            if (remainingAmount > 0) {
                (bool success, ) = quote.rskRefundAddress.call{value : uint(remainingAmount)}("");
                require(success, "Refund failed");
                emit Refund(quote.rskRefundAddress, remainingAmount, quoteHash);
            }            
            callRegistry[quoteHash].timestamp = 0;
        } else if (transferredAmount > 0) {
			// SDL: Here is where I think the user should have the option
			// to call quote.contractAddress.call{gas:quote.gasLimit, value: quote.value}(quote.data);
			// Why: For regulatory reasons, if the user can force the call
			// to happen even if the LP does not, then I think that the
			// chances the LP is considered a Money Transmitter are much lower.
			//
            (bool success, ) = quote.rskRefundAddress.call{value : uint256(transferredAmount)}("");
            require(success, "Refund failed");
            emit Refund(quote.rskRefundAddress, transferredAmount, quoteHash);
        } 
        return transferredAmount;
    }

    function hashQuote(Quote memory quote) public pure returns (bytes32) { 
        return keccak256(encodeQuote(quote));        
    }

    function min(uint a, uint b) private pure returns (uint) {
        return a < b ? a : b;
    }
	/**
		SDL: Write a comment here of the importance this method is private
	*/
    function increaseBalance(address dest, uint amount) private {
        balances[dest] += amount;
        emit BalanceIncrease(dest, amount);
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
	 // SDL: Method name should be shouldPenalizeLP()
    function shouldPenalize(Quote memory quote, int256 amount, uint256 callTimestamp, uint256 height) private view returns (bool) {

		// SDL: A comment is required here because amount may be also
		//  a negative error code and the argument name does not show this.
		//
		// SDL: What happens if amount==0 ? In that case
		// the LP should not be penalized. I undestand that the Bridge
		// doesn't allow zero value, BUT this exception merits a comment
		// explaining why amount ==0 is special here.
		// Finally I would invert the order and compare first for amount >0
		// because comparing "amount < int(..." while amount is an error code
		// makes no sense and confuses the readed.
		// best way:
		// if (amount > 0) { // Do not consider error codes
		//   if (amount < int(quote.value + quote.callFee) {
        //    return false;
        //   }
		// }
        if (amount < int(quote.value + quote.callFee) && amount > 0) {
            return false;
        }
		// SDL: here a comment is requires to explain why the bridge
		// will always return a valid header (reasons: height is pre-validated?)
        bytes memory firstConfirmationHeader = bridge.getBtcBlockchainBlockHeaderByHeight(height);
		
		// SDL: Same here: explain why it can't fail
        uint256 firstConfirmationTimestamp = getBtcBlockTimestamp(firstConfirmationHeader);        

        // do not penalize if deposit was not made on time
        if (firstConfirmationTimestamp > quote.agreementTimestamp + quote.timeForDeposit) {
            return false;
        }
        // penalize if call was not made
		// SDL: Why <=0 if the argument is an Uint ? Defensive?
        if (callTimestamp <= 0) {
            return true;
        }
		// SDL: Explain why this can't fail.
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
		// SDL: With some slicing you can avoid the shifts and use 
		// a lot less gas (2943 compared to 571)
        return (uint256)(shiftLeft(header[68], 24) | shiftLeft(header[69], 16) | shiftLeft(header[70], 8) | shiftLeft(header[71], 0));
    }

	// SDL: bytes must have at least 28 bytes before the uint32
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
		//return (uint32) (x & (1<<64-1));
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
		// SDL: I'm think we should not use this signature format
		// but an EIP712 compatible format.
        bytes memory prefix = "\x19Ethereum Signed Message:\n32";
        bytes32 prefixedHash = keccak256(abi.encodePacked(prefix, hash));
        return ecrecover(prefixedHash, v, r, s) == addr;
    }

	// SDL: Sadly this is not the format that I designed for the bridge.
	// I designed it to be a double hash but it's a single hash.
	// We may have problems in the future introducing versioning, because
	// of the variable size.
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
            quote.depositConfirmations);
    }
}
