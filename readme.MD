# Liquidity Bridge Contract

The Liquidity Bridge Contract (LBC) manages the interaction between users and liquidity providers (LP) in order to achieve fast peg-ins. The process is as follows:

1. A user and an LP agree on the conditions of the service
2. The user makes a deposit in BTC
3. After a number of confirmations, the LP performs a call in RSK on behalf of the user advancing the funds
4. After the deposit achieves a number of additional confirmations, the Bridge contract refunds the LBC in RBTC. The LBC then pays the LP for the service.

Note that the call performed by the LP can be a transfer of value to an account or a call to a contract method. This is specified by the ``value`` and ``data`` arguments of the call.

## Quote

The quote structure defines the conditions of a service, and acts as a contract between users and LPs. Quotes consist of:

    Quote {
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

## ABI Signature

### callForUser

    function callForUser(
        Quote quote
    ) returns bool success

This method performs a call on behalf of a user.

### registerPegIn

    function registerPegIn(
		Quote quote,
        bytes signature,            // LP's signature of the quote
        bytes btcRawTransaction,    // raw deposit transaction
        bytes partialMerkleTree,    // PMT that proves the inclusion of the deposit in a block
        uint256 height              // block number that contains the deposit tx
	) returns int executionStatus

This method requests the Bridge contract on RSK a refund for the service. This method returns the amount transferred to the contract or an [error code](https://github.com/rsksmart/RSKIPs/blob/fast-bridge-alternative/IPs/RSKIP176.
md#error-codes).

### Deploy and Upgrade

After the first dploy we don't have to change anymore the LiquidityBridgeContract.sol instead we need to create a new version like LiquidityBridgeContractV2.sol and uncomment and update the 3_upgrade_contracts.js script with the last version that will upgrade the contract.
With that we can easily get back on any mistake and swicth version.
