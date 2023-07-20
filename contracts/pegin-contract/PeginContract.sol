// SPDX-License-Identifier: MIT
pragma solidity ^0.8.3;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts-upgradeable/access/AccessControlDefaultAdminRulesUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "../Bridge.sol";
import "../libraries/Quotes.sol";
import "../libraries/BtcUtils.sol";
import "../libraries/FlyoverModule.sol";
import "../libraries/SignatureValidator.sol";
import "../liquidity-provider-contract/LiquidityProviderContract.sol";

contract PeginContract is Initializable, ReentrancyGuardUpgradeable, AccessControlDefaultAdminRulesUpgradeable {

    uint16 constant public MAX_CALL_GAS_COST = 35000;
    uint16 constant public MAX_REFUND_GAS_LIMIT = 2300;

    uint8 constant public UNPROCESSED_QUOTE_CODE = 0;
    uint8 constant public CALL_DONE_CODE = 1;
    uint8 constant public PROCESSED_QUOTE_CODE = 2;

    uint32 constant public MAX_INT32 = 2147483647;
    uint32 constant public MAX_UINT32 = 4294967295;

    struct Registry {
        uint32 timestamp;
        bool success;
    }

    Bridge public bridge;
    LiquidityProviderContract private liquidityProviderContract;

    mapping(bytes32 => Registry) private callRegistry;
    uint256 private minPegIn;
    uint32 private rewardP;
    uint private dust;
    mapping(bytes32 => uint8) private processedQuotes;

    // there isn't one LBC anymore so this contract needs to know
    // which address are using LPs to hash the quotes
    address private providerInterfaceAddress;

    event CallForUser(
        address indexed from, address indexed dest, uint gasLimit,
        uint value, bytes data, bool success, bytes32 quoteHash
    );
    event BridgeCapExceeded(bytes32 quoteHash, int256 errorCode);
    event Refund(address dest, uint amount, bool success, bytes32 quoteHash);
    event BalanceReturned(LiquidityProviderContract lpContract, uint amount);

    modifier onlyLP(address sender) {
        require(liquidityProviderContract.isRegistered(sender), "LBC001");
        _;
    }

    receive() external payable {
        if (msg.sender != address(liquidityProviderContract)) {
            returnBalance(msg.value);
        }
    }

    function returnBalance(uint amount) private {
        (bool success, ) = address(liquidityProviderContract).call{value: amount}("");
        require(success, "LBC070");
        emit BalanceReturned(liquidityProviderContract, amount);
    }

    /**
        @param _bridgeAddress The address of the bridge contract
        @param _minimumPegIn The minimum peg-in amount
        @param _rewardPercentage The percentage of the penalty fee that an honest party
        // receives when calling registerPegIn in case of a liquidity provider misbehaving
        @param _dustThreshold Amount that is considered dust
     */
    function initialize(
        address payable _bridgeAddress,
        address payable _liquidityProviderContract,
        uint256 _minimumPegIn,
        uint32 _rewardPercentage,
        uint _dustThreshold
    ) external initializer {
        require(_rewardPercentage <= 100, "LBC004");
        __AccessControlDefaultAdminRules_init(30 minutes, msg.sender);
        bridge = Bridge(_bridgeAddress);
        liquidityProviderContract = LiquidityProviderContract(_liquidityProviderContract);
        minPegIn = _minimumPegIn;
        rewardP = _rewardPercentage;
        dust = _dustThreshold;
    }

    function getMinPegIn() external view returns (uint) {
        return minPegIn;
    }

    function getRewardPercentage() external view returns (uint) {
        return rewardP;
    }

    function getDustThreshold() external view returns (uint) {
        return dust;
    }

    /**
        @dev Calculates hash of a quote. Note: besides calculation this function also validates the quote.
        @param quote The quote of the service
        @return The hash of a quote
     */
    function hashQuote(Quotes.PeginQuote memory quote) public view
        onlyRole(FlyoverModule.MODULE_ROLE) returns (bytes32) {
        return validateAndHashQuote(quote);
    }

    /**
        @dev Performs a call on behalf of a user
        @param quote The quote that identifies the service
        @return Boolean indicating whether the call was successful
     */
    function callForUser(
        address sender,
        Quotes.PeginQuote memory quote
    ) external payable onlyRole(FlyoverModule.MODULE_ROLE) onlyLP(sender) nonReentrant returns (bool) {
        require(
            sender == quote.liquidityProviderRskAddress,
            "LBC024"
        );
        require(
            liquidityProviderContract.getBalance(quote.liquidityProviderRskAddress) + msg.value >=
            quote.value,
            "LBC019"
        );

        bytes32 quoteHash = validateAndHashQuote(quote);
        require(
            processedQuotes[quoteHash] == UNPROCESSED_QUOTE_CODE,
            "LBC025"
        );

        returnBalance(msg.value);
        liquidityProviderContract.increaseBalance(quote.liquidityProviderRskAddress, msg.value);

        // This check ensures that the call cannot be performed with less gas than the agreed amount
        require(
            gasleft() >= quote.gasLimit + MAX_CALL_GAS_COST,
            "LBC026"
        );
        liquidityProviderContract.useBalance(quote.value);
        (bool success,) = quote.contractAddress.call{
                gas: quote.gasLimit,
                value: quote.value
            }(quote.data);

        require(block.timestamp <= MAX_UINT32, "LBC027");
        callRegistry[quoteHash].timestamp = uint32(block.timestamp);

        if (success) {
            callRegistry[quoteHash].success = true;
            liquidityProviderContract.decreaseBalance(quote.liquidityProviderRskAddress, quote.value);
        } else {
            returnBalance(quote.value);
        }
        emit CallForUser(
            sender,
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
        address sender,
        Quotes.PeginQuote calldata quote,
        bytes calldata signature,
        bytes calldata btcRawTransaction,
        bytes calldata partialMerkleTree,
        uint256 height
    ) public onlyRole(FlyoverModule.MODULE_ROLE) nonReentrant returns (int256) {
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
        require(height < uint256(MAX_INT32), "LBC030");

        int256 transferredAmountOrErrorCode = registerBridge(
            quote,
            btcRawTransaction,
            partialMerkleTree,
            height,
            quoteHash
        );

        require(
            transferredAmountOrErrorCode !=
            FlyoverModule.BRIDGE_UNPROCESSABLE_TX_VALIDATIONS_ERROR,
            "LBC031"
        );
        require(
            transferredAmountOrErrorCode !=
            FlyoverModule.BRIDGE_UNPROCESSABLE_TX_ALREADY_PROCESSED_ERROR_CODE,
            "LBC032"
        );
        require(
            transferredAmountOrErrorCode !=
            FlyoverModule.BRIDGE_UNPROCESSABLE_TX_VALUE_ZERO_ERROR,
            "LBC033"
        );
        require(
            transferredAmountOrErrorCode !=
            FlyoverModule.BRIDGE_UNPROCESSABLE_TX_UTXO_AMOUNT_SENT_BELOW_MINIMUM_ERROR,
            "LBC034"
        );
        require(
            transferredAmountOrErrorCode != FlyoverModule.BRIDGE_GENERIC_ERROR,
            "LBC035"
        );
        require(
            transferredAmountOrErrorCode > 0 ||
            transferredAmountOrErrorCode == FlyoverModule.BRIDGE_REFUNDED_LP_ERROR_CODE ||
            transferredAmountOrErrorCode == FlyoverModule.BRIDGE_REFUNDED_USER_ERROR_CODE,
            "LBC036"
        );

        penalizeIfApplies(sender, quote, transferredAmountOrErrorCode, quoteHash, height);

        if (
            transferredAmountOrErrorCode == FlyoverModule.BRIDGE_REFUNDED_LP_ERROR_CODE ||
            transferredAmountOrErrorCode == FlyoverModule.BRIDGE_REFUNDED_USER_ERROR_CODE
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

        Quotes.checkAgreedAmount(quote, transferredAmount);

        if (callRegistry[quoteHash].timestamp > 0) {
            registerCallForUserPerformed(quote, quoteHash, transferredAmount);
        } else {
            registerCallForUserNotPerformed(sender, quote, quoteHash, transferredAmount);
        }
        processedQuotes[quoteHash] = PROCESSED_QUOTE_CODE;
        delete callRegistry[quoteHash];
        return transferredAmountOrErrorCode;
    }

    function penalizeIfApplies(
        address sender,
        Quotes.PeginQuote calldata quote,
        int256 value,
        bytes32 quoteHash,
        uint256 height
    ) private {
        if (
            shouldPenalizeLP(
            quote,
            value,
            callRegistry[quoteHash].timestamp,
            height
        )
        ) {
            uint penalizationAmount= liquidityProviderContract.penalizeForPegin(quote, quoteHash);

            // pay reward to sender
            uint256 punisherReward = (penalizationAmount * rewardP) / 100;
            liquidityProviderContract.increaseBalance(sender, punisherReward);
        }
    }

    function registerCallForUserPerformed(
        Quotes.PeginQuote calldata quote,
        bytes32 quoteHash,
        uint transferredAmount
    ) private {
        uint refundAmount;

        if (callRegistry[quoteHash].success) {
            refundAmount = min(
                transferredAmount,
                quote.value + quote.callFee
            );
        } else {
            refundAmount = min(transferredAmount, quote.callFee);
        }
        liquidityProviderContract.increaseBalance(quote.liquidityProviderRskAddress, refundAmount);
        uint remainingAmount = transferredAmount - refundAmount;

        if (remainingAmount > dust) {
            // refund rskRefundAddress, if remaining amount greater than dust
            liquidityProviderContract.useBalance(remainingAmount);
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
                returnBalance(remainingAmount);
                // transfer funds to LP instead, if for some reason transfer to rskRefundAddress was unsuccessful
                liquidityProviderContract.increaseBalance(
                    quote.liquidityProviderRskAddress,
                    remainingAmount
                );
            }
        }
    }

    function registerCallForUserNotPerformed(
        address sender,
        Quotes.PeginQuote calldata quote,
        bytes32 quoteHash,
        uint transferredAmount
    ) private {
        uint refundAmount = transferredAmount;

        if (quote.callOnRegister && refundAmount >= quote.value) {
            liquidityProviderContract.useBalance(quote.value);
            (bool callSuccess,) = quote.contractAddress.call{
                    gas: quote.gasLimit,
                    value: quote.value
                }(quote.data);
            emit CallForUser(
                sender,
                quote.contractAddress,
                quote.gasLimit,
                quote.value,
                quote.data,
                callSuccess,
                quoteHash
            );

            if (callSuccess) {
                refundAmount -= quote.value;
            } else {
                returnBalance(quote.value);
            }
        }
            
        if (refundAmount > dust) {
            // refund rskRefundAddress, if refund amount greater than dust
            liquidityProviderContract.useBalance(refundAmount);
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
            if (!success) {
                returnBalance(refundAmount);
            }
        }
    }

    function validateAndHashQuote(
        Quotes.PeginQuote memory quote
    ) private view returns (bytes32) {
        require(providerInterfaceAddress == quote.lbcAddress, "LBC051");
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
            quote.value + quote.callFee >= minPegIn,
            "LBC055"
        );

        return keccak256(Quotes.encodeQuote(quote));
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
        Quotes.PeginQuote memory quote,
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
            payable(liquidityProviderContract),
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
        Quotes.PeginQuote memory quote,
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

    function min(uint a, uint b) private pure returns (uint) {
        return a < b ? a : b;
    }

    function getProviderInterfaceAddress() external view returns (address) {
        require(msg.sender == owner(), "LBC072");
        return providerInterfaceAddress;
    }

    function setProviderInterfaceAddress(address _providerInterfaceAddress) external {
        require(msg.sender == owner(), "LBC072");
        providerInterfaceAddress = _providerInterfaceAddress;
    }
}