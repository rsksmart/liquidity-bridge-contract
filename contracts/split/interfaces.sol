// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

// TODO this file is temporary, once the gas measurements are done, we need to split this file

library Flyover {
    enum ProviderType { PegIn, PegOut, Both }

    error ProviderNotRegistered(address from);

    struct LiquidityProvider {
        uint id;
        address providerAddress;
        string name;
        string apiBaseUrl;
        bool status;
        ProviderType providerType;
    }
}

interface CollateralManagement {
    event MinCollateralSet(uint256 oldMinCollateral, uint256 newMinCollateral);
    event ResignDelayInBlocksSet(uint oldResignDelayInBlocks, uint newResignDelayInBlocks);
    event PegInCollateralAdded(address indexed addr, uint256 amount);
    event PegOutCollateralAdded(address indexed addr, uint256 amount);

    function getPegInCollateral(address addr) external view returns (uint256);
    function getPegOutCollateral(address addr) external view returns (uint256);
    function getResignationBlock(address addr) external view returns (uint256);
    function addPegInCollateralTo(address addr, uint256 amount) external payable;
    function addPegInCollateral(uint256 amount) external payable;
    function addPegOutCollateralTo(address addr, uint256 amount) external payable;
    function addPegOutCollateral(uint256 amount) external payable;
    function getMinCollateral() external view returns (uint256);
    function isRegistered(Flyover.ProviderType providerType, address addr) external view returns (bool);
    function isCollateralSufficient(Flyover.ProviderType providerType, address addr) external view returns (bool);
}

interface FlyoverDiscovery {
    event Register(uint indexed id, address indexed from, uint256 amount);
    event ProviderUpdate(address indexed from, string name, string apiBaseUrl);
    event ProviderStatusSet(uint indexed id, bool status);


    function register(
        string memory name,
        string memory apiBaseUrl,
        bool status,
        Flyover.ProviderType providerType
    ) external payable returns (uint);

    function updateProvider(string memory name,string memory apiBaseUrl) external;
    function getProviders() external view returns (Flyover.LiquidityProvider[] memory);
    function getProvider(address providerAddress) external view returns (Flyover.LiquidityProvider memory);
    function isOperational(Flyover.ProviderType providerType, address addr) external view returns (bool);
    function setProviderStatus(uint providerId, bool status) external;
}
