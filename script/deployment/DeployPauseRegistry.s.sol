// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Script, console} from "lib/forge-std/src/Script.sol";
import {HelperConfig} from "../HelperConfig.s.sol";
import {ProxyReader} from "../helpers/ProxyReader.sol";
import {PauseRegistry} from "../../src/PauseRegistry.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

/// @title DeployPauseRegistry
/// @notice Deploys the PauseRegistry with proxy pattern (no dependencies)
contract DeployPauseRegistry is Script {
    struct DeploymentResult {
        address implementation;
        address proxy;
        address admin;
    }

    function run() external returns (DeploymentResult memory result) {
        HelperConfig helper = new HelperConfig();
        uint256 deployerKey = helper.getDeployerPrivateKey();
        address deployer = vm.rememberKey(deployerKey);

        vm.startBroadcast(deployerKey);
        result = _deploy(deployer);
        vm.stopBroadcast();

        _log(result);
    }

    function _deploy(
        address defaultAdmin
    ) private returns (DeploymentResult memory result) {
        result.implementation = address(new PauseRegistry());
        result.proxy = address(
            new TransparentUpgradeableProxy(
                result.implementation,
                defaultAdmin,
                abi.encodeCall(PauseRegistry.initialize, (0, defaultAdmin))
            )
        );
        result.admin = ProxyReader.readAdmin(vm, result.proxy);
    }

    function _log(DeploymentResult memory r) private pure {
        console.log("=== PauseRegistry Deployed ===");
        console.log("Implementation:", r.implementation);
        console.log("Proxy:", r.proxy);
        console.log("ProxyAdmin:", r.admin);
    }
}
