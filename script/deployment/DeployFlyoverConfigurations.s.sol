// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Options} from "openzeppelin-foundry-upgrades/Options.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";

import {Script, console} from "lib/forge-std/src/Script.sol";

import {HelperConfig} from "../HelperConfig.s.sol";
import {ProxyReader} from "../helpers/ProxyReader.sol";

import {FlyoverConfigurations} from "../../src/FlyoverConfigurations.sol";
import {FlyoverConfigurationsRegtest} from "../../src/libraries/FlyoverConfigurationsRegtest.sol";

/// @title DeployFlyoverConfigurations
/// @notice Deploys FlyoverConfigurations with provisional regtest seed values (S12.1).
contract DeployFlyoverConfigurations is Script {
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
        result = _deploy(deployer, cfg.adminDelay, helper.getOptions());
        vm.stopBroadcast();

        _log(result);
    }

    /// @notice Test-only helper to deploy without broadcast/env key lookup.
    function deployForTesting(
        address defaultAdmin,
        uint48 adminDelay,
        Options memory opts
    ) external returns (DeploymentResult memory) {
        return _deploy(defaultAdmin, adminDelay, opts);
    }

    function _deploy(
        address defaultAdmin,
        uint48 adminDelay,
        Options memory opts
    ) private returns (DeploymentResult memory result) {
        address proxy = Upgrades.deployTransparentProxy(
            "FlyoverConfigurations.sol",
            defaultAdmin,
            abi.encodeCall(
                FlyoverConfigurations.initialize,
                (
                    defaultAdmin,
                    adminDelay,
                    FlyoverConfigurationsRegtest.TIMELOCK_DELAY,
                    FlyoverConfigurationsRegtest.pegInConfig(),
                    FlyoverConfigurationsRegtest.pegInMin(),
                    FlyoverConfigurationsRegtest.pegInMax()
                )
            ),
            opts
        );

        FlyoverConfigurations(payable(proxy)).initializePegOut(
            FlyoverConfigurationsRegtest.pegOutConfig(),
            FlyoverConfigurationsRegtest.pegOutMin(),
            FlyoverConfigurationsRegtest.pegOutMax()
        );

        result.proxy = proxy;
        result.implementation = ProxyReader.readImplementation(vm, proxy);
        result.admin = ProxyReader.readAdmin(vm, proxy);
    }

    function _log(DeploymentResult memory r) private pure {
        console.log("=== FlyoverConfigurations Deployed ===");
        console.log("Implementation:", r.implementation);
        console.log("Proxy:", r.proxy);
        console.log("ProxyAdmin:", r.admin);
    }
}
