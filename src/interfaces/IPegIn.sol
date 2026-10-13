// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {IERC5267} from "@openzeppelin/contracts/interfaces/IERC5267.sol";
import {IPausable} from "./IPausable.sol";

/// @title PegIn interface
/// @notice This interface is used to expose the required functions to provide the Flyover peg in service
interface IPegIn is IPausable, IERC5267 {

    /// @notice The states of a peg in quote
    enum PegInStates { UNPROCESSED_QUOTE, CALL_DONE, PROCESSED_QUOTE }

    /// @notice Emitted when the balance of a liquidity provider increases
    /// @param dest The address of the liquidity provider
    /// @param amount The amount of the increase
    event BalanceIncrease(address indexed dest, uint256 indexed amount);

    /// @notice Emitted when the balance of a liquidity provider decreases
    /// @param dest The address of the liquidity provider
    /// @param amount The amount of the decrease
    event BalanceDecrease(address indexed dest, uint256 indexed amount);

    /// @notice Emitted when a liquidity provider withdraws funds
    /// @param from The address of the liquidity provider
    /// @param amount The amount of the withdrawal
    event Withdrawal(address indexed from, uint256 indexed amount);

    /// @notice This function is used to deposit funds into the contract to provide the
    /// peg in service
    /// @dev This function is only callable by a liquidity provider
    function deposit() external payable;

    /// @notice This function is used to withdraw funds from the contract
    /// @dev This function is only callable by a liquidity provider. They can partially
    /// withdraw their balance, this includes the profit made with the peg in service.
    /// @param amount The amount of the withdrawal
    function withdraw(uint256 amount) external;

    /// @notice This function is used to get the balance of a liquidity provider
    /// @param addr The address of the liquidity provider
    /// @return balance The balance of the liquidity provider
    function getBalance(address addr) external view returns (uint256);

    /// @notice This function is used to get the minimum peg in amount allowed by the protocol
    /// @return minPegIn The minimum peg in amount
    function getMinPegIn() external view returns (uint256);
}
