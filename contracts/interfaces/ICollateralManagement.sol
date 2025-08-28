// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Flyover} from "../libraries/Flyover.sol";
import {Quotes} from "../libraries/Quotes.sol";

event CollateralManagementSet(address indexed oldAddress, address indexed newAddress);

/// @title Collateral Management interface
/// @notice This interface is used to expose the required functions to
/// provide the Flyover collateral management service.
/// This involves, slashing, resigning and registering processes.
interface ICollateralManagement {

    /// @notice Emitted when the collateral is withdrawn
    /// @param addr The address of the liquidity provider
    /// @param amount The amount of collateral withdrawn
    event WithdrawCollateral(address indexed addr, uint indexed amount);

    /// @notice Emitted when the liquidity provider resigns
    /// @param addr The address of the liquidity provider
    event Resigned(address indexed addr);

    /// @notice Emitted when the rewards are withdrawn by a punisher
    /// @param addr The address of the punisher
    /// @param amount The amount of rewards withdrawn
    event RewardsWithdrawn(address indexed addr, uint256 indexed amount);

    /// @notice Emitted when the peg in collateral is added
    /// @param addr The address of the liquidity provider
    /// @param amount The amount of peg in collateral added
    event PegInCollateralAdded(address indexed addr, uint256 indexed amount);

    /// @notice Emitted when the peg out collateral is added
    /// @param addr The address of the liquidity provider
    /// @param amount The amount of peg out collateral added
    event PegOutCollateralAdded(address indexed addr, uint256 indexed amount);

    /// @notice Emitted when a liquidity provider is penalized by not behaving as expected
    /// @param liquidityProvider The address of the liquidity provider
    /// @param punisher The address of the punisher
    /// @param quoteHash The hash of the quote
    /// @param collateralType The type of collateral
    /// @param penalty The penalty amount for the liquidity provider
    /// @param reward The reward amount for the punisher
    event Penalized(
        address indexed liquidityProvider,
        address indexed punisher,
        bytes32 indexed quoteHash,
        Flyover.ProviderType collateralType,
        uint256 penalty,
        uint256 reward
    );

    /// @notice Emitted when a liquidity provider has already resigned
    /// @param from The address of the liquidity provider
    error AlreadyResigned(address from);

    /// @notice Emitted when a liquidity provider has not resigned yet
    /// @param from The address of the liquidity provider
    error NotResigned(address from);

    /// @notice Emitted when a liquidity provider has not resigned yet
    /// @param from The address of the liquidity provider
    /// @param resignationBlockNum The block number at which the liquidity provider resigned
    /// @param resignDelayInBlocks The delay in blocks before a liquidity provider can withdraw their collateral
    error ResignationDelayNotMet(address from, uint resignationBlockNum, uint resignDelayInBlocks);

    /// @notice Emitted when a liquidity provider tries to withdraw collateral but the withdrawal fails
    /// @param from The address of the liquidity provider
    /// @param amount The amount of collateral that was attempted to be withdrawn
    error WithdrawalFailed(address from, uint amount);

    /// @notice Emitted when a liquidity provider tries to withdraw collateral but has nothing to withdraw
    /// @param from The address of the liquidity provider
    error NothingToWithdraw(address from);

    /// @notice Adds peg in collateral to an account
    /// @param addr The address of the account
    /// @dev This function requires the COLLATERAL_ADDER role
    function addPegInCollateralTo(address addr) external payable;

    /// @notice Adds peg in collateral to the caller
    /// @dev This function can only be called by a liquidity provider. This means an
    /// account that has been registered by adding collateral with addPegInCollateralTo.
    /// This means the COLLATERAL_ADDER can't use this function unless they register themselves.
    function addPegInCollateral() external payable;

    /// @notice Slashes peg in collateral from a liquidity provider. The slashed amount
    /// is the penalty fee of the quote. Depending on the reward percentage, the punisher
    /// will receive a reward. The rest of the penalty fee remains in the contract.
    /// @param punisher The address of the punisher
    /// @param quote The quote of the peg in collateral
    /// @param quoteHash The hash of the quote
    /// @dev This function requires the COLLATERAL_SLASHER role
    function slashPegInCollateral(
        address punisher,
        Quotes.PegInQuote calldata quote,
        bytes32 quoteHash
    ) external;

    /// @notice Adds peg out collateral to an account
    /// @param addr The address of the account
    /// @dev This function requires the COLLATERAL_ADDER role
    function addPegOutCollateralTo(address addr) external payable;

    /// @notice Adds peg out collateral to the caller
    /// @dev This function can only be called by a liquidity provider. This means an
    /// account that has been registered by adding collateral with addPegOutCollateralTo.
    /// This means the COLLATERAL_ADDER can't use this function unless they register themselves.
    function addPegOutCollateral() external payable;

    /// @notice Slashes peg out collateral from a liquidity provider. The slashed amount
    /// is the penalty fee of the quote. Depending on the reward percentage, the punisher
    /// will receive a reward. The rest of the penalty fee remains in the contract.
    /// @param punisher The address of the punisher
    /// @param quote The quote of the peg out collateral
    /// @param quoteHash The hash of the quote
    /// @dev This function requires the COLLATERAL_SLASHER role
    function slashPegOutCollateral(
        address punisher,
        Quotes.PegOutQuote calldata quote,
        bytes32 quoteHash
    ) external;

    /// @notice Withdraws rewards from the contract. This implies that the caller has
    /// been a punisher at some point in time.
    function withdrawRewards() external;

    /// @notice Withdraws collateral from the contract. This requires the liquidity provider
    /// to have resigned and the resignation delay to have passed.
    function withdrawCollateral() external;

    /// @notice Resigns a liquidity provider
    function resign() external;

    /// @notice Gets the peg in collateral of an account
    /// @param addr The address of the account
    /// @return The amount of peg in collateral
    function getPegInCollateral(address addr) external view returns (uint256);

    /// @notice Gets the peg out collateral of an account
    /// @param addr The address of the account
    /// @return The amount of peg out collateral
    function getPegOutCollateral(address addr) external view returns (uint256);

    /// @notice Gets the block number at which a liquidity provider resigned
    function getResignationBlock(address addr) external view returns (uint256);

    /// @notice Gets the reward percentage from the penalty fee that the punisher will receive
    /// @return The reward percentage
    function getRewardPercentage() external view returns (uint256);

    /// @notice Gets the resignation delay in blocks
    /// @return The resignation delay in blocks
    function getResignDelayInBlocks() external view returns (uint256);

    /// @notice Gets the minimum collateral **per operation** required for a liquidity provider
    /// @return The minimum collateral required for a liquidity provider
    function getMinCollateral() external view returns (uint256);

    /// @notice Checks if an account is registered this means having added collateral to the
    /// contract and not having resigned
    /// @param providerType The type of provider
    /// @param addr The address of the account
    function isRegistered(Flyover.ProviderType providerType, address addr) external view returns (bool);

    /// @notice Checks if an account has sufficient collateral. This means having at least the minimum collateral
    /// for that operation and not having resigned.
    /// @param providerType The type of provider
    /// @param addr The address of the account
    function isCollateralSufficient(Flyover.ProviderType providerType, address addr) external view returns (bool);

    /// @notice Gets the rewards of an account accumulated from the punishments
    /// @param addr The address of the account
    /// @return The rewards of the account
    function getRewards(address addr) external view returns (uint256);

    /// @notice Gets the total penalties stored in the contract from the penalized liquidity providers
    /// @return The penalties amount
    function getPenalties() external view returns (uint256);
}
