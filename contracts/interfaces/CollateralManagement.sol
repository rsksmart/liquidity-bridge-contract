// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import "../libraries/Flyover.sol";

interface CollateralManagement {
    event WithdrawCollateral(address indexed addr, uint amount);
    event Resigned(address indexed addr);
    event PegInCollateralAdded(address indexed addr, uint256 amount);
    event PegOutCollateralAdded(address indexed addr, uint256 amount);

    error AlreadyResigned(address from);
    error NotResigned(address from);
    error ResignationDelayNotMet(address from, uint resignationBlockNum, uint resignDelayInBlocks);
    error WithdrawalFailed(address from, uint amount);

    function getPegInCollateral(address addr) external view returns (uint256);
    function getPegOutCollateral(address addr) external view returns (uint256);
    function getResignationBlock(address addr) external view returns (uint256);
    function addPegInCollateralTo(address addr) external payable;
    function addPegInCollateral() external payable;
    function addPegOutCollateralTo(address addr) external payable;
    function addPegOutCollateral() external payable;
    function getMinCollateral() external view returns (uint256);
    function isRegistered(Flyover.ProviderType providerType, address addr) external view returns (bool);
    function isCollateralSufficient(Flyover.ProviderType providerType, address addr) external view returns (bool);
}
