// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Script, console} from "lib/forge-std/src/Script.sol";
import {HelperConfig} from "../HelperConfig.s.sol";
import {ProxyReader} from "../helpers/ProxyReader.sol";
import {FlyoverDiscovery} from "../../src/FlyoverDiscovery.sol";
import {PauseRegistry} from "../../src/PauseRegistry.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {Options} from "openzeppelin-foundry-upgrades/Options.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";

/// @title DeployFlyoverDiscovery
/// @notice Deploys the FlyoverDiscovery contract with proxy pattern
/// @dev Requires COLLATERAL_MANAGEMENT_PROXY and PAUSE_REGISTRY_PROXY env vars
contract DeployFlyoverDiscovery is Script {
    struct DeploymentResult {
        address implementation;
        address proxy;
        address admin;
    }

    function run() external returns (DeploymentResult memory result) {
        HelperConfig helper = new HelperConfig();
        HelperConfig.FlyoverConfig memory cfg = helper.getFlyoverConfig();
        uint256 deployerKey = helper.getDeployerPrivateKey();
        address deployer = vm.rememberKey(deployerKey);

        address collateralManagementProxy = vm.envAddress(
            "COLLATERAL_MANAGEMENT_PROXY"
        );
        address pauseRegistryProxy = vm.envAddress("PAUSE_REGISTRY_PROXY");
        require(
            collateralManagementProxy != address(0),
            "COLLATERAL_MANAGEMENT_PROXY required"
        );
        require(
            pauseRegistryProxy != address(0),
            "PAUSE_REGISTRY_PROXY required"
        );

        vm.startBroadcast(deployerKey);
        result = _deploy(
            deployer,
            cfg,
            collateralManagementProxy,
            pauseRegistryProxy,
            helper.getOptions()
        );
        vm.stopBroadcast();

        _log(result);
    }

    function _deploy(
        address defaultAdmin,
        HelperConfig.FlyoverConfig memory cfg,
        address collateralManagementProxy,
        address pauseRegistryProxy,
        Options memory opts
    ) private returns (DeploymentResult memory result) {
        address flyoverDiscoveryProxy = Upgrades.deployTransparentProxy(
            "FlyoverDiscovery.sol",
            defaultAdmin,
            abi.encodeCall(
                FlyoverDiscovery.initialize,
                (
                    defaultAdmin,
                    cfg.adminDelay,
                    collateralManagementProxy,
                    PauseRegistry(pauseRegistryProxy)
                )
            ),
            opts
        );
        result.proxy = flyoverDiscoveryProxy;
        result.implementation = ProxyReader.readImplementation(
            vm,
            flyoverDiscoveryProxy
        );
        result.admin = ProxyReader.readAdmin(vm, flyoverDiscoveryProxy);
    }

    function _log(DeploymentResult memory r) private pure {
        console.log("=== FlyoverDiscovery Deployed ===");
        console.log("Implementation:", r.implementation);
        console.log("Proxy:", r.proxy);
        console.log("ProxyAdmin:", r.admin);
    }
}
