// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {BtcUtils} from "@rsksmart/btc-transaction-solidity-helper/contracts/BtcUtils.sol";
import {OwnableDaoContributorUpgradeable} from "./DaoContributor.sol";
import {IBridge} from "./interfaces/IBridge.sol";
import {ICollateralManagement, CollateralManagementSet} from "./interfaces/ICollateralManagement.sol";
import {IPegOut} from "./interfaces/IPegOut.sol";
import {Flyover} from "./libraries/Flyover.sol";
import {Quotes} from "./libraries/Quotes.sol";
import {SignatureValidator} from "./libraries/SignatureValidator.sol";

/// @title PegOutContract
/// @notice This contract is used to handle the peg out of the RSK network to the Bitcoin network
/// @author Rootstock Labs
contract PegOutContract is
    OwnableDaoContributorUpgradeable,
    IPegOut
{
    /// @notice This struct is used to store the information of a peg out
    /// @param completed whether the peg out has been completed or not,
    /// completed means the peg out was paid and refunded (to any party)
    /// @param depositTimestamp the timestamp of the deposit
    struct PegOutRecord {
        bool completed;
        uint256 depositTimestamp;
    }

    /// @notice The version of the contract
    string constant public VERSION = "1.0.0";
    Flyover.ProviderType constant private _PEG_TYPE = Flyover.ProviderType.PegOut;
    uint256 constant private _PAY_TO_ADDRESS_OUTPUT = 0;
    uint256 constant private _QUOTE_HASH_OUTPUT = 1;
    uint256 constant private _SAT_TO_WEI_CONVERSION = 10**10;
    uint256 constant private _QUOTE_HASH_SIZE = 32;

    IBridge private _bridge;
    ICollateralManagement private _collateralManagement;

    mapping(bytes32 => Quotes.PegOutQuote) private _pegOutQuotes;
    mapping(bytes32 => PegOutRecord) private _pegOutRegistry;

    /// @notice The dust threshold for the peg out. If the difference between the amount paid and the amount required
    /// is more than this value, the difference goes back to the user's wallet
    uint256 public dustThreshold;
    /// @notice Average Bitcoin block time in seconds, used to calculate the expected confirmation time
    uint256 public btcBlockTime;
    bool private _mainnet;

    /// @notice This event is emitted when the dust threshold is set
    /// @param oldThreshold the old dust threshold
    /// @param newThreshold the new dust threshold
    event DustThresholdSet(uint256 indexed oldThreshold, uint256 indexed newThreshold);
    /// @notice This event is emitted when the Bitcoin block time is set
    /// @param oldTime the old Bitcoin block time
    /// @param newTime the new Bitcoin block time
    event BtcBlockTimeSet(uint256 indexed oldTime, uint256 indexed newTime);

    /// @inheritdoc IPegOut
    function depositPegOut(
        Quotes.PegOutQuote calldata quote,
        bytes calldata signature
    ) external payable nonReentrant override {
        if(!_collateralManagement.isRegistered(_PEG_TYPE, quote.lpRskAddress)) {
            revert Flyover.ProviderNotRegistered(quote.lpRskAddress);
        }
        uint256 requiredAmount = quote.value + quote.callFee + quote.productFeeAmount + quote.gasFee;
        if (msg.value < requiredAmount) {
            revert InsufficientAmount(msg.value, requiredAmount);
        }
        if (quote.depositDateLimit < block.timestamp || quote.expireDate < block.timestamp) {
            revert QuoteExpiredByTime(quote.depositDateLimit, quote.expireDate);
        }
        if (quote.expireBlock < block.number) {
            revert QuoteExpiredByBlocks(quote.expireBlock);
        }

        bytes32 quoteHash = _hashPegOutQuote(quote);
        if (!SignatureValidator.verify(quote.lpRskAddress, quoteHash, signature)) {
            revert SignatureValidator.IncorrectSignature(quote.lpRskAddress, quoteHash, signature);
        }

        Quotes.PegOutQuote storage registeredQuote = _pegOutQuotes[quoteHash];

        if (_isQuoteCompleted(quoteHash)) {
            revert QuoteAlreadyCompleted(quoteHash);
        }
        if (registeredQuote.lbcAddress != address(0)) {
            revert QuoteAlreadyRegistered(quoteHash);
        }

        _pegOutQuotes[quoteHash] = quote;
        _pegOutRegistry[quoteHash].depositTimestamp = block.timestamp;

        emit PegOutDeposit(quoteHash, msg.sender, msg.value, block.timestamp);

        if (dustThreshold > msg.value - requiredAmount) {
            return;
        }

        uint256 change = msg.value - requiredAmount;
        emit PegOutChangePaid(quoteHash, quote.rskRefundAddress, change);
        (bool sent, bytes memory reason) = quote.rskRefundAddress.call{value: change}("");
        if (!sent) {
            revert Flyover.PaymentFailed(quote.rskRefundAddress, change, reason);
        }
    }

    /// @notice This function is used to initialize the contract
    /// @param owner the owner of the contract
    /// @param bridge the address of the Rootstock bridge
    /// @param dustThreshold_ the dust threshold for the peg out
    /// @param collateralManagement the address of the Collateral Management contract
    /// @param mainnet whether the contract is on the mainnet or not
    /// @param btcBlockTime_ the average Bitcoin block time in seconds
    /// @param daoFeePercentage the percentage of the peg out amount that goes to the DAO.
    /// Use zero to disable the DAO integration feature
    /// @param daoFeeCollector the address of the DAO fee collector
    // solhint-disable-next-line comprehensive-interface
    function initialize(
        address owner,
        address payable bridge,
        uint256 dustThreshold_,
        address collateralManagement,
        bool mainnet,
        uint256 btcBlockTime_,
        uint256 daoFeePercentage,
        address payable daoFeeCollector
    ) external initializer {
        if (collateralManagement.code.length == 0) revert Flyover.NoContract(collateralManagement);
        __OwnableDaoContributor_init(owner, daoFeePercentage, daoFeeCollector);
        _bridge = IBridge(bridge);
        _collateralManagement = ICollateralManagement(collateralManagement);
        _mainnet = mainnet;
        dustThreshold = dustThreshold_;
        btcBlockTime = btcBlockTime_;
    }

    /// @notice This function is used to set the collateral management contract
    /// @param collateralManagement the address of the Collateral Management contract
    /// @dev This function is only callable by the owner of the contract
    // solhint-disable-next-line comprehensive-interface
    function setCollateralManagement(address collateralManagement) external onlyOwner {
        if (collateralManagement.code.length == 0) revert Flyover.NoContract(collateralManagement);
        emit CollateralManagementSet(address(_collateralManagement), collateralManagement);
        _collateralManagement = ICollateralManagement(collateralManagement);
    }

    /// @notice This function is used to set the dust threshold
    /// @param threshold the new dust threshold
    /// @dev This function is only callable by the owner of the contract
    // solhint-disable-next-line comprehensive-interface
    function setDustThreshold(uint256 threshold) external onlyOwner {
        emit DustThresholdSet(dustThreshold, threshold);
        dustThreshold = threshold;
    }

    /// @notice This function is used to set the average Bitcoin block time
    /// @param blockTime the new average Bitcoin block time in seconds
    /// @dev This function is only callable by the owner of the contract
    // solhint-disable-next-line comprehensive-interface
    function setBtcBlockTime(uint256 blockTime) external onlyOwner {
        emit BtcBlockTimeSet(btcBlockTime, blockTime);
        btcBlockTime = blockTime;
    }

    /// @inheritdoc IPegOut
    function refundPegOut(
        bytes32 quoteHash,
        bytes calldata btcTx,
        bytes32 btcBlockHeaderHash,
        uint256 merkleBranchPath,
        bytes32[] calldata merkleBranchHashes
    ) external nonReentrant override {
        if(!_collateralManagement.isRegistered(_PEG_TYPE, msg.sender)) {
            revert Flyover.ProviderNotRegistered(msg.sender);
        }
        if (_isQuoteCompleted(quoteHash)) revert QuoteAlreadyCompleted(quoteHash);

        Quotes.PegOutQuote memory quote = _pegOutQuotes[quoteHash];
        if (quote.lbcAddress == address(0)) revert Flyover.QuoteNotFound(quoteHash);
        if (quote.lpRskAddress != msg.sender) revert InvalidSender(quote.lpRskAddress, msg.sender);

        BtcUtils.TxRawOutput[] memory outputs = BtcUtils.getOutputs(btcTx);
        _validateBtcTxNullData(outputs, quoteHash);
        _validateBtcTxConfirmations(quote, btcTx, btcBlockHeaderHash, merkleBranchPath, merkleBranchHashes);
        _validateBtcTxAmount(outputs, quote);
        _validateBtcTxDestination(outputs, quote);

        delete _pegOutQuotes[quoteHash];
        _pegOutRegistry[quoteHash].completed = true;
        emit PegOutRefunded(quoteHash);

        _addDaoContribution(quote.lpRskAddress, quote.productFeeAmount);

        if (_shouldPenalize(quote, quoteHash, btcBlockHeaderHash)) {
            _collateralManagement.slashPegOutCollateral(quote, quoteHash);
        }

        uint256 refundAmount = quote.value + quote.callFee + quote.gasFee;
        (bool sent, bytes memory reason) = quote.lpRskAddress.call{value: refundAmount}("");
        if (!sent) {
            revert Flyover.PaymentFailed(quote.lpRskAddress, refundAmount, reason);
        }
    }

    /// @inheritdoc IPegOut
    function refundUserPegOut(bytes32 quoteHash) external nonReentrant override {
        Quotes.PegOutQuote memory quote = _pegOutQuotes[quoteHash];

        if (quote.lbcAddress == address(0)) revert Flyover.QuoteNotFound(quoteHash);
        // solhint-disable-next-line gas-strict-inequalities
        if (quote.expireDate >= block.timestamp || quote.expireBlock >= block.number) revert QuoteNotExpired(quoteHash);

        uint256 valueToTransfer = quote.value + quote.callFee + quote.productFeeAmount + quote.gasFee;
        address addressToTransfer = quote.rskRefundAddress;

        delete _pegOutQuotes[quoteHash];
        _pegOutRegistry[quoteHash].completed = true;

        emit PegOutUserRefunded(quoteHash, addressToTransfer, valueToTransfer);
        _collateralManagement.slashPegOutCollateral(quote, quoteHash);

        (bool sent, bytes memory reason) = addressToTransfer.call{value: valueToTransfer}("");
        if (!sent) {
            revert Flyover.PaymentFailed(addressToTransfer, valueToTransfer, reason);
        }
    }

    /// @inheritdoc IPegOut
    function hashPegOutQuote(
        Quotes.PegOutQuote calldata quote
    ) external view override returns (bytes32) {
        return _hashPegOutQuote(quote);
    }

    /// @inheritdoc IPegOut
    function isQuoteCompleted(bytes32 quoteHash) external view override returns (bool) {
        return _isQuoteCompleted(quoteHash);
    }

    /// @notice This function is used to hash a peg out quote
    /// @dev The function also validates the quote belongs to this contract
    /// @param quote the peg out quote to hash
    /// @return quoteHash the hash of the peg out quote
    function _hashPegOutQuote(
        Quotes.PegOutQuote calldata quote
    ) private view returns (bytes32) {
        if (address(this) != quote.lbcAddress) {
            revert Flyover.IncorrectContract(address(this), quote.lbcAddress);
        }
        return keccak256(Quotes.encodePegOutQuote(quote));
    }

    /// @notice This function is used to check if a quote has been completed (refunded by any party)
    /// @param quoteHash the hash of the quote to check
    /// @return completed whether the quote has been completed or not
    function _isQuoteCompleted(bytes32 quoteHash) private view returns (bool) {
        return _pegOutRegistry[quoteHash].completed;
    }

    /// @notice This function is used to check if a liquidity provider should be penalized
    /// according to the following rules:
    /// - If the transfer was not made on time, the liquidity provider should be penalized
    /// - If the liquidity provider is refunding after expiration, the liquidity provider should be penalized
    /// @param quote the peg out quote
    /// @param quoteHash the hash of the quote
    /// @param blockHash the hash of the block that contains the first confirmation of the peg out transaction
    /// @return shouldPenalize whether the liquidity provider should be penalized or not
    function _shouldPenalize(
        Quotes.PegOutQuote memory quote,
        bytes32 quoteHash,
        bytes32 blockHash
    ) private view returns (bool) {
        bytes memory firstConfirmationHeader = _bridge.getBtcBlockchainBlockHeaderByHash(blockHash);
        if(firstConfirmationHeader.length < 1) revert Flyover.EmptyBlockHeader(blockHash);

        uint256 firstConfirmationTimestamp = BtcUtils.getBtcBlockTimestamp(firstConfirmationHeader);
        uint256 expectedConfirmationTime = _pegOutRegistry[quoteHash].depositTimestamp +
            quote.transferTime +
            btcBlockTime;

        // penalize if the transfer was not made on time
        if (firstConfirmationTimestamp > expectedConfirmationTime) {
            return true;
        }

        // penalize if LP is refunding after expiration
        if (block.timestamp > quote.expireDate || block.number > quote.expireBlock) {
            return true;
        }

        return false;
    }

    /// @notice This function is used to validate the number of confirmations of the Bitcoin transaction.
    /// The function interacts with the Rootstock bridge to get the number of confirmations
    /// @param quote the peg out quote
    /// @param btcTx the Bitcoin transaction
    /// @param btcBlockHeaderHash the hash of the block that contains the first confirmation of the peg out transaction
    /// @param merkleBranchPath the path of the merkle branch
    /// @param merkleBranchHashes the hashes of the merkle branch
    function _validateBtcTxConfirmations(
        Quotes.PegOutQuote memory quote,
        bytes calldata btcTx,
        bytes32 btcBlockHeaderHash,
        uint256 merkleBranchPath,
        bytes32[] calldata merkleBranchHashes
    ) private view {
        int256 confirmations = _bridge.getBtcTransactionConfirmations(
            BtcUtils.hashBtcTx(btcTx),
            btcBlockHeaderHash,
            merkleBranchPath,
            merkleBranchHashes
        );
        if (confirmations < 0) {
            revert UnableToGetConfirmations(confirmations);
        } else if (confirmations < int(uint256(quote.transferConfirmations))) {
            revert NotEnoughConfirmations(int(uint256(quote.transferConfirmations)), confirmations);
        }
    }

    /// @notice This function is used to validate the destination of the Bitcoin transaction
    /// @param outputs the outputs of the Bitcoin transaction
    /// @param quote the peg out quote
    function _validateBtcTxDestination(
        BtcUtils.TxRawOutput[] memory outputs,
        Quotes.PegOutQuote memory quote
    ) private view {
        bytes memory btcTxDestination = BtcUtils.outputScriptToAddress(
            outputs[_PAY_TO_ADDRESS_OUTPUT].pkScript,
            _mainnet
        );
        if (keccak256(quote.depositAddress) != keccak256(btcTxDestination)) {
            revert InvalidDestination(quote.depositAddress, btcTxDestination);
        }
    }

    /// @notice This function is used to validate the amount of the Bitcoin transaction
    /// @param outputs the outputs of the Bitcoin transaction
    /// @param quote the peg out quote
    function _validateBtcTxAmount(
        BtcUtils.TxRawOutput[] memory outputs,
        Quotes.PegOutQuote memory quote
    ) private pure {
        uint256 requiredAmount = quote.value;
        if (quote.value > _SAT_TO_WEI_CONVERSION && (quote.value % _SAT_TO_WEI_CONVERSION) != 0) {
            requiredAmount = quote.value - (quote.value % _SAT_TO_WEI_CONVERSION);
        }
        uint256 paidAmount = outputs[_PAY_TO_ADDRESS_OUTPUT].value * _SAT_TO_WEI_CONVERSION;
        if (paidAmount < requiredAmount) revert InsufficientAmount(paidAmount, requiredAmount);
    }

    /// @notice This function is used to validate the null data of the Bitcoin transaction. The null data
    /// is used to store the hash of the peg out quote in the Bitcoin transaction
    /// @param outputs the outputs of the Bitcoin transaction
    /// @param quoteHash the hash of the peg out quote
    function _validateBtcTxNullData(BtcUtils.TxRawOutput[] memory outputs, bytes32 quoteHash) private pure {
        bytes memory scriptContent = BtcUtils.parseNullDataScript(outputs[_QUOTE_HASH_OUTPUT].pkScript);
        uint256 scriptLength = scriptContent.length;

        if (scriptLength != _QUOTE_HASH_SIZE + 1 || uint8(scriptContent[0]) != _QUOTE_HASH_SIZE) {
            revert MalformedTransaction(scriptContent);
        }

        bytes32 txQuoteHash;
        assembly {
            txQuoteHash := mload(add(scriptContent, 33)) // 32 bytes after the first byte
        }
        if (quoteHash != txQuoteHash) revert InvalidQuoteHash(quoteHash, txQuoteHash);
    }
}
