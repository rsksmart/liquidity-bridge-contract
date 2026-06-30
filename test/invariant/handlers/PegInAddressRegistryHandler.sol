// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {HandlerBase} from "./HandlerBase.sol";
import {PegInAddressRegistry} from "../../../src/PegInAddressRegistry.sol";
import {PauseRegistry} from "../../../src/PauseRegistry.sol";
import {IPauseRegistry} from "../../../src/interfaces/IPauseRegistry.sol";
import {IPegInAddressRegistry} from "../../../src/interfaces/IPegInAddressRegistry.sol";

/// @title PegInAddressRegistry Invariant Handler
/// @notice Provides fuzzable handler functions for PegInAddressRegistry invariant testing
contract PegInAddressRegistryHandler is HandlerBase {
    PegInAddressRegistry public registry;
    PauseRegistry public pauseRegistry;
    address public owner;

    address[] public registeredAddresses;
    mapping(address => uint256) public ghost_registrationBlocks;
    mapping(address => address) public ghost_registrants;

    uint256 public ghost_registeredCount;
    uint256 public ghost_invariantViolations;

    constructor(
        PegInAddressRegistry registry_,
        PauseRegistry pauseRegistry_,
        address owner_
    ) {
        registry = registry_;
        pauseRegistry = pauseRegistry_;
        owner = owner_;
    }

    function registerAddress(uint256 seed) external {
        handlerCalls["registerAddress"] += 1;

        address addr = address(uint160(seed));
        address registrant = address(
            uint160(uint256(keccak256(abi.encode(seed, "registrant"))))
        );
        if (addr == address(0) || registrant == address(0)) return;
        if (registry.isRegistered(addr)) return;
        if (pauseRegistry.pauseLevel() != IPauseRegistry.PauseLevel.None)
            return;

        vm.prank(registrant);
        try registry.registerAddress(addr) {
            registeredAddresses.push(addr);
            ghost_registrationBlocks[addr] = block.number;
            ghost_registrants[addr] = registrant;
            ++ghost_registeredCount;
        } catch {}
    }

    function registerAddress_duplicate(uint256 seed) external {
        handlerCalls["registerAddress_duplicate"] += 1;
        if (registeredAddresses.length == 0) return;

        address addr = registeredAddresses[seed % registeredAddresses.length];

        try registry.registerAddress(addr) {
            ++ghost_invariantViolations;
        } catch {}
    }

    function registerAddress_zero() external {
        handlerCalls["registerAddress_zero"] += 1;

        try registry.registerAddress(address(0)) {
            ++ghost_invariantViolations;
        } catch {}
    }

    function pauseSoft() external {
        handlerCalls["pauseSoft"] += 1;
        vm.prank(owner);
        pauseRegistry.setPauseLevel(
            IPauseRegistry.PauseLevel.Soft,
            "invariant"
        );
    }

    function unpause() external {
        handlerCalls["unpause"] += 1;
        vm.prank(owner);
        pauseRegistry.setPauseLevel(IPauseRegistry.PauseLevel.None, "");
    }

    function registerWhilePaused(uint256 seed) external {
        handlerCalls["registerWhilePaused"] += 1;
        if (pauseRegistry.pauseLevel() == IPauseRegistry.PauseLevel.None)
            return;

        address addr = address(uint160(seed));
        if (addr == address(0) || registry.isRegistered(addr)) return;

        try registry.registerAddress(addr) {
            ++ghost_invariantViolations;
        } catch {}
    }

    function getRegisteredCount() external view returns (uint256) {
        return registeredAddresses.length;
    }

    function getRegisteredAddress(
        uint256 index
    ) external view returns (address) {
        return registeredAddresses[index];
    }

    function ghost_computeRegistrationRoot()
        public
        view
        returns (bytes32 root)
    {
        for (uint256 i = 0; i < registeredAddresses.length; ++i) {
            root = keccak256(abi.encodePacked(root, registeredAddresses[i]));
        }
    }
}
