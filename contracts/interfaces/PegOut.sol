// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Quotes} from "../libraries/Quotes.sol";

interface IPegOut {
    event PegOutRefunded(bytes32 indexed quoteHash);
    event PegOutUserRefunded(
        bytes32 indexed quoteHash,
        address indexed userAddress,
        uint256 indexed value
    );
    event PegOutChangePaid(
        bytes32 indexed quoteHash,
        address indexed userAddress,
        uint256 indexed change
    );
    event PegOutDeposit(
        bytes32 indexed quoteHash,
        address indexed sender,
        uint256 indexed timestamp,
        uint256 amount
    );

    error InsufficientAmount(uint256 amount, uint256 target);
    error QuoteExpiredByBlocks(uint32 expireBlock);
    error QuoteExpiredByTime(uint32 depositDateLimit, uint32 expireDate);
    error QuoteAlreadyCompleted(bytes32 quoteHash);
    error QuoteAlreadyRegistered(bytes32 quoteHash);
    error MalformedTransaction(bytes outputScript);
    error InvalidDestination(bytes expected, bytes actual);
    error InvalidQuoteHash(bytes32 expected, bytes32 actual);
    error InvalidSender(address expected, address actual);
    error UnableToGetConfirmations(int errorCode);
    error NotEnoughConfirmations(int required, int current);
    error QuoteNotExpired(bytes32 quoteHash);

    function depositPegOut(Quotes.PegOutQuote calldata quote, bytes calldata signature) external payable;

    function refundPegOut(
        bytes32 quoteHash,
        bytes calldata btcTx,
        bytes32 btcBlockHeaderHash,
        uint256 partialMerkleTree,
        bytes32[] calldata merkleBranchHashes
    ) external;

    function refundUserPegOut(bytes32 quoteHash) external;

    function hashPegOutQuote(Quotes.PegOutQuote calldata quote) external view returns (bytes32);

    function isQuoteCompleted(bytes32 quoteHash) external view returns (bool);
}
