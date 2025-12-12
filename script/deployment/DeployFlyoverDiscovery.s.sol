// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Script, console} from "lib/forge-std/src/Script.sol";
import {HelperConfig} from "../HelperConfig.s.sol";
import {FlyoverDiscovery} from "../../src/FlyoverDiscovery.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";

/// @title DeployFlyoverDiscovery
/// @notice Deploys the FlyoverDiscovery contract with proxy pattern
/// @dev Requires COLLATERAL_MANAGEMENT_PROXY env var
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
        require(
            collateralManagementProxy != address(0),
            "COLLATERAL_MANAGEMENT_PROXY required"
        );

        vm.startBroadcast(deployerKey);
        result = _deploy(deployer, cfg, collateralManagementProxy);
        vm.stopBroadcast();

        _log(result);
    }

    function _deploy(
        address defaultAdmin,
        HelperConfig.FlyoverConfig memory cfg,
        address collateralManagementProxy
    ) private returns (DeploymentResult memory result) {
        result.implementation = address(new FlyoverDiscovery());
        result.admin = address(new ProxyAdmin(defaultAdmin));
        result.proxy = address(
            new TransparentUpgradeableProxy(
                result.implementation,
                result.admin,
                abi.encodeCall(
                    FlyoverDiscovery.initialize,
                    (defaultAdmin, cfg.adminDelay, collateralManagementProxy)
                )
            )
        );
    }

    function _log(DeploymentResult memory r) private pure {
        console.log("=== FlyoverDiscovery Deployed ===");
        console.log("Implementation:", r.implementation);
        console.log("Proxy:", r.proxy);
        console.log("ProxyAdmin:", r.admin);
    }
}
