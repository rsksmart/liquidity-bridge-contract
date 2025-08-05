// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Flyover} from "../libraries/Flyover.sol";

interface IFlyoverDiscovery {
    event Register(uint indexed id, address indexed from, uint256 indexed amount);
    event ProviderUpdate(address indexed from, string name, string apiBaseUrl);
    event ProviderStatusSet(uint indexed id, bool indexed status);

    error NotAuthorized(address from);
    error NotEOA(address from);
    error InvalidProviderData(string name, string apiBaseUrl);
    error InvalidProviderType(Flyover.ProviderType providerType);
    error AlreadyRegistered(address from);
    error InsufficientCollateral(uint amount);

    function register(
        string memory name,
        string memory apiBaseUrl,
        bool status,
        Flyover.ProviderType providerType
    ) external payable returns (uint);

    function updateProvider(string memory name,string memory apiBaseUrl) external;
    function setProviderStatus(uint providerId, bool status) external;
    function getProviders() external view returns (Flyover.LiquidityProvider[] memory);
    function getProvider(address providerAddress) external view returns (Flyover.LiquidityProvider memory);
    function isOperational(Flyover.ProviderType providerType, address addr) external view returns (bool);
}
