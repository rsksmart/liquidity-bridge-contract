// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {
    AccessControlDefaultAdminRulesUpgradeable
} from "@openzeppelin/contracts-upgradeable/access/extensions/AccessControlDefaultAdminRulesUpgradeable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {EmergencyPause} from "./EmergencyPause/EmergencyPause.sol";
import {ICollateralManagement} from "./interfaces/ICollateralManagement.sol";
import {IPauseRegistry} from "./interfaces/IPauseRegistry.sol";
import {Flyover} from "./libraries/Flyover.sol";
import {Quotes} from "./libraries/Quotes.sol";

/// @title Collateral Management
/// @notice This contract is used to manage the collateral related aspects of the Flyover system.
/// This involves adding, slashing, resigning and withdrawing collateral.
/// @author Rootstock Labs
contract CollateralManagementContract is
    AccessControlDefaultAdminRulesUpgradeable,
    ReentrancyGuard,
    EmergencyPause,
    ICollateralManagement
{
    using EnumerableSet for EnumerableSet.AddressSet;

    /// @notice The version of the contract
    string constant public VERSION = "1.0.0";

    /// @notice Default registration grace window in blocks (S0.3 provisional value).
    /// A freshly registered LP is exempt from a global slash while it is inside this window.
    uint256 public constant DEFAULT_GRACE_WINDOW = 100;

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

    // ------------------------------------------------------------
    // E3 global-slash / grace-window state.
    // Appended after the pre-existing fields above to preserve the storage
    // layout of the upgradeable contract (existing slots are never reordered).
    // ------------------------------------------------------------

    /// @notice Set of currently registered LPs. Added on the registration path,
    /// removed on resign or full collateral withdrawal.
    EnumerableSet.AddressSet private _registeredLPs;
    /// @notice Block number at which each LP was (most recently) registered.
    mapping(address => uint256) private _registrationBlock;
    /// @notice Number of blocks a freshly registered LP is exempt from a global slash.
    uint256 private _graceWindow;

    /// @notice Emitted when the grace window is set
    /// @param oldGraceWindow The old grace window in blocks
    /// @param newGraceWindow The new grace window in blocks
    event GraceWindowSet(uint256 indexed oldGraceWindow, uint256 indexed newGraceWindow);

    /// @notice Thrown when globalSlash is called with a zero total
    error InvalidGlobalSlashAmount();
    /// @notice Thrown when globalSlash finds no past-grace LP collateral to slash
    error NoEligibleCollateral();

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
        if (address(pauseRegistry).code.length == 0) revert Flyover.NoContract(address(pauseRegistry));
        __AccessControlDefaultAdminRules_init(initialDelay, defaultAdmin);
        __EmergencyPause_init(pauseRegistry);
        _minCollateral = minCollateral;
        _resignDelayInBlocks = resignDelayInBlocks;
        _rewardPercentage = rewardPercentage;
        _graceWindow = DEFAULT_GRACE_WINDOW;
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
        if (rewardPercentage > TOTAL_REWARD_PERCENTAGE) {
            revert InvalidRewardPercentage(TOTAL_REWARD_PERCENTAGE, rewardPercentage);
        }
        emit RewardPercentageSet(_rewardPercentage, rewardPercentage);
        _rewardPercentage = rewardPercentage;
    }

    /// @notice Sets the registration grace window in blocks. A freshly registered LP whose
    /// `block.number <= registrationBlock + graceWindow` is exempt from a global slash.
    /// @dev Restricted to DEFAULT_ADMIN_ROLE, matching the existing time-locked setter style
    /// (the admin role transitions are governed by AccessControlDefaultAdminRules).
    /// @param graceWindow The new grace window in blocks
    // solhint-disable-next-line comprehensive-interface
    function setGraceWindow(uint256 graceWindow) external onlyRole(DEFAULT_ADMIN_ROLE) {
        emit GraceWindowSet(_graceWindow, graceWindow);
        _graceWindow = graceWindow;
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

    /// @notice Distributes a total penalty proportionally across all registered LPs that are
    /// past their grace window, reusing the existing reward/penalty split.
    /// @dev Eligible LPs are those with `block.number > registrationBlock[lp] + graceWindow`.
    /// Each eligible LP is reduced by `total * lpCollateral / sumEligible` (capped at its
    /// collateral). LPs inside their grace window are skipped and excluded from the
    /// denominator. Reverts if there is no eligible collateral to slash.
    /// Not paused, consistent with the individual slash functions.
    /// @param total The total penalty to distribute (S0.3: one penaltyFee).
    function globalSlash(uint256 total) external onlyRole(COLLATERAL_SLASHER) override {
        if (total == 0) revert InvalidGlobalSlashAmount();

        uint256 length = _registeredLPs.length();

        // First pass: sum collateral of eligible (past-grace) LPs.
        uint256 sumEligible = 0;
        for (uint256 i = 0; i < length; ++i) {
            address lp = _registeredLPs.at(i);
            if (_isPastGraceWindow(lp)) {
                sumEligible += _lpCollateral(lp);
            }
        }
        if (sumEligible == 0) revert NoEligibleCollateral();

        // Second pass: reduce each eligible LP proportionally and split per the
        // existing reward/penalty scheme.
        for (uint256 i = 0; i < length; ++i) {
            address lp = _registeredLPs.at(i);
            if (!_isPastGraceWindow(lp)) continue;

            uint256 lpCollateral = _lpCollateral(lp);
            if (lpCollateral == 0) continue;

            // Proportional share, capped at the LP's collateral.
            uint256 penalty = Math.min((total * lpCollateral) / sumEligible, lpCollateral);
            if (penalty == 0) continue;

            // Reduce peg-in first, then peg-out, to drain the LP's total collateral.
            uint256 fromPegIn = Math.min(penalty, _pegInCollateral[lp]);
            _pegInCollateral[lp] -= fromPegIn;
            uint256 fromPegOut = penalty - fromPegIn;
            if (fromPegOut > 0) {
                _pegOutCollateral[lp] -= fromPegOut;
            }

            uint256 punisherReward = (penalty * _rewardPercentage) / TOTAL_REWARD_PERCENTAGE;
            _penalties += penalty - punisherReward;
            _rewards[msg.sender] += punisherReward;

            emit Penalized(
                lp,
                msg.sender,
                bytes32(0),
                Flyover.ProviderType.Both,
                penalty,
                punisherReward
            );
        }
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
        _deregisterLP(providerAddress);
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

    /// @notice The number of currently registered LPs in the enumerable set.
    /// @return The set size
    // solhint-disable-next-line comprehensive-interface
    function registeredLPCount() external view returns (uint256) {
        return _registeredLPs.length();
    }

    /// @notice Whether the given address is in the registered-LP set.
    /// @param addr The address to check
    /// @return True if the address is a registered LP
    // solhint-disable-next-line comprehensive-interface
    function isRegisteredLP(address addr) external view returns (bool) {
        return _registeredLPs.contains(addr);
    }

    /// @notice The block at which the given LP was registered (0 if not registered).
    /// @param addr The LP address
    /// @return The registration block number
    // solhint-disable-next-line comprehensive-interface
    function getRegistrationBlock(address addr) external view returns (uint256) {
        return _registrationBlock[addr];
    }

    /// @notice The current registration grace window in blocks.
    /// @return The grace window
    // solhint-disable-next-line comprehensive-interface
    function getGraceWindow() external view returns (uint256) {
        return _graceWindow;
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
        if (amount < 1) revert NothingToWithdraw(providerAddress);
        _pegOutCollateral[providerAddress] = 0;
        _pegInCollateral[providerAddress] = 0;
        _resignationBlockNum[providerAddress] = 0;
        // Full withdrawal: ensure the LP is out of the registered set (normally
        // already removed at resign, which is a prerequisite for withdrawal).
        _deregisterLP(providerAddress);

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
        _registerLP(addr);
        emit ICollateralManagement.PegInCollateralAdded(addr, amount);
    }

    /// @notice Adds peg out collateral to an account
    /// @dev Is very important for this function to remain private as the public function
    /// is the one protected by the role checks
    /// @param addr The address of the account
    /// @param amount The amount of peg out collateral to add
    function _addPegOutCollateralTo(address addr, uint256 amount) private {
        _pegOutCollateral[addr] += amount;
        _registerLP(addr);
        emit ICollateralManagement.PegOutCollateralAdded(addr, amount);
    }

    /// @notice Adds an LP to the registered-LP set on its first registration and
    /// records the registration block. No-op if the LP is already in the set, so a
    /// later top-up does not reset its grace window.
    /// @param addr The address of the LP
    function _registerLP(address addr) private {
        if (_registeredLPs.add(addr)) {
            _registrationBlock[addr] = block.number;
        }
    }

    /// @notice Removes an LP from the registered-LP set and clears its registration block.
    /// @param addr The address of the LP
    function _deregisterLP(address addr) private {
        if (_registeredLPs.remove(addr)) {
            _registrationBlock[addr] = 0;
        }
    }

    /// @notice True if the LP is past its registration grace window and so is eligible
    /// for a global slash. Boundary: an LP at exactly registrationBlock + graceWindow is
    /// still in grace; one block later it is eligible.
    /// @param lp The LP address
    /// @return True if `block.number > registrationBlock[lp] + graceWindow`
    function _isPastGraceWindow(address lp) private view returns (bool) {
        return block.number > _registrationBlock[lp] + _graceWindow;
    }

    /// @notice The total (peg-in + peg-out) collateral held by an LP.
    /// @param lp The LP address
    /// @return The combined collateral
    function _lpCollateral(address lp) private view returns (uint256) {
        return _pegInCollateral[lp] + _pegOutCollateral[lp];
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
