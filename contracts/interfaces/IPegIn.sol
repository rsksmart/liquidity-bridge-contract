// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Quotes} from "../libraries/Quotes.sol";

interface IPegIn {
    enum PegInStates { UNPROCESSED_QUOTE, CALL_DONE, PROCESSED_QUOTE }

    event BalanceIncrease(address indexed dest, uint256 indexed amount);
    event BalanceDecrease(address indexed dest, uint256 indexed amount);
    event Withdrawal(address indexed from, uint256 indexed amount);
    event BridgeCapExceeded(bytes32 indexed quoteHash, int256 indexed errorCode);
    event PegInRegistered(bytes32 indexed quoteHash, uint256 indexed transferredAmount);
    event Refund(address indexed dest, bytes32 indexed quoteHash, uint indexed amount, bool success);
    event CallForUser(
        address indexed from,
        address indexed dest,
        bytes32 indexed quoteHash,
        uint gasLimit,
        uint value,
        bytes data,
        bool success
    );

    error InvalidRefundAddress(bytes refundAddress);
    error AmountUnderMinimum(uint256 amount);
    error QuoteAlreadyProcessed(bytes32 quoteHash);
    error InsufficientGas(uint256 gasLeft, uint256 gasRequired);
    error NotEnoughConfirmations();
    error UnexpectedBridgeError(int256 errorCode);

    function deposit() external payable;
    function callForUser(Quotes.PegInQuote calldata quote) external payable returns (bool);
    function withdraw(uint256 amount) external;
    function registerPegIn(
        Quotes.PegInQuote calldata quote,
        bytes calldata signature,
        bytes calldata btcRawTransaction,
        bytes calldata partialMerkleTree,
        uint256 height
    ) external returns (int256);
    function getBalance(address addr) external view returns (uint256);
    function getQuoteStatus(bytes32 quoteHash) external view returns (PegInStates);
    function validatePegInDepositAddress(
        Quotes.PegInQuote calldata quote,
        bytes calldata depositAddress
    ) external view returns (bool);
    function hashPegInQuote(Quotes.PegInQuote calldata quote) external view returns (bytes32);
}
