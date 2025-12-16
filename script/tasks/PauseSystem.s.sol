// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import "lib/forge-std/src/Script.sol";
import "lib/forge-std/src/console.sol";
import {AddressResolver} from "../helpers/AddressResolver.sol";

/**
 * @title PauseSystem
 * @notice Foundry script to pause/unpause all Flyover system contracts simultaneously
 * @dev This script handles FlyoverDiscovery, PegInContract, PegOutContract, and CollateralManagementContract
 *
 * ## Prerequisites
 * - Contract addresses must be provided via environment variables or addresses.json
 * - Signer must have PAUSER_ROLE on all contracts
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
 * - FLYOVER_DISCOVERY_ADDRESS: Address of FlyoverDiscovery contract
 * - PEGIN_CONTRACT_ADDRESS: Address of PegInContract
 * - PEGOUT_CONTRACT_ADDRESS: Address of PegOutContract
 * - COLLATERAL_MANAGEMENT_ADDRESS: Address of CollateralManagementContract
 * - NETWORK: Network name to use when reading from addresses.json (default: rskRegtest)
 */

interface IPausable {
    function pause(string calldata reason) external;

    function unpause() external;

    function pauseStatus()
        external
        view
        returns (bool isPaused, string memory reason, uint64 since);
}

contract PauseSystem is Script, AddressResolver {
    struct ContractInfo {
        string name;
        address addr;
        bool isPaused;
        string reason;
        uint64 since;
    }

    error PartialPauseFailure(
        uint256 succeeded,
        uint256 total,
        string[] failedContracts
    );
    error PartialUnpauseFailure(
        uint256 succeeded,
        uint256 total,
        string[] failedContracts
    );

    /**
     * @notice Load all contract addresses
     */
    function loadContracts() internal view returns (ContractInfo[] memory) {
        ContractInfo[] memory contracts = new ContractInfo[](4);

        contracts[0].name = "FlyoverDiscovery";
        contracts[0].addr = getFlyoverDiscoveryAddress();

        contracts[1].name = "PegInContract";
        contracts[1].addr = getPegInAddress();

        contracts[2].name = "PegOutContract";
        contracts[2].addr = getPegOutAddress();

        contracts[3].name = "CollateralManagement";
        contracts[3].addr = getCollateralManagementAddress();

        return contracts;
    }

    /**
     * @notice Check and display pause status of all contracts
     */
    function checkStatus() public view {
        console.log("\n=== FLYOVER PAUSE STATUS ===\n");

        ContractInfo[] memory contracts = loadContracts();

        console.log("Contract Addresses:");
        for (uint256 i = 0; i < contracts.length; i++) {
            console.log(
                string.concat(
                    "  ",
                    contracts[i].name,
                    ": ",
                    vm.toString(contracts[i].addr)
                )
            );
        }

        console.log("\nCurrent Pause Status:");
        for (uint256 i = 0; i < contracts.length; i++) {
            IPausable pausable = IPausable(contracts[i].addr);
            (bool isPaused, string memory reason, uint64 since) = pausable
                .pauseStatus();

            console.log(
                string.concat(
                    "  ",
                    contracts[i].name,
                    ": ",
                    isPaused ? "PAUSED" : "ACTIVE"
                )
            );
            if (isPaused) {
                console.log(string.concat("    - Reason: ", reason));
                console.log(string.concat("    - Since: ", vm.toString(since)));
            }
        }

        console.log("\n=============================\n");
    }

    /**
     * @notice Pause all system contracts atomically
     * @dev If any contract fails to pause, the entire transaction reverts to prevent inconsistent state
     */
    function pauseAll(string memory reason) public {
        require(bytes(reason).length > 0, "Reason cannot be empty");

        console.log("\n=== PAUSE OPERATION ===\n");
        console.log(string.concat("Reason: ", reason));

        ContractInfo[] memory contracts = loadContracts();

        vm.startBroadcast();

        // First pass: attempt all pauses, collect failures
        string[] memory failedContracts = new string[](contracts.length);
        uint256 failCount = 0;

        for (uint256 i = 0; i < contracts.length; i++) {
            try IPausable(contracts[i].addr).pause(reason) {
                console.log(
                    string.concat("  [OK] ", contracts[i].name, " paused")
                );
            } catch Error(string memory error) {
                console.log(
                    string.concat("  [FAIL] ", contracts[i].name, " - ", error)
                );
                failedContracts[failCount] = contracts[i].name;
                failCount++;
            }
        }

        vm.stopBroadcast();

        uint256 successCount = contracts.length - failCount;
        console.log(
            string.concat(
                "\nPaused: ",
                vm.toString(successCount),
                "/",
                vm.toString(contracts.length)
            )
        );

        // If any failed, revert the entire transaction to prevent inconsistent state
        if (failCount > 0) {
            // Trim the failed contracts array
            string[] memory trimmedFailed = new string[](failCount);
            for (uint256 i = 0; i < failCount; i++) {
                trimmedFailed[i] = failedContracts[i];
            }
            revert PartialPauseFailure(
                successCount,
                contracts.length,
                trimmedFailed
            );
        }

        console.log("\n[SUCCESS] All contracts paused successfully!");
    }

    /**
     * @notice Unpause all system contracts atomically
     * @dev If any contract fails to unpause, the entire transaction reverts to prevent inconsistent state
     */
    function unpauseAll() public {
        console.log("\n=== UNPAUSE OPERATION ===\n");

        ContractInfo[] memory contracts = loadContracts();

        vm.startBroadcast();

        // First pass: attempt all unpauses, collect failures
        string[] memory failedContracts = new string[](contracts.length);
        uint256 failCount = 0;

        for (uint256 i = 0; i < contracts.length; i++) {
            try IPausable(contracts[i].addr).unpause() {
                console.log(
                    string.concat("  [OK] ", contracts[i].name, " unpaused")
                );
            } catch Error(string memory error) {
                console.log(
                    string.concat("  [FAIL] ", contracts[i].name, " - ", error)
                );
                failedContracts[failCount] = contracts[i].name;
                failCount++;
            }
        }

        vm.stopBroadcast();

        uint256 successCount = contracts.length - failCount;
        console.log(
            string.concat(
                "\nUnpaused: ",
                vm.toString(successCount),
                "/",
                vm.toString(contracts.length)
            )
        );

        // If any failed, revert the entire transaction to prevent inconsistent state
        if (failCount > 0) {
            // Trim the failed contracts array
            string[] memory trimmedFailed = new string[](failCount);
            for (uint256 i = 0; i < failCount; i++) {
                trimmedFailed[i] = failedContracts[i];
            }
            revert PartialUnpauseFailure(
                successCount,
                contracts.length,
                trimmedFailed
            );
        }

        console.log("\n[SUCCESS] All contracts unpaused successfully!");
    }
}
