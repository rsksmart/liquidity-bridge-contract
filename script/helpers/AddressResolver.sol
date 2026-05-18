// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Vm} from "lib/forge-std/src/Vm.sol";

/**
 * @title AddressResolver
 * @notice Shared utility for resolving contract addresses from environment variables or addresses.json
 * @dev Provides consistent address resolution across all task scripts
 */
library AddressResolverLib {
    /// @notice Resolve a contract address from environment variable or addresses.json
    /// @param vm The Forge VM instance
    /// @param envVarName The environment variable name to check first
    /// @param jsonKey The key to look up in addresses.json (e.g., "PegInContract")
    /// @return The resolved address
    function getContractAddress(
        Vm vm,
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

    /// @notice Get PegIn contract address
    function getPegInAddress(Vm vm) internal view returns (address) {
        return
            getContractAddress(vm, "PEGIN_CONTRACT_ADDRESS", "PegInContract");
    }

    /// @notice Get PegOut contract address
    function getPegOutAddress(Vm vm) internal view returns (address) {
        return
            getContractAddress(vm, "PEGOUT_CONTRACT_ADDRESS", "PegOutContract");
    }

    /// @notice Get FlyoverDiscovery contract address
    function getFlyoverDiscoveryAddress(Vm vm) internal view returns (address) {
        return
            getContractAddress(
                vm,
                "FLYOVER_DISCOVERY_ADDRESS",
                "FlyoverDiscovery"
            );
    }

    /// @notice Get CollateralManagement contract address
    function getCollateralManagementAddress(
        Vm vm
    ) internal view returns (address) {
        return
            getContractAddress(
                vm,
                "COLLATERAL_MANAGEMENT_ADDRESS",
                "CollateralManagementContract"
            );
    }

    /// @notice Get PauseRegistry contract address
    function getPauseRegistryAddress(Vm vm) internal view returns (address) {
        return
            getContractAddress(vm, "PAUSE_REGISTRY_ADDRESS", "PauseRegistry");
    }
}

/**
 * @title AddressResolver
 * @notice Abstract contract for easy inheritance in scripts
 * @dev Uses the cheatcode VM address directly to avoid inheritance conflicts
 */
abstract contract AddressResolver {
    Vm private constant VM = Vm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);

    function getContractAddress(
        string memory envVarName,
        string memory jsonKey
    ) internal view returns (address) {
        return AddressResolverLib.getContractAddress(VM, envVarName, jsonKey);
    }

    function getPegInAddress() internal view returns (address) {
        return AddressResolverLib.getPegInAddress(VM);
    }

    function getPegOutAddress() internal view returns (address) {
        return AddressResolverLib.getPegOutAddress(VM);
    }

    function getFlyoverDiscoveryAddress() internal view returns (address) {
        return AddressResolverLib.getFlyoverDiscoveryAddress(VM);
    }

    function getCollateralManagementAddress() internal view returns (address) {
        return AddressResolverLib.getCollateralManagementAddress(VM);
    }

    function getPauseRegistryAddress() internal view returns (address) {
        return AddressResolverLib.getPauseRegistryAddress(VM);
    }
}
