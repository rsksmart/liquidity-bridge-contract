// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

/* solhint-disable comprehensive-interface */

import {
    AccessControlDefaultAdminRulesUpgradeable
} from "@openzeppelin/contracts-upgradeable/access/extensions/AccessControlDefaultAdminRulesUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {IPauseRegistry} from "./interfaces/IPauseRegistry.sol";

/// @title PauseRegistry
/// @notice Centralized registry for pause state; all Flyover contracts read from here.
/// @dev Level 0 = normal, 1 = soft (no new business), 2 = hard (full freeze). Uses namespaced storage.
contract PauseRegistry is
    Initializable,
    AccessControlDefaultAdminRulesUpgradeable,
    IPauseRegistry
{
    /// @custom:storage-location erc7201:rsk.flyover.PauseRegistry
    struct PauseRegistryStorage {
        bool paused;
        uint8 pauseLevel;
        uint64 pauseTimestamp;
        string pauseReason;
        HardPause[] hardPauses;
    }

    struct HardPause {
        uint64 startTimestamp;
        uint64 endTimestamp; // 0 while ongoing
        uint64 startBlock;
        uint64 endBlock; // 0 while ongoing
    }

    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    // ERC-7201: keccak256(abi.encode(uint256(keccak256("rsk.flyover.PauseRegistry")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant _PAUSE_REGISTRY_STORAGE =
        0xde609c7d5a78f434280e4782344f7bcf6ccb01cacb109dfb3b05fed1bfa41900;

    event EmergencyPaused(address indexed by, string reason);
    event EmergencyUnpaused(address indexed by);
    error InvalidPauseLevel(uint8 level);

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
        _setPauseLevel(1);
        PauseRegistryStorage storage $ = _getPauseRegistryStorage();
        $.pauseTimestamp = uint64(block.timestamp);
        emit EmergencyPaused(msg.sender, reason);
    }

    /// @inheritdoc IPauseRegistry
    function unpause() external onlyRole(PAUSER_ROLE) {
        _setPauseLevel(0);
        PauseRegistryStorage storage $ = _getPauseRegistryStorage();
        $.pauseTimestamp = 0;
        emit EmergencyUnpaused(msg.sender);
    }

    /// @inheritdoc IPauseRegistry
    function setPauseLevel(uint8 level) external onlyRole(PAUSER_ROLE) {
        if (level > 2) revert InvalidPauseLevel(level);
        _setPauseLevel(level);
    }

    /// @inheritdoc IPauseRegistry
    function paused() external view returns (bool) {
        PauseRegistryStorage storage $ = _getPauseRegistryStorage();
        return $.pauseLevel != 0;
    }

    /// @inheritdoc IPauseRegistry
    function pauseStatus()
        external
        view
        returns (bool isPaused, string memory reason, uint64 since)
    {
        PauseRegistryStorage storage $ = _getPauseRegistryStorage();
        isPaused = $.pauseLevel != 0;
        reason = "";
        since = $.pauseTimestamp;
    }

    /// @inheritdoc IPauseRegistry
    function pauseLevel() external view returns (uint8) {
        return _getPauseRegistryStorage().pauseLevel;
    }

    /// @inheritdoc IPauseRegistry
    function hardPausesCount() external view returns (uint256) {
        return _getPauseRegistryStorage().hardPauses.length;
    }

    /// @inheritdoc IPauseRegistry
    function hardPauses(uint256 index)
        external
        view
        returns (
            uint64 startTimestamp,
            uint64 endTimestamp,
            uint64 startBlock,
            uint64 endBlock
        )
    {
        HardPause storage p = _getPauseRegistryStorage().hardPauses[index];
        return (p.startTimestamp, p.endTimestamp, p.startBlock, p.endBlock);
    }

    /// @inheritdoc IPauseRegistry
    function computePauseOverlap(uint256 startTimestamp, uint256 endTimestamp)
        external
        view
        returns (uint256 totalPauseTime)
    {
        HardPause[] storage pauses = _getPauseRegistryStorage().hardPauses;
        uint256 n = pauses.length;
        for (uint256 i = n; i > 0;) {
            unchecked {
                --i;
            }
            HardPause storage p = pauses[i];
            uint64 pEnd = p.endTimestamp;
            if (pEnd != 0 && !(pEnd > startTimestamp)) break;
            uint256 effectiveStart = startTimestamp;
            if (p.startTimestamp > effectiveStart) effectiveStart = p.startTimestamp;
            uint256 effectiveEnd = endTimestamp;
            uint256 pEndOrNow = pEnd == 0 ? block.timestamp : pEnd;
            if (pEndOrNow < effectiveEnd) effectiveEnd = pEndOrNow;
            if (effectiveEnd > effectiveStart) {
                totalPauseTime += effectiveEnd - effectiveStart;
            }
        }
    }

    /// @inheritdoc IPauseRegistry
    function computePauseOverlapBlocks(uint256 startBlock, uint256 endBlock)
        external
        view
        returns (uint256 totalPauseBlocks)
    {
        HardPause[] storage pauses = _getPauseRegistryStorage().hardPauses;
        uint256 n = pauses.length;
        for (uint256 i = n; i > 0;) {
            unchecked {
                --i;
            }
            HardPause storage p = pauses[i];
            uint64 pEndBlock = p.endBlock;
            if (pEndBlock != 0 && !(pEndBlock > startBlock)) break;
            uint256 effectiveStart = startBlock;
            if (p.startBlock > effectiveStart) effectiveStart = p.startBlock;
            uint256 effectiveEnd = endBlock;
            uint256 pEndOrNow = pEndBlock == 0 ? block.number : pEndBlock;
            if (pEndOrNow < effectiveEnd) effectiveEnd = pEndOrNow;
            if (effectiveEnd > effectiveStart) {
                totalPauseBlocks += effectiveEnd - effectiveStart;
            }
        }
    }

    function _setPauseLevel(uint8 level) internal {
        PauseRegistryStorage storage $ = _getPauseRegistryStorage();
        uint8 prev = $.pauseLevel;
        $.pauseLevel = level;
        $.paused = (level != 0);

        if (prev == 2 && level != 2) {
            HardPause[] storage pauses = $.hardPauses;
            uint256 len = pauses.length;
            if (len > 0) {
                HardPause storage last = pauses[len - 1];
                if (last.endTimestamp == 0) {
                    last.endTimestamp = uint64(block.timestamp);
                    last.endBlock = uint64(block.number);
                }
            }
        } else if (prev != 2 && level == 2) {
            $.hardPauses.push(
                HardPause({
                    startTimestamp: uint64(block.timestamp),
                    endTimestamp: 0,
                    startBlock: uint64(block.number),
                    endBlock: 0
                })
            );
        }
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
