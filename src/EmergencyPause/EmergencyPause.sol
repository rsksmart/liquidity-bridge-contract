// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

/* solhint-disable comprehensive-interface */

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {IPausable} from "../interfaces/IPausable.sol";
import {IPauseRegistry} from "../interfaces/IPauseRegistry.sol";
import {Flyover} from "../libraries/Flyover.sol";

/// @notice Base contract for Flyover contracts that delegate pause state to a central PauseRegistry.
/// pauseStatus() and pause-level checks read from the registry. Pause/unpause are done only on the registry.
/// Uses two modifiers:
/// - whenNotSoftPaused(): blocks at level >= 1 (soft and hard pause)
/// - whenNotHardPaused(): blocks at level >= 2 (hard pause only)
/// Uses namespaced storage; no AccessControl (children that need roles inherit it separately).
abstract contract EmergencyPause is Initializable, IPausable {

    /// @custom:storage-location erc7201:rsk.flyover.EmergencyPause
    struct EmergencyPauseStorage {
        IPauseRegistry pauseRegistry;
    }

    // ERC-7201: keccak256(abi.encode(uint256(keccak256("rsk.flyover.EmergencyPause")) - 1)) &
    // ~bytes32(uint256(0xff))
    bytes32 private constant _EMERGENCY_PAUSE_STORAGE =
        0x9231f352ae2e78fc5cd04a185b8fc917dd5cf9947923b7000e25955769a61f00;

    /// @notice Reverts at pause level >= 1 (soft pause: no new business)
    modifier whenNotSoftPaused() {
        if (_getEmergencyPauseStorage().pauseRegistry.pauseLevel() > 0) {
            revert Flyover.EnforcedPause();
        }
        _;
    }

    /// @notice Reverts at pause level >= 2 (hard pause: full freeze)
    modifier whenNotHardPaused() {
        if (_getEmergencyPauseStorage().pauseRegistry.pauseLevel() > 1) {
            revert Flyover.EnforcedPause();
        }
        _;
    }

    /// @inheritdoc IPausable
    function pauseStatus()
        public
        view
        virtual
        override(IPausable)
        returns (bool isPaused, string memory reason, uint64 since)
    {
        return _getEmergencyPauseStorage().pauseRegistry.pauseStatus();
    }

    /// @notice Returns the PauseRegistry used for pause state
    function pauseRegistry() public view returns (IPauseRegistry) {
        return _getEmergencyPauseStorage().pauseRegistry;
    }

    /// @notice Initialize EmergencyPause with reference to PauseRegistry
    /// @param pauseRegistry_ The central PauseRegistry
    // solhint-disable-next-line func-name-mixedcase
    function __EmergencyPause_init(IPauseRegistry pauseRegistry_)
        internal
        onlyInitializing
    {
        _getEmergencyPauseStorage().pauseRegistry = pauseRegistry_;
    }

    /// @notice Allows child contracts to update the pause registry (e.g. after upgrade or config change)
    /// @param pauseRegistry_ The new PauseRegistry
    function _setPauseRegistry(IPauseRegistry pauseRegistry_) internal {
        _getEmergencyPauseStorage().pauseRegistry = pauseRegistry_;
    }

    function _getEmergencyPauseStorage()
        private
        pure
        returns (EmergencyPauseStorage storage $)
    {
        assembly {
            $.slot := _EMERGENCY_PAUSE_STORAGE
        }
    }
}
