// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

/* solhint-disable comprehensive-interface */

import {
    AccessControlDefaultAdminRulesUpgradeable
} from "@openzeppelin/contracts-upgradeable/access/extensions/AccessControlDefaultAdminRulesUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {IPauseRegistry} from "./interfaces/IPauseRegistry.sol";

/// @title PauseRegistry
/// @notice Centralized registry for pause state; all Flyover contracts read from here
/// @dev Only accounts with PAUSER_ROLE can pause/unpause. Uses namespaced storage.
contract PauseRegistry is
    Initializable,
    AccessControlDefaultAdminRulesUpgradeable,
    IPauseRegistry
{
    /// @custom:storage-location erc7201:rsk.flyover.PauseRegistry
    struct PauseRegistryStorage {
        bool paused;
        uint64 pauseTimestamp;
        string pauseReason;
    }

    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    // ERC-7201: keccak256(abi.encode(uint256(keccak256("rsk.flyover.PauseRegistry")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant _PAUSE_REGISTRY_STORAGE =
        0xde609c7d5a78f434280e4782344f7bcf6ccb01cacb109dfb3b05fed1bfa41900;

    event EmergencyPaused(address indexed by, string reason);
    event EmergencyUnpaused(address indexed by);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @notice Initialize the registry
    /// @param initialDelay The initial delay for admin role changes (use 0 for immediate access)
    /// @param defaultAdmin The default admin and initial pauser
    function initialize(uint48 initialDelay, address defaultAdmin) external initializer {
        __AccessControlDefaultAdminRules_init(initialDelay, defaultAdmin);
        _grantRole(PAUSER_ROLE, defaultAdmin);
    }

    /// @inheritdoc IPauseRegistry
    function pause(string calldata reason) external onlyRole(PAUSER_ROLE) {
        PauseRegistryStorage storage $ = _getPauseRegistryStorage();
        if ($.paused) return;
        $.paused = true;
        $.pauseReason = reason;
        $.pauseTimestamp = uint64(block.timestamp);
        emit EmergencyPaused(msg.sender, reason);
    }

    /// @inheritdoc IPauseRegistry
    function unpause() external onlyRole(PAUSER_ROLE) {
        PauseRegistryStorage storage $ = _getPauseRegistryStorage();
        if (!$.paused) return;
        $.paused = false;
        $.pauseReason = "";
        $.pauseTimestamp = 0;
        emit EmergencyUnpaused(msg.sender);
    }

    /// @inheritdoc IPauseRegistry
    function paused() external view returns (bool) {
        return _getPauseRegistryStorage().paused;
    }

    /// @inheritdoc IPauseRegistry
    function pauseStatus()
        external
        view
        returns (bool isPaused, string memory reason, uint64 since)
    {
        PauseRegistryStorage storage $ = _getPauseRegistryStorage();
        return ($.paused, $.pauseReason, $.pauseTimestamp);
    }

    function _getPauseRegistryStorage()
        private
        pure
        returns (PauseRegistryStorage storage $)
    {
        assembly {
            $.slot := _PAUSE_REGISTRY_STORAGE
        }
    }
}
