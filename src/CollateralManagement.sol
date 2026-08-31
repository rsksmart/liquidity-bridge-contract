// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {
    AccessControlDefaultAdminRulesUpgradeable
} from "@openzeppelin/contracts-upgradeable/access/extensions/AccessControlDefaultAdminRulesUpgradeable.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {EmergencyPause} from "./EmergencyPause/EmergencyPause.sol";
import {ICollateralManagement} from "./interfaces/ICollateralManagement.sol";
import {IFlyoverDiscovery} from "./interfaces/IFlyoverDiscovery.sol";
import {IPauseRegistry} from "./interfaces/IPauseRegistry.sol";
import {Flyover} from "./libraries/Flyover.sol";
import {Quotes} from "./libraries/Quotes.sol";

/// @title Collateral Management
/// @notice This contract is used to manage the collateral related aspects of the Flyover system.
/// This involves adding, slashing, resigning and withdrawing collateral.
/// @author Rootstock Labs
// solhint-disable-next-line max-states-count
contract CollateralManagementContract is
    AccessControlDefaultAdminRulesUpgradeable,
    ReentrancyGuard,
    EmergencyPause,
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
    uint256 public constant TOTAL_REWARD_PERCENTAGE = 10_000;

    uint256 private _minCollateral;
    uint256 private _resignDelayInBlocks;
    uint256 private _rewardPercentage;
    uint256 private _penalties;
    mapping(address => uint256) private _pegInCollateral;
    mapping(address => uint256) private _pegOutCollateral;
    mapping(address => uint256) private _resignationBlockNum;
    mapping(address => uint256) private _rewards;

    /// @dev FlyoverDiscovery is the source of truth for the listed provider set.
    IFlyoverDiscovery private _flyoverDiscovery;
    /// @dev Block at which peg-out collateral first became positive; used by the grace window.
    mapping(address => uint256) private _pegOutRegistrationBlock;
    uint256 private _globalSlashGraceBlocks;

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
    /// @notice Emitted when the global-slash grace window is set
    /// @param oldGraceBlocks The previous grace window in blocks
    /// @param newGraceBlocks The new grace window in blocks
    event GlobalSlashGraceBlocksSet(uint256 indexed oldGraceBlocks, uint256 indexed newGraceBlocks);
    /// @notice Emitted when the FlyoverDiscovery address used for the provider set is updated
    /// @param oldAddress The previous Discovery address
    /// @param newAddress The new Discovery address
    event FlyoverDiscoverySet(address indexed oldAddress, address indexed newAddress);

    /// @notice Raised when {globalSlash} is called before FlyoverDiscovery is wired
    error FlyoverDiscoveryNotSet();

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

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    // solhint-disable-next-line comprehensive-interface
    receive() external payable {
        revert Flyover.PaymentNotAllowed();
    }

    /// @inheritdoc ICollateralManagement
    function addPegInCollateralTo(address addr) external onlyRole(COLLATERAL_ADDER) whenNotSoftPaused payable override {
        _addPegInCollateralTo(addr, msg.value);
    }

    /// @inheritdoc ICollateralManagement
    function addPegInCollateral() external whenNotSoftPaused onlyRegisteredForPegIn(msg.sender) payable override {
        _addPegInCollateralTo(msg.sender, msg.value);
    }

    /// @inheritdoc ICollateralManagement
    function addPegOutCollateralTo(address addr)
        external
        whenNotSoftPaused
        onlyRole(COLLATERAL_ADDER)
        payable
        override
    {
        _addPegOutCollateralTo(addr, msg.value);
    }

    /// @inheritdoc ICollateralManagement
    function addPegOutCollateral() external whenNotSoftPaused onlyRegisteredForPegOut(msg.sender) payable override {
        _addPegOutCollateralTo(msg.sender, msg.value);
    }

    /// @notice Initializes the contract
    /// @param defaultAdmin The default admin of the contract
    /// @param initialDelay The initial delay for changes in the default admin role
    /// @param minCollateral The minimum collateral required for a liquidity provider **per operation**
    /// @param resignDelayInBlocks The delay in blocks before a liquidity provider can withdraw their collateral
    /// @param rewardPercentage The reward percentage from the penalty fee of the quotes that the punisher will receive
    /// @param pauseRegistry The central PauseRegistry for pause state
    // solhint-disable-next-line comprehensive-interface
    function initialize(
        address defaultAdmin,
        uint48 initialDelay,
        uint256 minCollateral,
        uint256 resignDelayInBlocks,
        uint256 rewardPercentage,
        IPauseRegistry pauseRegistry
    ) external initializer {
        if (rewardPercentage > TOTAL_REWARD_PERCENTAGE) {
            revert InvalidRewardPercentage(TOTAL_REWARD_PERCENTAGE, rewardPercentage);
        }
        if (minCollateral < 1) revert MinCollateralTooLow(minCollateral);
        if (address(pauseRegistry).code.length == 0) revert Flyover.NoContract(address(pauseRegistry));
        __AccessControlDefaultAdminRules_init(initialDelay, defaultAdmin);
        __EmergencyPause_init(pauseRegistry);
        _minCollateral = minCollateral;
        _resignDelayInBlocks = resignDelayInBlocks;
        _rewardPercentage = rewardPercentage;
    }

    /// @notice Sets the minimum collateral required for a liquidity provider **per operation**
    /// @param minCollateral The new minimum collateral
    // solhint-disable-next-line comprehensive-interface
    function setMinCollateral(uint minCollateral) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (minCollateral < 1) revert MinCollateralTooLow(minCollateral);
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
        if (rewardPercentage > TOTAL_REWARD_PERCENTAGE) {
            revert InvalidRewardPercentage(TOTAL_REWARD_PERCENTAGE, rewardPercentage);
        }
        emit RewardPercentageSet(_rewardPercentage, rewardPercentage);
        _rewardPercentage = rewardPercentage;
    }

    /// @notice Sets the no-penalty grace window (blocks after peg-out registration) for global slash
    /// @dev Default is 0 (no LP is in-window until configured).
    /// @param graceBlocks The new grace window length in blocks
    // solhint-disable-next-line comprehensive-interface
    function setGlobalSlashGraceBlocks(uint256 graceBlocks) external onlyRole(DEFAULT_ADMIN_ROLE) {
        emit GlobalSlashGraceBlocksSet(_globalSlashGraceBlocks, graceBlocks);
        _globalSlashGraceBlocks = graceBlocks;
    }

    /// @notice Sets the FlyoverDiscovery used as the provider-set source of truth for {globalSlash}
    /// @param flyoverDiscovery_ The Discovery contract address
    // solhint-disable-next-line comprehensive-interface
    function setFlyoverDiscovery(address flyoverDiscovery_) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (flyoverDiscovery_.code.length == 0) revert Flyover.NoContract(flyoverDiscovery_);
        emit FlyoverDiscoverySet(address(_flyoverDiscovery), flyoverDiscovery_);
        _flyoverDiscovery = IFlyoverDiscovery(flyoverDiscovery_);
    }

    /// @inheritdoc ICollateralManagement
    /// @dev Intentionally not paused: slashing must remain available so PegIn/PegOut can enforce penalties
    ///      when they call this during registerPegIn/refundPegOut; a separate pause would cause reverts.
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
        uint256 punisherReward = (penalty * _rewardPercentage) / TOTAL_REWARD_PERCENTAGE;
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
    /// @dev Intentionally not paused: slashing must remain available so PegIn/PegOut can enforce penalties
    ///      when they call this during registerPegIn/refundPegOut; a separate pause would cause reverts.
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
        uint256 punisherReward = (penalty * _rewardPercentage) / TOTAL_REWARD_PERCENTAGE;
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
    /// @dev Intentionally not paused: slashing must remain available so PegOutEscrow can
    ///      enforce penalties from refundOnNoClaim. Provider set is FlyoverDiscovery.getProviders.
    function globalSlash(uint256 total) external onlyRole(COLLATERAL_SLASHER) override {
        if (total == 0) revert GlobalSlashZeroAmount();
        if (address(_flyoverDiscovery) == address(0)) revert FlyoverDiscoveryNotSet();

        (address[] memory lps, uint256[] memory amounts, uint256 sum, uint256 n) =
            _eligiblePegOutProviders();
        if (sum == 0) revert GlobalSlashNoEligibleProviders();

        _distributeGlobalSlash(total, lps, amounts, sum, n);
    }

    /// @inheritdoc ICollateralManagement
    function withdrawCollateral() external nonReentrant whenNotHardPaused override {
        _withdrawCollateralTo(payable(msg.sender));
    }

    /// @inheritdoc ICollateralManagement
    function withdrawCollateral(address payable to) external nonReentrant whenNotHardPaused override {
        _withdrawCollateralTo(to);
    }

    /// @inheritdoc ICollateralManagement
    function withdrawRewards() external nonReentrant whenNotHardPaused override {
        _withdrawRewardsTo(payable(msg.sender));
    }

    /// @inheritdoc ICollateralManagement
    function withdrawRewards(address payable to) external nonReentrant whenNotHardPaused override {
        _withdrawRewardsTo(to);
    }

    /// @inheritdoc ICollateralManagement
    function resign() external whenNotHardPaused override {
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

    /// @notice Gets the no-penalty grace window used by {globalSlash}
    /// @return The grace window length in blocks
    // solhint-disable-next-line comprehensive-interface
    function getGlobalSlashGraceBlocks() external view returns (uint256) {
        return _globalSlashGraceBlocks;
    }

    /// @notice Gets the block at which an account's peg-out collateral first became positive
    /// @dev Zero means no recorded registration (pre-upgrade / never registered for peg-out).
    /// @param addr The liquidity provider address
    /// @return The registration block, or 0 if unset
    // solhint-disable-next-line comprehensive-interface
    function getPegOutRegistrationBlock(address addr) external view returns (uint256) {
        return _pegOutRegistrationBlock[addr];
    }

    /// @notice Gets the FlyoverDiscovery used as the provider-set source of truth
    /// @return The Discovery contract address (zero if unset)
    // solhint-disable-next-line comprehensive-interface
    function getFlyoverDiscovery() external view returns (address) {
        return address(_flyoverDiscovery);
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

    function _withdrawRewardsTo(address payable to) private {
        if (to == address(0)) revert Flyover.InvalidAddress(to);
        address addr = msg.sender;
        uint256 rewards = _rewards[addr];
        if (rewards < 1) revert NothingToWithdraw(addr);
        _rewards[addr] = 0;
        emit RewardsWithdrawn(addr, to, rewards);
        (bool success,) = to.call{value: rewards}("");
        if (!success) revert WithdrawalFailed(to, rewards);
    }

    function _withdrawCollateralTo(address payable to) private {
        if (to == address(0)) revert Flyover.InvalidAddress(to);
        address providerAddress = msg.sender;
        uint256 resignationBlock = _resignationBlockNum[providerAddress];
        if (resignationBlock < 1) revert NotResigned(providerAddress);
        uint256 pauseBlocks = pauseRegistry().computePauseOverlapBlocks(resignationBlock, block.number);
        if (block.number - resignationBlock - pauseBlocks < _resignDelayInBlocks) {
            revert ResignationDelayNotMet(providerAddress, resignationBlock, _resignDelayInBlocks);
        }

        uint256 amount = _pegOutCollateral[providerAddress] + _pegInCollateral[providerAddress];
        if (amount < 1) {
            _resignationBlockNum[providerAddress] = 0;
            return;
        }
        _pegOutCollateral[providerAddress] = 0;
        _pegInCollateral[providerAddress] = 0;
        _resignationBlockNum[providerAddress] = 0;

        emit WithdrawCollateral(providerAddress, to, amount);
        (bool success,) = to.call{value: amount}("");
        if (!success) revert WithdrawalFailed(to, amount);
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
    /// is the one protected by the role checks. Records the registration block on first
    /// peg-out collateral for the global-slash grace window.
    /// @param addr The address of the account
    /// @param amount The amount of peg out collateral to add
    function _addPegOutCollateralTo(address addr, uint256 amount) private {
        if (_pegOutCollateral[addr] == 0 && amount > 0) {
            _pegOutRegistrationBlock[addr] = block.number;
        }
        _pegOutCollateral[addr] += amount;
        emit ICollateralManagement.PegOutCollateralAdded(addr, amount);
    }

    /// @notice Takes `min(total, sum)` from eligible LPs proportional to peg-out collateral.
    /// @dev Last LP receives the remainder, capped at their collateral, so rounding dust stays in the split.
    /// TODO: Confirm whether global slash should stay proportional to collateral
    /// or move to an equal/fixed split
    /// @param total Requested slash amount
    /// @param lps Eligible provider addresses
    /// @param amounts Peg-out collateral of each eligible provider
    /// @param sum Total peg-out collateral of eligible providers
    /// @param n Number of eligible providers
    function _distributeGlobalSlash(
        uint256 total,
        address[] memory lps,
        uint256[] memory amounts,
        uint256 sum,
        uint256 n
    ) private {
        uint256 toTake = Math.min(total, sum);
        uint256 distributed;
        for (uint256 i; i < n; ++i) {
            uint256 share = (i == n - 1)
                ? Math.min(toTake - distributed, amounts[i])
                : (toTake * amounts[i]) / sum;
            if (share == 0) continue;
            _pegOutCollateral[lps[i]] -= share;
            distributed += share;
            emit GlobalSlashShare(lps[i], share);
        }
        _penalties += distributed;
        emit GlobalSlashExecuted(total, distributed);
    }

    /// @notice Listed PegOut/Both LPs outside the grace window, with their peg-out collateral.
    /// @dev Arrays are sized to `getProviders().length`; only the first `n` entries are populated.
    /// @return lps Eligible provider addresses
    /// @return amounts Peg-out collateral of each eligible provider
    /// @return sum Total peg-out collateral of eligible providers
    /// @return n Number of eligible providers
    function _eligiblePegOutProviders()
        private
        view
        returns (address[] memory lps, uint256[] memory amounts, uint256 sum, uint256 n)
    {
        Flyover.LiquidityProvider[] memory providers = _flyoverDiscovery.getProviders();
        uint256 length = providers.length;
        lps = new address[](length);
        amounts = new uint256[](length);

        for (uint256 i; i < length; ++i) {
            if (providers[i].providerType == Flyover.ProviderType.PegIn) continue;
            address lp = providers[i].providerAddress;
            if (_isInGlobalSlashGraceWindow(lp)) continue;
            lps[n] = lp;
            amounts[n] = _pegOutCollateral[lp];
            sum += amounts[n];
            ++n;
        }
    }

    /// @notice Whether an LP is still inside the global-slash grace window
    /// @dev `regBlock == 0` (never recorded) is eligible, not in grace.
    /// @param addr The liquidity provider address
    /// @return True if the LP must be skipped by {globalSlash}
    function _isInGlobalSlashGraceWindow(address addr) private view returns (bool) {
        uint256 regBlock = _pegOutRegistrationBlock[addr];
        if (regBlock == 0) return false;
        return block.number < regBlock + _globalSlashGraceBlocks;
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
