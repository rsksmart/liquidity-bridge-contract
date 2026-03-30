// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

interface IPauseRegistry {
    /// @notice Canonical pause levels used by the registry
    /// @dev Underlying values are fixed: None=0, Soft=1, Hard=2
    enum PauseLevel {
        None,
        Soft,
        Hard
    }

    /// @notice Set pause level with an explicit reason.
    /// @dev Setting PauseLevel.None clears the pause reason.
    /// @param level The target pause level
    /// @param reason The reason for pausing (ignored when level is PauseLevel.None)
    function setPauseLevel(PauseLevel level, string calldata reason) external;

    /// @notice Returns whether the system is paused (level != PauseLevel.None)
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

    /// @notice Current pause level encoded as PauseLevel numeric value
    function pauseLevel() external view returns (PauseLevel);

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
