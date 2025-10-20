// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

/* solhint-disable comprehensive-interface */

import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {EmergencyPauser} from "./EmergencyPauser.sol";

abstract contract EmergencyPauserPeg is EmergencyPauser, AccessControlUpgradeable {

    function pause(string calldata reason) external onlyRole(_PAUSER_ROLE) {
        _emergencyPause(reason);
    }

    function unpause() external onlyRole(_PAUSER_ROLE) {
        _emergencyUnpause();
    }
}
