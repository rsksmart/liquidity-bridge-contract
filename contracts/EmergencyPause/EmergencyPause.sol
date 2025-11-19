// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

/* solhint-disable comprehensive-interface */

import {
    AccessControlDefaultAdminRulesUpgradeable
} from "@openzeppelin/contracts-upgradeable/access/extensions/AccessControlDefaultAdminRulesUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";

abstract contract EmergencyPause is AccessControlDefaultAdminRulesUpgradeable, PausableUpgradeable {

    bytes32 internal constant _PAUSER_ROLE = keccak256("PAUSER_ROLE");

    string private _pauseReason;
    uint64 private _pauseTimestamp;

    event EmergencyPaused(address indexed by, string reason);
    event EmergencyUnpaused(address indexed by);

    /// @notice Initialize EmergencyPause with AccessControl and Pausable
    /// @param initialDelay The initial delay for admin role changes (use 0 for immediate access)
    /// @param defaultAdmin The default admin address
    // solhint-disable-next-line func-name-mixedcase
    function __EmergencyPause_init(
        uint48 initialDelay,
        address defaultAdmin
    ) internal onlyInitializing {
        __AccessControlDefaultAdminRules_init(initialDelay, defaultAdmin);
        __Pausable_init();
        _grantRole(_PAUSER_ROLE, defaultAdmin);
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

    /// @notice Pauses the contract
    /// @param reason The reason for pausing
    function pause(string calldata reason) external onlyRole(_PAUSER_ROLE) {
        _emergencyPause(reason);
    }

    /// @notice Unpauses the contract
    function unpause() external onlyRole(_PAUSER_ROLE) {
        _emergencyUnpause();
    }
}
