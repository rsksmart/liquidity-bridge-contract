// SPDX-License-Identifier: MIT
pragma solidity ^0.8.3;
pragma experimental ABIEncoderV2;

import "./Bridge.sol";
import "./SignatureValidator.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

/**
    @title Contract that assists with the Flyover protocol
 */

contract LiquidityBridgeContract is Initializable, OwnableUpgradeable {
    uint16 constant MAX_CALL_GAS_COST = 35000;
    uint16 constant MAX_REFUND_GAS_LIMIT = 2300;

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
    int16 constant BRIDGE_UNPROCESSABLE_TX_UTXO_AMOUNT_SENT_BELOW_MINIMUM_ERROR =
        -305;
    int16 constant BRIDGE_GENERIC_ERROR = -900;
    uint constant MAX_UINT = 2 ** 256 - 1;

    struct Quote {
        bytes20 fedBtcAddress;
        address lbcAddress;
        address liquidityProviderRskAddress;
        bytes btcRefundAddress;
        address payable rskRefundAddress;
        bytes liquidityProviderBtcAddress;
        uint256 callFee;
        uint256 penaltyFee;
        address contractAddress;
        bytes data;
        uint32 gasLimit;
        int64 nonce;
        uint256 value;
        uint32 agreementTimestamp;
        uint32 timeForDeposit;
        uint32 callTime;
        uint16 depositConfirmations;
        bool callOnRegister;
    }

    struct PegOutQuote {
        address lbcAddress;
        address lpRskAddress;
        bytes btcRefundAddress;
        address rskRefundAddress;
        bytes lpBtcAddress;
        uint256 callFee;
        uint256 penaltyFee;
        int64 nonce;
        bytes deposityAddress;
        uint32 gasLimit;
        uint256 value;
        uint32 agreementTimestamp;
        uint32 depositDateLimit;
        uint16 depositConfirmations;
        uint16 transferConfirmations;
        uint32 transferTime;
        uint32 expireDate;
        uint32 expireBlock;
    }

    struct PegOutQuoteState {
        uint256 receivedAmount;
        uint8 statusCode;
        bool refunded;
    }

    struct Registry {
        uint32 timestamp;
        bool success;
    }

    struct LiquidityProvider {
        uint id;
        address provider;
        string name;
        uint fee;
        uint quoteExpiration;
        uint acceptedQuoteExpiration;
        uint minTransactionValue;
        uint maxTransactionValue;
        string apiBaseUrl;
        bool status;
        string providerType;
    }

    event Register(uint indexed id, address indexed from, uint256 amount);
    event Deposit(address from, uint256 amount);
    event CollateralIncrease(address from, uint256 amount);
    event PegoutCollateralIncrease(address from, uint256 amount);
    event Withdrawal(address from, uint256 amount);
    event WithdrawCollateral(address from, uint256 amount);
    event PegoutWithdrawCollateral(address from, uint256 amount);
    event Resigned(address from);
    event CallForUser(
        address indexed from,
        address indexed dest,
        uint gasLimit,
        uint value,
        bytes data,
        bool success,
        bytes32 quoteHash
    );
    event Penalized(address liquidityProvider, uint penalty, bytes32 quoteHash);
    event BridgeCapExceeded(bytes32 quoteHash, int256 errorCode);
    event BalanceIncrease(address dest, uint amount);
    event BalanceDecrease(address dest, uint amount);
    event BridgeError(bytes32 quoteHash, int256 errorCode);
    event Refund(address dest, uint amount, bool success, bytes32 quoteHash);
    event PegOut(
        address from,
        uint256 amount,
        bytes32 quotehash,
        uint processed
    );
    event PegOutBalanceIncrease(address dest, uint amount);
    event PegOutBalanceDecrease(address dest, uint amount);
    event PegOutRefunded(bytes32 quoteHash);
    event PegOutDeposit(
        bytes32 quoteHash,
        uint256 accumulatedAmount,
        uint256 timestamp
    );
    event PegOutUserRefunded(
        bytes32 quoteHash,
        uint256 value,
        address userAddress
    );

    Bridge bridge;
    mapping(address => uint256) private balances;
    mapping(address => uint256) private collateral;
    mapping(address => uint256) private pegoutCollateral;
    mapping(uint => LiquidityProvider) private liquidityProviders;
    mapping(bytes32 => Registry) private callRegistry;
    mapping(address => uint256) private resignationBlockNum;

    uint256 private minCollateral;
    uint256 private minPegIn;

    uint32 private rewardP;
    uint32 private resignDelayInBlocks;
    uint private dust;
    uint256 private maxQuoteValue;
    uint providerId;

    bool private locked;

    mapping(bytes32 => uint8) private processedQuotes;
    mapping(bytes32 => PegOutQuoteState) private pegOutQuotesStates;
    mapping(bytes32 => PegOutQuote) private registeredPegoutQuotes;

    modifier onlyRegistered() {
        require(isRegistered(msg.sender), "Not registered");
        _;
    }

    modifier onlyRegisteredForPegout() {
        require(isRegisteredForPegout(msg.sender), "Not registered");
        _;
    }

    modifier noReentrancy() {
        require(!locked, "Reentrant call");
        locked = true;
        _;
        locked = false;
    }

    modifier onlyEoa() {
        require(tx.origin == msg.sender, "Not EOA");
        _;
    }

    /**
        @param _bridgeAddress The address of the bridge contract
        @param _minimumCollateral The minimum required collateral for liquidity providers
        @param _minimumPegIn The minimum peg-in amount
        @param _rewardPercentage The percentage of the penalty fee that an honest party receives when calling registerPegIn in case of a liquidity provider misbehaving
        @param _resignDelayBlocks The number of block confirmations that a liquidity provider needs to wait before it can withdraw its collateral
        @param _dustThreshold Amount that is considered dust
     */
    function initialize(
        address payable _bridgeAddress,
        uint256 _minimumCollateral,
        uint256 _minimumPegIn,
        uint32 _rewardPercentage,
        uint32 _resignDelayBlocks,
        uint _dustThreshold,
        uint _maxQuoteValue
    ) external initializer {
        require(_rewardPercentage <= 100, "Invalid reward percentage");
        __Ownable_init_unchained();
        bridge = Bridge(_bridgeAddress);
        minCollateral = _minimumCollateral;
        minPegIn = _minimumPegIn;
        rewardP = _rewardPercentage;
        resignDelayInBlocks = _resignDelayBlocks;
        dust = _dustThreshold;
        maxQuoteValue = _maxQuoteValue;
    }

    modifier onlyOwnerAndProvider(uint _providerId) {
        require(
            msg.sender == owner() ||
                msg.sender == liquidityProviders[_providerId].provider,
            "Not owner or provider"
        );
        _;
    }

    function setProviderStatus(
        uint _providerId,
        bool status
    ) public onlyOwnerAndProvider(_providerId) {
        require(status == true || status == false, "Invalid Status");
        liquidityProviders[_providerId].status = status;
    }

    receive() external payable {
        require(msg.sender == address(bridge), "Not allowed");
    }

    function getMaxQuoteValue() external view returns (uint256) {
        return maxQuoteValue;
    }

    function getProviderIds() external view returns (uint) {
        return providerId;
    }

    function getBridgeAddress() external view returns (address) {
        return address(bridge);
    }

    function getMinCollateral() external view returns (uint) {
        return minCollateral;
    }

    function getMinPegIn() external view returns (uint) {
        return minPegIn;
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

    function getPegOutQuoteState(
        bytes32 quoteHash
    ) external view returns (PegOutQuoteState memory) {
        return pegOutQuotesStates[quoteHash];
    }

    function getRegisteredPegOutQuote(
        bytes32 quoteHash
    ) external view returns (PegOutQuote memory) {
        return registeredPegoutQuotes[quoteHash];
    }

    /**
        @dev Checks whether a liquidity provider can deliver a pegin service
        @return Whether the liquidity provider is registered and has enough locked collateral
     */
    function isOperational(address addr) external view returns (bool) {
        return isRegistered(addr) && collateral[addr] >= minCollateral;
    }

    /**
        @dev Checks whether a liquidity provider can deliver a pegout service
        @return Whether the liquidity provider is registered and has enough locked collateral
     */
    function isOperationalForPegout(address addr) external view returns (bool) {
        return
            isRegisteredForPegout(addr) &&
            pegoutCollateral[addr] >= minCollateral;
    }

    /**
        @dev Registers msg.sender as a liquidity provider with msg.value as collateral
     */
    function register(
        string memory _name,
        uint _fee,
        uint _quoteExpiration,
        uint _acceptedQuoteExpiration,
        uint _minTransactionValue,
        uint _maxTransactionValue,
        string memory _apiBaseUrl,
        bool _status,
        string memory _providerType
    ) external payable onlyEoa returns (uint) {
        //require(collateral[msg.sender] == 0, "Already registered");
        validateRegisterParameters(
            _name,
            _fee,
            _quoteExpiration,
            _acceptedQuoteExpiration,
            _minTransactionValue,
            _maxTransactionValue,
            _apiBaseUrl,
            _providerType
        );
        // TODO multiplication by 2 is a temporal fix until we define solution with product team
        require(msg.value >= minCollateral * 2, "Not enough collateral");
        require(
            resignationBlockNum[msg.sender] == 0,
            "Withdraw collateral first"
        );
        // TODO split 50/50 between pegin and pegout is a temporal fix until we define solution with product team
        if (msg.value % 2 == 0) {
            collateral[msg.sender] = msg.value / 2;
            pegoutCollateral[msg.sender] = msg.value / 2;
        } else {
            collateral[msg.sender] = msg.value / 2 + 1;
            pegoutCollateral[msg.sender] = msg.value / 2;
        }

        providerId++;
        liquidityProviders[providerId] = LiquidityProvider({
            id: providerId,
            provider: msg.sender,
            name: _name,
            fee: _fee,
            quoteExpiration: _quoteExpiration,
            acceptedQuoteExpiration: _acceptedQuoteExpiration,
            minTransactionValue: _minTransactionValue,
            maxTransactionValue: _maxTransactionValue,
            apiBaseUrl: _apiBaseUrl,
            status: _status,
            providerType: _providerType
        });
        emit Register(providerId, msg.sender, msg.value);
        return (providerId);
    }

    /**
        @dev Validates input parameters for the register function
  */
    function validateRegisterParameters(
        string memory _name,
        uint _fee,
        uint _quoteExpiration,
        uint _acceptedQuoteExpiration,
        uint _minTransactionValue,
        uint _maxTransactionValue,
        string memory _apiBaseUrl,
        string memory _providerType
    ) internal view {
        require(bytes(_name).length > 0, "Name must not be empty");
        require(_fee > 0, "Fee must be greater than 0");
        require(
            _quoteExpiration > 0,
            "Quote expiration must be greater than 0"
        );
        require(
            _acceptedQuoteExpiration > 0,
            "Accepted quote expiration must be greater than 0"
        );
        require(
            _minTransactionValue > 0,
            "Min transaction value must be greater than 0"
        );
        require(
            _maxTransactionValue > _minTransactionValue,
            "Max transaction value must be greater than min transaction value"
        );
        require(_maxTransactionValue <= maxQuoteValue, "Max transaction value can't be higher than maximum quote value");
        require(
            bytes(_apiBaseUrl).length > 0,
            "API base URL must not be empty"
        );

        // Check if _providerType is one of the valid strings
        require(
            keccak256(abi.encodePacked(_providerType)) ==
                keccak256(abi.encodePacked("pegin")) ||
                keccak256(abi.encodePacked(_providerType)) ==
                keccak256(abi.encodePacked("pegout")) ||
                keccak256(abi.encodePacked(_providerType)) ==
                keccak256(abi.encodePacked("both")),
            "Invalid provider type"
        );
    }

    function getProviders(
        uint[] memory providerIds
    ) external view returns (LiquidityProvider[] memory) {
        LiquidityProvider[] memory providersToReturn = new LiquidityProvider[](
            providerIds.length
        );
        uint count = 0;

        for (uint i = 0; i < providerIds.length; i++) {
            uint id = providerIds[i];
            if (isRegistered(liquidityProviders[id].provider)) {
                providersToReturn[count] = liquidityProviders[id];
                count++;
            }
        }
        return providersToReturn;
    }

    /**
        @dev Increases the amount of collateral of the sender
     */
    function addCollateral() external payable onlyRegistered {
        collateral[msg.sender] += msg.value;
        emit CollateralIncrease(msg.sender, msg.value);
    }

    function addPegoutCollateral() external payable onlyRegisteredForPegout {
        pegoutCollateral[msg.sender] += msg.value;
        emit PegoutCollateralIncrease(msg.sender, msg.value);
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
        (bool success, ) = msg.sender.call{value: amount}("");
        require(success, "Sending funds failed");
        emit Withdrawal(msg.sender, amount);
    }

    /**
        @dev Used to withdraw the locked collateral
     */
    function withdrawCollateral() external {
        require(resignationBlockNum[msg.sender] > 0, "Need to resign first");
        require(
            block.number - resignationBlockNum[msg.sender] >=
                resignDelayInBlocks,
            "Not enough blocks"
        );
        uint amount = collateral[msg.sender];
        collateral[msg.sender] = 0;
        resignationBlockNum[msg.sender] = 0;
        (bool success, ) = msg.sender.call{value: amount}("");
        require(success, "Sending funds failed");
        emit WithdrawCollateral(msg.sender, amount);
    }

    function withdrawPegoutCollateral() external {
        require(resignationBlockNum[msg.sender] > 0, "Need to resign first");
        require(
            block.number - resignationBlockNum[msg.sender] >=
                resignDelayInBlocks,
            "Not enough blocks"
        );
        uint amount = pegoutCollateral[msg.sender];
        pegoutCollateral[msg.sender] = 0;
        resignationBlockNum[msg.sender] = 0;
        (bool success, ) = msg.sender.call{value: amount}("");
        require(success, "Sending funds failed");
        emit PegoutWithdrawCollateral(msg.sender, amount);
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

    function getPegoutCollateral(address addr) external view returns (uint256) {
        return pegoutCollateral[addr];
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
    function callForUser(
        Quote memory quote
    ) external payable onlyRegistered noReentrancy returns (bool) {
        require(
            msg.sender == quote.liquidityProviderRskAddress,
            "Unauthorized"
        );
        require(
            balances[quote.liquidityProviderRskAddress] + msg.value >=
                quote.value,
            "Insufficient funds"
        );

        bytes32 quoteHash = validateAndHashQuote(quote);
        require(
            processedQuotes[quoteHash] == UNPROCESSED_QUOTE_CODE,
            "Quote already processed"
        );

        increaseBalance(quote.liquidityProviderRskAddress, msg.value);

        // This check ensures that the call cannot be performed with less gas than the agreed amount
        require(
            gasleft() >= quote.gasLimit + MAX_CALL_GAS_COST,
            "Insufficient gas"
        );
        (bool success, ) = quote.contractAddress.call{
            gas: quote.gasLimit,
            value: quote.value
        }(quote.data);

        require(block.timestamp <= MAX_UINT32, "Block timestamp overflow");
        callRegistry[quoteHash].timestamp = uint32(block.timestamp);

        if (success) {
            callRegistry[quoteHash].success = true;
            decreaseBalance(quote.liquidityProviderRskAddress, quote.value);
        }
        emit CallForUser(
            msg.sender,
            quote.contractAddress,
            quote.gasLimit,
            quote.value,
            quote.data,
            success,
            quoteHash
        );
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
        bytes32 quoteHash = validateAndHashQuote(quote);

        // TODO: allow multiple registerPegIns for the same quote with different transactions
        require(
            processedQuotes[quoteHash] <= CALL_DONE_CODE,
            "Quote already registered"
        );
        require(
            SignatureValidator.verify(
                quote.liquidityProviderRskAddress,
                quoteHash,
                signature
            ),
            "Invalid signature"
        );
        require(height < uint256(MAX_INT32), "Height must be lower than 2^31");

        int256 transferredAmountOrErrorCode = registerBridge(
            quote,
            btcRawTransaction,
            partialMerkleTree,
            height,
            quoteHash
        );

        require(
            transferredAmountOrErrorCode !=
                BRIDGE_UNPROCESSABLE_TX_VALIDATIONS_ERROR,
            "Error -303: Failed to validate BTC transaction"
        );
        require(
            transferredAmountOrErrorCode !=
                BRIDGE_UNPROCESSABLE_TX_ALREADY_PROCESSED_ERROR_CODE,
            "Error -302: Transaction already processed"
        );
        require(
            transferredAmountOrErrorCode !=
                BRIDGE_UNPROCESSABLE_TX_VALUE_ZERO_ERROR,
            "Error -304: Transaction value is zero"
        );
        require(
            transferredAmountOrErrorCode !=
                BRIDGE_UNPROCESSABLE_TX_UTXO_AMOUNT_SENT_BELOW_MINIMUM_ERROR,
            "Error -305: Transaction UTXO value is below the minimum"
        );
        require(
            transferredAmountOrErrorCode != BRIDGE_GENERIC_ERROR,
            "Error -900: Bridge error"
        );
        require(
            transferredAmountOrErrorCode > 0 ||
                transferredAmountOrErrorCode == BRIDGE_REFUNDED_LP_ERROR_CODE ||
                transferredAmountOrErrorCode == BRIDGE_REFUNDED_USER_ERROR_CODE,
            "Unknown Bridge error"
        );

        if (
            shouldPenalizeLP(
                quote,
                transferredAmountOrErrorCode,
                callRegistry[quoteHash].timestamp,
                height
            )
        ) {
            uint penalizationAmount = min(
                quote.penaltyFee,
                collateral[quote.liquidityProviderRskAddress]
            ); // prevent underflow when collateral is less than penalty fee.
            collateral[quote.liquidityProviderRskAddress] -= penalizationAmount;
            emit Penalized(
                quote.liquidityProviderRskAddress,
                penalizationAmount,
                quoteHash
            );

            // pay reward to sender
            uint256 punisherReward = (penalizationAmount * rewardP) / 100;
            increaseBalance(msg.sender, punisherReward);
        }

        if (
            transferredAmountOrErrorCode == BRIDGE_REFUNDED_LP_ERROR_CODE ||
            transferredAmountOrErrorCode == BRIDGE_REFUNDED_USER_ERROR_CODE
        ) {
            // Bridge cap exceeded
            processedQuotes[quoteHash] = PROCESSED_QUOTE_CODE;
            delete callRegistry[quoteHash];
            emit BridgeCapExceeded(quoteHash, transferredAmountOrErrorCode);
            return transferredAmountOrErrorCode;
        }

        // the amount is safely assumed positive because it's already been validated in lines 287/298 there's no (negative) error code being returned by the bridge.
        uint transferredAmount = uint(transferredAmountOrErrorCode);

        checkAgreedAmount(quote, transferredAmount);

        if (callRegistry[quoteHash].timestamp > 0) {
            uint refundAmount;

            if (callRegistry[quoteHash].success) {
                refundAmount = min(
                    transferredAmount,
                    quote.value + quote.callFee
                );
            } else {
                refundAmount = min(transferredAmount, quote.callFee);
            }
            increaseBalance(quote.liquidityProviderRskAddress, refundAmount);
            uint remainingAmount = transferredAmount - refundAmount;

            if (remainingAmount > dust) {
                // refund rskRefundAddress, if remaining amount greater than dust
                (bool success, ) = quote.rskRefundAddress.call{
                    gas: MAX_REFUND_GAS_LIMIT,
                    value: remainingAmount
                }("");
                emit Refund(
                    quote.rskRefundAddress,
                    remainingAmount,
                    success,
                    quoteHash
                );

                if (!success) {
                    // transfer funds to LP instead, if for some reason transfer to rskRefundAddress was unsuccessful
                    increaseBalance(
                        quote.liquidityProviderRskAddress,
                        remainingAmount
                    );
                }
            }
        } else {
            uint refundAmount = transferredAmount;

            if (quote.callOnRegister && refundAmount >= quote.value) {
                (bool callSuccess, ) = quote.contractAddress.call{
                    gas: quote.gasLimit,
                    value: quote.value
                }(quote.data);
                emit CallForUser(
                    msg.sender,
                    quote.contractAddress,
                    quote.gasLimit,
                    quote.value,
                    quote.data,
                    callSuccess,
                    quoteHash
                );

                if (callSuccess) {
                    refundAmount -= quote.value;
                }
            }
            if (refundAmount > dust) {
                // refund rskRefundAddress, if refund amount greater than dust
                (bool success, ) = quote.rskRefundAddress.call{
                    gas: MAX_REFUND_GAS_LIMIT,
                    value: refundAmount
                }("");
                emit Refund(
                    quote.rskRefundAddress,
                    refundAmount,
                    success,
                    quoteHash
                );
            }
        }
        processedQuotes[quoteHash] = PROCESSED_QUOTE_CODE;
        delete callRegistry[quoteHash];
        return transferredAmountOrErrorCode;
    }

    function depositPegout(
        PegOutQuote calldata quote
    ) external payable {
        require(isRegisteredForPegout(quote.lpRskAddress), "Provider not registered");
        bytes32 quoteHash = hashPegoutQuote(quote);
        PegOutQuoteState storage state = pegOutQuotesStates[quoteHash];
        require(!state.refunded, "LBC: Quote already refunded");
        if(state.receivedAmount == 0) {
            registeredPegoutQuotes[quoteHash] = quote;
        }
        state.receivedAmount += msg.value;
        emit PegOutDeposit(quoteHash, state.receivedAmount, block.timestamp);
    }

    function registerPegOut(
        PegOutQuote memory quote,
        bytes memory signature
    ) public onlyRegisteredForPegout {
        bytes32 quoteHash = validateAndHashPegOutQuote(quote);

        require(
            SignatureValidator.verify(quote.lpRskAddress, quoteHash, signature),
            "LBC: Invalid signature"
        );
        require(
            quote.depositDateLimit < block.timestamp,
            "LBC: Block height overflown"
        );
        require(
            pegOutQuotesStates[quoteHash].statusCode != PROCESSED_QUOTE_CODE,
            "LBC: Quote already pegged out"
        );

        pegOutQuotesStates[quoteHash].statusCode = PROCESSED_QUOTE_CODE;

        emit PegOut(
            msg.sender,
            quote.value + quote.callFee,
            quoteHash,
            pegOutQuotesStates[quoteHash].statusCode
        );
    }

    function refundUserPegOut(
        PegOutQuote memory quote,
        bytes memory signature
    ) public {
        bytes32 quoteHash = hashPegoutQuote(quote);
        PegOutQuoteState storage state = pegOutQuotesStates[quoteHash];

        require(
            block.timestamp > quote.expireDate &&
                block.number > quote.expireBlock,
            "LBC: Quote not expired yet"
        );
        require(state.receivedAmount >= quote.value, "LBC: Deposit not found");
        require(!state.refunded, "LBC: Quote already refunded");
        require(
            pegOutQuotesStates[quoteHash].statusCode ==
                UNPROCESSED_QUOTE_CODE,
            "LBC: Quote already processed"
        );
        require(
            SignatureValidator.verify(quote.lpRskAddress, quoteHash, signature),
            "LBC: Invalid signature"
        );

        uint valueToTransfer = state.receivedAmount;
        state.refunded = true;
        state.receivedAmount = 0;

        (bool sent, ) = quote.rskRefundAddress.call{value: valueToTransfer}("");

        require(sent, "LBC: Error on refund user");

        emit PegOutUserRefunded(
            quoteHash,
            valueToTransfer,
            quote.rskRefundAddress
        );
    }

    function refundPegOut(
        PegOutQuote memory quote,
        bytes32 btcTxHash,
        bytes32 btcBlockHeaderHash,
        uint256 partialMerkleTree,
        bytes32[] memory merkleBranchHashes
    ) public noReentrancy onlyRegisteredForPegout {
        bytes32 quoteHash = validateAndHashPegOutQuote(quote);
        require(
            pegOutQuotesStates[quoteHash].statusCode == PROCESSED_QUOTE_CODE,
            "LBC: Quote not processed"
        );
        require(
            block.timestamp <= quote.expireDate,
            "LBC: Quote expired by date"
        );
        require(
            block.number <= quote.expireBlock,
            "LBC: Quote expired by blocks"
        );
        require(msg.sender == quote.lpRskAddress, "LBC: Wrong sender");
        require(
            bridge.getBtcTransactionConfirmations(
                btcTxHash,
                btcBlockHeaderHash,
                partialMerkleTree,
                merkleBranchHashes
            ) >= int(uint256(quote.transferConfirmations)),
            "LBC: Don't have required confirmations"
        );

        if (
            shouldPenalizePegOutLP(
                quote,
                quote.penaltyFee,
                callRegistry[quoteHash].timestamp,
                block.timestamp
            )
        ) {
            uint penalty = min(
                quote.penaltyFee,
                pegoutCollateral[quote.lpRskAddress]
            );
            pegoutCollateral[quote.lpRskAddress] -= penalty;
        }

        (bool sent, ) = quote.lpRskAddress.call{
            value: quote.value + quote.callFee
        }("");
        require(sent, "Failed to send refund to LP address");

        delete pegOutQuotesStates[quoteHash];
        delete registeredPegoutQuotes[quoteHash];
        emit PegOutRefunded(quoteHash);
    }

    /**
        @dev Calculates hash of a quote. Note: besides calculation this function also validates the quote.
        @param quote The quote of the service
        @return The hash of a quote
     */
    function hashQuote(Quote memory quote) public view returns (bytes32) {
        return validateAndHashQuote(quote);
    }

    function hashPegoutQuote(
        PegOutQuote memory quote
    ) public view returns (bytes32) {
        return validateAndHashPegOutQuote(quote);
    }

    function validateAndHashQuote(
        Quote memory quote
    ) private view returns (bytes32) {
        require(address(this) == quote.lbcAddress, "Wrong LBC address");
        require(
            address(bridge) != quote.contractAddress,
            "Bridge is not an accepted contract address"
        );
        require(
            quote.btcRefundAddress.length == 21 ||
                quote.btcRefundAddress.length == 33,
            "BTC refund address must be 21 or 33 bytes long"
        );
        require(
            quote.liquidityProviderBtcAddress.length == 21,
            "BTC LP address must be 21 bytes long"
        );
        require(
            quote.value + quote.callFee >= minPegIn,
            "Too low agreed amount"
        );

        return keccak256(encodeQuote(quote));
    }

    function validateAndHashPegOutQuote(
        PegOutQuote memory quote
    ) private view returns (bytes32) {
        require(address(this) == quote.lbcAddress, "Wrong LBC address");

        return keccak256(encodePegOutQuote(quote));
    }

    function checkAgreedAmount(
        Quote memory quote,
        uint transferredAmount
    ) private pure {
        uint agreedAmount = quote.value + quote.callFee;
        uint delta = agreedAmount / 10000;
        // transferred amount should not be lower than (agreed amount - delta), where delta is intended to tackle rounding problems
        require(
            transferredAmount >= agreedAmount - delta,
            "Too low transferred amount"
        );
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

    function isRegisteredForPegout(address addr) private view returns (bool) {
        return pegoutCollateral[addr] > 0 && resignationBlockNum[addr] == 0;
    }

    /**
        @dev Registers a transaction with the bridge contract
        @param quote The quote of the service
        @param btcRawTransaction The peg-in transaction
        @param partialMerkleTree The merkle tree path that proves transaction inclusion
        @param height The block that contains the transaction
        @return The total peg-in amount received from the bridge contract or an error code
     */
    function registerBridge(
        Quote memory quote,
        bytes memory btcRawTransaction,
        bytes memory partialMerkleTree,
        uint256 height,
        bytes32 derivationHash
    ) private returns (int256) {
        return
            bridge.registerFastBridgeBtcTransaction(
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
    function shouldPenalizeLP(
        Quote memory quote,
        int256 amount,
        uint256 callTimestamp,
        uint256 height
    ) private view returns (bool) {
        // do not penalize if deposit amount is insufficient
        if (amount > 0 && uint256(amount) < quote.value + quote.callFee) {
            return false;
        }

        bytes memory firstConfirmationHeader = bridge
            .getBtcBlockchainBlockHeaderByHeight(height);
        require(firstConfirmationHeader.length > 0, "Invalid block height");

        uint256 firstConfirmationTimestamp = getBtcBlockTimestamp(
            firstConfirmationHeader
        );

        // do not penalize if deposit was not made on time
        uint timeLimit = quote.agreementTimestamp + quote.timeForDeposit; // prevent overflow when collateral is less than penalty fee.
        if (firstConfirmationTimestamp > timeLimit) {
            return false;
        }

        // penalize if call was not made
        if (callTimestamp == 0) {
            return true;
        }

        bytes memory nConfirmationsHeader = bridge
            .getBtcBlockchainBlockHeaderByHeight(
                height + quote.depositConfirmations - 1
            );
        require(nConfirmationsHeader.length > 0, "Invalid block height");

        uint256 nConfirmationsTimestamp = getBtcBlockTimestamp(
            nConfirmationsHeader
        );

        // penalize if the call was not made on time
        if (callTimestamp > nConfirmationsTimestamp + quote.callTime) {
            return true;
        }
        return false;
    }

    function shouldPenalizePegOutLP(
        PegOutQuote memory quote,
        uint256 penaltyFee,
        uint256 callTimestamp,
        uint256 height
    ) private view returns (bool) {
        // do not penalize if deposit amount is insufficient
        if (penaltyFee > 0 && uint256(penaltyFee) < quote.value) {
            return false;
        }

        bytes memory firstConfirmationHeader = bridge
            .getBtcBlockchainBlockHeaderByHeight(height);
        require(firstConfirmationHeader.length > 0, "1st block height invalid");

        uint256 firstConfirmationTimestamp = getBtcBlockTimestamp(
            firstConfirmationHeader
        );

        // do not penalize if deposit was not made on time
        uint timeLimit = quote.agreementTimestamp + quote.depositDateLimit;
        if (firstConfirmationTimestamp > timeLimit) {
            return false;
        }

        // penalize if call was not made
        if (callTimestamp == 0) {
            return true;
        }

        bytes memory nConfirmationsHeader = bridge
            .getBtcBlockchainBlockHeaderByHeight(
                height + quote.depositConfirmations - 1
            );
        require(nConfirmationsHeader.length > 0, "N block height invalid");

        uint256 nConfirmationsTimestamp = getBtcBlockTimestamp(
            nConfirmationsHeader
        );

        // penalize if the call was not made on time
        if (callTimestamp > nConfirmationsTimestamp + quote.transferTime) {
            return true;
        }

        return false;
    }

    /**
        @dev Gets the timestamp of a Bitcoin block header
        @param header The block header
        @return The timestamp of the block header
     */
    function getBtcBlockTimestamp(
        bytes memory header
    ) public pure returns (uint256) {
        // bitcoin header is 80 bytes and timestamp is 4 bytes from byte 68 to byte 71 (both inclusive)
        require(header.length == 80, "invalid header length");

        return sliceUint32FromLSB(header, 68);
    }

    // bytes must have at least 28 bytes before the uint32
    function sliceUint32FromLSB(
        bytes memory bs,
        uint offset
    ) internal pure returns (uint32) {
        require(bs.length >= offset + 4, "slicing out of range");

        return
            uint32(uint8(bs[offset])) |
            (uint32(uint8(bs[offset + 1])) << 8) |
            (uint32(uint8(bs[offset + 2])) << 16) |
            (uint32(uint8(bs[offset + 3])) << 24);
    }

    function encodeQuote(
        Quote memory quote
    ) private pure returns (bytes memory) {
        // Encode in two parts because abi.encode cannot take more than 12 parameters due to stack depth limits.
        return abi.encode(encodePart1(quote), encodePart2(quote));
    }

    function encodePegOutQuote(
        PegOutQuote memory quote
    ) private pure returns (bytes memory) {
        // Encode in two parts because abi.encode cannot take more than 12 parameters due to stack depth limits.
        return abi.encode(encodePegOutPart1(quote), encodePegOutPart2(quote));
    }

    function encodePart1(
        Quote memory quote
    ) private pure returns (bytes memory) {
        return
            abi.encode(
                quote.fedBtcAddress,
                quote.lbcAddress,
                quote.liquidityProviderRskAddress,
                quote.btcRefundAddress,
                quote.rskRefundAddress,
                quote.liquidityProviderBtcAddress,
                quote.callFee,
                quote.penaltyFee,
                quote.contractAddress
            );
    }

    function encodePart2(
        Quote memory quote
    ) private pure returns (bytes memory) {
        return
            abi.encode(
                quote.data,
                quote.gasLimit,
                quote.nonce,
                quote.value,
                quote.agreementTimestamp,
                quote.timeForDeposit,
                quote.callTime,
                quote.depositConfirmations,
                quote.callOnRegister
            );
    }

    function encodePegOutPart1(
        PegOutQuote memory quote
    ) private pure returns (bytes memory) {
        return
            abi.encode(
                quote.lbcAddress,
                quote.lpRskAddress,
                quote.btcRefundAddress,
                quote.rskRefundAddress,
                quote.lpBtcAddress,
                quote.callFee,
                quote.penaltyFee,
                quote.nonce,
                quote.deposityAddress
            );
    }

    function encodePegOutPart2(
        PegOutQuote memory quote
    ) private pure returns (bytes memory) {
        return
            abi.encode(
                quote.gasLimit,
                quote.value,
                quote.agreementTimestamp,
                quote.depositDateLimit,
                quote.depositConfirmations,
                quote.transferConfirmations,
                quote.transferTime,
                quote.expireDate,
                quote.expireBlock
            );
    }
}
