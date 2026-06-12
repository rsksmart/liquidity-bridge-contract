// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {
    AccessControlDefaultAdminRulesUpgradeable
} from "@openzeppelin/contracts-upgradeable/access/extensions/AccessControlDefaultAdminRulesUpgradeable.sol";
import {EIP712Upgradeable} from "@openzeppelin/contracts-upgradeable/utils/cryptography/EIP712Upgradeable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {BtcUtils} from "@rsksmart/btc-transaction-solidity-helper/contracts/BtcUtils.sol";
import {EmergencyPause} from "./EmergencyPause/EmergencyPause.sol";
import {IBridge} from "./interfaces/IBridge.sol";
import {ICollateralManagement, CollateralManagementSet} from "./interfaces/ICollateralManagement.sol";
import {IPauseRegistry} from "./interfaces/IPauseRegistry.sol";
import {IPegOut} from "./interfaces/IPegOut.sol";
import {Flyover} from "./libraries/Flyover.sol";
import {Quotes} from "./libraries/Quotes.sol";
import {SignatureValidator} from "./libraries/SignatureValidator.sol";

/// @title PegOutContract
/// @notice This contract is used to handle the peg out of the RSK network to the Bitcoin network
/// @author Rootstock Labs
contract PegOutContract is
    AccessControlDefaultAdminRulesUpgradeable,
    EmergencyPause,
    ReentrancyGuard,
    EIP712Upgradeable,
    IPegOut
{
    /// @notice This struct is used to store the information of a peg out
    /// @param completed whether the peg out has been completed or not,
    /// completed means the peg out was paid and refunded (to any party)
    /// @param depositTimestamp the timestamp of the deposit
    /// @param depositBlock the block where the deposit was recorded
    struct PegOutRecord {
        bool completed;
        uint256 depositTimestamp;
        uint256 depositBlock;
    }

    /// @notice The version of the contract
    string constant public VERSION = "1.0.0";
    /// @notice The name of the contract (used for EIP712)
    string constant public NAME = "PegOutContract";
    Flyover.ProviderType constant private _PEG_TYPE = Flyover.ProviderType.PegOut;
    // Index of the BTC output that must pay quote.depositAddress during peg-out refund validation.
    uint256 constant private _PAY_TO_ADDRESS_OUTPUT = 0;
    // Index of the BTC output that must be OP_RETURN with the quote hash during peg-out refund validation.
    uint256 constant private _QUOTE_HASH_OUTPUT = 1;
    uint256 constant private _SAT_TO_WEI_CONVERSION = 10**10;
    uint256 constant private _QUOTE_HASH_SIZE = 32;

    IBridge private _bridge;
    ICollateralManagement private _collateralManagement;

    mapping(bytes32 => Quotes.PegOutQuote) private _pegOutQuotes;
    mapping(bytes32 => PegOutRecord) private _pegOutRegistry;
    mapping(address => uint256) private _balances;

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

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    // solhint-disable-next-line comprehensive-interface
    receive() external payable {
        revert Flyover.PaymentNotAllowed();
    }

    /// @inheritdoc IPegOut
    function depositPegOut(
        Quotes.PegOutQuote calldata quote,
        bytes calldata signature
    ) external payable nonReentrant whenNotSoftPaused override {
        if(!_collateralManagement.isRegistered(_PEG_TYPE, quote.lpRskAddress)) {
            revert Flyover.ProviderNotRegistered(quote.lpRskAddress);
        }
        uint256 requiredAmount = quote.value + quote.callFee + quote.gasFee;
        if (msg.value < requiredAmount) {
            revert Flyover.InsufficientAmount(msg.value, requiredAmount);
        }
        if (quote.depositDateLimit < block.timestamp || quote.expireDate < block.timestamp) {
            revert QuoteExpiredByTime(quote.depositDateLimit, quote.expireDate);
        }
        if (quote.expireBlock < block.number) {
            revert QuoteExpiredByBlocks(quote.expireBlock);
        }

        bytes32 eip712Hash = _hashPegOutQuoteEIP712(quote);
        if (!SignatureValidator.verify(quote.lpRskAddress, eip712Hash, signature)) {
            revert SignatureValidator.IncorrectSignature(quote.lpRskAddress, eip712Hash, signature);
        }
        bytes32 quoteHash = _hashPegOutQuote(quote);

        Quotes.PegOutQuote storage registeredQuote = _pegOutQuotes[quoteHash];

        if (_isQuoteCompleted(quoteHash)) {
            revert QuoteAlreadyCompleted(quoteHash);
        }
        if (registeredQuote.lbcAddress != address(0)) {
            revert QuoteAlreadyRegistered(quoteHash);
        }

        _pegOutQuotes[quoteHash] = quote;
        _pegOutRegistry[quoteHash].depositTimestamp = block.timestamp;
        _pegOutRegistry[quoteHash].depositBlock = block.number;

        emit PegOutDeposit(quoteHash, msg.sender, block.timestamp, msg.value);

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
    /// @param defaultAdmin the default admin of the contract
    /// @param bridge the address of the Rootstock bridge
    /// @param dustThreshold_ the dust threshold for the peg out
    /// @param collateralManagement the address of the Collateral Management contract
    /// @param mainnet whether the contract is on the mainnet or not
    /// @param btcBlockTime_ the average Bitcoin block time in seconds
    /// @param pauseRegistry the central PauseRegistry for pause state
    // solhint-disable-next-line comprehensive-interface
    function initialize(
        address defaultAdmin,
        address payable bridge,
        uint256 dustThreshold_,
        address collateralManagement,
        bool mainnet,
        uint256 btcBlockTime_,
        IPauseRegistry pauseRegistry
    ) external initializer {
        if (collateralManagement.code.length == 0) revert Flyover.NoContract(collateralManagement);
        if (address(pauseRegistry).code.length == 0) revert Flyover.NoContract(address(pauseRegistry));
        __AccessControlDefaultAdminRules_init(0, defaultAdmin);
        __EIP712_init(NAME, VERSION);
        __EmergencyPause_init(pauseRegistry);
        _bridge = IBridge(bridge);
        _collateralManagement = ICollateralManagement(collateralManagement);
        _mainnet = mainnet;
        dustThreshold = dustThreshold_;
        btcBlockTime = btcBlockTime_;
    }

    /// @notice This function is used to set the collateral management contract
    /// @param collateralManagement the address of the Collateral Management contract
    /// @dev This function is only callable by the default admin of the contract
    // solhint-disable-next-line comprehensive-interface
    function setCollateralManagement(address collateralManagement) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (collateralManagement.code.length == 0) revert Flyover.NoContract(collateralManagement);
        emit CollateralManagementSet(address(_collateralManagement), collateralManagement);
        _collateralManagement = ICollateralManagement(collateralManagement);
    }

    /// @notice This function is used to set the dust threshold
    /// @param threshold the new dust threshold
    /// @dev This function is only callable by the default admin of the contract
    // solhint-disable-next-line comprehensive-interface
    function setDustThreshold(uint256 threshold) external onlyRole(DEFAULT_ADMIN_ROLE) {
        emit DustThresholdSet(dustThreshold, threshold);
        dustThreshold = threshold;
    }

    /// @notice This function is used to set the average Bitcoin block time
    /// @param blockTime the new average Bitcoin block time in seconds
    /// @dev This function is only callable by the default admin of the contract
    // solhint-disable-next-line comprehensive-interface
    function setBtcBlockTime(uint256 blockTime) external onlyRole(DEFAULT_ADMIN_ROLE) {
        emit BtcBlockTimeSet(btcBlockTime, blockTime);
        btcBlockTime = blockTime;
    }

    /// @inheritdoc IPegOut
    function withdraw(address payable addr, uint256 amount) external nonReentrant whenNotHardPaused override {
        if (addr == address(0)) revert Flyover.InvalidAddress(addr);
        uint256 balance = _balances[msg.sender];
        if (balance < amount) {
            revert Flyover.NoBalance(amount, balance);
        }
        _decreaseBalance(msg.sender, amount);
        emit Withdrawal(msg.sender, addr, amount);
        (bool success, bytes memory reason) = addr.call{value: amount}("");
        if (!success) {
            revert Flyover.PaymentFailed(addr, amount, reason);
        }
    }

    /// @inheritdoc IPegOut
    function refundPegOut(
        bytes32 quoteHash,
        bytes calldata btcTx,
        bytes32 btcBlockHeaderHash,
        uint256 merkleBranchPath,
        bytes32[] calldata merkleBranchHashes
    ) external nonReentrant whenNotHardPaused override {
        Quotes.PegOutQuote memory quote = _validatePegOutTransaction(quoteHash, btcTx);
        _validateBtcTxConfirmations(quote, btcTx, btcBlockHeaderHash, merkleBranchPath, merkleBranchHashes);

        delete _pegOutQuotes[quoteHash];
        _pegOutRegistry[quoteHash].completed = true;
        emit PegOutRefunded(quoteHash);

        if (_shouldPenalize(quote, quoteHash, btcBlockHeaderHash)) {
            _collateralManagement.slashPegOutCollateral(msg.sender, quote, quoteHash);
        }

        uint256 refundAmount = quote.value + quote.callFee + quote.gasFee;
        (bool sent,) = quote.lpRskAddress.call{value: refundAmount}("");
        if (!sent) {
            _increaseBalance(quote.lpRskAddress, refundAmount);
        }
    }

    /// @inheritdoc IPegOut
    function refundUserPegOut(bytes32 quoteHash) external nonReentrant whenNotHardPaused override {
        Quotes.PegOutQuote memory quote = _pegOutQuotes[quoteHash];

        if (quote.lbcAddress == address(0)) revert Flyover.QuoteNotFound(quoteHash);

        uint256 depositTs = _pegOutRegistry[quoteHash].depositTimestamp;
        uint256 depositBlock = _pegOutRegistry[quoteHash].depositBlock;
        uint256 pauseOverlap = pauseRegistry().computePauseOverlap(depositTs, block.timestamp);
        // Backward-compatibility for legacy quotes predating depositBlock tracking.
        uint256 pauseBlocks = _computePauseBlocksFromDeposit(depositBlock);
        // User may refund only after effective expiration (adjusted for hard-pause overlap)
        // solhint-disable-next-line gas-strict-inequalities
        if (block.timestamp <= quote.expireDate + pauseOverlap || block.number <= quote.expireBlock + pauseBlocks) {
            revert QuoteNotExpired(quoteHash);
        }

        uint256 valueToTransfer = quote.value + quote.callFee + quote.gasFee;
        address addressToTransfer = quote.rskRefundAddress;

        delete _pegOutQuotes[quoteHash];
        _pegOutRegistry[quoteHash].completed = true;

        emit PegOutUserRefunded(quoteHash, addressToTransfer, valueToTransfer);
        _collateralManagement.slashPegOutCollateral(msg.sender, quote, quoteHash);

        (bool sent,) = addressToTransfer.call{value: valueToTransfer}("");
        if (!sent) {
            _increaseBalance(addressToTransfer, valueToTransfer);
        }
    }

    /// @inheritdoc IPegOut
    function validatePegout(
        bytes32 quoteHash,
        bytes calldata btcTx
    ) external view override returns (Quotes.PegOutQuote memory quote) {
        return _validatePegOutTransaction(quoteHash, btcTx);
    }

    /// @inheritdoc IPegOut
    function hashPegOutQuote(
        Quotes.PegOutQuote calldata quote
    ) external view override returns (bytes32) {
        return _hashPegOutQuote(quote);
    }

    /// @inheritdoc IPegOut
    function hashPegOutQuoteEIP712(
        Quotes.PegOutQuote calldata quote
    ) external view override returns (bytes32) {
        return _hashPegOutQuoteEIP712(quote);
    }

    /// @inheritdoc IPegOut
    function isQuoteCompleted(bytes32 quoteHash) external view override returns (bool) {
        return _isQuoteCompleted(quoteHash);
    }

    /// @inheritdoc IPegOut
    function getBalance(address addr) external view override returns (uint256) {
        if (_reentrancyGuardEntered()) revert ReentrancyGuardReentrantCall();
        return _balances[addr];
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

    /// @notice This function is used to hash a peg out quote
    /// @dev The function also validates the quote belongs to this contract
    /// @param quote the peg out quote to hash
    /// @return quoteHash the hash of the peg out quote
    function _hashPegOutQuote(
        Quotes.PegOutQuote calldata quote
    ) private view returns (bytes32) {
        _validatePegOutQuote(quote);
        return keccak256(Quotes.encodePegOutQuote(quote));
    }

    /// @notice This function is used to hash a peg out quote using EIP712 specification
    /// @dev The function also validates the quote belongs to this contract
    /// @param quote the peg out quote to hash
    /// @return quoteHash the hash of the peg out quote
    function _hashPegOutQuoteEIP712(Quotes.PegOutQuote calldata quote) private view returns (bytes32) {
        _validatePegOutQuote(quote);
        return _hashTypedDataV4(Quotes.hashPegOutQuoteEIP712(quote));
    }

    /// @notice This function is used to validate a peg out quote before hashing it
    /// @param quote The peg out quote to validate
    function _validatePegOutQuote(Quotes.PegOutQuote calldata quote) private view {
        if (quote.chainId != block.chainid) {
            revert Flyover.InvalidChainId(block.chainid, quote.chainId);
        }
        if (address(this) != quote.lbcAddress) {
            revert Flyover.IncorrectContract(address(this), quote.lbcAddress);
        }
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

        // penalize if the transfer was not made on time (BTC-side, no pause adjustment)
        if (firstConfirmationTimestamp > expectedConfirmationTime) {
            return true;
        }

        uint256 depositTs = _pegOutRegistry[quoteHash].depositTimestamp;
        uint256 depositBlock = _pegOutRegistry[quoteHash].depositBlock;
        uint256 pauseOverlap = pauseRegistry().computePauseOverlap(depositTs, block.timestamp);
        uint256 pauseBlocks = _computePauseBlocksFromDeposit(depositBlock);

        // penalize if LP is refunding after expiration (adjusted for hard pause)
        if (block.timestamp > quote.expireDate + pauseOverlap || block.number > quote.expireBlock + pauseBlocks) {
            return true;
        }

        return false;
    }

    function _computePauseBlocksFromDeposit(
        uint256 depositBlock
    ) private view returns (uint256 pauseBlocks) {
        if (depositBlock == 0) {
            // Legacy records created before block anchor support must not count historical pauses.
            return 0;
        }
        return pauseRegistry().computePauseOverlapBlocks(depositBlock, block.number);
    }

    /// @notice This function performs common validations for peg out transactions without checking confirmations.
    /// Used by both validatePegout (for unbroadcasted transactions) and refundPegOut (before confirmation check).
    /// The validation expects fixed output positions in btcTx:
    /// output 0 is the payment output and output 1 is the OP_RETURN quote-hash output.
    /// @param quoteHash the hash of the quote being validated
    /// @param btcTx the Bitcoin transaction
    /// @return quote the PegOutQuote associated with the transaction
    function _validatePegOutTransaction(
        bytes32 quoteHash,
        bytes calldata btcTx
    ) private view returns (Quotes.PegOutQuote memory quote) {
        if(!_collateralManagement.isRegistered(_PEG_TYPE, msg.sender)) {
            revert Flyover.ProviderNotRegistered(msg.sender);
        }
        if (_isQuoteCompleted(quoteHash)) revert QuoteAlreadyCompleted(quoteHash);

        quote = _pegOutQuotes[quoteHash];
        if (quote.lbcAddress == address(0)) revert Flyover.QuoteNotFound(quoteHash);
        if (quote.lpRskAddress != msg.sender) revert Flyover.InvalidSender(quote.lpRskAddress, msg.sender);

        BtcUtils.TxRawOutput[] memory outputs = BtcUtils.getOutputs(btcTx);
        _validateBtcTxNullData(outputs, quoteHash);
        _validateBtcTxAmount(outputs, quote);
        _validateBtcTxDestination(outputs, quote);
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
        if (paidAmount < requiredAmount) revert Flyover.InsufficientAmount(paidAmount, requiredAmount);
    }

    /// @notice This function is used to validate the null data of the Bitcoin transaction. The null data
    /// is used to store the hash of the peg out quote in the Bitcoin transaction.
    /// It reads the OP_RETURN script from output index 1 and expects:
    /// first byte == 32, followed by 32 bytes containing quoteHash.
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
