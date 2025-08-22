// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {
    AccessControlDefaultAdminRulesUpgradeable
} from "@openzeppelin/contracts-upgradeable/access/extensions/AccessControlDefaultAdminRulesUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {ICollateralManagement} from "./interfaces/ICollateralManagement.sol";
import {Flyover} from "./libraries/Flyover.sol";
import {Quotes} from "./libraries/Quotes.sol";

contract CollateralManagementContract is
    AccessControlDefaultAdminRulesUpgradeable,
    ReentrancyGuardUpgradeable,
    ICollateralManagement
{
    /// @notice The version of the contract
    string constant public VERSION = "1.0.0";
    bytes32 public constant COLLATERAL_ADDER = keccak256("COLLATERAL_ADDER");
    bytes32 public constant COLLATERAL_SLASHER = keccak256("COLLATERAL_SLASHER");

    uint256 private _minCollateral;
    uint256 private _resignDelayInBlocks;
    uint256 private _rewardPercentage;
    uint256 private _penalties;
    mapping(address => uint256) private _pegInCollateral;
    mapping(address => uint256) private _pegOutCollateral;
    mapping(address => uint256) private _resignationBlockNum;
    mapping(address => uint256) private _rewards;

    event MinCollateralSet(uint256 indexed oldMinCollateral, uint256 indexed newMinCollateral);
    event ResignDelayInBlocksSet(uint256 indexed oldResignDelayInBlocks, uint256 indexed newResignDelayInBlocks);
    event RewardPercentageSet(uint256 indexed oldReward, uint256 indexed newReward);

    modifier onlyRegisteredForPegIn(address addr) {
        if (!_isRegistered(Flyover.ProviderType.PegIn, addr))
            revert Flyover.ProviderNotRegistered(addr);
        _;
    }

    modifier onlyRegisteredForPegOut(address addr) {
        if (!_isRegistered(Flyover.ProviderType.PegOut, addr))
            revert Flyover.ProviderNotRegistered(addr);
        _;
    }

    // solhint-disable-next-line comprehensive-interface
    receive() external payable {
        revert Flyover.PaymentNotAllowed();
    }

    function addPegInCollateralTo(address addr) external onlyRole(COLLATERAL_ADDER) payable override {
        _addPegInCollateralTo(addr, msg.value);
    }

    function addPegInCollateral() external onlyRegisteredForPegIn(msg.sender) payable override {
        _addPegInCollateralTo(msg.sender, msg.value);
    }

    function addPegOutCollateralTo(address addr) external onlyRole(COLLATERAL_ADDER) payable override {
        _addPegOutCollateralTo(addr, msg.value);
    }

    function addPegOutCollateral() external onlyRegisteredForPegOut(msg.sender) payable override {
        _addPegOutCollateralTo(msg.sender, msg.value);
    }

    // solhint-disable-next-line comprehensive-interface
    function initialize(
        address owner,
        uint48 initialDelay,
        uint256 minCollateral,
        uint256 resignDelayInBlocks,
        uint256 rewardPercentage
    ) external initializer {
        __AccessControlDefaultAdminRules_init(initialDelay, owner);
        __ReentrancyGuard_init();
        _minCollateral = minCollateral;
        _resignDelayInBlocks = resignDelayInBlocks;
        _rewardPercentage = rewardPercentage;
        _penalties = 0;
    }

    // solhint-disable-next-line comprehensive-interface
    function setMinCollateral(uint minCollateral) external onlyRole(DEFAULT_ADMIN_ROLE) {
        emit MinCollateralSet(_minCollateral, minCollateral);
        _minCollateral = minCollateral;
    }

    // solhint-disable-next-line comprehensive-interface
    function setResignDelayInBlocks(uint resignDelayInBlocks) external onlyRole(DEFAULT_ADMIN_ROLE) {
        emit ResignDelayInBlocksSet(_resignDelayInBlocks, resignDelayInBlocks);
        _resignDelayInBlocks = resignDelayInBlocks;
    }

    // solhint-disable-next-line comprehensive-interface
    function setRewardPercentage(uint256 rewardPercentage) external onlyRole(DEFAULT_ADMIN_ROLE) {
        emit RewardPercentageSet(_rewardPercentage, rewardPercentage);
        _rewardPercentage = rewardPercentage;
    }

    function slashPegInCollateral(
        address punisher,
        Quotes.PegInQuote calldata quote,
        bytes32 quoteHash
    ) external onlyRole(COLLATERAL_SLASHER) override {
        uint penalty = Math.min(
            quote.penaltyFee,
            _pegInCollateral[quote.liquidityProviderRskAddress]
        );
        _pegInCollateral[quote.liquidityProviderRskAddress] -= penalty;
        uint256 punisherReward = (penalty * _rewardPercentage) / 100;
        _penalties += penalty - punisherReward;
        _rewards[punisher] += punisherReward;
        emit Penalized(
            quote.liquidityProviderRskAddress,
            punisher,
            quoteHash,
            Flyover.ProviderType.PegIn,
            penalty,
            punisherReward
        );
    }

    function slashPegOutCollateral(
        address punisher,
        Quotes.PegOutQuote calldata quote,
        bytes32 quoteHash
    ) external onlyRole(COLLATERAL_SLASHER) override {
        uint penalty = Math.min(
            quote.penaltyFee,
            _pegOutCollateral[quote.lpRskAddress]
        );
        _pegOutCollateral[quote.lpRskAddress] -= penalty;
        uint256 punisherReward = (penalty * _rewardPercentage) / 100;
        _penalties += penalty - punisherReward;
        _rewards[punisher] += punisherReward;
        emit Penalized(
            quote.lpRskAddress,
            punisher,
            quoteHash,
            Flyover.ProviderType.PegOut,
            penalty,
            punisherReward
        );
    }

    function withdrawCollateral() external nonReentrant override {
        address providerAddress = msg.sender;
        uint resignationBlock = _resignationBlockNum[providerAddress];
        if (resignationBlock < 1) revert NotResigned(providerAddress);
        if (block.number - resignationBlock < _resignDelayInBlocks) {
            revert ResignationDelayNotMet(providerAddress, resignationBlock, _resignDelayInBlocks);
        }

        uint256 amount = _pegOutCollateral[providerAddress] + _pegInCollateral[providerAddress];
        if (amount < 1) revert NothingToWithdraw(providerAddress);
        _pegOutCollateral[providerAddress] = 0;
        _pegInCollateral[providerAddress] = 0;
        _resignationBlockNum[providerAddress] = 0;

        emit WithdrawCollateral(providerAddress, amount);
        (bool success,) = providerAddress.call{value: amount}("");
        if (!success) revert WithdrawalFailed(providerAddress, amount);
    }

    function withdrawRewards(address addr) external override {
        if (addr == address(0)) revert Flyover.InvalidAddress(addr);
        uint256 rewards = _rewards[addr];
        if (rewards < 1) revert NothingToWithdraw(addr);
        _rewards[addr] = 0;
        emit RewardsWithdrawn(addr, rewards);
        (bool success,) = addr.call{value: rewards}("");
        if (!success) revert WithdrawalFailed(addr, rewards);
    }

    function resign() external override {
        address providerAddress = msg.sender;
        if (providerAddress == address(0)) revert Flyover.InvalidAddress(providerAddress);
        if (_resignationBlockNum[providerAddress] != 0) revert AlreadyResigned(providerAddress);
        if (_pegInCollateral[providerAddress] < 1 && _pegOutCollateral[providerAddress] < 1) {
            revert Flyover.ProviderNotRegistered(providerAddress);
        }
        _resignationBlockNum[providerAddress] = block.number;
        emit Resigned(providerAddress);
    }

    function getPegInCollateral(address addr) external view override returns (uint256) {
        return _pegInCollateral[addr];
    }

    function getPegOutCollateral(address addr) external view override returns (uint256) {
        return _pegOutCollateral[addr];
    }

    function getResignationBlock(address addr) external view override returns (uint256) {
        return _resignationBlockNum[addr];
    }

    function getRewardPercentage() external view override returns (uint256) {
        return _rewardPercentage;
    }

    function getResignDelayInBlocks() external view override returns (uint256) {
        return _resignDelayInBlocks;
    }

    function getMinCollateral() external view override returns (uint256) {
        return _minCollateral;
    }

    function isRegistered(Flyover.ProviderType providerType, address addr) external view override returns (bool) {
        return _isRegistered(providerType, addr);
    }

    function isCollateralSufficient(
        Flyover.ProviderType providerType,
        address addr
    ) external view override returns (bool) {
       if (providerType == Flyover.ProviderType.PegIn) {
            return _pegInCollateral[addr] > _minCollateral - 1 && _resignationBlockNum[addr] == 0;
        } else if (providerType == Flyover.ProviderType.PegOut) {
            return _pegOutCollateral[addr] > _minCollateral - 1 && _resignationBlockNum[addr] == 0;
        } else {
            return _pegInCollateral[addr] > _minCollateral - 1 &&
                _pegOutCollateral[addr] > _minCollateral - 1 &&
                _resignationBlockNum[addr] == 0;
        }
    }

    function getRewards(address addr) external view override returns (uint256) {
        return _rewards[addr];
    }

    function getPenalties() external view override returns (uint256) {
        return _penalties;
    }

    function _addPegInCollateralTo(address addr, uint256 amount) private {
        _pegInCollateral[addr] += amount;
        emit ICollateralManagement.PegInCollateralAdded(addr, amount);
    }

    function _addPegOutCollateralTo(address addr, uint256 amount) private {
        _pegOutCollateral[addr] += amount;
        emit ICollateralManagement.PegOutCollateralAdded(addr, amount);
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
}
