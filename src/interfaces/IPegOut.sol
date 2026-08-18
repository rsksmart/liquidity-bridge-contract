// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {IERC5267} from "@openzeppelin/contracts/interfaces/IERC5267.sol";
import {Quotes} from "../libraries/Quotes.sol";
import {IPausable} from "./IPausable.sol";

/// @title PegOut interface
/// @notice This interface is used to expose the required functions to provide the Flyover peg out service.
/// Users are expected to and are responsible for reviewing all fields of any quote before accepting or acting on it,
/// as those fields represent the terms of the service agreed with the liquidity provider (LP).
interface IPegOut is IPausable, IERC5267 {

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

    /// @notice Emitted when the balance of a liquidity provider increases
    /// @param dest The address of the liquidity provider
    /// @param amount The amount of the increase
    event BalanceIncrease(address indexed dest, uint256 indexed amount);

    /// @notice Emitted when the balance of a liquidity provider decreases
    /// @param dest The address of the liquidity provider
    /// @param amount The amount of the decrease
    event BalanceDecrease(address indexed dest, uint256 indexed amount);

    /// @notice Emitted when an account withdraws funds from the contract
    /// @param from The address making the withdrawal
    /// @param to The address receiving the withdrawal
    /// @param amount The amount of the withdrawal
    event Withdrawal(address indexed from, address indexed to, uint256 indexed amount);

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

    /// @notice This error is emitted when the terms of the quote are not fair for the contract. This includes:
    /// - The expiration blocks of the quote is more than the native peg out blocks
    /// - The expiration date of the quote is more than the native peg out seconds
    error UnfairQuote();

    /// @notice This error is emitted when the collateral is insufficient to cover the penalty fee
    /// @param amount the amount of collateral that is insufficient
    error InsufficientCollateral(uint amount);

    /// @notice LP cannot start a new claim while `block.timestamp < restrictedUntil`
    error LpRestricted(address lp, uint256 restrictedUntil);


    /// @notice This function is used to withdraw funds from the contract
    /// @dev This is usually used if some payment failed and the funds need to be returned to a different address.
    /// The amount will be subtracted from the sender's balance.
    /// @param addr The address that will receive the withdrawn funds
    /// @param amount The amount of the withdrawal
    function withdraw(address payable addr, uint256 amount) external;

    /// @notice Legacy quote path: user pays a pre-signed peg-out quote
    /// @dev Commit-first flow uses {registerClaimedPegOut} instead; this remains for existing LPS/SDK.
    /// TODO: drop this when Commit-first flow is complete.
    /// @param quote The quote that is being paid
    /// @param signature The signature of the quote hash provided by the liquidity provider after the quote acceptance
    function depositPegOut(Quotes.PegOutQuote calldata quote, bytes calldata signature) external payable;

    /// @notice Commit-first path: PegOutEscrow registers a claimed peg-out under the request hash
    /// @dev Only callable by the wired PegOutEscrow. Loads the escrow-built quote, re-verifies the LP
    /// signature, stores the same quote-shaped record as {depositPegOut} under requestHash, records
    /// claim timing, and holds the forwarded RBTC so settlement validation stays on one struct / one path.
    /// @param requestHash Escrow-minted request id
    /// @param signature LP EIP-712 signature over the escrowed quote (with lpRskAddress set)
    function registerClaimedPegOut(bytes32 requestHash, bytes calldata signature) external payable;

    /// @notice Recovers escrowed RBTC plus the LP fee against an SPV proof of the BTC payment.
    /// @dev Any caller may submit the proof (e.g. a watchtower). Payout always goes to the
    /// recorded LP (`quote.lpRskAddress`), never to `msg.sender`. Late fulfillment still
    /// completes but may slash the LP and credit the caller via the existing punisher reward.
    /// @param quoteHash hash of the quote being refunded
    /// @param btcTx the Bitcoin raw transaction without witness data. It must include
    /// the required outputs in this EXACT order
    /// (otherwise the LP risks losing its funds and getting its collateral slashed):
    /// - output 0: payment to quote.depositAddress
    /// - output 1: OP_RETURN storing the quoteHash
    /// The contract validates these outputs by fixed indices during peg-out refunds.
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
    /// this function. The user is responsible for having reviewed all quote fields when accepting the quote,
    /// as they represent the terms agreed with the LP (including refund address and expiration).
    /// @param quoteHash the hash of the quote being refunded
    function refundUserPegOut(bytes32 quoteHash) external;

    /// @notice Admin indefinite ban: `restrictedUntil = type(uint256).max`. Does not change fail count.
    function revoke(address lp) external;

    /// @notice Admin clear ban / timed freeze: `restrictedUntil = 0`. Does not change fail count.
    function unrevoke(address lp) external;

    /// @notice This view is used to get the hash of a quote, this should be used as the single source of truth so
    /// all the involved parties can compute the quote hash in the same way.
    /// Users should review all fields of the quote before relying on its hash, as those fields are the terms agreed
    /// with the LP.
    /// @param quote the quote to hash
    function hashPegOutQuote(Quotes.PegOutQuote calldata quote) external view returns (bytes32);

    /// @notice This view is used to get the hash of a peg out quote using EIP712 specification.
    /// The user is expected to review all quote fields before signing or accepting, as they
    /// represent the terms agreed with the LP.
    /// @param quote The quote of the peg out
    /// @return hashStruct The hash struct to be combined with the domain separator
    function hashPegOutQuoteEIP712(Quotes.PegOutQuote calldata quote) external view returns (bytes32);

    /// @notice This view is used to check if a quote has been completed. Completed means it was paid and refunded
    /// doesn't matter if the refund was to the liquidity provider (success) or to the user (failure)
    /// @param quoteHash the hash of the quote to check
    function isQuoteCompleted(bytes32 quoteHash) external view returns (bool);

    /// @notice Validates a Bitcoin transaction for a peg-out refund without checking confirmations.
    /// @dev Same checks as {refundPegOut} except confirmations. Any caller may preflight
    /// (including a third party); does not move funds.
    /// @param quoteHash hash of the quote being validated
    /// @param btcTx the bitcoin raw transaction without the witness (does not need to be broadcasted yet)
    /// @return quote the PegOutQuote associated with the validated transaction
    function validatePegout(bytes32 quoteHash, bytes calldata btcTx)
        external
        view
        returns (Quotes.PegOutQuote memory quote);

    /// @notice This function is used to get the balance of an address
    /// @param addr The address to get the balance of
    /// @return balance The balance of the address
    function getBalance(address addr) external view returns (uint256);

    /// @notice Dust threshold for overpayment change refunds (wei)
    /// @dev Used by depositPegOut and by PegOutEscrow request-time change handling.
    function dustThreshold() external view returns (uint256);

    /// @notice Number of claim-fail bumps for `lp` (used as exponent `n` in freeze length)
    function claimFailCount(address lp) external view returns (uint256);

    /// @notice Timestamp until which `lp` cannot call {claimPegOut} (`0` ⇒ not frozen)
    function restrictedUntil(address lp) external view returns (uint256);
}
