// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Script, console} from "lib/forge-std/src/Script.sol";

import {HelperConfig} from "../HelperConfig.s.sol";

import {LiquidityBridgeContractV2} from "../../contracts/legacy/LiquidityBridgeContractV2.sol";
import {LiquidityBridgeContractAdmin} from "../../contracts/legacy/LiquidityBridgeContractAdmin.sol";
import {ITransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

/**
 * @title UpgradeLBC
 * @notice Upgrades the LiquidityBridgeContract proxy to V2
 * @dev Supports two workflows:
 *      1. Deploy implementation and upgrade in one transaction (default)
 *      2. Upgrade to a pre-deployed implementation (set IMPLEMENTATION_ADDRESS env var)
 *
 * Usage:
 *   # Deploy + Upgrade:
 *   make upgrade-lbc NETWORK=testnet
 *
 *   # Upgrade to existing implementation:
 *   IMPLEMENTATION_ADDRESS=0x... make upgrade-lbc NETWORK=testnet
 */
contract UpgradeLBC is Script {
    function run() external {
        HelperConfig helper = new HelperConfig();
        HelperConfig.NetworkConfig memory cfg = helper.getConfig();

        uint256 deployerKey = helper.getDeployerPrivateKey();
        vm.rememberKey(deployerKey);

        // Get the existing proxy and admin addresses from environment or config
        address proxyAddress = cfg.existingProxy;
        address wrapperAddress = cfg.existingAdmin;

        require(proxyAddress != address(0), "Proxy address must be provided");
        require(
            wrapperAddress != address(0),
            "Admin wrapper address must be provided"
        );

        vm.startBroadcast(deployerKey);

        // Check if we should use a pre-deployed implementation
        address implementationAddress;
        try vm.envAddress("IMPLEMENTATION_ADDRESS") returns (address addr) {
            implementationAddress = addr;
            console.log("=== Using pre-deployed implementation ===");
            console.log("Implementation address:", implementationAddress);
        } catch {
            console.log("=== Deploying new implementation ===");
            // Deploy new V2 implementation (libraries are linked via command line)
            LiquidityBridgeContractV2 newImplementation = new LiquidityBridgeContractV2();
            implementationAddress = address(newImplementation);
            console.log(
                "LiquidityBridgeContractV2 implementation:",
                implementationAddress
            );
        }

        // Get the actual ProxyAdmin address from the proxy
        address proxyAdminAddress = address(
            uint160(
                uint256(
                    vm.load(
                        proxyAddress,
                        bytes32(uint256(keccak256("eip1967.proxy.admin")) - 1)
                    )
                )
            )
        );
        console.log("ProxyAdmin address:", proxyAdminAddress);

        // Get the ProxyAdmin contract instance
        LiquidityBridgeContractAdmin admin = LiquidityBridgeContractAdmin(
            proxyAdminAddress
        );

        // Get the owner of the ProxyAdmin (should be the wrapper)
        address adminOwner = admin.owner();
        console.log("ProxyAdmin owner:", adminOwner);

        vm.stopBroadcast();

        // Impersonate the ProxyAdmin owner to call upgradeAndCall
        // This works in simulation/fork mode for testing
        vm.startPrank(adminOwner);

        // Upgrade the proxy to point to the new implementation
        // Note: Pass empty bytes - no initialization needed on upgrade (initializeV2 can only be called once)
        admin.upgradeAndCall(
            ITransparentUpgradeableProxy(proxyAddress),
            implementationAddress,
            ""
        );

        vm.stopPrank();

        console.log("Proxy upgraded successfully");
        console.log("Proxy address:", proxyAddress);
        console.log("New implementation:", implementationAddress);

        // Verify the upgrade by checking the version
        LiquidityBridgeContractV2 upgradedContract = LiquidityBridgeContractV2(
            payable(proxyAddress)
        );
        console.log(
            "Contract version after upgrade:",
            upgradedContract.version()
        );
    }
}
