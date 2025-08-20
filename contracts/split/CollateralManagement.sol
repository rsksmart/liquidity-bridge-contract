// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {ICollateralManagement} from "../interfaces/ICollateralManagement.sol";
import {Flyover} from "../libraries/Flyover.sol";
import {Quotes} from "../libraries/Quotes.sol";
import {
    AccessControlDefaultAdminRulesUpgradeable
} from "@openzeppelin/contracts-upgradeable/access/extensions/AccessControlDefaultAdminRulesUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";

contract CollateralManagementContract is
    AccessControlDefaultAdminRulesUpgradeable,
    ReentrancyGuardUpgradeable,
    ICollateralManagement
{
    bytes32 public constant COLLATERAL_ADDER = keccak256("COLLATERAL_ADDER");
    bytes32 public constant COLLATERAL_SLASHER = keccak256("COLLATERAL_SLASHER");

    event MinCollateralSet(uint256 oldMinCollateral, uint256 newMinCollateral);
    event ResignDelayInBlocksSet(uint oldResignDelayInBlocks, uint newResignDelayInBlocks);
    event RewardPercentageSet(uint256 indexed oldReward, uint256 indexed newReward);

    uint private _minCollateral;
    uint private _resignDelayInBlocks;
    mapping(address => uint256) private _pegInCollateral;
    mapping(address => uint256) private _pegOutCollateral;
    mapping(address => uint256) private _resignationBlockNum;
    mapping(address => uint256) private _rewards;
    uint256 public rewardPercentage;

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
        uint resignDelayInBlocks,
        uint256 rewardPercentage_
    ) public initializer {
        __AccessControlDefaultAdminRules_init(initialDelay, owner);
        __ReentrancyGuard_init();
        _minCollateral = minCollateral;
        _resignDelayInBlocks = resignDelayInBlocks;
        rewardPercentage = rewardPercentage_;
    }

    function setMinCollateral(uint minCollateral) external onlyRole(DEFAULT_ADMIN_ROLE) {
        emit MinCollateralSet(_minCollateral, minCollateral);
        _minCollateral = minCollateral;
    }

    function setResignDelayInBlocks(uint resignDelayInBlocks) external onlyRole(DEFAULT_ADMIN_ROLE) {
        emit ResignDelayInBlocksSet(_resignDelayInBlocks, resignDelayInBlocks);
        _resignDelayInBlocks = resignDelayInBlocks;
    }

    // solhint-disable-next-line comprehensive-interface
    function setRewardPercentage(uint256 rewardPercentage_) external onlyRole(DEFAULT_ADMIN_ROLE) {
        emit RewardPercentageSet(rewardPercentage, rewardPercentage_);
        rewardPercentage = rewardPercentage_;
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

    function addPegInCollateralTo(address addr) external onlyRole(COLLATERAL_ADDER) payable {
        _addPegInCollateralTo(addr);
    }

    function addPegInCollateral() external onlyRegisteredForPegIn payable {
        _addPegInCollateralTo(msg.sender);
    }

    function slashPegInCollateral(
        address punisher,
        Quotes.PegInQuote calldata quote,
        bytes32 quoteHash
    ) external onlyRole(COLLATERAL_SLASHER) returns (uint256) {
        uint penalty = _min(
            quote.penaltyFee,
            _pegInCollateral[quote.liquidityProviderRskAddress]
        );
        _pegInCollateral[quote.liquidityProviderRskAddress] -= penalty;
        uint256 punisherReward = (penalty * rewardPercentage) / 100;
        _rewards[punisher] += punisherReward;
        emit Penalized(quote.liquidityProviderRskAddress, quoteHash, Flyover.ProviderType.PegIn, penalty, punisherReward);
        return penalty;
    }

    function addPegOutCollateralTo(address addr) external onlyRole(COLLATERAL_ADDER) payable {
        _addPegOutCollateralTo(addr);
    }

    function addPegOutCollateral() external onlyRegisteredForPegOut payable {
        _addPegOutCollateralTo(msg.sender);
    }

    function slashPegOutCollateral(
        address punisher,
        Quotes.PegOutQuote calldata quote,
        bytes32 quoteHash
    ) external onlyRole(COLLATERAL_SLASHER) returns (uint256) {
        uint penalty = _min(
            quote.penaltyFee,
            _pegOutCollateral[quote.lpRskAddress]
        );
        _pegOutCollateral[quote.lpRskAddress] -= penalty;
        uint256 punisherReward = (penalty * rewardPercentage) / 100;
        _rewards[punisher] += punisherReward;
        emit Penalized(quote.lpRskAddress, quoteHash, Flyover.ProviderType.PegOut, penalty, punisherReward);
        return penalty;
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

    function _addPegInCollateralTo(address addr) private {
        uint amount = msg.value;
        _pegInCollateral[addr] += amount;
        emit ICollateralManagement.PegInCollateralAdded(addr, amount);
    }

    function _addPegOutCollateralTo(address addr) private {
        uint amount = msg.value;
        _pegOutCollateral[addr] += amount;
        emit ICollateralManagement.PegOutCollateralAdded(addr, amount);
    }

    function _min(uint a, uint b) private pure returns (uint) {
        return a < b ? a : b;
    }
}
