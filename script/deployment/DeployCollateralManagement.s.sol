// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Script, console} from "lib/forge-std/src/Script.sol";
import {HelperConfig} from "../HelperConfig.s.sol";
import {ProxyReader} from "../helpers/ProxyReader.sol";
import {CollateralManagementContract} from "../../src/CollateralManagement.sol";
import {PauseRegistry} from "../../src/PauseRegistry.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {Options} from "openzeppelin-foundry-upgrades/Options.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";

/// @title DeployCollateralManagement
/// @notice Deploys the CollateralManagement contract with proxy pattern
contract DeployCollateralManagement is Script {
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

        address pauseRegistryProxy = vm.envAddress("PAUSE_REGISTRY_PROXY");
        require(
            pauseRegistryProxy != address(0),
            "PAUSE_REGISTRY_PROXY required"
        );

        vm.startBroadcast(deployerKey);
        result = _deploy(
            deployer,
            cfg,
            pauseRegistryProxy,
            helper.getOptions()
        );
        vm.stopBroadcast();

        _log(result);
    }

    function _deploy(
        address defaultAdmin,
        HelperConfig.FlyoverConfig memory cfg,
        address pauseRegistryProxy,
        Options memory opts
    ) private returns (DeploymentResult memory result) {
        address collateralManagementProxy = Upgrades.deployTransparentProxy(
            "CollateralManagement.sol:CollateralManagementContract",
            defaultAdmin,
            abi.encodeCall(
                CollateralManagementContract.initialize,
                (
                    defaultAdmin,
                    cfg.adminDelay,
                    cfg.minimumCollateral,
                    cfg.resignDelayBlocks,
                    cfg.rewardPercentage,
                    PauseRegistry(pauseRegistryProxy)
                )
            ),
            opts
        );
        result.proxy = collateralManagementProxy;
        result.implementation = ProxyReader.readImplementation(
            vm,
            collateralManagementProxy
        );
        result.admin = ProxyReader.readAdmin(vm, collateralManagementProxy);

        address flyoverDiscoveryProxy = vm.envOr(
            "FLYOVER_DISCOVERY_PROXY",
            address(0)
        );
        if (flyoverDiscoveryProxy != address(0)) {
            CollateralManagementContract(payable(collateralManagementProxy))
                .initializeV2_1_0(flyoverDiscoveryProxy);
        }
    }

    function _log(DeploymentResult memory r) private pure {
        console.log("=== CollateralManagement Deployed ===");
        console.log("Implementation:", r.implementation);
        console.log("Proxy:", r.proxy);
        console.log("ProxyAdmin:", r.admin);
    }
}
