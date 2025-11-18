// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Script, console} from "lib/forge-std/src/Script.sol";

import {HelperConfig} from "../HelperConfig.s.sol";
import {LiquidityBridgeContractV2} from "../../src/legacy/LiquidityBridgeContractV2.sol";

/**
 * @title PrepareUpgrade
 * @notice Deploys the V2 implementation WITHOUT upgrading the proxy
 * @dev This allows for a two-step upgrade process:
 *      1. Deploy and verify the implementation (this script)
 *      2. Perform the actual upgrade (UpgradeLBC script)
 *
 * Usage:
 *   make prepare-upgrade NETWORK=testnet
 */
contract PrepareUpgrade is Script {
    function run() external {
        HelperConfig helper = new HelperConfig();

        uint256 deployerKey = helper.getDeployerPrivateKey();
        vm.rememberKey(deployerKey);

        vm.startBroadcast(deployerKey);

        console.log(
            "=== Deploying LiquidityBridgeContractV2 implementation ==="
        );

        // Deploy new V2 implementation (libraries are linked via command line)
        LiquidityBridgeContractV2 newImplementation = new LiquidityBridgeContractV2();

        console.log("IMPLEMENTATION ADDRESS:", address(newImplementation));
        console.log("");
        console.log("Next step:");
        console.log(
            "Run the upgrade script: make upgrade-lbc NETWORK=<network>"
        );

        vm.stopBroadcast();
    }
}
