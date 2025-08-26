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

/// @title Collateral Management
/// @notice This contract is used to manage the collateral related aspects of the Flyover system.
/// This involves adding, slashing, resigning and withdrawing collateral.
/// @author Rootstock Labs
contract CollateralManagementContract is
    AccessControlDefaultAdminRulesUpgradeable,
    ReentrancyGuardUpgradeable,
    ICollateralManagement
{
    /// @notice The version of the contract
    string constant public VERSION = "1.0.0";

    /// @notice The role that can add collateral to the contract by using
    /// the addPegInCollateralTo or addPegOutCollateralTo functions
    bytes32 public constant COLLATERAL_ADDER = keccak256("COLLATERAL_ADDER");
    /// @notice The role that can slash collateral from the contract by using
    /// the slashPegInCollateral or slashPegOutCollateral functions
    bytes32 public constant COLLATERAL_SLASHER = keccak256("COLLATERAL_SLASHER");

    uint256 private _minCollateral;
    uint256 private _resignDelayInBlocks;
    uint256 private _rewardPercentage;
    uint256 private _penalties;
    mapping(address => uint256) private _pegInCollateral;
    mapping(address => uint256) private _pegOutCollateral;
    mapping(address => uint256) private _resignationBlockNum;
    mapping(address => uint256) private _rewards;

    /// @notice Emitted when the minimum collateral is set
    /// @param oldMinCollateral The old minimum collateral
    /// @param newMinCollateral The new minimum collateral
    event MinCollateralSet(uint256 indexed oldMinCollateral, uint256 indexed newMinCollateral);
    /// @notice Emitted when the resignation delay in blocks is set
    /// @param oldResignDelayInBlocks The old resignation delay in blocks
    /// @param newResignDelayInBlocks The new resignation delay in blocks
    event ResignDelayInBlocksSet(uint256 indexed oldResignDelayInBlocks, uint256 indexed newResignDelayInBlocks);
    /// @notice Emitted when the reward percentage is set
    /// @param oldReward The old reward percentage
    /// @param newReward The new reward percentage
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

    /// @inheritdoc ICollateralManagement
    function addPegInCollateralTo(address addr) external onlyRole(COLLATERAL_ADDER) payable override {
        _addPegInCollateralTo(addr, msg.value);
    }

    /// @inheritdoc ICollateralManagement
    function addPegInCollateral() external onlyRegisteredForPegIn(msg.sender) payable override {
        _addPegInCollateralTo(msg.sender, msg.value);
    }

    /// @inheritdoc ICollateralManagement
    function addPegOutCollateralTo(address addr) external onlyRole(COLLATERAL_ADDER) payable override {
        _addPegOutCollateralTo(addr, msg.value);
    }

    /// @inheritdoc ICollateralManagement
    function addPegOutCollateral() external onlyRegisteredForPegOut(msg.sender) payable override {
        _addPegOutCollateralTo(msg.sender, msg.value);
    }

    /// @notice Initializes the contract
    /// @param owner The owner of the contract
    /// @param initialDelay The initial delay for changes in the default admin role
    /// @param minCollateral The minimum collateral required for a liquidity provider **per operation**
    /// @param resignDelayInBlocks The delay in blocks before a liquidity provider can withdraw their collateral
    /// @param rewardPercentage The reward percentage from the penalty fee of the quotes that the punisher will receive
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

    /// @notice Sets the minimum collateral required for a liquidity provider **per operation**
    /// @param minCollateral The new minimum collateral
    // solhint-disable-next-line comprehensive-interface
    function setMinCollateral(uint minCollateral) external onlyRole(DEFAULT_ADMIN_ROLE) {
        emit MinCollateralSet(_minCollateral, minCollateral);
        _minCollateral = minCollateral;
    }

    /// @notice Sets the resignation delay in blocks
    /// @param resignDelayInBlocks The new resignation delay in blocks
    // solhint-disable-next-line comprehensive-interface
    function setResignDelayInBlocks(uint resignDelayInBlocks) external onlyRole(DEFAULT_ADMIN_ROLE) {
        emit ResignDelayInBlocksSet(_resignDelayInBlocks, resignDelayInBlocks);
        _resignDelayInBlocks = resignDelayInBlocks;
    }

    /// @notice Sets the reward percentage from the penalty fee of the quotes that the punisher will receive
    /// @param rewardPercentage The new reward percentage
    // solhint-disable-next-line comprehensive-interface
    function setRewardPercentage(uint256 rewardPercentage) external onlyRole(DEFAULT_ADMIN_ROLE) {
        emit RewardPercentageSet(_rewardPercentage, rewardPercentage);
        _rewardPercentage = rewardPercentage;
    }

    /// @inheritdoc ICollateralManagement
    function slashPegInCollateral(
        address punisher,
        Quotes.PegInQuote calldata quote,
        bytes32 quoteHash
    ) external onlyRole(COLLATERAL_SLASHER) override {
        uint256 penalty = Math.min(
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

    /// @inheritdoc ICollateralManagement
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

    /// @inheritdoc ICollateralManagement
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

    /// @inheritdoc ICollateralManagement
    function withdrawRewards() external override {
        address addr = msg.sender;
        uint256 rewards = _rewards[addr];
        if (rewards < 1) revert NothingToWithdraw(addr);
        _rewards[addr] = 0;
        emit RewardsWithdrawn(addr, rewards);
        (bool success,) = addr.call{value: rewards}("");
        if (!success) revert WithdrawalFailed(addr, rewards);
    }

    /// @inheritdoc ICollateralManagement
    function resign() external override {
        address providerAddress = msg.sender;
        if (_resignationBlockNum[providerAddress] != 0) revert AlreadyResigned(providerAddress);
        if (_pegInCollateral[providerAddress] < 1 && _pegOutCollateral[providerAddress] < 1) {
            revert Flyover.ProviderNotRegistered(providerAddress);
        }
        _resignationBlockNum[providerAddress] = block.number;
        emit Resigned(providerAddress);
    }

    /// @inheritdoc ICollateralManagement
    function getPegInCollateral(address addr) external view override returns (uint256) {
        return _pegInCollateral[addr];
    }

    /// @inheritdoc ICollateralManagement
    function getPegOutCollateral(address addr) external view override returns (uint256) {
        return _pegOutCollateral[addr];
    }

    /// @inheritdoc ICollateralManagement
    function getResignationBlock(address addr) external view override returns (uint256) {
        return _resignationBlockNum[addr];
    }

    /// @inheritdoc ICollateralManagement
    function getRewardPercentage() external view override returns (uint256) {
        return _rewardPercentage;
    }

    /// @inheritdoc ICollateralManagement
    function getResignDelayInBlocks() external view override returns (uint256) {
        return _resignDelayInBlocks;
    }

    /// @inheritdoc ICollateralManagement
    function getMinCollateral() external view override returns (uint256) {
        return _minCollateral;
    }

    /// @inheritdoc ICollateralManagement
    function isRegistered(Flyover.ProviderType providerType, address addr) external view override returns (bool) {
        return _isRegistered(providerType, addr);
    }

    /// @inheritdoc ICollateralManagement
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

    /// @inheritdoc ICollateralManagement
    function getRewards(address addr) external view override returns (uint256) {
        return _rewards[addr];
    }

    /// @inheritdoc ICollateralManagement
    function getPenalties() external view override returns (uint256) {
        return _penalties;
    }

    /// @notice Adds peg in collateral to an account
    /// @dev Is very important for this function to remain private as the public function
    /// is the one protected by the role checks
    /// @param addr The address of the account
    /// @param amount The amount of peg in collateral to add
    function _addPegInCollateralTo(address addr, uint256 amount) private {
        _pegInCollateral[addr] += amount;
        emit ICollateralManagement.PegInCollateralAdded(addr, amount);
    }

    /// @notice Adds peg out collateral to an account
    /// @dev Is very important for this function to remain private as the public function
    /// is the one protected by the role checks
    /// @param addr The address of the account
    /// @param amount The amount of peg out collateral to add
    function _addPegOutCollateralTo(address addr, uint256 amount) private {
        _pegOutCollateral[addr] += amount;
        emit ICollateralManagement.PegOutCollateralAdded(addr, amount);
    }

    /// @notice Checks if an account is registered
    /// @dev Registered means having added collateral to the contract and not having resigned
    /// @param providerType The type of provider
    /// @param addr The address of the account
    /// @return True if the account is registered, false otherwise
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
