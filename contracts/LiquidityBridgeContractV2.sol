// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;
pragma experimental ABIEncoderV2;

import "./Bridge.sol";
import "./QuotesV2.sol";
import "./SignatureValidator.sol";
import "@rsksmart/btc-transaction-solidity-helper/contracts/BtcUtils.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";

/**
    @title Contract that assists with the Flyover protocol
 */

contract LiquidityBridgeContractV2 is Initializable, OwnableUpgradeable, ReentrancyGuardUpgradeable {
    uint16 constant public MAX_CALL_GAS_COST = 35000;
    uint16 constant public MAX_REFUND_GAS_LIMIT = 2300;

    uint8 constant public UNPROCESSED_QUOTE_CODE = 0;
    uint8 constant public CALL_DONE_CODE = 1;
    uint8 constant public PROCESSED_QUOTE_CODE = 2;

    int16 constant public BRIDGE_REFUNDED_USER_ERROR_CODE = - 100;
    int16 constant public BRIDGE_REFUNDED_LP_ERROR_CODE = - 200;
    int16 constant public BRIDGE_UNPROCESSABLE_TX_NOT_CONTRACT_ERROR_CODE = - 300;
    int16 constant public BRIDGE_UNPROCESSABLE_TX_INVALID_SENDER_ERROR_CODE = - 301;
    int16 constant public BRIDGE_UNPROCESSABLE_TX_ALREADY_PROCESSED_ERROR_CODE = - 302;
    int16 constant public BRIDGE_UNPROCESSABLE_TX_VALIDATIONS_ERROR = - 303;
    int16 constant public BRIDGE_UNPROCESSABLE_TX_VALUE_ZERO_ERROR = - 304;
    int16 constant public BRIDGE_UNPROCESSABLE_TX_UTXO_AMOUNT_SENT_BELOW_MINIMUM_ERROR =
    - 305;
    int16 constant public BRIDGE_GENERIC_ERROR = - 900;
    uint constant public PAY_TO_ADDRESS_OUTPUT = 0;
    uint constant public QUOTE_HASH_OUTPUT = 1;

    struct Registry {
        uint32 timestamp;
        bool success;
    }

    struct PegoutRecord {
        uint256 depositTimestamp;
        bool completed;
    }

    struct LiquidityProvider {
        uint id;
        address provider;
        string name;
        string apiBaseUrl;
        bool status;
        string providerType;
    }

    event Register(uint id, address indexed from, uint256 amount);
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
    event PegInRegistered(bytes32 indexed quoteHash, int256 transferredAmount);
    event Penalized(address liquidityProvider, uint penalty, bytes32 quoteHash);
    event BridgeCapExceeded(bytes32 quoteHash, int256 errorCode);
    event BalanceIncrease(address dest, uint amount);
    event BalanceDecrease(address dest, uint amount);
    event Refund(address dest, uint amount, bool success, bytes32 quoteHash);
    event PegOutRefunded(bytes32 indexed quoteHash);
    event PegOutDeposit(
        bytes32 indexed quoteHash,
        address indexed sender,
        uint256 amount,
        uint256 timestamp
    );
    event PegOutUserRefunded(
        bytes32 indexed quoteHash,
        uint256 value,
        address userAddress
    );
    event DaoFeeSent(bytes32 indexed quoteHash, uint256 amount);
    event ProviderUpdate(address indexed providerAddress, string name, string url);

    Bridge public bridge;
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
    uint public providerId;

    uint private btcBlockTime;
    bool private mainnet;

    mapping(bytes32 => uint8) private processedQuotes;
    mapping(bytes32 => QuotesV2.PegOutQuote) private registeredPegoutQuotes;
    mapping(bytes32 => PegoutRecord) private pegoutRegistry;

    uint256 public productFeePercentage;
    address public daoFeeCollectorAddress;

    modifier onlyRegistered() {
        require(isRegistered(msg.sender), "LBC001");
        _;
    }

    modifier onlyRegisteredForPegout() {
        require(isRegisteredForPegout(msg.sender), "LBC001");
        _;
    }

    modifier onlyOwnerAndProvider(uint _providerId) {
        require(
            msg.sender == owner() ||
            msg.sender == liquidityProviders[_providerId].provider,
            "LBC005"
        );
        _;
    }

    function setProviderStatus(
        uint _providerId,
        bool status
    ) external onlyOwnerAndProvider(_providerId) {
        liquidityProviders[_providerId].status = status;
    }

    receive() external payable {
        require(msg.sender == address(bridge), "LBC007");
    }

    function getProviderIds() external view returns (uint) {
        return providerId;
    }

    function getBridgeAddress() external view returns (address) {
        return address(bridge);
    }

    function getMinCollateral() public view returns (uint) {
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

    function isPegOutQuoteCompleted(bytes32 quoteHash) external view returns (bool) {
        return pegoutRegistry[quoteHash].completed;
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
        string memory _apiBaseUrl,
        bool _status,
        string memory _providerType
    ) external payable returns (uint) {
        require(tx.origin == msg.sender, "LBC003");
        //require(collateral[msg.sender] == 0, "Already registered");
        require(bytes(_name).length > 0, "LBC010");
        require(
            bytes(_apiBaseUrl).length > 0,
            "LBC017"
        );

        // Check if _providerType is one of the valid strings
        require(
            keccak256(abi.encodePacked(_providerType)) ==
            keccak256(abi.encodePacked("pegin")) ||
            keccak256(abi.encodePacked(_providerType)) ==
            keccak256(abi.encodePacked("pegout")) ||
            keccak256(abi.encodePacked(_providerType)) ==
            keccak256(abi.encodePacked("both")),
            "LBC018"
        );

        require(collateral[msg.sender] == 0 && pegoutCollateral[msg.sender] == 0, "LBC070");
        require(
            resignationBlockNum[msg.sender] == 0,
            "LBC009"
        );

        if (keccak256(abi.encodePacked(_providerType)) == keccak256(abi.encodePacked("pegin"))) {
            require(msg.value >= minCollateral, "LBC008");
            collateral[msg.sender] = msg.value;
        } else if (keccak256(abi.encodePacked(_providerType)) == keccak256(abi.encodePacked("pegout"))) {
            require(msg.value >= minCollateral, "LBC008");
            pegoutCollateral[msg.sender] = msg.value;
        } else {
            require(msg.value >= minCollateral * 2, "LBC008");
            uint halfMsgValue = msg.value / 2;
            collateral[msg.sender] = msg.value % 2 == 0 ? halfMsgValue : halfMsgValue + 1;
            pegoutCollateral[msg.sender] = halfMsgValue;
        }

        providerId++;
        liquidityProviders[providerId] = LiquidityProvider({
            id: providerId,
            provider: msg.sender,
            name: _name,
            apiBaseUrl: _apiBaseUrl,
            status: _status,
            providerType: _providerType
        });
        emit Register(providerId, msg.sender, msg.value);
        return (providerId);
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
            if (
                (isRegistered(liquidityProviders[id].provider) ||
                    isRegisteredForPegout(liquidityProviders[id].provider)) &&
                liquidityProviders[id].status
            ) {
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
        require(balances[msg.sender] >= amount, "LBC019");
        balances[msg.sender] -= amount;
        (bool success,) = msg.sender.call{value: amount}("");
        require(success, "LBC020");
        emit Withdrawal(msg.sender, amount);
    }

    /**
        @dev Used to withdraw the locked collateral
     */
    function withdrawCollateral() external {
        require(resignationBlockNum[msg.sender] > 0, "LBC021");
        require(
            block.number - resignationBlockNum[msg.sender] >=
            resignDelayInBlocks,
            "LBC022"
        );
        uint amount = collateral[msg.sender];
        collateral[msg.sender] = 0;
        resignationBlockNum[msg.sender] = 0;
        (bool success,) = msg.sender.call{value: amount}("");
        require(success, "LBC020");
        emit WithdrawCollateral(msg.sender, amount);
    }

    function withdrawPegoutCollateral() external {
        require(resignationBlockNum[msg.sender] > 0, "LBC021");
        require(
            block.number - resignationBlockNum[msg.sender] >=
            resignDelayInBlocks,
            "LBC022"
        );
        uint amount = pegoutCollateral[msg.sender];
        pegoutCollateral[msg.sender] = 0;
        resignationBlockNum[msg.sender] = 0;
        (bool success,) = msg.sender.call{value: amount}("");
        require(success, "LBC020");
        emit PegoutWithdrawCollateral(msg.sender, amount);
    }

    /**
        @dev Used to resign as a liquidity provider
     */
    function resign() external onlyRegistered {
        require(resignationBlockNum[msg.sender] == 0, "LBC023");
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
        QuotesV2.PeginQuote memory quote
    ) external payable onlyRegistered nonReentrant returns (bool) {
        require(
            msg.sender == quote.liquidityProviderRskAddress,
            "LBC024"
        );
        require(
            balances[quote.liquidityProviderRskAddress] + msg.value >=
            quote.value,
            "LBC019"
        );

        bytes32 quoteHash = validateAndHashQuote(quote);
        require(
            processedQuotes[quoteHash] == UNPROCESSED_QUOTE_CODE,
            "LBC025"
        );

        increaseBalance(quote.liquidityProviderRskAddress, msg.value);

        // This check ensures that the call cannot be performed with less gas than the agreed amount
        require(
            gasleft() >= quote.gasLimit + MAX_CALL_GAS_COST,
            "LBC026"
        );
        (bool success,) = quote.contractAddress.call{
                gas: quote.gasLimit,
                value: quote.value
            }(quote.data);

        require(block.timestamp <= type(uint32).max, "LBC027");
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
        QuotesV2.PeginQuote memory quote,
        bytes memory signature,
        bytes memory btcRawTransaction,
        bytes memory partialMerkleTree,
        uint256 height
    ) external nonReentrant returns (int256) {
        bytes32 quoteHash = validateAndHashQuote(quote);

        // TODO: allow multiple registerPegIns for the same quote with different transactions
        require(
            processedQuotes[quoteHash] <= CALL_DONE_CODE,
            "LBC028"
        );
        require(
            SignatureValidator.verify(
                quote.liquidityProviderRskAddress,
                quoteHash,
                signature
            ),
            "LBC029"
        );
        require(height < uint256(int256(type(int32).max)), "LBC030");

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
            "LBC031"
        );
        require(
            transferredAmountOrErrorCode !=
            BRIDGE_UNPROCESSABLE_TX_ALREADY_PROCESSED_ERROR_CODE,
            "LBC032"
        );
        require(
            transferredAmountOrErrorCode !=
            BRIDGE_UNPROCESSABLE_TX_VALUE_ZERO_ERROR,
            "LBC033"
        );
        require(
            transferredAmountOrErrorCode !=
            BRIDGE_UNPROCESSABLE_TX_UTXO_AMOUNT_SENT_BELOW_MINIMUM_ERROR,
            "LBC034"
        );
        require(
            transferredAmountOrErrorCode != BRIDGE_GENERIC_ERROR,
            "LBC035"
        );
        require(
            transferredAmountOrErrorCode > 0 ||
            transferredAmountOrErrorCode == BRIDGE_REFUNDED_LP_ERROR_CODE ||
            transferredAmountOrErrorCode == BRIDGE_REFUNDED_USER_ERROR_CODE,
            "LBC036"
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

        // the amount is safely assumed positive because it's already been
        // validated in lines 287/298 there's no (negative) error code being returned by the bridge.
        uint transferredAmount = uint(transferredAmountOrErrorCode);

        QuotesV2.checkAgreedAmount(quote, transferredAmount);

        if (callRegistry[quoteHash].timestamp > 0) {
            uint refundAmount;

            if (callRegistry[quoteHash].success) {
                refundAmount = min(
                    transferredAmount,
                    quote.value + quote.callFee + quote.gasFee
                );
            } else {
                refundAmount = min(transferredAmount, quote.callFee + quote.gasFee);
            }
            increaseBalance(quote.liquidityProviderRskAddress, refundAmount);

            uint remainingAmount = transferredAmount - refundAmount;
            payToFeeCollector(quote.productFeeAmount, quoteHash);

            if (remainingAmount > dust) {
                // refund rskRefundAddress, if remaining amount greater than dust
                (bool success,) = quote.rskRefundAddress.call{
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
                (bool callSuccess,) = quote.contractAddress.call{
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
                (bool success,) = quote.rskRefundAddress.call{
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
        emit PegInRegistered(quoteHash, transferredAmountOrErrorCode);
        return transferredAmountOrErrorCode;
    }

    function depositPegout( // TODO convert to calldata when contract size issues are fixed
        QuotesV2.PegOutQuote memory quote,
        bytes memory signature
    ) external payable {
        require(isRegisteredForPegout(quote.lpRskAddress), "LBC037");
        require(quote.value + quote.callFee + quote.productFeeAmount + quote.gasFee <= msg.value, "LBC063");
        require(block.timestamp <= quote.depositDateLimit, "LBC065");
        require(block.timestamp <= quote.expireDate, "LBC046");
        require(block.number <= quote.expireBlock, "LBC047");
        bytes32 quoteHash = hashPegoutQuote(quote);
        require(
            SignatureValidator.verify(quote.lpRskAddress, quoteHash, signature),
            "LBC029"
        );

        QuotesV2.PegOutQuote storage registeredQuote = registeredPegoutQuotes[quoteHash];

        require(pegoutRegistry[quoteHash].completed == false, "LBC064");
        require(registeredQuote.lbcAddress == address(0), "LBC028");
        registeredPegoutQuotes[quoteHash] = quote;
        pegoutRegistry[quoteHash].depositTimestamp = block.timestamp;
        emit PegOutDeposit(quoteHash, msg.sender, msg.value, block.timestamp);
    }

    function refundUserPegOut(
        bytes32 quoteHash
    ) external nonReentrant {
        QuotesV2.PegOutQuote storage quote = registeredPegoutQuotes[quoteHash];

        require(quote.lbcAddress != address(0), "LBC042");
        require(
            block.timestamp > quote.expireDate &&
            block.number > quote.expireBlock,
            "LBC041"
        );

        uint valueToTransfer = quote.value + quote.callFee + quote.productFeeAmount + quote.gasFee;
        address addressToTransfer = quote.rskRefundAddress;

        uint penalty = min(quote.penaltyFee, pegoutCollateral[quote.lpRskAddress]);
        pegoutCollateral[quote.lpRskAddress] -= penalty;

        emit Penalized(quote.lpRskAddress, penalty, quoteHash);
        emit PegOutUserRefunded(
            quoteHash,
            valueToTransfer,
            quote.rskRefundAddress
        );

        delete registeredPegoutQuotes[quoteHash];
        pegoutRegistry[quoteHash].completed = true;

        (bool sent,) = addressToTransfer.call{value: valueToTransfer}("");
        require(sent, "LBC044");
    }

    function refundPegOut(
        bytes32 quoteHash,
        bytes memory btcTx,
        bytes32 btcBlockHeaderHash,
        uint256 partialMerkleTree,
        bytes32[] memory merkleBranchHashes
    ) external nonReentrant onlyRegisteredForPegout {
        require(pegoutRegistry[quoteHash].completed == false, "LBC064");
        QuotesV2.PegOutQuote storage quote = registeredPegoutQuotes[quoteHash];
        require(quote.lbcAddress != address(0), "LBC042");
        BtcUtils.TxRawOutput[] memory outputs = BtcUtils.getOutputs(btcTx);
        bytes memory scriptContent = BtcUtils.parseNullDataScript(outputs[QUOTE_HASH_OUTPUT].pkScript);
        require(scriptContent.length == 33 && scriptContent[0] == 0x20, "LBC075");
        // shift the array to remove the first byte (the size)
        for (uint8 i = 0 ; i < scriptContent.length - 1; i++) {
            scriptContent[i] = scriptContent[i + 1];
        }
        bytes32 txQuoteHash = abi.decode(scriptContent, (bytes32));
        require(quoteHash == txQuoteHash, "LBC069");
        require(msg.sender == quote.lpRskAddress, "LBC048");
        require(
            bridge.getBtcTransactionConfirmations(
                BtcUtils.hashBtcTx(btcTx),
                btcBlockHeaderHash,
                partialMerkleTree,
                merkleBranchHashes
            ) >= int(uint256(quote.transferConfirmations)),
            "LBC049"
        );
        require(quote.value <= outputs[PAY_TO_ADDRESS_OUTPUT].value * (10**10), "LBC067"); // satoshi to wei
        bytes memory btcTxDestination = BtcUtils.parsePayToPubKeyHash(outputs[PAY_TO_ADDRESS_OUTPUT].pkScript, mainnet);
        require(keccak256(quote.deposityAddress) == keccak256(btcTxDestination), "LBC068");

        if (
            shouldPenalizePegOutLP(
            quote,
            txQuoteHash,
            btcBlockHeaderHash
        )
        ) {
            uint penalty = min(
                quote.penaltyFee,
                pegoutCollateral[quote.lpRskAddress]
            );
            pegoutCollateral[quote.lpRskAddress] -= penalty;
            emit Penalized(quote.lpRskAddress, penalty, txQuoteHash);
        }

        (bool sent,) = quote.lpRskAddress.call{
                value: quote.value + quote.callFee
            }("");
        require(sent, "LBC050");

        payToFeeCollector(quote.productFeeAmount, quoteHash);

        delete registeredPegoutQuotes[txQuoteHash];
        pegoutRegistry[txQuoteHash].completed = true;
        emit PegOutRefunded(txQuoteHash);
    }

    function validatePeginDepositAddress(
        QuotesV2.PeginQuote memory quote,
        bytes memory depositAddress
    ) external view returns (bool) {
        bytes32 derivationValue = keccak256(
            bytes.concat(
                hashQuote(quote),
                quote.btcRefundAddress,
                bytes20(quote.lbcAddress),
                quote.liquidityProviderBtcAddress
            )
        );
        bytes memory flyoverRedeemScript = bytes.concat(
            hex"20",
            derivationValue,
            hex"75",
            bridge.getActivePowpegRedeemScript()
        );
        return BtcUtils.validateP2SHAdress(depositAddress, flyoverRedeemScript, mainnet);
    }

    /**
        @dev Calculates hash of a quote. Note: besides calculation this function also validates the quote.
        @param quote The quote of the service
        @return The hash of a quote
     */
    function hashQuote(QuotesV2.PeginQuote memory quote) public view returns (bytes32) {
        return validateAndHashQuote(quote);
    }

    function hashPegoutQuote(
        QuotesV2.PegOutQuote memory quote
    ) public view returns (bytes32) {
        return validateAndHashPegOutQuote(quote);
    }

    function validateAndHashQuote(
        QuotesV2.PeginQuote memory quote
    ) private view returns (bytes32) {
        require(address(this) == quote.lbcAddress, "LBC051");
        require(
            address(bridge) != quote.contractAddress,
            "LBC052"
        );
        require(
            quote.btcRefundAddress.length == 21 ||
            quote.btcRefundAddress.length == 33,
            "LBC053"
        );
        require(
            quote.liquidityProviderBtcAddress.length == 21,
            "LBC054"
        );
        require(
            quote.value + quote.callFee + quote.productFeeAmount + quote.gasFee >= minPegIn,
            "LBC055"
        );
        require(
            type(uint32).max >= uint64(quote.agreementTimestamp) + uint64(quote.timeForDeposit),
            "LBC071"
        );

        return keccak256(QuotesV2.encodeQuote(quote));
    }

    function validateAndHashPegOutQuote(
        QuotesV2.PegOutQuote memory quote
    ) private view returns (bytes32) {
        require(address(this) == quote.lbcAddress, "LBC056");

        return keccak256(QuotesV2.encodePegOutQuote(quote));
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
        QuotesV2.PeginQuote memory quote,
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
            callRegistry[derivationHash].timestamp > 0 && callRegistry[derivationHash].success
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
        QuotesV2.PeginQuote memory quote,
        int256 amount,
        uint256 callTimestamp,
        uint256 height
    ) private view returns (bool) {
        // do not penalize if deposit amount is insufficient
        if (amount > 0 && uint256(amount) < quote.value + quote.callFee + quote.productFeeAmount + quote.gasFee) {
            return false;
        }

        bytes memory firstConfirmationHeader = bridge
            .getBtcBlockchainBlockHeaderByHeight(height);
        require(firstConfirmationHeader.length > 0, "Invalid block height");

        uint256 firstConfirmationTimestamp = BtcUtils.getBtcBlockTimestamp(
            firstConfirmationHeader
        );

        // do not penalize if deposit was not made on time
        // prevent overflow when collateral is less than penalty fee.
        uint timeLimit = quote.agreementTimestamp + quote.timeForDeposit;
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
        require(nConfirmationsHeader.length > 0, "LBC058");

        uint256 nConfirmationsTimestamp = BtcUtils.getBtcBlockTimestamp(
            nConfirmationsHeader
        );

        // penalize if the call was not made on time
        if (callTimestamp > nConfirmationsTimestamp + quote.callTime) {
            return true;
        }
        return false;
    }

    function shouldPenalizePegOutLP(
        QuotesV2.PegOutQuote memory quote,
        bytes32 quoteHash,
        bytes32 blockHash
    ) private view returns (bool) {
        bytes memory firstConfirmationHeader = bridge.getBtcBlockchainBlockHeaderByHash(blockHash);
        require(firstConfirmationHeader.length > 0, "LBC059");

        uint256 firstConfirmationTimestamp = BtcUtils.getBtcBlockTimestamp(firstConfirmationHeader);

        // penalize if the transfer was not made on time
        if (firstConfirmationTimestamp > pegoutRegistry[quoteHash].depositTimestamp +
        quote.transferTime + btcBlockTime) {
            return true;
        }

        // penalize if LP is refunding after expiration
        if (block.timestamp > quote.expireDate || block.number > quote.expireBlock) {
            return true;
        }

        return false;
    }

    function payToFeeCollector(uint amount, bytes32 quoteHash) private {
        if (amount > 0) {
            (bool daoSuccess,) = payable(daoFeeCollectorAddress).call{value: amount}("");
            require(daoSuccess, "LBC074");
            emit DaoFeeSent(quoteHash, amount);
        }
    }

    function updateProvider(string memory _name, string memory _url) external {
        require(bytes(_name).length > 0 && bytes(_url).length > 0, "LBC076");
        LiquidityProvider storage lp;
        for (uint i = 1; i <= providerId; i++) {
            lp = liquidityProviders[i];
            if (msg.sender == lp.provider) {
                lp.name = _name;
                lp.apiBaseUrl = _url;
                emit ProviderUpdate(msg.sender, lp.name, lp.apiBaseUrl);
                return;
            }
        }
        revert("LBC001");
    }
}
