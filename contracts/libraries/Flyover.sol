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
    error InvalidBlockHeader(bytes header);
    error NoBalance(uint256 wanted, uint256 actual);
}
