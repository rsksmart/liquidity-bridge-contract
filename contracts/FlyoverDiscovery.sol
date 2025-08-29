// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

/* solhint-disable comprehensive-interface */

import {
    AccessControlDefaultAdminRulesUpgradeable
} from "@openzeppelin/contracts-upgradeable/access/extensions/AccessControlDefaultAdminRulesUpgradeable.sol";
import {ICollateralManagement} from "./interfaces/ICollateralManagement.sol";
import {IFlyoverDiscovery} from "./interfaces/IFlyoverDiscovery.sol";
import {Flyover} from "./libraries/Flyover.sol";

/// @title FlyoverDiscovery
/// @notice Registry and discovery of Liquidity Providers (LPs) for Flyover
/// @dev Keeps LP metadata and consults `ICollateralManagement` to decide listing and operational status
contract FlyoverDiscovery is
    AccessControlDefaultAdminRulesUpgradeable,
    IFlyoverDiscovery
{

    // ------------------------------------------------------------
    // FlyoverDiscovery State Variables
    // ------------------------------------------------------------

    mapping(uint => Flyover.LiquidityProvider) private _liquidityProviders;
    ICollateralManagement private _collateralManagement;
    uint public lastProviderId;

    // ------------------------------------------------------------
    // FlyoverDiscovery Public Functions and Modifiers
    // ------------------------------------------------------------

    /// @notice Initializes the contract with admin configuration
    /// @dev Uses OZ upgradeable admin rules. Must be called only once
    /// @param owner The Default Admin and initial owner address
    /// @param initialDelay The initial admin delay for `AccessControlDefaultAdminRulesUpgradeable`
    /// @param collateralManagement The address of the `ICollateralManagement` contract
    function initialize(
        address owner,
        uint48 initialDelay,
        address collateralManagement
    ) external initializer {
        __AccessControlDefaultAdminRules_init(initialDelay, owner);
        _collateralManagement = ICollateralManagement(collateralManagement);
    }

    /// @inheritdoc IFlyoverDiscovery
    function register(
        string calldata name,
        string calldata apiBaseUrl,
        bool status,
        Flyover.ProviderType providerType
    ) external payable returns (uint) {

       _validateRegistration(name, apiBaseUrl, providerType, msg.sender, msg.value);

        ++lastProviderId;
        _liquidityProviders[lastProviderId] = Flyover.LiquidityProvider({
            id: lastProviderId,
            providerAddress: msg.sender,
            name: name,
            apiBaseUrl: apiBaseUrl,
            status: status,
            providerType: providerType
        });
        _addCollateral(providerType, msg.sender, msg.value);
        emit Register(lastProviderId, msg.sender, msg.value);
        return (lastProviderId);
    }

    /// @inheritdoc IFlyoverDiscovery
    function setProviderStatus(
        uint providerId,
        bool status
    ) external {
        if (msg.sender != owner() && msg.sender != _liquidityProviders[providerId].providerAddress) {
            revert NotAuthorized(msg.sender);
        }
        _liquidityProviders[providerId].status = status;
        emit IFlyoverDiscovery.ProviderStatusSet(providerId, status);
    }

    /// @inheritdoc IFlyoverDiscovery
    function updateProvider(string calldata name, string calldata apiBaseUrl) external {
        if (bytes(name).length < 1 || bytes(apiBaseUrl).length < 1) revert InvalidProviderData(name, apiBaseUrl);
        Flyover.LiquidityProvider storage lp;
        address providerAddress = msg.sender;
        for (uint i = 1; i < lastProviderId + 1; ++i) {
            lp = _liquidityProviders[i];
            if (providerAddress == lp.providerAddress) {
                lp.name = name;
                lp.apiBaseUrl = apiBaseUrl;
                emit IFlyoverDiscovery.ProviderUpdate(providerAddress, lp.name, lp.apiBaseUrl);
                return;
            }
        }
        revert Flyover.ProviderNotRegistered(providerAddress);
    }

    /// @inheritdoc IFlyoverDiscovery
    function getProviders() external view returns (Flyover.LiquidityProvider[] memory) {
        uint count = 0;
        Flyover.LiquidityProvider storage lp;
        for (uint i = 1; i < lastProviderId + 1; ++i) {
            if (_shouldBeListed(_liquidityProviders[i])) {
                ++count;
            }
        }
        Flyover.LiquidityProvider[] memory providersToReturn = new Flyover.LiquidityProvider[](count);
        count = 0;
        for (uint i = 1; i < lastProviderId + 1; ++i) {
            lp = _liquidityProviders[i];
            if (_shouldBeListed(lp)) {
                providersToReturn[count] = lp;
                ++count;
            }
        }
        return providersToReturn;
    }

    /// @inheritdoc IFlyoverDiscovery
    function getProvider(address providerAddress) external view returns (Flyover.LiquidityProvider memory) {
        return _getProvider(providerAddress);
    }

    /// @inheritdoc IFlyoverDiscovery
    function isOperational(Flyover.ProviderType, address addr) external view returns (bool) {
        return _collateralManagement.isCollateralSufficient(Flyover.ProviderType.PegIn, addr) &&
            _getProvider(addr).status;
    }

    // ------------------------------------------------------------
    // Getter Functions
    // ------------------------------------------------------------

    /// @inheritdoc IFlyoverDiscovery
    function getProvidersId() external view returns (uint) {
        return lastProviderId;
    }

    // ------------------------------------------------------------
    // FlyoverDiscovery Private Functions
    // ------------------------------------------------------------

    /// @notice Adds collateral to the collateral management contract based on provider type
    /// @dev Distributes collateral between peg-in and peg-out based on provider type
    /// @param providerType The type of provider (PegIn, PegOut, or Both)
    /// @param providerAddress The address of the provider
    /// @param collateralAmount The total amount of collateral to add
    function _addCollateral(
        Flyover.ProviderType providerType,
        address providerAddress,
        uint256 collateralAmount
    ) private {
        if (providerType == Flyover.ProviderType.PegIn) {
            _collateralManagement.addPegInCollateralTo{value: collateralAmount}(providerAddress);
        } else if (providerType == Flyover.ProviderType.PegOut) {
            _collateralManagement.addPegOutCollateralTo{value: collateralAmount}(providerAddress);
        } else if (providerType == Flyover.ProviderType.Both) {
            uint256 halfAmount = collateralAmount / 2;
            uint256 remainder = collateralAmount % 2;
            _collateralManagement.addPegInCollateralTo{value: halfAmount + remainder}(providerAddress);
            _collateralManagement.addPegOutCollateralTo{value: halfAmount}(providerAddress);
        }
    }

    /// @notice Checks if a liquidity provider should be listed in the public provider list
    /// @dev A provider is listed if it is registered and has status enabled
    /// @param lp The liquidity provider storage reference
    /// @return True if the provider should be listed, false otherwise
    function _shouldBeListed(Flyover.LiquidityProvider storage lp) private view returns(bool){
        return _collateralManagement.isRegistered(lp.providerType, lp.providerAddress) && lp.status;
    }

    /// @notice Validates registration parameters and requirements
    /// @dev Checks EOA status, data validity, provider type, registration status, and collateral requirements
    /// @param name The provider name to validate
    /// @param apiBaseUrl The provider API URL to validate
    /// @param providerType The provider type to validate
    /// @param providerAddress The provider address to validate
    /// @param collateralAmount The collateral amount to validate against minimum requirements
    function _validateRegistration(
        string memory name,
        string memory apiBaseUrl,
        Flyover.ProviderType providerType,
        address providerAddress,
        uint256 collateralAmount
    ) private view {
        if (providerAddress != msg.sender || providerAddress.code.length != 0) revert NotEOA(providerAddress);

        if (
            bytes(name).length < 1 ||
            bytes(apiBaseUrl).length < 1
        ) {
            revert InvalidProviderData(name, apiBaseUrl);
        }

        if (providerType > type(Flyover.ProviderType).max) revert InvalidProviderType(providerType);

        if (
            _collateralManagement.getPegInCollateral(providerAddress) > 0 ||
            _collateralManagement.getPegOutCollateral(providerAddress) > 0 ||
            _collateralManagement.getResignationBlock(providerAddress) != 0
        ) {
            revert AlreadyRegistered(providerAddress);
        }

        // Check minimum collateral requirement
        uint256 minCollateral = _collateralManagement.getMinCollateral();
        if (providerType == Flyover.ProviderType.Both) {
            if (collateralAmount < minCollateral * 2) {
                revert InsufficientCollateral(collateralAmount);
            }
        } else {
            if (collateralAmount < minCollateral) {
                revert InsufficientCollateral(collateralAmount);
            }
        }
    }

    /// @notice Retrieves a liquidity provider by address
    /// @dev Searches through all registered providers to find a match
    /// @param providerAddress The address of the provider to find
    /// @return The liquidity provider record, reverts if not found
    function _getProvider(address providerAddress) private view returns (Flyover.LiquidityProvider memory) {
        for (uint i = 1; i < lastProviderId + 1; ++i) {
            if (_liquidityProviders[i].providerAddress == providerAddress) {
                return _liquidityProviders[i];
            }
        }
        revert Flyover.ProviderNotRegistered(providerAddress);
    }
}
