// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

interface IPauseRegistry {
    /// @notice Pauses the system (all contracts using this registry)
    /// @param reason The reason for pausing
    function pause(string calldata reason) external;

    /// @notice Unpauses the system
    function unpause() external;

    /// @notice Returns whether the system is paused
    /// @return True if paused
    function paused() external view returns (bool);

    /// @notice Returns full pause status
    /// @return isPaused Whether the system is paused
    /// @return reason The reason for pausing
    /// @return since The timestamp when the system was paused
    function pauseStatus()
        external
        view
        returns (bool isPaused, string memory reason, uint64 since);
}
