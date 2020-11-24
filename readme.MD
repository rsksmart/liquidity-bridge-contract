# Liquidity Bridge Contract

## registerFastBridgeBtcTransaction

```
function registerFastBridgeBtcTransaction(
    bytes btcRawTransaction, 
    bytes partialMerkleTree, 
    int height, 
    bytes fedBtcAddress, 
    address LiquidityProviderRskAddres, 
    bytes userBtcRefundAddress, 
    address LiquidityProviderBtcAddres, 
    address callContract, 
    bytes callContractArguments, 
    int penaltyFee, 
    int successFee, 
    int gasLimit, 
    int nonce ,
    int valueToTransfer) returns int
```
**TBD: ARE WE GOING TO HAVE BOTH FEES OR ARE WE CONSOLIDATING THEM INTO JUST ONE FEE?**

This method will, first of all, obtain the derivation hash to verify if this transaction belongs to an outstanding registered operation.

### Hashing

The derivation arguments are hashed in two steps. First a part of the parameters is hashed using using sha3, and then this hash and the rest of the derivation arguments are once again hashed to obtained the derivation hash (as stated in the [RSKIP-176](https://github.com/rsksmart/RSKIPs/blob/fast-bridge-alternative/IPs/RSKIP176.md#bridge) => `Sha256Hash(derivationArgumentsHash, userRefundAddress, LBCAddress, LPBtcAddress)`).

#### First hash

Perform a keccak256 of:
- fedBtcAddress
- LiquidityProviderRskAddres
- callContract
- callContractArguments
- penaltyFee
- successFee
- gasLimit
- nonce
- valueToTransfer

Store this value in a variable (e.g. derivationPreHash).

#### Second hash

Perform a keccak256 of:
- derivationPreHash
- userBtcRefundAddress
- LBCAddress: This value is THIS contract address
- LiquidityProviderBtcAddres

This value should also be stored as it will be used for the verifications.

### Verifications

The contract will implement a validation method to ensure the obtained derivation hash corresponds to a registered operation.
From this method's execution, registerFastBridgeBtcTransaction will determine how to interact with the Bridge to register the BTC transaction.

**TBD: DEFINE METHOD SIGNATURE**

### Bridge interaction

Once registerFastBridgeBtcTransaction verified the operation, will call the Bridge indicating how to proceed.
Bridge exposes this method:
```
registerFastBridgeBtcTransaction(
    bytes btcTxSerialized, 
    int height, 
    bytes pmtSerialized, 
    bytes32 derivationArgumentsHash, 
    string userRefundBtcAddress, 
    string LiquidityBridgeContractAddress, 
    string LiquidityProviderBtcAddress, 
    int amountToTransferToLBC
) returns int
```
- derivationArgumentsHash: obtained from the Hashing step.
- amountToTransferToLBC: obtained from the Verifications step.
- The other arguments are exactly the same received by the contract.

The response from the Bride indicates indicates the status of the operation.
If the Bridge returns a negative value it means something went wrong. This contract should handle this situation and return a corresponding value to the caller.
If the value is bigger than zero, the value indicates how many Weis were transferred back to this contract. The contract should use this response to substract it from the operation. (e.g. if the operation consists of 1 rbtc, and the response is 0.5 rbtc, the contract should register that there is a remainder of 0.5 rbtc).
