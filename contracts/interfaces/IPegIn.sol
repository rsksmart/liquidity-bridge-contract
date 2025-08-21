// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Quotes} from "../libraries/Quotes.sol";

/// @title PegIn interface
/// @notice This interface is used to expose the required functions to provide the Flyover peg in service
interface IPegIn {

    /// @notice The states of a peg in quote
    /// @dev The quote set to CALL_DONE when the callForUser function is called
    /// @dev The quote set to PROCESSED_QUOTE when the registerPegIn function is called
    /// @dev The quote set to UNPROCESSED_QUOTE when the the contract is not aware of the quote
    enum PegInStates { UNPROCESSED_QUOTE, CALL_DONE, PROCESSED_QUOTE }

    /// @notice Emitted when the balance of a liquidity provider increases
    /// @param dest The address of the liquidity provider
    /// @param amount The amount of the increase
    event BalanceIncrease(address indexed dest, uint256 indexed amount);

    /// @notice Emitted when the balance of a liquidity provider decreases
    /// @param dest The address of the liquidity provider
    /// @param amount The amount of the decrease
    event BalanceDecrease(address indexed dest, uint256 indexed amount);

    /// @notice Emitted when a liquidity provider withdraws funds
    /// @param from The address of the liquidity provider
    /// @param amount The amount of the withdrawal
    event Withdrawal(address indexed from, uint256 indexed amount);

    /// @notice Emitted when the bridge capacity is exceeded
    /// @param quoteHash The hash of the quote
    /// @param errorCode The error code returned by the bridge
    event BridgeCapExceeded(bytes32 indexed quoteHash, int256 indexed errorCode);

    /// @notice Emitted when a peg in is registered successfully
    /// @param quoteHash The hash of the quote
    /// @param transferredAmount The amount of the peg in
    event PegInRegistered(bytes32 indexed quoteHash, uint256 indexed transferredAmount);

    /// @notice Emitted when a user is refunded. This can happen if the liquidity provider
    /// fails to provide the service, if the user's payment was invalid, if the user requires
    /// to receive the change of their payment
    /// @param dest The address of the user
    /// @param quoteHash The hash of the quote
    /// @param amount The amount of the refund
    /// @param success Whether the refund was successful or not
    event Refund(address indexed dest, bytes32 indexed quoteHash, uint indexed amount, bool success);

    /// @notice Emitted when a call is made on behalf of the user
    /// @param from The address of the caller
    /// @param dest The address of the destination
    /// @param quoteHash The hash of the quote
    /// @param gasLimit The gas limit of the call
    /// @param value The value of the call
    /// @param data The data of the call
    /// @param success Whether the call was successful or not
    event CallForUser(
        address indexed from,
        address indexed dest,
        bytes32 indexed quoteHash,
        uint gasLimit,
        uint value,
        bytes data,
        bool success
    );

    /// @notice This error is emitted when the refund address is invalid
    /// @param refundAddress The refund address that is invalid
    error InvalidRefundAddress(bytes refundAddress);

    /// @notice This error is emitted when the amount is under the bridge's minimum amount
    /// @param amount The amount that is under the bridge's minimum
    error AmountUnderMinimum(uint256 amount);

    /// @notice This error is emitted when the quote has already been processed.
    /// This can happen if the callForUser or the registerPegIn functions are being
    /// called twice with the same quote
    /// @param quoteHash The hash of the quote
    error QuoteAlreadyProcessed(bytes32 quoteHash);

    /// @notice This error is emitted when the gas limit is insufficient to make the call
    /// on behalf of the user
    /// @param gasLeft The amount of gas left
    /// @param gasRequired The amount of gas required
    error InsufficientGas(uint256 gasLeft, uint256 gasRequired);

    /// @notice This error is emitted when the bridge needs more confirmations in order to
    /// be capable of registering the peg in
    error NotEnoughConfirmations();

    /// @notice This error is emitted when the bridge returns an unexpected error code
    /// @param errorCode The error code returned by the bridge
    error UnexpectedBridgeError(int256 errorCode);

    /// @notice This function is used to deposit funds into the contract to provide the
    /// peg in service
    /// @dev This function is only callable by a liquidity provider
    function deposit() external payable;

    /// @notice This function is used to make a peg in call on behalf of the user
    /// @dev This function is only callable by a liquidity provider. The value of the call
    /// will be added to the liquidity provider's balance.
    /// @param quote The quote of the peg in
    /// @return success Whether the call was successful or not
    function callForUser(Quotes.PegInQuote calldata quote) external payable returns (bool);

    /// @notice This function is used to withdraw funds from the contract
    /// @dev This function is only callable by a liquidity provider. They can partially
    /// withdraw their balance, this includes the profit made with the peg in service.
    /// @param amount The amount of the withdrawal
    function withdraw(uint256 amount) external;

    /// @notice This function is used to register a peg in in the bridge.
    /// It refunds the proper parties and penalizes the liquidity provider
    /// if applicable.
    /// @dev This function can be called by anyone
    /// @param quote The quote of the peg in
    /// @param signature The signature of the quoteHash by the liquidity provider
    /// @param btcRawTransaction The raw transaction of the peg in in the Bitcoin network
    /// @param partialMerkleTree The partial merkle tree proving the inclusion of the peg
    /// in transaction
    /// @param height The height of the peg in transaction
    /// @return registerResult The result of the registration. It can be:
    /// - A negative value: An error code returned by the bridge
    /// - A positive value: The amount of the peg in transaction
    function registerPegIn(
        Quotes.PegInQuote calldata quote,
        bytes calldata signature,
        bytes calldata btcRawTransaction,
        bytes calldata partialMerkleTree,
        uint256 height
    ) external returns (int256);

    /// @notice This function is used to get the balance of a liquidity provider
    /// @param addr The address of the liquidity provider
    /// @return balance The balance of the liquidity provider
    function getBalance(address addr) external view returns (uint256);

    /// @notice This function is used to get the status of a peg in quote
    /// @param quoteHash The hash of the quote
    /// @return status The status of the quote. Any value of the PegInStates enum
    function getQuoteStatus(bytes32 quoteHash) external view returns (PegInStates);

    /// @notice This function is used to validate the deposit address of a peg in quote
    /// @dev This function is used to validate the derivation address returned by the
    /// liquidity provider.
    /// @param quote The quote of the peg in
    /// @param depositAddress The deposit address to validate
    /// @return isValid Whether the deposit address is valid or not
    function validatePegInDepositAddress(
        Quotes.PegInQuote calldata quote,
        bytes calldata depositAddress
    ) external view returns (bool);

    /// @notice This view is used to get the hash of a peg in quote, this should be used as the
    /// single source of truth so all the involved parties can compute the quote hash in the same way
    /// @param quote The quote of the peg in
    /// @return quoteHash The hash of the quote
    function hashPegInQuote(Quotes.PegInQuote calldata quote) external view returns (bytes32);
}
