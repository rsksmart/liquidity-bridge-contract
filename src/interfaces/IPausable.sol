// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

interface IPausable {
    /// @notice Returns the pause status (from the central PauseRegistry)
    /// @return isPaused Whether the system is paused
    /// @return reason The reason for pausing
    /// @return since The timestamp when the system was paused
    function pauseStatus() external view returns (bool isPaused, string memory reason, uint64 since);
}
