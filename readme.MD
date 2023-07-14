# Liquidity Bridge Contract

The Liquidity Bridge Contract (LBC) manages the interaction between users and liquidity providers (LP) in order to achieve fast peg-ins and peg-outs.

## PegIn process

1. A user and an LP agree on the conditions of the service
2. The user makes a deposit in BTC
3. After a number of confirmations, the LP performs a call in RSK on behalf of the user advancing the funds
4. After the deposit achieves a number of additional confirmations, the Bridge contract refunds the LBC in RBTC. The LBC then pays the LP for the service.

Note that the call performed by the LP can be a transfer of value to an account or a call to a contract method. This is specified by the ``value`` and ``data`` arguments of the call.

## PegOut process

1. A user and an LP agree on the conditions of the service
2. The user sends RBTC to the LBC using depositPegout function
3. After a number of confirmations, the LP makes a deposit in the Bitcoin address specified by user
4. After the deposit achieves a number of additional confirmations, the LP calls refundPegout function in LBC so the contract refunds the LP in RBTC and pay him for the service
5. Once the LP has been refunded with RBTC he sends that RBTC to the Bridge contract to convert it to BTC and get the liquidity back


## Quote
The quote structure defines the conditions of a service, and acts as a contract between users and LPs.

### PegIn Quote
PegIn Quotes consist of:

    PeginQuote {
        bytes20 fedBtcAddress;                  // the BTC address of the Powpeg
        address lbcAddress;                     // the address of the LBC
        address liquidityProviderRskAddress;    // the RSK address of the LP
        bytes btcRefundAddress;                 // a user BTC refund address
        address rskRefundAddress;               // a user RSK refund address 
        bytes liquidityProviderBtcAddress;      // the BTC address of the LP
        uint callFee;                           // the fee charged by the LP
        uint penaltyFee;                        // the penalty that the LP pays if it fails to deliver the service
        address contractAddress;                // the destination address of the peg-in
        bytes data;                             // the arguments to send in the call
        uint gasLimit;                          // the gas limit
        uint nonce;                             // a nonce that uniquely identifies this quote
        uint value;                             // the value to transfer in the call
        uint agreementTimestamp;                // the timestamp of the agreement
        uint timeForDeposit;                    // the time (in seconds) that the user has to achieve one confirmation on the BTC deposit
        uint callTime;                          // the time (in seconds) that the LP has to perform the call on behalf of the user after the deposit achieves the number of confirmations
        uint depositConfirmations;              // the number of confirmations that the LP requires before making the call
        bool callOnRegister:                    // a boolean value indicating whether the callForUser can be called on registerPegIn.
    }

PegOut Quotes consist of:

    PegOutQuote {
        address lbcAddress;                     // the address of the LBC
        address lpRskAddress;                   // the RSK address of the LP
        bytes btcRefundAddress;                 // a user BTC refund address
        address rskRefundAddress;               // a user RSK refund address 
        bytes lpBtcAddress;                     // the BTC address of the LP
        uint callFee;                           // the fee charged by the LP
        uint penaltyFee;                        // the penalty that the LP pays if it fails to deliver the service
        uint nonce;                             // a nonce that uniquely identifies this quote
        bytes deposityAddress;                  // the destination address of the peg-out
        uint gasLimit;                          // the gas limit
        uint value;                             // the value in btc to transfer
        uint agreementTimestamp;                // the timestamp of the agreement
        uint depositDateLimit                 // the limit timestamp for the user to do the deposit
        uint depositConfirmations;              // the number of confirmations that the LP requires before making the call
        uint transferConfirmations;             // the number of confirmations that the BTC transfer requires to be refunded
        uint transferTime;                      // the time (in seconds) that the LP has to transfer on behalf of the user after the deposit achieves the number of confirmations
        uint expireDate;                      // the timestamp to consider the quote expired
        uint expireBlock;                     // the block number to consider the quote expired
    }

## ABI Signature

### **callForUser**

    function callForUser(
        Quote quote
    ) returns bool success

This method performs a call on behalf of a user.
#### Parameters 
    * quote: The quote that identifies the service
#### Return value
    Boolean indicating whether the call was successful

### **registerPegIn**

    function registerPegIn(
		Quote quote,
        bytes signature,
        bytes btcRawTransaction,
        bytes partialMerkleTree,
        uint256 height
	) returns int executionStatus

This method requests the Bridge contract on RSK a refund for the service.
#### Parameters
    * quote The quote of the service
    * signature The signature of the quote
    * btcRawTransaction The peg-in transaction
    * partialMerkleTree The merkle tree path that proves transaction inclusion
    * height The block that contains the peg-in transaction
#### Return value    
    This method returns the amount transferred to the contract or an [error code](https://github.com/rsksmart/RSKIPs/blob/fast-bridge-alternative/IPs/RSKIP176.md#error-codes).

### **isOperational**
    function isOperational(address addr) external view returns (bool)
Checks whether a liquidity provider can deliver a pegin service
#### Parametets
    * addr: address of the liquidity provider
#### Return value
    Whether the liquidity provider is registered and has enough locked collateral

### **isOperationalForPegout**
    function isOperationalForPegout(address addr) external view returns (bool)
Checks whether a liquidity provider can deliver a pegout service
#### Parametets
    * addr: address of the liquidity provider
#### Return value
    Whether the liquidity provider is registered and has enough locked pegout collateral

### **register**
    function register(
            string memory _name,
            uint _fee,
            uint _quoteExpiration,
            uint _minTransactionValue,
            uint _maxTransactionValue,
            string memory _apiBaseUrl,
            bool _status,
            string memory _providerType
        ) external payable onlyEoa returns (uint)
Registers tx.origin as a liquidity provider with msg.value as collateral
#### Parametets
    * name: name of the LP
    * fee: fee that LP charges for this service
    * quoteExpiration: time to accept the quotes of this LP 
    * minTransactionValue: miminum value to get quotes from this LP
    * maxTransactionValue: maximum value to get quotes from this LP
    * apiBaseUrl: url of this LP's Liquidity Provider Server instance
    * status: if the LP is active
    * providerType: if the LP allows pegin operations, pegout operations or both
#### Return value
    The registered provider ID

### **getProviders**
    function getProviders(
        uint[] memory providerIds
    ) external view returns (LiquidityProvider[] memory)
Retrieves the information of a group of liquidity providers
#### Parametets
    * providerIds: IDs of the providers to fetch
#### Return value
    Array with the information of the requested LPs

### **withdrawCollateral**
    function withdrawCollateral() external
Used to withdraw the locked collateral. It is only for LPs who have resigned

### **withdrawPegoutCollateral**
    function withdrawCollateral() external
Used to withdraw the locked pegout collateral. It is only for LPs who have resigned

### **resign**
    function resign() external
Used to resign as a liquidity provider

### **addCollateral**
    function addCollateral() external payable
Increases the amount of collateral of the sender

### **addPegoutCollateral**
    function addPegoutCollateral() external payable
Increases the amount of pegout collateral of the sender

### **withdraw**
    function withdraw(uint256 amount) external
Used by LPs to withdraw funds
#### Parametets
    * amount: the amount to withdraw

### **refundPegOut**
    function refundPegOut(
        PegOutQuote calldata quote,
        bytes calldata btcTx,
        bytes32 btcBlockHeaderHash,
        uint256 partialMerkleTree,
        bytes32[] memory merkleBranchHashes
    ) public
Validates that the LP made the deposit of the service and applies the corresponding punishments if any apply
#### Parametets
    * quote: the pegout quote representing the service
    * btcTx: raw btc transaction
    * btcBlockHeaderHash: header of the block where the transaction was included
    * partialMerkleTree: PMT to validate transaction
    * merkleBranchHashes: merkleBranchHashes used by the bridge to validate transaction

### **refundUserPegOut**
    function refundUserPegOut(
        PegOutQuote memory quote,
        bytes memory signature
    ) public
Allows user to get his money back if LP didn't made the BTC deposit
#### Parametets
    * quote: the pegout quote to be refunded
    * signature: signature provided to user when quote was accepted

### **depositPegout**
    function depositPegout(
        bytes32 quoteHash
    ) external payable
Used by the user to deposit the payment of a pegout service
#### Parametets
    * quoteHash: the accepted quote hash
    * lpAddress: address of the LP that created the quote

### Deploy and Upgrade

After the first dploy we don't have to change anymore the LiquidityBridgeContract.sol instead we need to create a new version like LiquidityBridgeContractV2.sol and uncomment and update the 3_upgrade_contracts.js script with the last version that will upgrade the contract.
With that we can easily get back on any mistake and swicth version.
