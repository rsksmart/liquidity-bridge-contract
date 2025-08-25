// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {BtcUtils} from "@rsksmart/btc-transaction-solidity-helper/contracts/BtcUtils.sol";
import {OwnableDaoContributorUpgradeable} from "./DaoContributor.sol";
import {IBridge} from "./interfaces/IBridge.sol";
import {ICollateralManagement, CollateralManagementSet} from "./interfaces/ICollateralManagement.sol";
import {IPegIn} from "./interfaces/IPegIn.sol";
import {Flyover} from "./libraries/Flyover.sol";
import {Quotes} from "./libraries/Quotes.sol";
import {SignatureValidator} from "./libraries/SignatureValidator.sol";

/// @title PegIn
/// @notice This contract is used to handle the peg in of the Bitcoin network to the Rootstock network
/// @dev All non pure/view functions in this contract should be marked as nonReentrant
/// @author Rootstock Labs
contract PegInContract is
    OwnableDaoContributorUpgradeable,
    IPegIn {

    /// @notice This struct is used to store the information of a call on behalf of the user
    /// @param timestamp The timestamp of the call
    /// @param success Whether the call was successful or not
    struct Registry {
        uint256 timestamp;
        bool success;
    }

    /// @notice The version of the contract
    string constant public VERSION = "1.0.0";
    Flyover.ProviderType constant private _PEG_TYPE = Flyover.ProviderType.PegIn;
    uint256 constant private _REFUND_ADDRESS_LENGTH = 21;

    uint256 constant private _MAX_CALL_GAS_COST = 35000;
    uint256 constant private _MAX_REFUND_GAS_LIMIT = 2300;

    int256 constant private _BRIDGE_UNPROCESSABLE_TX_VALIDATIONS_ERROR = -303;
    int256 constant private _BRIDGE_REFUNDED_USER_ERROR_CODE = -100;
    int256 constant private _BRIDGE_REFUNDED_LP_ERROR_CODE = -200;

    IBridge private _bridge;
    ICollateralManagement private _collateralManagement;

    mapping(address => uint256) private _balances;
    mapping(bytes32 => PegInStates) private _processedQuotes;
    mapping(bytes32 => Registry) private _callRegistry;

    uint256 private _minPegIn;
    bool private _mainnet;
    /// @notice The dust threshold for the peg in. If the difference between the amount paid and the amount required
    /// is more than this value, the difference goes back to the user's wallet
    uint256 public dustThreshold;

    /// @notice Emitted when the dust threshold is set
    /// @param oldThreshold The old dust threshold
    /// @param newThreshold The new dust threshold
    event DustThresholdSet(uint256 indexed oldThreshold, uint256 indexed newThreshold);

    /// @notice Emitted when the minimum peg in amount is set
    /// @param oldMinPegIn The old minimum peg in amount
    /// @param newMinPegIn The new minimum peg in amount
    event MinPegInSet(uint256 indexed oldMinPegIn, uint256 indexed newMinPegIn);

    // solhint-disable-next-line comprehensive-interface
    receive() external payable {
        if (msg.sender != address(_bridge)) {
            revert Flyover.PaymentNotAllowed();
        }
    }

    /// @notice This function is used to initialize the contract
    /// @param owner the owner of the contract
    /// @param bridge the address of the Rootstock bridge
    /// @param dustThreshold_ the dust threshold for the peg in
    /// @param minPegIn the minimum peg in amount supported by the bridge
    /// @param collateralManagement the address of the Collateral Management contract
    /// @param mainnet whether the contract is on the mainnet or not
    /// @param daoFeePercentage the percentage of the peg in amount that goes to the DAO.
    /// Use zero to disable the DAO integration feature
    /// @param daoFeeCollector the address of the DAO fee collector
    // solhint-disable-next-line comprehensive-interface
    function initialize(
        address owner,
        address payable bridge,
        uint256 dustThreshold_,
        uint256 minPegIn,
        address collateralManagement,
        bool mainnet,
        uint256 daoFeePercentage,
        address payable daoFeeCollector
    ) external initializer {
        if (collateralManagement.code.length == 0) revert Flyover.NoContract(collateralManagement);
        __OwnableDaoContributor_init(owner, daoFeePercentage, daoFeeCollector);
        _bridge = IBridge(bridge);
        _collateralManagement = ICollateralManagement(collateralManagement);
        _mainnet = mainnet;
        dustThreshold = dustThreshold_;
        _minPegIn = minPegIn;
    }

    /// @notice This function is used to set the collateral management contract
    /// @param collateralManagement the address of the Collateral Management contract
    /// @dev This function is only callable by the owner of the contract
    // solhint-disable-next-line comprehensive-interface
    function setCollateralManagement(address collateralManagement) external onlyOwner nonReentrant {
        if (collateralManagement.code.length == 0) revert Flyover.NoContract(collateralManagement);
        emit CollateralManagementSet(address(_collateralManagement), collateralManagement);
        _collateralManagement = ICollateralManagement(collateralManagement);
    }

    /// @notice This function is used to set the dust threshold
    /// @param threshold the new dust threshold
    /// @dev This function is only callable by the owner of the contract
    // solhint-disable-next-line comprehensive-interface
    function setDustThreshold(uint256 threshold) external onlyOwner nonReentrant {
        emit DustThresholdSet(dustThreshold, threshold);
        dustThreshold = threshold;
    }

    /// @notice This function is used to set the minimum peg in amount
    /// @param minPegIn the new minimum peg in amount
    /// @dev This function is only callable by the owner of the contract
    // solhint-disable-next-line comprehensive-interface
    function setMinPegIn(uint256 minPegIn) external onlyOwner nonReentrant {
        emit MinPegInSet(_minPegIn, minPegIn);
        _minPegIn = minPegIn;
    }

    /// @inheritdoc IPegIn
    function deposit() external payable nonReentrant override {
        if(!_collateralManagement.isRegistered(_PEG_TYPE, msg.sender)) {
            revert Flyover.ProviderNotRegistered(msg.sender);
        }
        _increaseBalance(msg.sender, msg.value);
    }

    /// @inheritdoc IPegIn
    function withdraw(uint256 amount) external nonReentrant override  {
        uint256 balance = _balances[msg.sender];
        if (balance < amount) {
            revert Flyover.NoBalance(amount, balance);
        }
        _decreaseBalance(msg.sender, amount);
        emit Withdrawal(msg.sender, amount);
        (bool success, bytes memory reason) = msg.sender.call{value: amount}("");
        if (!success) {
            revert Flyover.PaymentFailed(msg.sender, amount, reason);
        }
    }

    /// @inheritdoc IPegIn
    function callForUser(
        Quotes.PegInQuote calldata quote
    ) external payable nonReentrant override returns (bool) {
        if(!_collateralManagement.isRegistered(_PEG_TYPE, msg.sender)) {
            revert Flyover.ProviderNotRegistered(msg.sender);
        }
        if (quote.liquidityProviderRskAddress != msg.sender) {
            revert Flyover.InvalidSender(quote.liquidityProviderRskAddress, msg.sender);
        }
        uint256 newBalance = _balances[quote.liquidityProviderRskAddress] + msg.value;
        if (newBalance < quote.value) {
            revert Flyover.InsufficientAmount(newBalance, quote.value);
        }

        bytes32 quoteHash = _hashPegInQuote(quote);
        if (_processedQuotes[quoteHash] != PegInStates.UNPROCESSED_QUOTE) {
            revert QuoteAlreadyProcessed(quoteHash);
        }

        _increaseBalance(quote.liquidityProviderRskAddress, msg.value);

        // This check ensures that the call cannot be performed with less gas than the agreed amount
        if (gasleft() < quote.gasLimit + _MAX_CALL_GAS_COST) {
            revert InsufficientGas(gasleft(), quote.gasLimit + _MAX_CALL_GAS_COST);
        }
        _callRegistry[quoteHash].timestamp = block.timestamp;
        _processedQuotes[quoteHash] = PegInStates.CALL_DONE;

        (bool success,) = quote.contractAddress.call{
            gas: quote.gasLimit,
            value: quote.value
        }(quote.data);

        if (success) {
            _callRegistry[quoteHash].success = true;
            _decreaseBalance(quote.liquidityProviderRskAddress, quote.value);
        }

        emit CallForUser(
            msg.sender,
            quote.contractAddress,
            quoteHash,
            quote.gasLimit,
            quote.value,
            quote.data,
            success
        );
        return success;
    }

    /// @inheritdoc IPegIn
    function registerPegIn(
        Quotes.PegInQuote calldata quote,
        bytes calldata signature,
        bytes calldata btcRawTransaction,
        bytes calldata partialMerkleTree,
        uint256 height
    ) external nonReentrant override returns (int256) {
        bytes32 quoteHash = _hashPegInQuote(quote);
        _validateRegisterParams(quote, quoteHash, height, signature);
        int256 registerResult = _registerBridge(quote, btcRawTransaction, partialMerkleTree, height, quoteHash);

        bool btcRefunded = registerResult == _BRIDGE_REFUNDED_USER_ERROR_CODE ||
            registerResult == _BRIDGE_REFUNDED_LP_ERROR_CODE;
        if (registerResult == _BRIDGE_UNPROCESSABLE_TX_VALIDATIONS_ERROR) {
            revert NotEnoughConfirmations();
        } else if (!btcRefunded && registerResult < 1) {
            revert UnexpectedBridgeError(registerResult);
        }

        Registry memory callRegistry = _callRegistry[quoteHash];
        delete _callRegistry[quoteHash];
        if (_shouldPenalize(quote, registerResult, callRegistry.timestamp, height)) {
            _collateralManagement.slashPegInCollateral(msg.sender, quote, quoteHash);
        }
        if (btcRefunded) {
            _processedQuotes[quoteHash] = PegInStates.PROCESSED_QUOTE;
            emit BridgeCapExceeded(quoteHash, registerResult);
            return registerResult;
        }

        // the amount is safely assumed positive because it's already been validated there's
        // no (negative) error code being returned by the bridge.
        uint256 transferredAmount = uint256(registerResult);
        Quotes.checkAgreedAmount(quote, transferredAmount);

        _processedQuotes[quoteHash] = PegInStates.PROCESSED_QUOTE;
        emit PegInRegistered(quoteHash, transferredAmount);
        if (callRegistry.timestamp > 0) {
            _registerCallDone(quote, quoteHash, callRegistry.success, transferredAmount);
        } else {
            _registerCallNotDone(quote, quoteHash, transferredAmount);
        }
        return registerResult;
    }

    /// @inheritdoc IPegIn
    function validatePegInDepositAddress(
        Quotes.PegInQuote calldata quote,
        bytes calldata depositAddress
    ) external view override returns (bool) {
        bytes32 derivationValue = keccak256(
            bytes.concat(
                _hashPegInQuote(quote),
                quote.btcRefundAddress,
                bytes20(quote.lbcAddress),
                quote.liquidityProviderBtcAddress
            )
        );
        bytes memory flyoverRedeemScript = bytes.concat(
            hex"20",
            derivationValue,
            hex"75",
            _bridge.getActivePowpegRedeemScript()
        );
        return BtcUtils.validateP2SHAdress(depositAddress, flyoverRedeemScript, _mainnet);
    }

    /// @inheritdoc IPegIn
    function getMinPegIn() external view override returns (uint256) {
        return _minPegIn;
    }

    /// @inheritdoc IPegIn
    function getBalance(address addr) external view override returns (uint256) {
        if (_reentrancyGuardEntered()) revert ReentrancyGuardReentrantCall();
        return _balances[addr];
    }

    /// @inheritdoc IPegIn
    function hashPegInQuote(Quotes.PegInQuote calldata quote) external view override returns (bytes32) {
        return _hashPegInQuote(quote);
    }

    /// @inheritdoc IPegIn
    function getQuoteStatus(bytes32 quoteHash) external view override returns (PegInStates) {
        if (_reentrancyGuardEntered()) revert ReentrancyGuardReentrantCall();
        return _processedQuotes[quoteHash];
    }

    /// @notice This function is used to increase the balance of an account
    /// @dev This function must remain private. Any exposure can lead to a loss of funds.
    /// It is responsibility of the caller to ensure that the account is a liquidity provider
    /// @param dest The address of account
    /// @param amount The amount of balance to increase
    function _increaseBalance(address dest, uint256 amount) private {
        if (amount > 0) {
            _balances[dest] += amount;
            emit BalanceIncrease(dest, amount);
        }
    }

    /// @notice This function is used to decrease the balance of an account
    /// @dev This function must remain private. Any exposure can lead to a loss of funds.
    /// It is responsibility of the caller to ensure that the account is a liquidity provider
    /// @param dest The address of account
    /// @param amount The amount of balance to decrease
    function _decreaseBalance(address dest, uint256 amount) private {
        if (amount > 0) {
            _balances[dest] -= amount;
            emit BalanceDecrease(dest, amount);
        }
    }

    /// @notice This function is used to register the peg in into the bridge
    /// @param quote The quote of the peg in
    /// @param btcRawTransaction The raw transaction of the peg in in the Bitcoin network,
    /// without the witness data
    /// @param partialMerkleTree The partial merkle tree proving the inclusion of the peg
    /// in transaction
    /// @param height The height of the peg in transaction
    /// @param derivationHash The hash of the quote used to derive the deposit address
    /// @return registerResult The result of the registration. It can be:
    /// - A negative value: An error code returned by the bridge
    /// - A positive value: The amount of the peg in transaction
    function _registerBridge(
        Quotes.PegInQuote memory quote,
        bytes memory btcRawTransaction,
        bytes memory partialMerkleTree,
        uint256 height,
        bytes32 derivationHash
    ) private returns (int256) {
        Registry memory callRegistry = _callRegistry[derivationHash];
        return _bridge.registerFastBridgeBtcTransaction(
            btcRawTransaction,
            height,
            partialMerkleTree,
            derivationHash,
            quote.btcRefundAddress,
            payable(this),
            quote.liquidityProviderBtcAddress,
            callRegistry.timestamp > 0 && callRegistry.success
        );
    }

    /// @notice This function is used by the registerPegIn function to handle the scenarios
    /// where the liquidity provider has already called the callForUser function
    /// @dev This function makes an external call, therefore it might be exposed to a reentrancy attack,
    /// the caller must have the nonReentrant modifier or any kind of reentrancy protection. Not all the
    /// modifications to the state can be done before the call as some of them depend on the result of the
    /// call itself
    /// @param quote The quote of the peg in
    /// @param quoteHash The hash of the quote
    /// @param callSuccessful Whether the call on behalf of the user was successful or not
    /// @param transferredAmount The amount of the peg in transaction
    function _registerCallDone(
        Quotes.PegInQuote calldata quote,
        bytes32 quoteHash,
        bool callSuccessful,
        uint256 transferredAmount
    ) private {
        uint refundAmount;
        if (callSuccessful) {
            refundAmount = _min(transferredAmount, quote.value + quote.callFee + quote.gasFee);
        } else {
            refundAmount = _min(transferredAmount, quote.callFee + quote.gasFee);
        }
        _increaseBalance(quote.liquidityProviderRskAddress, refundAmount);
        _addDaoContribution(quote.liquidityProviderRskAddress, quote.productFeeAmount);

        uint remainingAmount = transferredAmount - refundAmount - quote.productFeeAmount;
        if (remainingAmount > dustThreshold) {
            // refund rskRefundAddress, if remaining amount greater than dust
            (bool success,) = quote.rskRefundAddress.call{
                gas: _MAX_REFUND_GAS_LIMIT,
                value: remainingAmount
            }("");

            emit Refund(
                quote.rskRefundAddress,
                quoteHash,
                remainingAmount,
                success
            );

            if (!success) {
                // transfer funds to LP instead, if for some reason transfer to rskRefundAddress was unsuccessful
                _increaseBalance(quote.liquidityProviderRskAddress, remainingAmount);
            }
        }
    }

    /// @notice This function is used by the registerPegIn function to handle the scenarios
    /// where the liquidity provider has not called the callForUser function
    /// @dev This function makes an external call, therefore it might be exposed to a reentrancy attack,
    /// the caller must have the nonReentrant modifier or any kind of reentrancy protection. Not all the
    /// modifications to the state can be done before the call as some of them depend on the result of the
    /// call itself
    /// @param quote The quote of the peg in
    /// @param quoteHash The hash of the quote
    /// @param transferredAmount The amount of the peg in transaction
    function _registerCallNotDone(
        Quotes.PegInQuote calldata quote,
        bytes32 quoteHash,
        uint256 transferredAmount
    ) private {
        uint refundAmount = transferredAmount;

        if (quote.callOnRegister && refundAmount > quote.value - 1) {
            (bool callSuccess,) = quote.contractAddress.call{
                gas: quote.gasLimit,
                value: quote.value
            }(quote.data);

            emit CallForUser(
                msg.sender,
                quote.contractAddress,
                quoteHash,
                quote.gasLimit,
                quote.value,
                quote.data,
                callSuccess
            );

            if (callSuccess) {
                refundAmount -= quote.value;
            }
        }
        if (refundAmount > dustThreshold) {
            // refund rskRefundAddress, if refund amount greater than dust
            (bool success,) = quote.rskRefundAddress.call{
                gas: _MAX_REFUND_GAS_LIMIT,
                value: refundAmount
            }("");
            emit Refund(
                quote.rskRefundAddress,
                quoteHash,
                refundAmount,
                success
            );
        }
    }

    /// @notice This function is used to validate the parameters of the registerPegIn function
    /// @dev The validations include:
    /// - If the quote was already registered
    /// - If the signature provided by the liquidity provider is valid
    /// - If the height is supported by the Rootstock bridge
    /// @param quote The quote of the peg in
    /// @param quoteHash The hash of the quote
    /// @param height The height of the peg in transaction
    /// @param signature The signature of the quoteHash by the liquidity provider
    function _validateRegisterParams(
        Quotes.PegInQuote calldata quote,
        bytes32 quoteHash,
        uint256 height,
        bytes calldata signature
    ) private view {
        if (_processedQuotes[quoteHash] == PegInStates.PROCESSED_QUOTE) {
            revert QuoteAlreadyProcessed(quoteHash);
        }
        if (!SignatureValidator.verify(quote.liquidityProviderRskAddress, quoteHash, signature)) {
            revert SignatureValidator.IncorrectSignature(quote.liquidityProviderRskAddress, quoteHash, signature);
        }
        // the actual type in the RSKj node source code is a java int which is equivalent to int32
        if (height > uint256(int(type(int32).max)) - 1) {
            revert Flyover.Overflow(uint256(int(type(int32).max)));
        }
    }

    /// @notice This function is used to hash a peg in quote
    /// @dev The function also validates the following:
    /// - The quote belongs to this contract
    /// - The quote destination is not the bridge contract
    /// - The quote BTC refund address is valid
    /// - The quote liquidity provider BTC address is valid
    /// - The quote total amount is greater than the bridge minimum peg in amount
    /// - The sum of the timestamp values is not greater than the maximum uint32 value
    /// @param quote The peg in quote
    /// @return quoteHash The hash of the quote
    function _hashPegInQuote(Quotes.PegInQuote calldata quote) private view returns (bytes32) {
        if (address(this) != quote.lbcAddress) {
            revert Flyover.IncorrectContract(address(this), quote.lbcAddress);
        }
        if (address(_bridge) == quote.contractAddress) {
            revert Flyover.NoContract(quote.contractAddress);
        }
        if (quote.btcRefundAddress.length != _REFUND_ADDRESS_LENGTH) {
            revert InvalidRefundAddress(quote.btcRefundAddress);
        }
        if (quote.liquidityProviderBtcAddress.length != _REFUND_ADDRESS_LENGTH) {
            revert InvalidRefundAddress(quote.liquidityProviderBtcAddress);
        }
        uint256 total = quote.value + quote.callFee + quote.productFeeAmount + quote.gasFee;
        if (total < _minPegIn) {
            revert AmountUnderMinimum(_minPegIn);
        }
        if (type(uint32).max < uint64(quote.agreementTimestamp) + uint64(quote.timeForDeposit)) {
            revert Flyover.Overflow(type(uint32).max);
        }
        return keccak256(Quotes.encodeQuote(quote));
    }

    /// @notice This function is used to determine if the liquidity provider should be penalized
    /// @param quote The peg in quote
    /// @param amount The amount of the peg in transaction
    /// @param callTimestamp The timestamp of the call on behalf of the user
    /// @param height The height of the peg in transaction
    /// @return shouldPenalize Whether the liquidity provider should be penalized or not
    function _shouldPenalize(
        Quotes.PegInQuote calldata quote,
        int256 amount,
        uint256 callTimestamp,
        uint256 height
    ) private view returns (bool) {
        // do not penalize if deposit amount is insufficient
        uint256 quoteTotal = quote.value + quote.callFee + quote.productFeeAmount + quote.gasFee;
        if (amount > 0 && uint256(amount) < quoteTotal) {
            return false;
        }

        bytes memory firstConfirmationHeader = _bridge.getBtcBlockchainBlockHeaderByHeight(height);
        if (firstConfirmationHeader.length < 1) revert Flyover.EmptyBlockHeader(bytes32(height));

        uint256 firstConfirmationTimestamp = BtcUtils.getBtcBlockTimestamp(
            firstConfirmationHeader
        );

        // do not penalize if deposit was not made on time
        uint256 timeLimit = quote.agreementTimestamp + quote.timeForDeposit;
        if (firstConfirmationTimestamp > timeLimit) {
            return false;
        }

        // penalize if call was not made
        if (callTimestamp == 0) {
            return true;
        }

        bytes memory nConfirmationsHeader = _bridge.getBtcBlockchainBlockHeaderByHeight(
            height + quote.depositConfirmations - 1
        );
        if (nConfirmationsHeader.length < 1) revert Flyover.EmptyBlockHeader(bytes32(height));
        uint256 nConfirmationsTimestamp = BtcUtils.getBtcBlockTimestamp(
            nConfirmationsHeader
        );

        // penalize if the call was not made on time
        if (callTimestamp > nConfirmationsTimestamp + quote.callTime) {
            return true;
        }

        return false;
    }

    /// @dev Utility function to return the minimum of two uint256 values
    function _min(uint a, uint b) private pure returns (uint) {
        return a < b ? a : b;
    }
}
