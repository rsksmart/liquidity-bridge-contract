// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import "lib/forge-std/src/Script.sol";
import "lib/forge-std/src/console.sol";

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
 * ### Method 1: Using the wrapper script (recommended)
 *   # Dry run (check status only)
 *   ./forge-scripts/tasks/pause-system.sh --action status --rpc-url <rpc-url>
 *
 *   # Pause all contracts
 *   ./forge-scripts/tasks/pause-system.sh --action pause --reason "Emergency maintenance" --rpc-url <rpc-url> --broadcast --private-key <key>
 *
 *   # Unpause all contracts
 *   ./forge-scripts/tasks/pause-system.sh --action unpause --rpc-url <rpc-url> --broadcast --private-key <key>
 *
 * ### Method 2: Direct forge script invocation
 *   # Check status (dry-run)
 *   forge script forge-scripts/tasks/PauseSystem.s.sol:PauseSystem \
 *     --sig "checkStatus()" \
 *     --rpc-url <rpc-url>
 *
 *   # Pause (simulation)
 *   forge script forge-scripts/tasks/PauseSystem.s.sol:PauseSystem \
 *     --sig "pauseAll(string)" "Emergency maintenance" \
 *     --rpc-url <rpc-url>
 *
 *   # Pause (broadcast)
 *   forge script forge-scripts/tasks/PauseSystem.s.sol:PauseSystem \
 *     --sig "pauseAll(string)" "Emergency maintenance" \
 *     --rpc-url <rpc-url> \
 *     --broadcast \
 *     --private-key <private-key>
 *
 *   # Unpause (broadcast)
 *   forge script forge-scripts/tasks/PauseSystem.s.sol:PauseSystem \
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
 *
 * ## Private Key Options (in order of precedence)
 * 1. --private-key <key>: Direct private key
 * 2. --ledger: Use hardware wallet
 * 3. --interactive: Interactive keystore
 *
 * ## Examples
 *   # Using environment variables
 *   NETWORK=rskTestnet ./forge-scripts/tasks/pause-system.sh --action status --rpc-url https://testnet.rsk.co
 *
 *   # Pause with private key
 *   ./forge-scripts/tasks/pause-system.sh --action pause --reason "Security incident" --rpc-url <rpc> --broadcast --private-key $PRIVATE_KEY
 *
 *   # Unpause with ledger
 *   ./forge-scripts/tasks/pause-system.sh --action unpause --rpc-url <rpc> --broadcast --ledger
 */

interface IPausable {
    function pause(string calldata reason) external;

    function unpause() external;

    function pauseStatus()
        external
        view
        returns (bool isPaused, string memory reason, uint64 since);
}

contract PauseSystem is Script {
    struct ContractInfo {
        string name;
        address addr;
        bool isPaused;
        string reason;
        uint64 since;
    }

    /**
     * @notice Get contract address from environment variable or addresses.json
     * @param envVarName Environment variable name
     * @param jsonKey Key in addresses.json
     * @return The contract address
     */
    function getContractAddress(
        string memory envVarName,
        string memory jsonKey
    ) internal view returns (address) {
        // First try environment variable
        try vm.envAddress(envVarName) returns (address addr) {
            if (addr != address(0)) {
                return addr;
            }
        } catch {}

        // Try to read from addresses.json
        try vm.readFile("addresses.json") returns (string memory json) {
            // Get network from environment or default to rskRegtest
            string memory network = vm.envOr("NETWORK", string("rskRegtest"));
            string memory key = string.concat(
                ".",
                network,
                ".",
                jsonKey,
                ".address"
            );

            try vm.parseJsonAddress(json, key) returns (address addr) {
                if (addr != address(0)) {
                    return addr;
                }
            } catch {}
        } catch {}

        revert(
            string.concat(
                "Failed to find ",
                jsonKey,
                " address. Set ",
                envVarName,
                " env var or ensure addresses.json is configured."
            )
        );
    }

    /**
     * @notice Load all contract addresses
     * @return Array of contract info structs
     */
    function loadContracts() internal view returns (ContractInfo[] memory) {
        ContractInfo[] memory contracts = new ContractInfo[](4);

        contracts[0].name = "FlyoverDiscovery";
        contracts[0].addr = getContractAddress(
            "FLYOVER_DISCOVERY_ADDRESS",
            "FlyoverDiscovery"
        );

        contracts[1].name = "PegInContract";
        contracts[1].addr = getContractAddress(
            "PEGIN_CONTRACT_ADDRESS",
            "PegInContract"
        );

        contracts[2].name = "PegOutContract";
        contracts[2].addr = getContractAddress(
            "PEGOUT_CONTRACT_ADDRESS",
            "PegOutContract"
        );

        contracts[3].name = "CollateralManagementContract";
        contracts[3].addr = getContractAddress(
            "COLLATERAL_MANAGEMENT_ADDRESS",
            "CollateralManagementContract"
        );

        return contracts;
    }

    /**
     * @notice Check and display pause status of all contracts
     */
    function checkStatus() public view {
        console.log("\n=== PAUSE SYSTEM STATUS CHECK ===\n");

        ContractInfo[] memory contracts = loadContracts();

        console.log("Contract Addresses:");
        for (uint i = 0; i < contracts.length; i++) {
            console.log(string.concat("  ", contracts[i].name, ":"));
            console.log(
                string.concat("    Address: ", vm.toString(contracts[i].addr))
            );
        }

        console.log("\nCurrent Pause Status:");
        for (uint i = 0; i < contracts.length; i++) {
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
                console.log(
                    string.concat(
                        "    - Since: ",
                        vm.toString(since),
                        " (",
                        vm.toString(block.timestamp - since),
                        "s ago)"
                    )
                );
            }
        }

        console.log("\n=================================\n");
    }

    /**
     * @notice Pause all system contracts
     * @param reason The reason for pausing
     */
    function pauseAll(string memory reason) public {
        require(bytes(reason).length > 0, "Reason cannot be empty");

        console.log("\n=== PAUSE OPERATION STARTING ===\n");
        console.log(string.concat("Reason: ", reason));

        ContractInfo[] memory contracts = loadContracts();

        // Check current status
        console.log("\nCurrent pause status:");
        for (uint i = 0; i < contracts.length; i++) {
            IPausable pausable = IPausable(contracts[i].addr);
            (
                bool isPaused,
                string memory currentReason,
                uint64 since
            ) = pausable.pauseStatus();
            contracts[i].isPaused = isPaused;
            contracts[i].reason = currentReason;
            contracts[i].since = since;

            console.log(
                string.concat(
                    "  ",
                    contracts[i].name,
                    ": ",
                    isPaused ? "PAUSED" : "ACTIVE"
                )
            );
            if (isPaused) {
                console.log(string.concat("    - Reason: ", currentReason));
            }
        }

        // Execute pause operation
        console.log("\nExecuting pause operation...");

        vm.startBroadcast();

        uint256 successCount = 0;
        uint256 failCount = 0;

        for (uint i = 0; i < contracts.length; i++) {
            try IPausable(contracts[i].addr).pause(reason) {
                console.log(
                    string.concat(
                        "  [OK] ",
                        contracts[i].name,
                        " paused successfully"
                    )
                );
                successCount++;
            } catch Error(string memory error) {
                console.log(
                    string.concat("  [FAIL] ", contracts[i].name, " - ", error)
                );
                failCount++;
            } catch (bytes memory) {
                console.log(
                    string.concat(
                        "  [FAIL] ",
                        contracts[i].name,
                        " - Unknown error"
                    )
                );
                failCount++;
            }
        }

        vm.stopBroadcast();

        // Final status check
        console.log("\nFinal pause status:");
        for (uint i = 0; i < contracts.length; i++) {
            IPausable pausable = IPausable(contracts[i].addr);
            (bool isPaused, string memory finalReason, uint64 since) = pausable
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
                console.log(string.concat("    - Reason: ", finalReason));
                console.log(string.concat("    - Since: ", vm.toString(since)));
            }
        }

        // Summary
        console.log("\n=== OPERATION SUMMARY ===");
        console.log(
            string.concat(
                "Successful: ",
                vm.toString(successCount),
                "/",
                vm.toString(contracts.length)
            )
        );
        console.log(
            string.concat(
                "Failed: ",
                vm.toString(failCount),
                "/",
                vm.toString(contracts.length)
            )
        );

        require(failCount == 0, "Pause operation failed for some contracts");

        console.log("\n=== PAUSE OPERATION COMPLETED ===\n");
    }

    /**
     * @notice Unpause all system contracts
     */
    function unpauseAll() public {
        console.log("\n=== UNPAUSE OPERATION STARTING ===\n");

        ContractInfo[] memory contracts = loadContracts();

        // Check current status
        console.log("Current pause status:");
        for (uint i = 0; i < contracts.length; i++) {
            IPausable pausable = IPausable(contracts[i].addr);
            (
                bool isPaused,
                string memory currentReason,
                uint64 since
            ) = pausable.pauseStatus();
            contracts[i].isPaused = isPaused;
            contracts[i].reason = currentReason;
            contracts[i].since = since;

            console.log(
                string.concat(
                    "  ",
                    contracts[i].name,
                    ": ",
                    isPaused ? "PAUSED" : "ACTIVE"
                )
            );
            if (isPaused) {
                console.log(string.concat("    - Reason: ", currentReason));
            }
        }

        // Execute unpause operation
        console.log("\nExecuting unpause operation...");

        vm.startBroadcast();

        uint256 successCount = 0;
        uint256 failCount = 0;

        for (uint i = 0; i < contracts.length; i++) {
            try IPausable(contracts[i].addr).unpause() {
                console.log(
                    string.concat(
                        "  [OK] ",
                        contracts[i].name,
                        " unpaused successfully"
                    )
                );
                successCount++;
            } catch Error(string memory error) {
                console.log(
                    string.concat("  [FAIL] ", contracts[i].name, " - ", error)
                );
                failCount++;
            } catch (bytes memory) {
                console.log(
                    string.concat(
                        "  [FAIL] ",
                        contracts[i].name,
                        " - Unknown error"
                    )
                );
                failCount++;
            }
        }

        vm.stopBroadcast();

        // Final status check
        console.log("\nFinal pause status:");
        for (uint i = 0; i < contracts.length; i++) {
            IPausable pausable = IPausable(contracts[i].addr);
            (bool isPaused, string memory finalReason, ) = pausable
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
                console.log(string.concat("    - Reason: ", finalReason));
            }
        }

        // Summary
        console.log("\n=== OPERATION SUMMARY ===");
        console.log(
            string.concat(
                "Successful: ",
                vm.toString(successCount),
                "/",
                vm.toString(contracts.length)
            )
        );
        console.log(
            string.concat(
                "Failed: ",
                vm.toString(failCount),
                "/",
                vm.toString(contracts.length)
            )
        );

        require(failCount == 0, "Unpause operation failed for some contracts");

        console.log("\n=== UNPAUSE OPERATION COMPLETED ===\n");
    }
}
