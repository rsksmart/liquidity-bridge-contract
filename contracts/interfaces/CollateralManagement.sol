// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Flyover} from "../libraries/Flyover.sol";

interface ICollateralManagement {
    event WithdrawCollateral(address indexed addr, uint indexed amount);
    event Resigned(address indexed addr);
    event PegInCollateralAdded(address indexed addr, uint256 indexed amount);
    event PegOutCollateralAdded(address indexed addr, uint256 indexed amount);

    error AlreadyResigned(address from);
    error NotResigned(address from);
    error ResignationDelayNotMet(address from, uint resignationBlockNum, uint resignDelayInBlocks);
    error WithdrawalFailed(address from, uint amount);

    function addPegInCollateralTo(address addr) external payable;
    function addPegInCollateral() external payable;
    function addPegOutCollateralTo(address addr) external payable;
    function addPegOutCollateral() external payable;

    function getPegInCollateral(address addr) external view returns (uint256);
    function getPegOutCollateral(address addr) external view returns (uint256);
    function getResignationBlock(address addr) external view returns (uint256);
    function getMinCollateral() external view returns (uint256);
    function isRegistered(Flyover.ProviderType providerType, address addr) external view returns (bool);
    function isCollateralSufficient(Flyover.ProviderType providerType, address addr) external view returns (bool);
}
