// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

/// @title IDaoContributor
/// @notice This interface is should be implemented by any contract that wants to collect fees to send to the DAO
interface IDaoContributor {

    /// @notice This function is used to get the fee percentage
    /// that the child contracts use to calculate the contributions
    /// @return feePercentage the fee percentage
    function getFeePercentage() external view returns (uint256);

    /// @notice This function is used to get the current contribution
    /// @return currentContribution the current contribution
    function getCurrentContribution() external view returns (uint256);

    /// @notice This function is used to get the fee collector
    /// @return feeCollector the fee collector address
    function getFeeCollector() external view returns (address);
}
