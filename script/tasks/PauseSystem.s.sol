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
    function pauseStatus() external view returns (bool isPaused, string memory reason, uint64 since);
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
            string memory network = vm.envOr("NETWORK", string("rskRegtest"));
            string memory key = string.concat(".", network, ".", jsonKey, ".address");

            try vm.parseJsonAddress(json, key) returns (address addr) {
                if (addr != address(0)) {
                    return addr;
                }
            } catch {}
        } catch {}

        revert(
            string.concat(
                "Failed to find ", jsonKey, " address. Set ", envVarName,
                " env var or ensure addresses.json is configured."
            )
        );
    }

    /**
     * @notice Load all contract addresses
     */
    function loadContracts() internal view returns (ContractInfo[] memory) {
        ContractInfo[] memory contracts = new ContractInfo[](4);

        contracts[0].name = "FlyoverDiscovery";
        contracts[0].addr = getContractAddress("FLYOVER_DISCOVERY_ADDRESS", "FlyoverDiscovery");

        contracts[1].name = "PegInContract";
        contracts[1].addr = getContractAddress("PEGIN_CONTRACT_ADDRESS", "PegInContract");

        contracts[2].name = "PegOutContract";
        contracts[2].addr = getContractAddress("PEGOUT_CONTRACT_ADDRESS", "PegOutContract");

        contracts[3].name = "CollateralManagement";
        contracts[3].addr = getContractAddress("COLLATERAL_MANAGEMENT_ADDRESS", "CollateralManagement");

        return contracts;
    }

    /**
     * @notice Check and display pause status of all contracts
     */
    function checkStatus() public view {
        console.log("\n=== FLYOVER PAUSE STATUS ===\n");

        ContractInfo[] memory contracts = loadContracts();

        console.log("Contract Addresses:");
        for (uint i = 0; i < contracts.length; i++) {
            console.log(string.concat("  ", contracts[i].name, ": ", vm.toString(contracts[i].addr)));
        }

        console.log("\nCurrent Pause Status:");
        for (uint i = 0; i < contracts.length; i++) {
            IPausable pausable = IPausable(contracts[i].addr);
            (bool isPaused, string memory reason, uint64 since) = pausable.pauseStatus();

            console.log(string.concat("  ", contracts[i].name, ": ", isPaused ? "PAUSED" : "ACTIVE"));
            if (isPaused) {
                console.log(string.concat("    - Reason: ", reason));
                console.log(string.concat("    - Since: ", vm.toString(since)));
            }
        }

        console.log("\n=============================\n");
    }

    /**
     * @notice Pause all system contracts
     */
    function pauseAll(string memory reason) public {
        require(bytes(reason).length > 0, "Reason cannot be empty");

        console.log("\n=== PAUSE OPERATION ===\n");
        console.log(string.concat("Reason: ", reason));

        ContractInfo[] memory contracts = loadContracts();

        vm.startBroadcast();

        uint256 successCount = 0;
        for (uint i = 0; i < contracts.length; i++) {
            try IPausable(contracts[i].addr).pause(reason) {
                console.log(string.concat("  [OK] ", contracts[i].name, " paused"));
                successCount++;
            } catch Error(string memory error) {
                console.log(string.concat("  [FAIL] ", contracts[i].name, " - ", error));
            }
        }

        vm.stopBroadcast();

        console.log(string.concat("\nPaused: ", vm.toString(successCount), "/", vm.toString(contracts.length)));
        require(successCount == contracts.length, "Pause operation failed for some contracts");
    }

    /**
     * @notice Unpause all system contracts
     */
    function unpauseAll() public {
        console.log("\n=== UNPAUSE OPERATION ===\n");

        ContractInfo[] memory contracts = loadContracts();

        vm.startBroadcast();

        uint256 successCount = 0;
        for (uint i = 0; i < contracts.length; i++) {
            try IPausable(contracts[i].addr).unpause() {
                console.log(string.concat("  [OK] ", contracts[i].name, " unpaused"));
                successCount++;
            } catch Error(string memory error) {
                console.log(string.concat("  [FAIL] ", contracts[i].name, " - ", error));
            }
        }

        vm.stopBroadcast();

        console.log(string.concat("\nUnpaused: ", vm.toString(successCount), "/", vm.toString(contracts.length)));
        require(successCount == contracts.length, "Unpause operation failed for some contracts");
    }
}
