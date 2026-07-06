// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Script, console} from "lib/forge-std/src/Script.sol";
import {HelperConfig} from "../HelperConfig.s.sol";
import {PegInAddressRegistry} from "../../src/PegInAddressRegistry.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";

/// @title DeployPegInAddressRegistry
/// @notice Deploys the PegInAddressRegistry with the proxy pattern
contract DeployPegInAddressRegistry is Script {
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

        vm.startBroadcast(deployerKey);
        result = _deploy(deployer, cfg);
        vm.stopBroadcast();

        _log(result);
    }

    function _deploy(
        address defaultAdmin,
        HelperConfig.FlyoverConfig memory cfg
    ) private returns (DeploymentResult memory result) {
        result.implementation = address(new PegInAddressRegistry());
        result.admin = address(new ProxyAdmin(defaultAdmin));
        result.proxy = address(
            new TransparentUpgradeableProxy(
                result.implementation,
                result.admin,
                abi.encodeCall(
                    PegInAddressRegistry.initialize,
                    (
                        defaultAdmin,
                        cfg.adminDelay,
                        cfg.bridge,
                        cfg.mainnet
                    )
                )
            )
        );
    }

    function _log(DeploymentResult memory r) private pure {
        console.log("=== PegInAddressRegistry Deployed ===");
        console.log("Implementation:", r.implementation);
        console.log("Proxy:", r.proxy);
        console.log("ProxyAdmin:", r.admin);
    }
}
