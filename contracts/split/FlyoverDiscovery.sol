// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import "./interfaces.sol";

contract FlyoverDiscoveryContract is Ownable2StepUpgradeable, FlyoverDiscovery {
    event CollateralManagementSet(address oldContract, address newContract);

    error NotAuthorized(address from);
    error NotEOA(address from);
    error InvalidProviderData(string name, string apiBaseUrl);
    error InvalidProviderType(Flyover.ProviderType providerType);
    error AlreadyRegistered(address from);
    error InsufficientCollateral(uint amount);

    CollateralManagement public collateralManagement;
    mapping(uint => Flyover.LiquidityProvider) private _liquidityProviders;
    uint public lastProviderId;

    function initialize(
        address owner,
        address collateralManagement_
    ) public initializer {
        __Ownable_init(owner);
        collateralManagement = CollateralManagement(collateralManagement_);
    }

    function setCollateralManagement(address collateralManagement_) external onlyOwner {
        emit CollateralManagementSet(address(collateralManagement), collateralManagement_);
        collateralManagement = CollateralManagement(collateralManagement_);
    }

    function register(
        string memory name,
        string memory apiBaseUrl,
        bool status,
        Flyover.ProviderType providerType
    ) external payable returns (uint) {
        _validateRegistration(name, apiBaseUrl, providerType, msg.sender);

        lastProviderId++;
        _liquidityProviders[lastProviderId] = Flyover.LiquidityProvider({
            id: lastProviderId,
            providerAddress: msg.sender,
            name: name,
            apiBaseUrl: apiBaseUrl,
            status: status,
            providerType: providerType
        });
        emit FlyoverDiscovery.Register(lastProviderId, msg.sender, msg.value);

        _addCollateral(providerType, msg.sender, msg.value);
        return (lastProviderId);
    }

    function getProviders() external view returns (Flyover.LiquidityProvider[] memory) {
        uint count = 0;
        Flyover.LiquidityProvider storage lp;
        for (uint i = 1; i <= lastProviderId; i++) {
            if (_shouldBeListed(_liquidityProviders[i])) {
                count++;
            }
        }
        Flyover.LiquidityProvider[] memory providers = new Flyover.LiquidityProvider[](count);
        count = 0;
        for (uint i = 1; i <= lastProviderId; i++) {
            lp = _liquidityProviders[i];
            if (_shouldBeListed(lp)) {
                providers[count] = lp;
                count++;
            }
        }
        return providers;
    }

    function getProvider(address providerAddress) external view returns (Flyover.LiquidityProvider memory) {
        return _getProvider(providerAddress);
    }

    function _getProvider(address providerAddress) private view returns (Flyover.LiquidityProvider memory) {
        for (uint i = 1; i <= lastProviderId; i++) {
            if (_liquidityProviders[i].providerAddress == providerAddress) {
                return _liquidityProviders[i];
            }
        }
        revert Flyover.ProviderNotRegistered(providerAddress);
    }

    function setProviderStatus(
        uint providerId,
        bool status
    ) external {
        if (msg.sender != owner() && msg.sender != _liquidityProviders[providerId].providerAddress) {
            revert NotAuthorized(msg.sender);
        }
        _liquidityProviders[providerId].status = status;
        emit FlyoverDiscovery.ProviderStatusSet(providerId, status);
    }

    function updateProvider(string memory name, string memory url) external {
        if (bytes(name).length <= 0 || bytes(url).length <= 0) revert InvalidProviderData(name, url);
        Flyover.LiquidityProvider storage lp;
        address providerAddress = msg.sender;
        for (uint i = 1; i <= lastProviderId; i++) {
            lp = _liquidityProviders[i];
            if (providerAddress == lp.providerAddress) {
                lp.name = name;
                lp.apiBaseUrl = url;
                emit FlyoverDiscovery.ProviderUpdate(providerAddress, lp.name, lp.apiBaseUrl);
                return;
            }
        }
        revert Flyover.ProviderNotRegistered(providerAddress);
    }

    function isOperational(Flyover.ProviderType providerType, address providerAddress) external view returns (bool) {
        return collateralManagement.isCollateralSufficient(providerType, providerAddress) &&
            _getProvider(providerAddress).status;
    }

    function _shouldBeListed(Flyover.LiquidityProvider storage lp) private view returns(bool){
        return collateralManagement.isRegistered(lp.providerType, lp.providerAddress) && lp.status;
    }

    function _validateRegistration(
        string memory name,
        string memory apiBaseUrl,
        Flyover.ProviderType providerType,
        address providerAddress
    ) private view {
        if (providerAddress != tx.origin) revert NotEOA(providerAddress);

        if (
            bytes(name).length <= 0 ||
            bytes(apiBaseUrl).length <= 0
        ) {
            revert InvalidProviderData(name, apiBaseUrl);
        }

        if (providerType > type(Flyover.ProviderType).max) revert InvalidProviderType(providerType);

        if (
            collateralManagement.getPegInCollateral(providerAddress) > 0 ||
            collateralManagement.getPegOutCollateral(providerAddress) > 0 ||
            collateralManagement.getResignationBlock(providerAddress) != 0
        ) {
            revert AlreadyRegistered(providerAddress);
        }
    }

    function _addCollateral(
        Flyover.ProviderType providerType,
        address providerAddress,
        uint amount
    ) private {
        uint minCollateral = collateralManagement.getMinCollateral();
        if (providerType == Flyover.ProviderType.PegIn) {
            if (amount < minCollateral) revert InsufficientCollateral(amount);
            collateralManagement.addPegInCollateralTo(providerAddress, amount);
        } else if (providerType == Flyover.ProviderType.PegOut) {
            if (amount < minCollateral) revert InsufficientCollateral(amount);
            collateralManagement.addPegOutCollateralTo(providerAddress, amount);
        } else {
            if (amount < minCollateral * 2) revert InsufficientCollateral(amount);
            uint halfMsgValue = amount / 2;
            collateralManagement.addPegInCollateralTo(
                providerAddress, amount % 2 == 0 ? halfMsgValue : halfMsgValue + 1
            );
            collateralManagement.addPegOutCollateralTo(providerAddress, halfMsgValue);
        }
    }

}
