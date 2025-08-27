// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Flyover} from "../libraries/Flyover.sol";

interface IFlyoverDiscovery {
    event Register(uint indexed id, address indexed from, uint256 indexed amount);
    event ProviderUpdate(address indexed from, string name, string apiBaseUrl);
    event ProviderStatusSet(uint indexed id, bool indexed status);
    event Resigned(address indexed addr);

    error NotAuthorized(address from);
    error NotEOA(address from);
    error InvalidProviderData(string name, string apiBaseUrl);
    error InvalidProviderType(Flyover.ProviderType providerType);
    error AlreadyRegistered(address from);
    error InsufficientCollateral(uint amount);
    error AlreadyResigned(address from);

    function register(
        string calldata name,
        string calldata apiBaseUrl,
        bool status,
        Flyover.ProviderType providerType
    ) external payable returns (uint);

    function updateProvider(string calldata name, string calldata apiBaseUrl) external;
    function setProviderStatus(uint providerId, bool status) external;
    function setMinCollateral(uint minCollateral) external;
    function resign() external;

    function getProviders() external view returns (Flyover.LiquidityProvider[] memory);
    function getProvider(address providerAddress) external view returns (Flyover.LiquidityProvider memory);
    function isOperational(Flyover.ProviderType providerType, address addr) external view returns (bool);
    function isOperationalForPegout(address addr) external view returns (bool);

    function getMinCollateral() external view returns (uint256);
    function getProvidersId() external view returns (uint);
    function getResignationBlockNum(address addr) external view returns (uint256);
}
