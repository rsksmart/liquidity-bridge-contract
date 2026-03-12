// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

interface IPauseRegistry {
    /// @notice Pauses the system (all contracts using this registry) — sets level to 1 (soft)
    /// @param reason The reason for pausing
    function pause(string calldata reason) external;

    /// @notice Unpauses the system — sets level to 0
    function unpause() external;

    /// @notice Set pause level (PAUSER_ROLE). On enter 2 a HardPause entry is appended; on leave 2 it is closed.
    /// @param level 0, 1, or 2
    function setPauseLevel(uint8 level) external;

    /// @notice Returns whether the system is paused (level != 0)
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

    /// @notice Current pause level: 0 = normal, 1 = soft (no new business), 2 = hard (full freeze)
    function pauseLevel() external view returns (uint8);

    /// @notice Number of hard-pause log entries (for reverse iteration)
    function hardPausesCount() external view returns (uint256);

    /// @notice One hard-pause log entry (start/end timestamp and block; end 0 while ongoing)
    function hardPauses(uint256 index)
        external
        view
        returns (
            uint64 startTimestamp,
            uint64 endTimestamp,
            uint64 startBlock,
            uint64 endBlock
        );

    /// @notice Total seconds of hard pause overlapping [startTimestamp, endTimestamp]
    function computePauseOverlap(uint256 startTimestamp, uint256 endTimestamp)
        external
        view
        returns (uint256);

    /// @notice Total blocks of hard pause overlapping [startBlock, endBlock]
    function computePauseOverlapBlocks(uint256 startBlock, uint256 endBlock)
        external
        view
        returns (uint256);
}
