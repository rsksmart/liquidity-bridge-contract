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
    struct PendingRegistration {
        string name;
        string apiBaseUrl;
        bool status;
        Flyover.ProviderType providerType;
        uint256 collateralAmount;
    }

    /// @notice The version of the contract
    string constant public VERSION = "1.0.0";

    // ------------------------------------------------------------
    // FlyoverDiscovery State Variables
    // ------------------------------------------------------------

    mapping(uint => Flyover.LiquidityProvider) private _liquidityProviders;
    mapping(address => uint) private _providerIdByAddress;
    ICollateralManagement private _collateralManagement;
    uint public lastProviderId;

    // v2.6.0
    mapping(address => PendingRegistration) private _pendingRegistrations;
    mapping(address => IFlyoverDiscovery.RegistrationState) private _registrationStates;

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
    ) external payable whenNotSoftPaused returns (uint) {

       _validateRegistration(name, apiBaseUrl, providerType, msg.sender, msg.value);

        uint providerId = _providerIdByAddress[msg.sender];
        if (providerId == 0) {
            ++lastProviderId;
            providerId = lastProviderId;
            _providerIdByAddress[msg.sender] = providerId;
        }

        _pendingRegistrations[msg.sender] = PendingRegistration({
            name: name,
            apiBaseUrl: apiBaseUrl,
            status: status,
            providerType: providerType,
            collateralAmount: msg.value
        });
        _registrationStates[msg.sender] = RegistrationState.Pending;
        emit Register(providerId, msg.sender, msg.value);
        return providerId;
    }

    /// @inheritdoc IFlyoverDiscovery
    function withdrawRegisterRequest() external whenNotSoftPaused {
        if (_registrationStates[msg.sender] != RegistrationState.Pending) {
            revert RegistrationNotPending(msg.sender);
        }
        uint256 providerId = _providerIdByAddress[msg.sender];
        uint256 amount = _clearPendingRegistration(msg.sender, RegistrationState.Withdrawn);
        emit RegistrationWithdrawn(providerId, msg.sender, amount);
        _refundCollateral(payable(msg.sender), amount);
    }

    /// @inheritdoc IFlyoverDiscovery
    function approveRegistration(address providerAddress) external whenNotSoftPaused {
        _checkAdminPendingRegistration(providerAddress);

        uint256 providerId = _providerIdByAddress[providerAddress];
        PendingRegistration memory pending = _pendingRegistrations[providerAddress];
        _liquidityProviders[providerId] = Flyover.LiquidityProvider({
            id: providerId,
            providerAddress: providerAddress,
            name: pending.name,
            apiBaseUrl: pending.apiBaseUrl,
            status: pending.status,
            providerType: pending.providerType
        });
        _registrationStates[providerAddress] = RegistrationState.Approved;
        delete _pendingRegistrations[providerAddress];

        emit RegistrationApproved(providerId, providerAddress, pending.collateralAmount);
        _addCollateral(pending.providerType, providerAddress, pending.collateralAmount);
    }

    /// @inheritdoc IFlyoverDiscovery
    function rejectRegistration(address providerAddress) external whenNotSoftPaused {
        _checkAdminPendingRegistration(providerAddress);

        uint256 providerId = _providerIdByAddress[providerAddress];
        uint256 amount = _clearPendingRegistration(providerAddress, RegistrationState.Rejected);
        emit RegistrationRejected(providerId, providerAddress, amount);
        _refundCollateral(payable(providerAddress), amount);
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
    function updateProvider(string calldata name, string calldata apiBaseUrl) external whenNotHardPaused {
        if (bytes(name).length < 1 || bytes(apiBaseUrl).length < 1) revert InvalidProviderData(name, apiBaseUrl);
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

    /// @inheritdoc IFlyoverDiscovery
    function getRegistrationState(
        address providerAddress
    ) external view returns (IFlyoverDiscovery.RegistrationState) {
        return _registrationStates[providerAddress];
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

    function _clearPendingRegistration(
        address providerAddress,
        RegistrationState nextState
    ) private returns (uint256 amount) {
        amount = _pendingRegistrations[providerAddress].collateralAmount;
        delete _pendingRegistrations[providerAddress];
        _registrationStates[providerAddress] = nextState;
    }

    function _refundCollateral(address payable providerAddress, uint256 amount) private {
        (bool success,) = providerAddress.call{value: amount}("");
        if (!success) revert Flyover.PaymentFailed(providerAddress, amount, hex"");
    }

    function _checkAdminPendingRegistration(address providerAddress) private view {
        if (msg.sender != defaultAdmin()) revert NotAuthorized(msg.sender);
        if (_registrationStates[providerAddress] != RegistrationState.Pending) {
            revert RegistrationNotPending(providerAddress);
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

        if (
            bytes(name).length < 1 ||
            bytes(apiBaseUrl).length < 1
        ) {
            revert InvalidProviderData(name, apiBaseUrl);
        }

        if (providerType > type(Flyover.ProviderType).max) revert InvalidProviderType(providerType);

        if (_registrationStates[providerAddress] == RegistrationState.Pending) {
            revert RegistrationAlreadyPending(providerAddress);
        }

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
        if (providerId == 0 || _registrationStates[providerAddress] != RegistrationState.Approved) {
            revert Flyover.ProviderNotRegistered(providerAddress);
        }
        return _liquidityProviders[providerId];
    }
}
