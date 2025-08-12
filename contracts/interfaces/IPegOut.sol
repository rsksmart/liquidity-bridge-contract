// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Quotes} from "../libraries/Quotes.sol";

/// @title PegOut interface
/// @notice This interface is used to expose the required functions to provide the Flyover peg out service
interface IPegOut {

    /// @notice Emitted when a peg out is refunded to the liquidity
    /// provider after successfully providing the service
    /// @param quoteHash hash of the refunded quote
    event PegOutRefunded(bytes32 indexed quoteHash);

    /// @notice Emitted when a peg out is refunded to the user because
    /// the liquidity provider failed to provide the service
    /// @param quoteHash hash of the refunded quote
    /// @param userAddress address of the refunded user
    /// @param value refunded amount
    event PegOutUserRefunded(
        bytes32 indexed quoteHash,
        address indexed userAddress,
        uint256 indexed value
    );

    /// @notice Emitted when a user overpays a peg out quote and the excess is bigger
    /// than the dust threshold so its returned to the user
    /// @param quoteHash hash of the paid quote
    /// @param userAddress address of the user who is receiving the change
    /// @param change the change amount
    event PegOutChangePaid(
        bytes32 indexed quoteHash,
        address indexed userAddress,
        uint256 indexed change
    );

    /// Emitted when a peg out quote is paid
    /// @param quoteHash hash of the paid quote
    /// @param sender the payer of the quote
    /// @param timestamp timestamp of the block where the quote was paid
    /// @param amount the value of the deposit transaction
    event PegOutDeposit(
        bytes32 indexed quoteHash,
        address indexed sender,
        uint256 indexed timestamp,
        uint256 amount
    );

    /// @notice This error is emitted when the quote has expired by the number of blocks
    /// @param expireBlock the number of blocks the quote has expired
    error QuoteExpiredByBlocks(uint32 expireBlock);

    /// @notice This error is emitted when the quote has expired by the time
    /// @param depositDateLimit the date limit for the user to deposit
    /// @param expireDate the expiration of the quote
    error QuoteExpiredByTime(uint32 depositDateLimit, uint32 expireDate);

    /// @notice This error is emitted when the quote has already been completed
    /// @param quoteHash the hash of the quote that has already been completed
    error QuoteAlreadyCompleted(bytes32 quoteHash);

    /// @notice This error is emitted when the quote has already been registered
    /// @param quoteHash the hash of the quote that has already been registered
    error QuoteAlreadyRegistered(bytes32 quoteHash);

    /// @notice This error is emitted when one of the output scripts of the Bitcoin
    /// peg out transaction is malformed
    /// @param outputScript the output script that is malformed
    error MalformedTransaction(bytes outputScript);

    /// @notice This error is emitted when the destination of the Bitcoin transaction is invalid
    /// @param expected the expected destination
    /// @param actual the actual destination
    error InvalidDestination(bytes expected, bytes actual);

    /// @notice This error is emitted when the quote hash is invalid
    /// @param expected the expected quote hash
    /// @param actual the actual quote hash
    error InvalidQuoteHash(bytes32 expected, bytes32 actual);

    /// @notice This error is emitted when the get confirmations from the rootstock bridge fails
    /// @param errorCode The error code returned by the rootstock bridge
    error UnableToGetConfirmations(int errorCode);

    /// @notice This error is emitted when the number of confirmations of the Bitcoin transaction is not enough
    /// @param required the required number of confirmations
    /// @param current the current number of confirmations
    error NotEnoughConfirmations(int required, int current);

    /// @notice This error is emitted when the quote is not expired yet
    /// @param quoteHash the hash of the quote that is not expired
    error QuoteNotExpired(bytes32 quoteHash);

    /// @notice This is the function used to pay for a peg out quote. This is the only correct function to execute
    /// such payment, sending money directly to the contract does not work
    /// @param quote The quote that is being paid
    /// @param signature The signature of the quote hash provided by the liquidity provider after the quote acceptance
    function depositPegOut(Quotes.PegOutQuote calldata quote, bytes calldata signature) external payable;

    /// @notice This function is used by the liquidity provider to recover the funds spent on the peg out service plus
    /// their fee for the service. It proves the inclusion of the transaction paying to the user in the Bitcoin network
    /// @param quoteHash hash of the quote being refunded
    /// @param btcTx the bitcoin raw transaction without the witness
    /// @param btcBlockHeaderHash header hash of the block where the transaction was included
    /// @param merkleBranchPath index of the leaf that is being proved to be included in the merkle tree
    /// @param merkleBranchHashes hashes of the merkle branch to get to the merkle root using the leaf being proved
    function refundPegOut(
        bytes32 quoteHash,
        bytes calldata btcTx,
        bytes32 btcBlockHeaderHash,
        uint256 merkleBranchPath,
        bytes32[] calldata merkleBranchHashes
    ) external;

    /// @notice This function must be used by the user to recover the funds if the liquidity provider
    /// fails to provide the service. The user needs to wait for the quote to expire before calling
    /// this function
    /// @param quoteHash the hash of the quote being refunded
    function refundUserPegOut(bytes32 quoteHash) external;

    /// @notice This view is used to get the hash of a quote, this should be used as the single source of truth so
    /// all the involved parties can compute the quote hash in the same way
    /// @param quote the quote to hash
    function hashPegOutQuote(Quotes.PegOutQuote calldata quote) external view returns (bytes32);

    /// @notice This view is used to check if a quote has been completed. Completed means it was paid and refunded
    /// doesn't matter if the refund was to the liquidity provider (success) or to the user (failure)
    /// @param quoteHash the hash of the quote to check
    function isQuoteCompleted(bytes32 quoteHash) external view returns (bool);
}
