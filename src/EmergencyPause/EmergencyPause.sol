// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

/* solhint-disable comprehensive-interface */

import {
    AccessControlDefaultAdminRulesUpgradeable
} from "@openzeppelin/contracts-upgradeable/access/extensions/AccessControlDefaultAdminRulesUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {IPausable} from "../interfaces/IPausable.sol";

abstract contract EmergencyPause is AccessControlDefaultAdminRulesUpgradeable, PausableUpgradeable, IPausable {

    bytes32 internal constant _PAUSER_ROLE = keccak256("PAUSER_ROLE");

    string private _pauseReason;
    uint64 private _pauseTimestamp;

    event EmergencyPaused(address indexed by, string reason);
    event EmergencyUnpaused(address indexed by);

    /// @inheritdoc IPausable
    function pause(string calldata reason) public virtual override(IPausable) onlyRole(_PAUSER_ROLE) {
        _emergencyPause(reason);
    }

    //// @inheritdoc IPausable
    function unpause() public virtual override(IPausable) onlyRole(_PAUSER_ROLE) {
        _emergencyUnpause();
    }

    function pauseStatus()
        public virtual
        override(IPausable)
        view
        returns (bool isPaused, string memory reason, uint64 since)
    {
        return (paused(), _pauseReason, _pauseTimestamp);
    }

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
