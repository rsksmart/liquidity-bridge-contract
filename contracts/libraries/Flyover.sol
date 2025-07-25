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
}
