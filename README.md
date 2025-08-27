# Liquidity Bridge Contract

[![OpenSSF Scorecard](https://api.scorecard.dev/projects/github.com/rsksmart/liquidity-bridge-contract/badge)](https://scorecard.dev/viewer/?uri=github.com/rsksmart/liquidity-bridge-contract)

The Liquidity Bridge Contract (LBC) manages the interaction between users and liquidity providers (LP) in order to achieve fast peg-ins and peg-outs.

## PegIn process

1. A user and an LP agree on the conditions of the service
2. The user makes a deposit in BTC
3. After a number of confirmations, the LP performs a call in RSK on behalf of the user advancing the funds
4. After the deposit achieves a number of additional confirmations, the Bridge contract refunds the LBC in RBTC. The LBC then pays the LP for the service.

Note that the call performed by the LP can be a transfer of value to an account or a call to a contract method. This is specified by the `value` and `data` arguments of the call.

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
        uint256 productFeeAmount;               // the fee payed to the network DAO
        uint256 gasFee;                         // the fee payed to the LP to cover the gas of the RSK transaction
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
        uint value;                             // the value to transfer in the call (in wei)
        uint agreementTimestamp;                // the timestamp of the agreement
        uint depositDateLimit                   // the limit timestamp for the user to do the deposit
        uint depositConfirmations;              // the number of confirmations that the LP requires before making the call
        uint transferConfirmations;             // the number of confirmations that the BTC transfer requires to be refunded
        uint transferTime;                      // the time (in seconds) that the LP has to transfer on behalf of the user after the deposit achieves the number of confirmations
        uint expireDate;                        // the timestamp to consider the quote expired
        uint expireBlock;                       // the block number to consider the quote expired
        uint256 productFeeAmount;               // the fee payed to the network DAO
        uint256 gasFee;                         // the fee payed to the LP to cover the fee of the BTC transaction
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
            string memory _apiBaseUrl,
            bool _status,
            string memory _providerType
        ) external payable onlyEoa returns (uint)

Registers msg.sender as a liquidity provider with msg.value as collateral

#### Parametets

    * name: name of the LP
    * apiBaseUrl: url of this LP's Liquidity Provider Server instance
    * status: if the LP is active
    * providerType: if the LP allows pegin operations, pegout operations or both

#### Return value

    The registered provider ID

### **getProviders**

    function getProviders() external view returns (LiquidityProvider[] memory)

Retrieves the information of a group of liquidity providers

#### Return value

    Array with the information of the requested LPs

### **getProvider**

    function getProvider(address providerAddress) external view returns (LiquidityProvider memory)

Retrieves the information of a specific liquidity provider, regardless if it has resigned or has been disabled

#### Parameters

    * providerAddress: address of the provider to fetch

#### Return value

    Information of the requested LP

### **withdrawCollateral**

    function withdrawCollateral() external

Used to withdraw the locked collateral. It is only for LPs who have resigned

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

#### Parameters

    * amount: the amount to withdraw

### **refundPegOut**

    function refundPegOut(
        bytes32 quoteHash,
        bytes calldata btcTx,
        bytes32 btcBlockHeaderHash,
        uint256 partialMerkleTree,
        bytes32[] memory merkleBranchHashes
    ) public

Validates that the LP made the deposit of the service and applies the corresponding punishments if any apply

#### Parametets

    * quoteHash: the hash of the pegout quote representing the service
    * btcTx: raw btc transaction
    * btcBlockHeaderHash: header of the block where the transaction was included
    * partialMerkleTree: PMT to validate transaction
    * merkleBranchHashes: merkleBranchHashes used by the bridge to validate transaction

### **refundUserPegOut**

    function refundUserPegOut(
        bytes32 quoteHash
    ) public

Allows user to get his money back if LP didn't made the BTC deposit

#### Parametets

    * quote: the hash of the pegout quote to be refunded

### **depositPegout**

    function depositPegout(
        PegOutQuote memory quote,
        bytes memory signature
    ) external payable

Used by the user to deposit the payment of a pegout service

#### Parametets

    * quote: the accepted pegout quote
    * signature: signature of the LP expressing commitment to pay for the quote

### **setProviderStatus**

    function setProviderStatus(
        uint _providerId,
        bool status
    ) external

Enables or disables an specific liquidity provider

#### Parametets

    * _providerId: the id of the provider to modify its status
    * status: the new status

### **updateProvider**

    function updateProvider(
        string memory _name,
        string memory _url
    ) external

Updates the stored information about the LP (msg.sender)

#### Parametets

    * _name: the new provider name
    * _url: the new LPS url

### **isPegOutQuoteCompleted**

    function isPegOutQuoteCompleted(
        bytes32 quoteHash
    ) external view returns (bool)

Returns whether a given quote has been completed (refunded to the LP or the user) or not

#### Parametets

    * quoteHash: hash of the pegout quote

### **deposit**

    function deposit() external payable

Allows the LP to increase its balance by the msg.value amount

## **validatePeginDepositAddress**

    validatePeginDepositAddress(
        PeginQuote memory quote,
        bytes memory depositAddress
    ) external view returns (bool)

Validates if a given BTC address is the derivate deposit address for a pegin quote
_ quote: the quote of the pegin service
_ depositAddress: the bytes of the deposit address to validate (should include the 4 bytes of the base58check checksum)

#### Return value

    Whether the address is the correct deposit address for that quote or not

## **hashQuote**

    hashQuote(
        PeginQuote memory quote
    ) public view returns (bytes32)

Calculates hash of a pegin quote. Besides calculation, this function also validates the quote. \* quote: the pegin quote to hash

#### Return value

    The 32 bytes of the quote hash

## **hashPegoutQuote**

    hashPegoutQuote(
        PegOutQuote memory quote
    ) public view returns (bytes32)

Calculates hash of a pegout quote. Besides calculation, this function also validates the quote. \* quote: the pegout quote to hash

#### Return value

    The 32 bytes of the quote hash

## **getBalance**

    getBalance(
        address addr
    ) external view returns (uint256)

Returns the amount of funds of a liquidity provider \* addr: The address of the liquidity provider

#### Return value

    The balance of the liquidity provider

## **getCollateral**

    getCollateral(
        address addr
    ) external view returns (uint256)

Returns the amount of pegin collateral locked by a liquidity provider \* addr: The address of the liquidity provider

#### Return value

    The amount of locked collateral for pegin operations

## **getPegoutCollateral**

    getPegoutCollateral(
        address addr
    ) external view returns (uint256)

Returns the amount of pegout collateral locked by a liquidity provider \* addr: The address of the liquidity provider

#### Return value

    The amount of locked collateral for pegout operations

## Development & Deployment

### Foundry & Makefile

This project uses **Foundry** for smart contract development and deployment. We provide a comprehensive Makefile for easy deployment across different networks.

#### Quick Start

```bash
# Setup environment
cp example.env .env
make install
make build

# Test deployment (simulation)
make deploy-lbc NETWORK=testnet

# Actual deployment
make deploy-lbc-broadcast NETWORK=testnet
```

#### Documentation

- **[Complete Guide](./docs/FOUNDRY_MAKEFILE_GUIDE.md)** - Comprehensive documentation for Foundry and Makefile usage

#### Key Features

- **Multi-network support**: Mainnet, Testnet, Dev environments
- **Fork testing**: Test against forked networks
- **Safety validation**: Environment checks and mainnet confirmations
- **Simulation vs Deployment**: Separate commands for testing and actual deployment

#### Common Commands

```bash
# Deployment
make deploy-lbc NETWORK=testnet                    # Simulation
make deploy-lbc-broadcast NETWORK=testnet          # Actual deployment

# Upgrades
make upgrade-lbc NETWORK=testnet                   # Simulation
make upgrade-lbc-broadcast NETWORK=testnet         # Actual upgrade

# Fork testing
make testnet-fork-deploy                           # Testnet fork simulation
make testnet-fork-deploy-broadcast                 # Testnet fork actual deployment

# Utilities
make get-versions                                  # Get contract versions
make check-env NETWORK=testnet                     # Environment validation
make help                                          # Show all commands
```

For detailed usage instructions, see the [Foundry & Makefile Guide](./docs/FOUNDRY_MAKEFILE_GUIDE.md).
