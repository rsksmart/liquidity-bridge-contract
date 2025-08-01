// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {BtcUtils} from "@rsksmart/btc-transaction-solidity-helper/contracts/BtcUtils.sol";
import {OwnableDaoContributorUpgradeable} from "./DaoContributor.sol";
import {IBridge} from "./interfaces/Bridge.sol";
import {ICollateralManagement, CollateralManagementSet} from "./interfaces/CollateralManagement.sol";
import {IPegOut} from "./interfaces/PegOut.sol";
import {Flyover} from "./libraries/Flyover.sol";
import {Quotes} from "./libraries/Quotes.sol";
import {SignatureValidator} from "./libraries/SignatureValidator.sol";

contract PegOutContract is
    OwnableDaoContributorUpgradeable,
    IPegOut
{
    struct PegOutRecord {
        bool completed;
        uint256 depositTimestamp;
    }

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

    uint256 public dustThreshold;
    uint256 public btcBlockTime;
    bool private _mainnet;

    event DustThresholdSet(uint256 indexed oldThreshold, uint256 indexed newThreshold);
    event BtcBlockTimeSet(uint256 indexed oldTime, uint256 indexed newTime);

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

    // solhint-disable-next-line comprehensive-interface
    function setCollateralManagement(address collateralManagement) external onlyOwner {
        if (collateralManagement.code.length == 0) revert Flyover.NoContract(collateralManagement);
        emit CollateralManagementSet(address(_collateralManagement), collateralManagement);
        _collateralManagement = ICollateralManagement(collateralManagement);
    }

    // solhint-disable-next-line comprehensive-interface
    function setDustThreshold(uint256 threshold) external onlyOwner {
        emit DustThresholdSet(dustThreshold, threshold);
        dustThreshold = threshold;
    }

    // solhint-disable-next-line comprehensive-interface
    function setBtcBlockTime(uint256 blockTime) external onlyOwner {
        emit BtcBlockTimeSet(btcBlockTime, blockTime);
        btcBlockTime = blockTime;
    }

    function refundPegOut(
        bytes32 quoteHash,
        bytes calldata btcTx,
        bytes32 btcBlockHeaderHash,
        uint256 partialMerkleTree,
        bytes32[] calldata merkleBranchHashes
    ) external nonReentrant override {
        if(!_collateralManagement.isRegistered(_PEG_TYPE, msg.sender)) {
            revert Flyover.ProviderNotRegistered(msg.sender);
        }
        if (_isQuoteCompleted(quoteHash)) revert QuoteAlreadyCompleted(quoteHash);

        Quotes.PegOutQuote storage quote = _pegOutQuotes[quoteHash];
        if (quote.lbcAddress == address(0)) revert Flyover.QuoteNotFound(quoteHash);
        if (quote.lpRskAddress != msg.sender) revert InvalidSender(quote.lpRskAddress, msg.sender);

        BtcUtils.TxRawOutput[] memory outputs = BtcUtils.getOutputs(btcTx);
        _validateBtcTxNullData(outputs, quoteHash);
        _validateBtcTxConfirmations(quote, btcTx, btcBlockHeaderHash, partialMerkleTree, merkleBranchHashes);
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

    function refundUserPegOut(bytes32 quoteHash) external nonReentrant override {
        Quotes.PegOutQuote storage quote = _pegOutQuotes[quoteHash];

        if (quote.lbcAddress == address(0)) revert Flyover.QuoteNotFound(quoteHash);
        // solhint-disable-next-line gas-strict-inequalities
        if (quote.expireDate >= block.timestamp || quote.expireBlock >= block.number) revert QuoteNotExpired(quoteHash);

        uint256 valueToTransfer = quote.value + quote.callFee + quote.productFeeAmount + quote.gasFee;
        address addressToTransfer = quote.rskRefundAddress;

        delete _pegOutQuotes[quoteHash];
        _pegOutRegistry[quoteHash].completed = true;

        emit PegOutUserRefunded(quoteHash, quote.rskRefundAddress, valueToTransfer);
        _collateralManagement.slashPegOutCollateral(quote, quoteHash);

        (bool sent, bytes memory reason) = addressToTransfer.call{value: valueToTransfer}("");
        if (!sent) {
            revert Flyover.PaymentFailed(addressToTransfer, valueToTransfer, reason);
        }
    }

    function hashPegOutQuote(
        Quotes.PegOutQuote calldata quote
    ) external view override returns (bytes32) {
        return _hashPegOutQuote(quote);
    }

    function isQuoteCompleted(bytes32 quoteHash) external view override returns (bool) {
        return _isQuoteCompleted(quoteHash);
    }

    function _hashPegOutQuote(
        Quotes.PegOutQuote calldata quote
    ) private view returns (bytes32) {
        if (address(this) != quote.lbcAddress) {
            revert Flyover.IncorrectContract(address(this), quote.lbcAddress);
        }
        return keccak256(Quotes.encodePegOutQuote(quote));
    }

    function _isQuoteCompleted(bytes32 quoteHash) private view returns (bool) {
        return _pegOutRegistry[quoteHash].completed;
    }

    function _shouldPenalize(
        Quotes.PegOutQuote storage quote,
        bytes32 quoteHash,
        bytes32 blockHash
    ) private view returns (bool) {
        bytes memory firstConfirmationHeader = _bridge.getBtcBlockchainBlockHeaderByHash(blockHash);
        if(firstConfirmationHeader.length < 1) revert Flyover.InvalidBlockHeader(firstConfirmationHeader);

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

    function _validateBtcTxConfirmations(
        Quotes.PegOutQuote storage quote,
        bytes calldata btcTx,
        bytes32 btcBlockHeaderHash,
        uint256 partialMerkleTree,
        bytes32[] calldata merkleBranchHashes
    ) private view {
        int256 confirmations = _bridge.getBtcTransactionConfirmations(
            BtcUtils.hashBtcTx(btcTx),
            btcBlockHeaderHash,
            partialMerkleTree,
            merkleBranchHashes
        );
        if (confirmations < 0) {
            revert UnableToGetConfirmations(confirmations);
        } else if (confirmations < int(uint256(quote.transferConfirmations))) {
            revert NotEnoughConfirmations(int(uint256(quote.transferConfirmations)), confirmations);
        }
    }

    function _validateBtcTxAmount(
        BtcUtils.TxRawOutput[] memory outputs,
        Quotes.PegOutQuote storage quote
    ) private view {
        uint256 requiredAmount = quote.value;
        if (quote.value > _SAT_TO_WEI_CONVERSION && (quote.value % _SAT_TO_WEI_CONVERSION) != 0) {
            requiredAmount = quote.value - (quote.value % _SAT_TO_WEI_CONVERSION);
        }
        uint256 paidAmount = outputs[_PAY_TO_ADDRESS_OUTPUT].value * _SAT_TO_WEI_CONVERSION;
        if (paidAmount < requiredAmount) revert InsufficientAmount(requiredAmount, paidAmount);
    }

    function _validateBtcTxDestination(
        BtcUtils.TxRawOutput[] memory outputs,
        Quotes.PegOutQuote storage quote
    ) private view {
        bytes memory btcTxDestination = BtcUtils.outputScriptToAddress(
            outputs[_PAY_TO_ADDRESS_OUTPUT].pkScript,
            _mainnet
        );
        if (keccak256(quote.depositAddress) != keccak256(btcTxDestination)) {
            revert InvalidDestination(quote.depositAddress, btcTxDestination);
        }
    }

    function _validateBtcTxNullData(BtcUtils.TxRawOutput[] memory outputs, bytes32 quoteHash) private pure {
        bytes memory scriptContent = BtcUtils.parseNullDataScript(outputs[_QUOTE_HASH_OUTPUT].pkScript);
        uint256 scriptLength = scriptContent.length;

        if (scriptLength != _QUOTE_HASH_SIZE + 1 || uint8(scriptContent[0]) != _QUOTE_HASH_SIZE) {
            revert MalformedTransaction(scriptContent);
        }

        // shift the array to remove the first byte (the size)
        for (uint8 i = 0 ; i < scriptLength - 1; ++i) {
            scriptContent[i] = scriptContent[i + 1];
        }
        bytes32 txQuoteHash = abi.decode(scriptContent, (bytes32));
        if (quoteHash != txQuoteHash) revert InvalidQuoteHash(quoteHash, txQuoteHash);
    }
}
