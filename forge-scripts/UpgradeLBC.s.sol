// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Script, console} from "forge-std/Script.sol";

import {HelperConfig} from "./HelperConfig.s.sol";

import {LiquidityBridgeContractV2} from "../contracts/legacy/LiquidityBridgeContractV2.sol";
import {LiquidityBridgeContractAdmin} from "../contracts/legacy/LiquidityBridgeContractAdmin.sol";
import {ITransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

// NOTE: It fails to call upgradeAndCall() on the admin contract properly.Needs to be fixed.
contract UpgradeLBC is Script {
    function run() external {
        HelperConfig helper = new HelperConfig();
        HelperConfig.NetworkConfig memory cfg = helper.getConfig();

        uint256 deployerKey = helper.getDeployerPrivateKey();
        address deployer = vm.rememberKey(deployerKey);

        // Get the existing proxy and admin addresses from environment or config
        address proxyAddress = cfg.existingProxy;
        address adminAddress = cfg.existingAdmin;

        require(proxyAddress != address(0), "Proxy address must be provided");
        require(adminAddress != address(0), "Admin address must be provided");

        vm.startBroadcast(deployerKey);

        console.log("=== Deploying implementation and upgrading ===");

        // Deploy new V2 implementation (libraries are linked via command line)
        LiquidityBridgeContractV2 newImplementation = new LiquidityBridgeContractV2();
        console.log("LiquidityBridgeContractV2 implementation:", address(newImplementation));

        // Get the admin contract instance
        LiquidityBridgeContractAdmin admin = LiquidityBridgeContractAdmin(adminAddress);

        // Upgrade the proxy to point to the new implementation
        admin.upgradeAndCall(
            ITransparentUpgradeableProxy(proxyAddress),
            address(newImplementation),
            abi.encodeCall(LiquidityBridgeContractV2.initializeV2, ())
        );

        console.log("Proxy upgraded successfully");
        console.log("Proxy address:", proxyAddress);
        console.log("New implementation:", address(newImplementation));

        // Verify the upgrade by checking the version
        LiquidityBridgeContractV2 upgradedContract = LiquidityBridgeContractV2(payable(proxyAddress));
        console.log("Contract version after upgrade:", upgradedContract.version());

        vm.stopBroadcast();
    }
}
