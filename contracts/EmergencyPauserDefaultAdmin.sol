// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

/* solhint-disable comprehensive-interface */

import {
    AccessControlDefaultAdminRulesUpgradeable
} from "@openzeppelin/contracts-upgradeable/access/extensions/AccessControlDefaultAdminRulesUpgradeable.sol";
import {EmergencyPauser} from "./EmergencyPauser.sol";

abstract contract EmergencyPauserDefaultAdmin is EmergencyPauser, AccessControlDefaultAdminRulesUpgradeable {

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
