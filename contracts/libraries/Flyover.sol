// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

library Flyover {
    enum ProviderType { PegIn, PegOut, Both }

    struct LiquidityProvider {
        uint id;
        address providerAddress;
        bool status;
        ProviderType providerType;
        string name;
        string apiBaseUrl;
    }

    error ProviderNotRegistered(address from);
    error IncorrectContract(address expected, address actual);
    error QuoteNotFound(bytes32 quoteHash);
    error PaymentFailed(address addr, uint amount, bytes reason);
    error EmptyBlockHeader(bytes32 heightOrHash);
    error NoBalance(uint256 wanted, uint256 actual);
    error NoContract(address addr);
    error PaymentNotAllowed();
    /// @notice This error is emitted when the sender is not allowed to perform a specific operation
    /// @param expected the expected sender
    /// @param actual the actual sender
    error InvalidSender(address expected, address actual);
    /// @notice This error is emitted when the amount sent is less than the amount required to pay for the quote
    /// @param amount the amount sent
    /// @param target the amount required to pay for the quote
    error InsufficientAmount(uint256 amount, uint256 target);
    error Overflow(uint256 passedAmount);
}
