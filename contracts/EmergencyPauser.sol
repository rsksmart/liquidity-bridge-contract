// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";

abstract contract EmergencyPauser is PausableUpgradeable {
    bytes32 internal constant _PAUSER_ROLE = keccak256("PAUSER_ROLE");

    string private _pauseReason;
    uint64 private _pauseTimestamp;

    event EmergencyPaused(address indexed by, string reason);
    event EmergencyUnpaused(address indexed by);

    function initialize() external initializer {
        __Pausable_init();
    }

    function pauseStatus() external view returns (bool isPaused, string memory reason, uint64 since) {
        return (paused(), _pauseReason, _pauseTimestamp);
    }

    function _emergencyPause(string calldata reason) internal {
        _pause();
        _pauseReason = reason; // storage string or reason hash/URI
        _pauseTimestamp = uint64(block.timestamp);
        emit EmergencyPaused(msg.sender, reason);
    }

    function _emergencyUnpause() internal {
        _pauseReason = "";
        _pauseTimestamp = 0;
        _unpause();
        emit EmergencyUnpaused(msg.sender);
    }

}
