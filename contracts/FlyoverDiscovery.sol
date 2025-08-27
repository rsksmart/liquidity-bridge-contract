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
    // Basic Configuration State Variables
    // ------------------------------------------------------------

    uint private _minCollateral;
    mapping(address => uint256) private _resignationBlockNum;

    // ------------------------------------------------------------
    // FlyoverDiscovery Public Functions and Modifiers
    // ------------------------------------------------------------

    /// @notice Initializes the contract with admin configuration
    /// @dev Uses OZ upgradeable admin rules. Must be called only once
    /// @param owner The Default Admin and initial owner address
    /// @param initialDelay The initial admin delay for `AccessControlDefaultAdminRulesUpgradeable`
    /// @param minCollateral The minimum collateral required per service side
    /// @param collateralManagement The address of the `ICollateralManagement` contract
    function initialize(
        address owner,
        uint48 initialDelay,
        uint minCollateral,
        address collateralManagement
    ) external initializer {
        __AccessControlDefaultAdminRules_init(initialDelay, owner);
        _minCollateral = minCollateral;
        _collateralManagement = ICollateralManagement(collateralManagement);
    }

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
    ) external payable returns (uint) {

       _validateRegistration(name, apiBaseUrl, providerType, msg.sender);

        ++lastProviderId;
        _liquidityProviders[lastProviderId] = Flyover.LiquidityProvider({
            id: lastProviderId,
            providerAddress: msg.sender,
            name: name,
            apiBaseUrl: apiBaseUrl,
            status: status,
            providerType: providerType
        });
        emit Register(lastProviderId, msg.sender, msg.value);
        return (lastProviderId);
    }

    /// @notice Resigns the caller as a Liquidity Provider
    /// @dev Reverts if the caller is not registered or already resigned
    /// @dev Resignation is permanent and cannot be undone
    function resign() external override {
        address providerAddress = msg.sender;
        if (_resignationBlockNum[providerAddress] != 0) revert AlreadyResigned(providerAddress);
        if (
            _collateralManagement.getPegInCollateral(providerAddress) <= 0 &&
            _collateralManagement.getPegOutCollateral(providerAddress) <= 0
        ) {
            revert Flyover.ProviderNotRegistered(providerAddress);
        }
        _resignationBlockNum[providerAddress] = block.number;
        emit Resigned(providerAddress);
    }

    // non-view external functions should be declared before external view functions (solhint ordering)
    /// @notice Updates a provider status flag
    /// @dev Callable by the LP itself or the contract owner
    /// @param providerId The provider identifier
    /// @param status The new status value
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

    /// @notice Updates the caller LP metadata
    /// @dev Reverts if the caller is not registered or provides invalid fields
    /// @param name New LP name
    /// @param apiBaseUrl New LP API base URL
    function updateProvider(string calldata name, string calldata apiBaseUrl) external {
        if (bytes(name).length < 1 || bytes(apiBaseUrl).length < 1) revert InvalidProviderData(name, apiBaseUrl);
        Flyover.LiquidityProvider storage lp;
        address providerAddress = msg.sender;
        for (uint i = 1; i <= lastProviderId; ++i) {
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

        /// @notice Sets the minimum collateral threshold per service side
        /// @dev Only callable by DEFAULT_ADMIN_ROLE
        /// @param minCollateral New minimum collateral value
        function setMinCollateral(uint minCollateral) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _minCollateral = minCollateral;
    }

    /// @notice Lists LPs that should be visible to users
    /// @dev A provider is listed if it has sufficient collateral for at least one side and `status` is true
    /// @return providersToReturn Array of LP records to display
    function getProviders() external view returns (Flyover.LiquidityProvider[] memory) {
        uint count = 0;
        Flyover.LiquidityProvider storage lp;
        for (uint i = 1; i <= lastProviderId; ++i) {
            if (_shouldBeListed(_liquidityProviders[i])) {
                ++count;
            }
        }
        Flyover.LiquidityProvider[] memory providersToReturn = new Flyover.LiquidityProvider[](count);
        count = 0;
        for (uint i = 1; i <= lastProviderId; ++i) {
            lp = _liquidityProviders[i];
            if (_shouldBeListed(lp)) {
                providersToReturn[count] = lp;
                ++count;
            }
        }
        return providersToReturn;
    }

    /// @notice Returns a single LP by address
    /// @param providerAddress The LP address
    /// @return provider LP record, reverts if not found
    function getProvider(address providerAddress) external view returns (Flyover.LiquidityProvider memory) {
        return _getProvider(providerAddress);
    }

    /// @notice Checks if an LP can operate for peg-in side
    /// @dev Ignores the first argument as compatibility stub with legacy signature
    /// @param addr The LP address
    /// @return isOp True if registered and peg-in collateral >= min
    function isOperational(Flyover.ProviderType, address addr) external view returns (bool) {
        return _isRegistered(addr) && _collateralManagement.getPegInCollateral(addr) >= _minCollateral;
    }

    /// @notice Checks if an LP can operate for peg-out side
    /// @param addr The LP address
    /// @return isOp True if registered-for-pegout and peg-out collateral >= min
    function isOperationalForPegout(address addr) external view returns (bool) {
        return _isRegisteredForPegout(addr) && _collateralManagement.getPegOutCollateral(addr) >= _minCollateral;
    }

    // ------------------------------------------------------------
    // Getter Functions
    // ------------------------------------------------------------

    /// @notice Returns the current minimum collateral threshold per side
    /// @return minCollateral The minimum collateral value
    function getMinCollateral() external view returns (uint256) {
        return _minCollateral;
    }

    /// @notice Returns the last assigned provider id
    /// @return lastId Last provider id
    function getProvidersId() external view returns (uint) {
        return lastProviderId;
    }

    /// @notice Returns the resignation starting block for an LP
    /// @param addr The LP address
    /// @return resignationBlock Block number when resignation started, or 0 if not resigned
    function getResignationBlockNum(address addr) external view returns (uint256) {
        return _resignationBlockNum[addr];
    }

    // ------------------------------------------------------------
    // FlyoverDiscovery Private Functions
    // ------------------------------------------------------------

    function _shouldBeListed(Flyover.LiquidityProvider storage lp) private view returns(bool){
        return (_isRegistered(lp.providerAddress) || _isRegisteredForPegout(lp.providerAddress)) && lp.status;
    }

    function _validateRegistration(
        string memory name,
        string memory apiBaseUrl,
        Flyover.ProviderType providerType,
        address providerAddress
    ) private view {
        if (providerAddress != msg.sender || providerAddress.code.length != 0) revert NotEOA(providerAddress);

        if (
            bytes(name).length < 1 ||
            bytes(apiBaseUrl).length < 1
        ) {
            revert InvalidProviderData(name, apiBaseUrl);
        }

        if (providerType > type(Flyover.ProviderType).max) revert InvalidProviderType(providerType);

        if (_resignationBlockNum[providerAddress] != 0) {
            revert AlreadyRegistered(providerAddress);
        }

        // Check minimum collateral requirement
        uint256 requiredCollateral = _minCollateral;
        if (providerType == Flyover.ProviderType.Both) {
            requiredCollateral = _minCollateral * 2;
        }
        if (msg.value < requiredCollateral) revert InsufficientCollateral(msg.value);
    }

    function _getProvider(address providerAddress) private view returns (Flyover.LiquidityProvider memory) {
        for (uint i = 1; i <= lastProviderId; ++i) {
            if (_liquidityProviders[i].providerAddress == providerAddress) {
                return _liquidityProviders[i];
            }
        }
        revert Flyover.ProviderNotRegistered(providerAddress);
    }

    function _isRegistered(address addr) private view returns (bool) {
        return _collateralManagement.getPegInCollateral(addr) > 0 && _resignationBlockNum[addr] == 0;
    }

    function _isRegisteredForPegout(address addr) private view returns (bool) {
        return _collateralManagement.getPegOutCollateral(addr) > 0 && _resignationBlockNum[addr] == 0;
    }
}
