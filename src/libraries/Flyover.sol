// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

library Flyover {
    /// @notice 1 satoshi expressed in wei — the scale every BTC amount crosses when it becomes an
    /// RBTC amount.
    /// @dev The single declaration of the scale for the commit-first path: {PegInContract} converts
    /// a deposit with it, {FlyoverConfigurations} rounds fees to it. It lives in a library, and not
    /// on the contract that owns the amount policy, because Solidity cannot reference a contract's
    /// public constant by type name — doing so needs an external call.
    uint256 internal constant SAT_TO_WEI_CONVERSION = 10 ** 10;

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
    error InvalidAddress(address addr);
    /// @notice Quote was created for a different chain
    /// @param expected The current chain id (block.chainid)
    /// @param actual The chain id in the quote
    error InvalidChainId(uint256 expected, uint256 actual);
    /// @notice Used by whenNotSoftPaused or whenNotHardPaused when the system is paused via PauseRegistry
    error EnforcedPause();
}
