// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

/* solhint-disable comprehensive-interface */

import {
    AccessControlDefaultAdminRulesUpgradeable
} from "@openzeppelin/contracts-upgradeable/access/extensions/AccessControlDefaultAdminRulesUpgradeable.sol";
import {EmergencyPause} from "./EmergencyPause/EmergencyPause.sol";
import {ICollateralManagement} from "./interfaces/ICollateralManagement.sol";
import {IFlyoverDiscovery} from "./interfaces/IFlyoverDiscovery.sol";
import {IPauseRegistry} from "./interfaces/IPauseRegistry.sol";
import {Flyover} from "./libraries/Flyover.sol";

/// @title FlyoverDiscovery
/// @notice Registry and discovery of Liquidity Providers (LPs) for Flyover
/// @dev Keeps LP metadata and consults `ICollateralManagement` to decide listing and operational status
contract FlyoverDiscovery is
    AccessControlDefaultAdminRulesUpgradeable,
    EmergencyPause,
    IFlyoverDiscovery
{
    /// @notice The version of the contract
    string constant public VERSION = "1.0.0";
    uint256 constant private _MAX_PROVIDER_NAME_LENGTH = 256;
    uint256 constant private _MAX_PROVIDER_API_BASE_URL_LENGTH = 512;

    // ------------------------------------------------------------
    // FlyoverDiscovery State Variables
    // ------------------------------------------------------------

    mapping(uint => Flyover.LiquidityProvider) private _liquidityProviders;
    mapping(address => uint) private _providerIdByAddress;
    ICollateralManagement private _collateralManagement;
    uint public lastProviderId;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    // ------------------------------------------------------------
    // FlyoverDiscovery Public Functions and Modifiers
    // ------------------------------------------------------------

    /// @notice Initializes the contract with admin configuration
    /// @dev Uses OZ upgradeable admin rules. Must be called only once
    /// @param defaultAdmin The Default Admin and initial owner address
    /// @param initialDelay The initial admin delay for `EmergencyPause`
    /// @param collateralManagement The address of the `ICollateralManagement` contract
    /// @param pauseRegistry The central PauseRegistry for pause state
    function initialize(
        address defaultAdmin,
        uint48 initialDelay,
        address collateralManagement,
        IPauseRegistry pauseRegistry
    ) external initializer {
        if (collateralManagement.code.length == 0) revert Flyover.NoContract(collateralManagement);
        if (address(pauseRegistry).code.length == 0) revert Flyover.NoContract(address(pauseRegistry));
        __AccessControlDefaultAdminRules_init(initialDelay, defaultAdmin);
        __EmergencyPause_init(pauseRegistry);
        _collateralManagement = ICollateralManagement(collateralManagement);
    }

    /// @inheritdoc IFlyoverDiscovery
    function register(
        string calldata name,
        string calldata apiBaseUrl,
        bool status,
        Flyover.ProviderType providerType
    ) external payable whenNotPaused returns (uint) {

       _validateRegistration(name, apiBaseUrl, providerType, msg.sender, msg.value);

        uint providerId = _providerIdByAddress[msg.sender];
        if (providerId == 0) {
            ++lastProviderId;
            providerId = lastProviderId;
            _providerIdByAddress[msg.sender] = providerId;
        }

        _liquidityProviders[providerId] = Flyover.LiquidityProvider({
            id: providerId,
            providerAddress: msg.sender,
            name: name,
            apiBaseUrl: apiBaseUrl,
            status: status,
            providerType: providerType
        });
        emit Register(providerId, msg.sender, msg.value);
        _addCollateral(providerType, msg.sender, msg.value);
        return providerId;
    }

    /// @inheritdoc IFlyoverDiscovery
    function setProviderStatus(
        uint providerId,
        bool status
    ) external {
        if (msg.sender != defaultAdmin() && msg.sender != _liquidityProviders[providerId].providerAddress) {
            revert NotAuthorized(msg.sender);
        }
        _liquidityProviders[providerId].status = status;
        emit IFlyoverDiscovery.ProviderStatusSet(providerId, status);
    }

    /// @inheritdoc IFlyoverDiscovery
    function updateProvider(string calldata name, string calldata apiBaseUrl) external whenNotPaused {
        _validateProviderData(name, apiBaseUrl);
        address providerAddress = msg.sender;
        uint providerId = _providerIdByAddress[providerAddress];
        if (providerId == 0) revert Flyover.ProviderNotRegistered(providerAddress);

        Flyover.LiquidityProvider storage lp = _liquidityProviders[providerId];
        lp.name = name;
        lp.apiBaseUrl = apiBaseUrl;
        emit IFlyoverDiscovery.ProviderUpdate(providerAddress, lp.name, lp.apiBaseUrl);
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
    function isOperational(Flyover.ProviderType providerType, address addr) external view returns (bool) {
        return _getProvider(addr).status &&
               _collateralManagement.isCollateralSufficient(providerType, addr);
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
        if (
            providerAddress != msg.sender ||
            msg.sender != tx.origin // solhint-disable-line avoid-tx-origin
        ) revert NotEOA(providerAddress);

        _validateProviderData(name, apiBaseUrl);

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
    /// @dev Uses providerAddress-to-id mapping for O(1) lookup
    /// @param providerAddress The address of the provider to find
    /// @return The liquidity provider record, reverts if not found
    function _getProvider(address providerAddress) private view returns (Flyover.LiquidityProvider memory) {
        uint providerId = _providerIdByAddress[providerAddress];
        if (providerId == 0) revert Flyover.ProviderNotRegistered(providerAddress);
        return _liquidityProviders[providerId];
    }

    /// @notice Validates provider metadata fields
    /// @dev Requires `name` and `apiBaseUrl` to be non-empty and within their configured max lengths
    /// @param name The provider display name to validate
    /// @param apiBaseUrl The provider API base URL to validate
    function _validateProviderData(string memory name, string memory apiBaseUrl) private pure {
        uint256 nameLength = bytes(name).length;
        uint256 apiBaseUrlLength = bytes(apiBaseUrl).length;
        if (
            nameLength < 1 ||
            nameLength > _MAX_PROVIDER_NAME_LENGTH ||
            apiBaseUrlLength < 1 ||
            apiBaseUrlLength > _MAX_PROVIDER_API_BASE_URL_LENGTH
        ) {
             revert IFlyoverDiscovery.ProviderDataLengthOutOfBounds(
                 nameLength,
                 apiBaseUrlLength,
                 _MAX_PROVIDER_NAME_LENGTH,
                 _MAX_PROVIDER_API_BASE_URL_LENGTH
             );
        }
    }
}
