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

    /// @notice Registers the caller as a Liquidity Provider
    /// @dev Reverts if caller is not an EOA, already resigned, provides invalid data, invalid type, or lacks collateral
    /// @param name Human-readable LP name
    /// @param apiBaseUrl Base URL of the LP public API
    /// @param status Initial status flag (enabled/disabled)
    /// @param providerType The service type(s) the LP offers
    /// @return id The newly assigned LP identifier
    function register(
        string calldata name,
        string calldata apiBaseUrl,
        bool status,
        Flyover.ProviderType providerType
    ) external payable returns (uint);

    /// @notice Updates the caller LP metadata
    /// @dev Reverts if the caller is not registered or provides invalid fields
    /// @param name New LP name
    /// @param apiBaseUrl New LP API base URL
    function updateProvider(string calldata name, string calldata apiBaseUrl) external;

    /// @notice Updates a provider status flag
    /// @dev Callable by the LP itself or the contract owner
    /// @param providerId The provider identifier
    /// @param status The new status value
    function setProviderStatus(uint providerId, bool status) external;

    /// @notice Lists LPs that should be visible to users
    /// @dev A provider is listed if it has sufficient collateral for at least one side and `status` is true
    /// @return providersToReturn Array of LP records to display
    function getProviders() external view returns (Flyover.LiquidityProvider[] memory);

    /// @notice Returns a single LP by address
    /// @param providerAddress The LP address
    /// @return provider LP record, reverts if not found
    function getProvider(address providerAddress) external view returns (Flyover.LiquidityProvider memory);

    /// @notice Checks if an LP can operate for peg-in side
    /// @dev Ignores the first argument as compatibility stub with legacy signature
    /// @param providerType The provider type (ignored for compatibility)
    /// @param addr The LP address
    /// @return isOp True if registered and peg-in collateral >= min
    function isOperational(Flyover.ProviderType providerType, address addr) external view returns (bool);

    /// @notice Returns the last assigned provider id
    /// @return lastId Last provider id
    function getProvidersId() external view returns (uint);
}
