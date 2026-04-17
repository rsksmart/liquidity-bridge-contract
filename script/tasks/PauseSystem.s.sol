// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import "lib/forge-std/src/Script.sol";
import "lib/forge-std/src/console.sol";
import {AddressResolver} from "../helpers/AddressResolver.sol";

/**
 * @title PauseSystem
 * @notice Foundry script to pause/unpause the Flyover system via the central PauseRegistry
 * @dev All Flyover contracts (Discovery, PegIn, PegOut, Collateral) read pause state from PauseRegistry.
 *      Signer must have PAUSER_ROLE on the PauseRegistry.
 *      Before running, verifies that PegIn, PegOut, CollateralManagement and FlyoverDiscovery
 *      all use the same PauseRegistry; otherwise the task fails.
 *
 * ## Prerequisites
 * - PAUSE_REGISTRY_ADDRESS must be set (or PauseRegistry in addresses.json)
 * - Signer must have PAUSER_ROLE on the PauseRegistry
 *
 * ## Usage
 *
 * ### Check status (dry-run)
 *   forge script script/tasks/PauseSystem.s.sol:PauseSystem \
 *     --sig "checkStatus()" \
 *     --rpc-url <rpc-url>
 *
 * ### Pause (broadcast)
 *   forge script script/tasks/PauseSystem.s.sol:PauseSystem \
 *     --sig "pauseAll(string)" "Emergency maintenance" \
 *     --rpc-url <rpc-url> \
 *     --broadcast \
 *     --private-key <private-key>
 *
 * ### Unpause (broadcast)
 *   forge script script/tasks/PauseSystem.s.sol:PauseSystem \
 *     --sig "unpauseAll()" \
 *     --rpc-url <rpc-url> \
 *     --broadcast \
 *     --private-key <private-key>
 *
 * ## Environment Variables
 * - PAUSE_REGISTRY_ADDRESS: Address of PauseRegistry (required; or set in addresses.json)
 * - PEGIN_CONTRACT_ADDRESS, PEGOUT_CONTRACT_ADDRESS, COLLATERAL_MANAGEMENT_ADDRESS, FLYOVER_DISCOVERY_ADDRESS:
 *   Used to verify all contracts point to the same registry (or from addresses.json)
 * - NETWORK: Network name for addresses.json (default: rskRegtest)
 */

import {IPauseRegistry} from "../../src/interfaces/IPauseRegistry.sol";

/// @dev Minimal interface to read pauseRegistry() from contracts that inherit EmergencyPause
interface IPauseRegistryGetter {
    function pauseRegistry() external view returns (IPauseRegistry);
}

contract PauseSystem is Script, AddressResolver {
    /**
     * @notice Resolve PauseRegistry from env / addresses.json
     */
    function getPauseRegistry() internal view returns (IPauseRegistry) {
        return IPauseRegistry(getPauseRegistryAddress());
    }

    /**
     * @notice Verify PegIn, PegOut, CollateralManagement and FlyoverDiscovery all use the same registry
     * @param registry The expected PauseRegistry address
     * @dev Reverts if any contract has a different registry
     */
    function _verifyAllContractsUseRegistry(
        IPauseRegistry registry
    ) internal view {
        address expected = address(registry);

        address pegInAddr = getPegInAddress();
        require(
            address(IPauseRegistryGetter(pegInAddr).pauseRegistry()) ==
                expected,
            "PauseSystem: PegInContract has different PauseRegistry"
        );

        address pegOutAddr = getPegOutAddress();
        require(
            address(IPauseRegistryGetter(pegOutAddr).pauseRegistry()) ==
                expected,
            "PauseSystem: PegOutContract has different PauseRegistry"
        );

        address collateralAddr = getCollateralManagementAddress();
        require(
            address(IPauseRegistryGetter(collateralAddr).pauseRegistry()) ==
                expected,
            "PauseSystem: CollateralManagement has different PauseRegistry"
        );

        address discoveryAddr = getFlyoverDiscoveryAddress();
        require(
            address(IPauseRegistryGetter(discoveryAddr).pauseRegistry()) ==
                expected,
            "PauseSystem: FlyoverDiscovery has different PauseRegistry"
        );
    }

    /**
     * @notice Check and display pause status (from central registry)
     */
    function checkStatus() public view {
        console.log("\n=== FLYOVER PAUSE STATUS ===\n");

        IPauseRegistry registry = getPauseRegistry();
        _verifyAllContractsUseRegistry(registry);

        console.log(
            string.concat("PauseRegistry: ", vm.toString(address(registry)))
        );
        console.log("");

        (bool isPaused, string memory reason, uint64 since) = registry
            .pauseStatus();

        console.log(string.concat("System: ", isPaused ? "PAUSED" : "ACTIVE"));
        if (isPaused) {
            console.log(string.concat("  Reason: ", reason));
            console.log(string.concat("  Since: ", vm.toString(since)));
        }

        console.log("\n=============================\n");
    }

    /**
     * @notice Pause the system via the central PauseRegistry (affects all Flyover contracts)
     */
    function pauseAll(string memory reason) public {
        require(bytes(reason).length > 0, "Reason cannot be empty");

        console.log("\n=== PAUSE OPERATION ===\n");
        console.log(string.concat("Reason: ", reason));

        IPauseRegistry registry = getPauseRegistry();
        _verifyAllContractsUseRegistry(registry);

        vm.startBroadcast();
        registry.setPauseLevel(IPauseRegistry.PauseLevel.Soft, reason);
        vm.stopBroadcast();

        console.log(
            "  [OK] PauseRegistry paused - all Flyover contracts are now paused"
        );
        console.log("\n[SUCCESS] System paused successfully!");
    }

    /**
     * @notice Unpause the system via the central PauseRegistry
     */
    function unpauseAll() public {
        console.log("\n=== UNPAUSE OPERATION ===\n");

        IPauseRegistry registry = getPauseRegistry();
        _verifyAllContractsUseRegistry(registry);

        vm.startBroadcast();
        registry.setPauseLevel(IPauseRegistry.PauseLevel.None, "");
        vm.stopBroadcast();

        console.log(
            "  [OK] PauseRegistry unpaused - all Flyover contracts are now active"
        );
        console.log("\n[SUCCESS] System unpaused successfully!");
    }
}
