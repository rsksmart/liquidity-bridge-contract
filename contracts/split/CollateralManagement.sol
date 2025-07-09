// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import "./interfaces.sol";
import "@openzeppelin/contracts-upgradeable/access/extensions/AccessControlDefaultAdminRulesUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";

contract CollateralManagementContract is
    AccessControlDefaultAdminRulesUpgradeable,
    ReentrancyGuardUpgradeable,
    CollateralManagement
{
    bytes32 public constant COLLATERAL_ADDER = keccak256("COLLATERAL_ADDER");
    bytes32 public constant COLLATERAL_SLASHER = keccak256("COLLATERAL_SLASHER");

    event WithdrawCollateral(address indexed addr, uint amount);
    event Resigned(address indexed addr);

    error AlreadyResigned(address from);
    error NotResigned(address from);
    error ResignationDelayNotMet(address from, uint resignationBlockNum, uint resignDelayInBlocks);
    error WithdrawalFailed(address from, uint amount);

    uint private _minCollateral;
    uint private _resignDelayInBlocks;
    mapping(address => uint) private _pegInCollateral;
    mapping(address => uint) private _pegOutCollateral;
    mapping(address => uint) private _resignationBlockNum;

    modifier onlyRegisteredForPegIn() {
        if (!_isRegistered(Flyover.ProviderType.PegIn, msg.sender))
            revert Flyover.ProviderNotRegistered(msg.sender);
        _;
    }

    modifier onlyRegisteredForPegOut() {
        if (!_isRegistered(Flyover.ProviderType.PegOut, msg.sender))
            revert Flyover.ProviderNotRegistered(msg.sender);
        _;
    }

    function initialize(
        address owner,
        uint48 initialDelay,
        uint minCollateral,
        uint resignDelayInBlocks
    ) public initializer {
        __AccessControlDefaultAdminRules_init(initialDelay, owner);
        __ReentrancyGuard_init();
        _minCollateral = minCollateral;
        _resignDelayInBlocks = resignDelayInBlocks;
    }

    function setMinCollateral(uint minCollateral) external onlyRole(DEFAULT_ADMIN_ROLE) {
        emit CollateralManagement.MinCollateralSet(_minCollateral, minCollateral);
        _minCollateral = minCollateral;
    }

    function setResignDelayInBlocks(uint resignDelayInBlocks) external onlyRole(DEFAULT_ADMIN_ROLE) {
        emit CollateralManagement.ResignDelayInBlocksSet(_resignDelayInBlocks, resignDelayInBlocks);
        _resignDelayInBlocks = resignDelayInBlocks;
    }

    function getPegInCollateral(address addr) external view returns (uint) {
        return _pegInCollateral[addr];
    }

    function getPegOutCollateral(address addr) external view returns (uint) {
        return _pegOutCollateral[addr];
    }

    function getResignationBlock(address addr) external view returns (uint) {
        return _resignationBlockNum[addr];
    }

    function addPegInCollateralTo(address addr) external payable {
        _addPegInCollateralTo(addr);
    }

    function addPegInCollateral() external onlyRegisteredForPegIn payable {
        _addPegInCollateralTo(msg.sender);
    }

    function addPegOutCollateralTo(address addr) external payable {
        _addPegOutCollateralTo(addr);
    }

    function addPegOutCollateral() external onlyRegisteredForPegOut payable {
        _addPegOutCollateralTo(msg.sender);
    }

    function getMinCollateral() external view returns (uint) {
        return _minCollateral;
    }

    function isRegistered(Flyover.ProviderType providerType, address addr) external view returns (bool) {
        return _isRegistered(providerType, addr);
    }

    function isCollateralSufficient(Flyover.ProviderType providerType, address addr) external view returns (bool) {
       if (providerType == Flyover.ProviderType.PegIn) {
            return _pegInCollateral[addr] >= _minCollateral && _resignationBlockNum[addr] == 0;
        } else if (providerType == Flyover.ProviderType.PegOut) {
            return _pegOutCollateral[addr] >= _minCollateral && _resignationBlockNum[addr] == 0;
        } else {
            return _pegInCollateral[addr] >= _minCollateral &&
                _pegOutCollateral[addr] >= _minCollateral &&
                _resignationBlockNum[addr] == 0;
        }
    }

    function withdrawCollateral() external nonReentrant {
        address providerAddress = msg.sender;
        uint resignationBlock = _resignationBlockNum[providerAddress];
        if (resignationBlock <= 0) revert NotResigned(providerAddress);
        if (block.number - resignationBlock < _resignDelayInBlocks) {
            revert ResignationDelayNotMet(providerAddress, resignationBlock, _resignDelayInBlocks);
        }

        uint amount = _pegOutCollateral[providerAddress] + _pegInCollateral[providerAddress];
        _pegOutCollateral[providerAddress] = 0;
        _pegInCollateral[providerAddress] = 0;
        _resignationBlockNum[providerAddress] = 0;

        emit WithdrawCollateral(providerAddress, amount);
        (bool success,) = providerAddress.call{value: amount}("");
        if (!success) revert WithdrawalFailed(providerAddress, amount);
    }

    function resign() external {
        address providerAddress = msg.sender;
        if (_resignationBlockNum[providerAddress] != 0) revert AlreadyResigned(providerAddress);
        if (_pegInCollateral[providerAddress] <= 0 && _pegOutCollateral[providerAddress] <= 0) {
            revert Flyover.ProviderNotRegistered(providerAddress);
        }
        _resignationBlockNum[providerAddress] = block.number;
        emit Resigned(providerAddress);
    }

    function _isRegistered(Flyover.ProviderType providerType, address addr) private view returns (bool) {
        if (providerType == Flyover.ProviderType.PegIn) {
            return _pegInCollateral[addr] > 0 && _resignationBlockNum[addr] == 0;
        } else if (providerType == Flyover.ProviderType.PegOut) {
            return _pegOutCollateral[addr] > 0 && _resignationBlockNum[addr] == 0;
        } else {
            return _pegInCollateral[addr] > 0 && _pegOutCollateral[addr] > 0 && _resignationBlockNum[addr] == 0;
        }
    }

    function _addPegInCollateralTo(address addr) private onlyRole(COLLATERAL_ADDER) {
        uint amount = msg.value;
        _pegInCollateral[addr] += amount;
        emit CollateralManagement.PegInCollateralAdded(addr, amount);
    }

    function _addPegOutCollateralTo(address addr) private onlyRole(COLLATERAL_ADDER) {
        uint amount = msg.value;
        _pegOutCollateral[addr] += amount;
        emit CollateralManagement.PegOutCollateralAdded(addr, amount);
    }
}
