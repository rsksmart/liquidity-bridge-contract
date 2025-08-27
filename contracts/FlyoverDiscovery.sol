// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

/* solhint-disable comprehensive-interface */

import {
    AccessControlDefaultAdminRulesUpgradeable
} from "@openzeppelin/contracts-upgradeable/access/extensions/AccessControlDefaultAdminRulesUpgradeable.sol";
import {ICollateralManagement} from "./interfaces/ICollateralManagement.sol";
import {IFlyoverDiscovery} from "./interfaces/IFlyoverDiscovery.sol";
import {Flyover} from "./libraries/Flyover.sol";

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

    // non-view external functions should be declared before external view functions (solhint ordering)
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

        function setMinCollateral(uint minCollateral) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _minCollateral = minCollateral;
    }

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

    function getProvider(address providerAddress) external view returns (Flyover.LiquidityProvider memory) {
        return _getProvider(providerAddress);
    }

    function isOperational(Flyover.ProviderType, address addr) external view returns (bool) {
        return _isRegistered(addr) && _collateralManagement.getPegInCollateral(addr) >= _minCollateral;
    }

    function isOperationalForPegout(address addr) external view returns (bool) {
        return _isRegisteredForPegout(addr) && _collateralManagement.getPegOutCollateral(addr) >= _minCollateral;
    }

    // ------------------------------------------------------------
    // Getter Functions
    // ------------------------------------------------------------

    function getMinCollateral() external view returns (uint256) {
        return _minCollateral;
    }

    function getProvidersId() external view returns (uint) {
        return lastProviderId;
    }

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
