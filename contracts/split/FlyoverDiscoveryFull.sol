// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {IFlyoverDiscovery} from "../interfaces/IFlyoverDiscovery.sol";
import {ICollateralManagement} from "../interfaces/ICollateralManagement.sol";
import {Flyover} from "../libraries/Flyover.sol";
import {Quotes} from "../libraries/Quotes.sol";
import {
    AccessControlDefaultAdminRulesUpgradeable
} from "@openzeppelin/contracts-upgradeable/access/extensions/AccessControlDefaultAdminRulesUpgradeable.sol";
import {
    ReentrancyGuardUpgradeable
} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";

contract FlyoverDiscoveryFull is
    AccessControlDefaultAdminRulesUpgradeable,
    ReentrancyGuardUpgradeable,
    IFlyoverDiscovery,
    ICollateralManagement
{

    // ------------------------------------------------------------
    // FlyoverDiscovery State Variables
    // ------------------------------------------------------------

    mapping(uint => Flyover.LiquidityProvider) private _liquidityProviders;
    uint public lastProviderId;

    // ------------------------------------------------------------
    // Collateral Management State Variables
    // ------------------------------------------------------------

    bytes32 public constant COLLATERAL_SLASHER = keccak256("COLLATERAL_SLASHER");
    bytes32 public constant COLLATERAL_ADDER = keccak256("COLLATERAL_ADDER");

    event MinCollateralSet(uint256 oldMinCollateral, uint256 newMinCollateral);
    event ResignDelayInBlocksSet(uint oldResignDelayInBlocks, uint newResignDelayInBlocks);

    uint private _minCollateral;
    uint private _resignDelayInBlocks;
    mapping(address => uint256) private _pegInCollateral;
    mapping(address => uint256) private _pegOutCollateral;
    mapping(address => uint256) private _resignationBlockNum;
    mapping(address => uint256) private _rewards;
    uint256 public rewardPercentage;

    // ------------------------------------------------------------
    // FlyoverDiscovery Public Functions and Modifiers
    // ------------------------------------------------------------

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
        uint rewardPercentage_
    ) public initializer {
        __AccessControlDefaultAdminRules_init(initialDelay, owner);
        __ReentrancyGuard_init();
        _minCollateral = minCollateral;
        _resignDelayInBlocks = resignDelayInBlocks;
        rewardPercentage = rewardPercentage_;
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
        emit IFlyoverDiscovery.Register(lastProviderId, msg.sender, msg.value);

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

    function updateProvider(string memory name, string memory url) external {
        if (bytes(name).length <= 0 || bytes(url).length <= 0) revert InvalidProviderData(name, url);
        Flyover.LiquidityProvider storage lp;
        address providerAddress = msg.sender;
        for (uint i = 1; i <= lastProviderId; i++) {
            lp = _liquidityProviders[i];
            if (providerAddress == lp.providerAddress) {
                lp.name = name;
                lp.apiBaseUrl = url;
                emit IFlyoverDiscovery.ProviderUpdate(providerAddress, lp.name, lp.apiBaseUrl);
                return;
            }
        }
        revert Flyover.ProviderNotRegistered(providerAddress);
    }

    // ------------------------------------------------------------
    // FlyoverDiscovery Private Functions
    // ------------------------------------------------------------

    function _shouldBeListed(Flyover.LiquidityProvider storage lp) private view returns(bool){
        return _isRegistered(lp.providerType, lp.providerAddress) && lp.status;
    }

    function _validateRegistration(
        string memory name,
        string memory apiBaseUrl,
        Flyover.ProviderType providerType,
        address providerAddress
    ) private view {
        if (providerAddress != msg.sender || providerAddress.code.length != 0) revert NotEOA(providerAddress);

        if (
            bytes(name).length <= 0 ||
            bytes(apiBaseUrl).length <= 0
        ) {
            revert InvalidProviderData(name, apiBaseUrl);
        }

        if (providerType > type(Flyover.ProviderType).max) revert InvalidProviderType(providerType);

        if (
            _pegInCollateral[providerAddress] > 0 ||
            _pegOutCollateral[providerAddress] > 0 ||
            _resignationBlockNum[providerAddress] != 0
        ) {
            revert AlreadyRegistered(providerAddress);
        }
    }

    function _addCollateral(
        Flyover.ProviderType providerType,
        address providerAddress,
        uint amount
    ) private {
        if (providerType == Flyover.ProviderType.PegIn) {
            if (amount < _minCollateral) revert InsufficientCollateral(amount);
            _addPegInCollateralTo(providerAddress, amount);
        } else if (providerType == Flyover.ProviderType.PegOut) {
            if (amount < _minCollateral) revert InsufficientCollateral(amount);
            _addPegOutCollateralTo(providerAddress, amount);
        } else {
            if (amount < _minCollateral * 2) revert InsufficientCollateral(amount);
            uint halfMsgValue = amount / 2;
            _addPegInCollateralTo(providerAddress, amount % 2 == 0 ? halfMsgValue : halfMsgValue + 1);
            _addPegOutCollateralTo(providerAddress, halfMsgValue);
        }
    }

    function _getProvider(address providerAddress) private view returns (Flyover.LiquidityProvider memory) {
        for (uint i = 1; i <= lastProviderId; i++) {
            if (_liquidityProviders[i].providerAddress == providerAddress) {
                return _liquidityProviders[i];
            }
        }
        revert Flyover.ProviderNotRegistered(providerAddress);
    }

    // ------------------------------------------------------------
    // Collateral Management Public Functions and Modifiers
    // ------------------------------------------------------------

    function setMinCollateral(uint minCollateral) external onlyRole(DEFAULT_ADMIN_ROLE) {
        emit MinCollateralSet(_minCollateral, minCollateral);
        _minCollateral = minCollateral;
    }

    function setResignDelayInBlocks(uint resignDelayInBlocks) external onlyRole(DEFAULT_ADMIN_ROLE) {
        emit ResignDelayInBlocksSet(_resignDelayInBlocks, resignDelayInBlocks);
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

    function addPegInCollateralTo(address addr) external onlyRole(COLLATERAL_ADDER) payable {
        _addPegInCollateralTo(addr, msg.value);
    }

    function addPegInCollateral() external onlyRegisteredForPegIn payable {
        _addPegInCollateralTo(msg.sender, msg.value);
    }

    function addPegOutCollateralTo(address addr) external onlyRole(COLLATERAL_ADDER) payable {
        _addPegOutCollateralTo(addr, msg.value);
    }

    function addPegOutCollateral() external onlyRegisteredForPegOut payable {
        _addPegOutCollateralTo(msg.sender, msg.value);
    }

    function getMinCollateral() external view returns (uint) {
        return _minCollateral;
    }

    function isRegistered(Flyover.ProviderType providerType, address addr) external view returns (bool) {
        return _isRegistered(providerType, addr);
    }

    function isOperational(Flyover.ProviderType providerType, address addr) external view returns (bool) {
       return _isCollateralSufficient(providerType, addr) && _getProvider(addr).status;
    }

    function isCollateralSufficient(Flyover.ProviderType providerType, address addr) external view returns (bool) {
        return _isCollateralSufficient(providerType, addr);
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

    // ------------------------------------------------------------
    // Collateral Management Private Functions
    // ------------------------------------------------------------

    function _addPegInCollateralTo(address addr, uint amount) private {
        _pegInCollateral[addr] += amount;
        emit ICollateralManagement.PegInCollateralAdded(addr, amount);
    }

    function _addPegOutCollateralTo(address addr, uint amount) private {
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

    function _isCollateralSufficient(Flyover.ProviderType providerType, address addr) private view returns (bool) {
        if (providerType == Flyover.ProviderType.PegIn) {
            return _pegInCollateral[addr] >= _minCollateral &&
              _resignationBlockNum[addr] == 0;
        } else if (providerType == Flyover.ProviderType.PegOut) {
            return _pegOutCollateral[addr] >= _minCollateral &&
              _resignationBlockNum[addr] == 0;
        } else {
            return _pegInCollateral[addr] >= _minCollateral &&
              _pegOutCollateral[addr] >= _minCollateral &&
              _resignationBlockNum[addr] == 0;
        }
    }

    function slashPegInCollateral(
        address punisher,
        Quotes.PegInQuote calldata quote,
        bytes32 quoteHash
    ) external onlyRole(COLLATERAL_SLASHER) {
        uint penalty = _min(
            quote.penaltyFee,
            _pegInCollateral[quote.liquidityProviderRskAddress]
        );
        _pegInCollateral[quote.liquidityProviderRskAddress] -= penalty;
        uint256 punisherReward = (penalty * rewardPercentage) / 100;
        _rewards[punisher] += punisherReward;
        emit Penalized(quote.liquidityProviderRskAddress, punisher, quoteHash, Flyover.ProviderType.PegIn, penalty, punisherReward);
    }

    function slashPegOutCollateral(
        address punisher,
        Quotes.PegOutQuote calldata quote,
        bytes32 quoteHash
    ) external onlyRole(COLLATERAL_SLASHER) {
        uint penalty = _min(
            quote.penaltyFee,
            _pegOutCollateral[quote.lpRskAddress]
        );
        _pegOutCollateral[quote.lpRskAddress] -= penalty;
        uint256 punisherReward = (penalty * rewardPercentage) / 100;
        _rewards[punisher] += punisherReward;
        emit Penalized(quote.lpRskAddress, punisher, quoteHash, Flyover.ProviderType.PegOut, penalty, punisherReward);
    }

    function getRewards(address addr) external view returns (uint256) {
        return _rewards[addr];
    }

    function getPenalties() external pure returns (uint256) {
        return 0;
    }

    function getRewardPercentage() external pure returns (uint256) {
        return 0;
    }

    function getResignDelayInBlocks() external pure returns (uint256) {
        return 0;
    }

    function withdrawRewards() external {
        address addr = msg.sender;
        uint256 rewards = _rewards[addr];
        if (rewards < 1) revert NothingToWithdraw(addr);
        _rewards[addr] = 0;
        emit RewardsWithdrawn(addr, rewards);
        (bool success,) = addr.call{value: rewards}("");
        if (!success) revert WithdrawalFailed(addr, rewards);
    }

    function _min(uint a, uint b) private pure returns (uint) {
        return a < b ? a : b;
    }
}
