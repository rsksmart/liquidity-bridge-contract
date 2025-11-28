// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

interface IPausable {
    /// @notice Pauses the contract
    /// @param reason The reason for pausing
    function pause(string calldata reason) external;

    /// @notice Unpauses the contract
    function unpause() external;

    /// @notice Returns the pause status of the contract
    /// @return isPaused Whether the contract is paused
    /// @return reason The reason for pausing
    /// @return since The timestamp when the contract was paused
    function pauseStatus() external view returns (bool isPaused, string memory reason, uint64 since);
}
