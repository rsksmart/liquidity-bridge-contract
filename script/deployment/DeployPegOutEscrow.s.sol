// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Options} from "openzeppelin-foundry-upgrades/Options.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";

import {Script, console} from "lib/forge-std/src/Script.sol";

import {HelperConfig} from "../HelperConfig.s.sol";
import {ProxyReader} from "../helpers/ProxyReader.sol";

import {CollateralManagementContract} from "../../src/CollateralManagement.sol";
import {IPauseRegistry} from "../../src/interfaces/IPauseRegistry.sol";
import {PegOutContract} from "../../src/PegOutContract.sol";
import {PegOutEscrow} from "../../src/PegOutEscrow.sol";

/// @title DeployPegOutEscrow
/// @notice Deploys PegOutEscrow with the S5 transparent-proxy pattern and wires PegOut + slash role.
/// @dev Requires PAUSE_REGISTRY_PROXY, PEGOUT_PROXY, COLLATERAL_MANAGEMENT_PROXY,
///      and FLYOVER_CONFIGURATIONS_PROXY env vars.
contract DeployPegOutEscrow is Script {
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
        address pegOutProxy = vm.envAddress("PEGOUT_PROXY");
        address collateralManagementProxy = vm.envAddress(
            "COLLATERAL_MANAGEMENT_PROXY"
        );
        address configurationsProxy = vm.envAddress(
            "FLYOVER_CONFIGURATIONS_PROXY"
        );
        require(
            pauseRegistryProxy != address(0),
            "PAUSE_REGISTRY_PROXY required"
        );
        require(pegOutProxy != address(0), "PEGOUT_PROXY required");
        require(
            collateralManagementProxy != address(0),
            "COLLATERAL_MANAGEMENT_PROXY required"
        );
        require(
            configurationsProxy != address(0),
            "FLYOVER_CONFIGURATIONS_PROXY required"
        );

        vm.startBroadcast(deployerKey);
        result = _deploy(
            deployer,
            cfg.adminDelay,
            pauseRegistryProxy,
            pegOutProxy,
            collateralManagementProxy,
            configurationsProxy,
            helper.getOptions()
        );
        vm.stopBroadcast();

        _log(result);
    }

    /// @notice Test-only helper to deploy without broadcast/env key lookup.
    function deployForTesting(
        address defaultAdmin,
        uint48 adminDelay,
        address pauseRegistryProxy,
        address pegOutProxy,
        address collateralManagementProxy,
        address configurationsProxy,
        Options memory opts
    ) external returns (DeploymentResult memory) {
        return
            _deploy(
                defaultAdmin,
                adminDelay,
                pauseRegistryProxy,
                pegOutProxy,
                collateralManagementProxy,
                configurationsProxy,
                opts
            );
    }

    function _deploy(
        address defaultAdmin,
        uint48 adminDelay,
        address pauseRegistryProxy,
        address pegOutProxy,
        address collateralManagementProxy,
        address configurationsProxy,
        Options memory opts
    ) private returns (DeploymentResult memory result) {
        address escrowProxy = Upgrades.deployTransparentProxy(
            "PegOutEscrow.sol",
            defaultAdmin,
            abi.encodeCall(
                PegOutEscrow.initialize,
                (
                    defaultAdmin,
                    adminDelay,
                    IPauseRegistry(pauseRegistryProxy),
                    pegOutProxy,
                    collateralManagementProxy,
                    configurationsProxy
                )
            ),
            opts
        );

        PegOutContract(payable(pegOutProxy)).setPegOutEscrow(escrowProxy);

        CollateralManagementContract cm = CollateralManagementContract(
            payable(collateralManagementProxy)
        );
        cm.grantRole(cm.COLLATERAL_SLASHER(), escrowProxy);

        result.proxy = escrowProxy;
        result.implementation = ProxyReader.readImplementation(vm, escrowProxy);
        result.admin = ProxyReader.readAdmin(vm, escrowProxy);
    }

    function _log(DeploymentResult memory r) private pure {
        console.log("=== PegOutEscrow Deployed ===");
        console.log("Implementation:", r.implementation);
        console.log("Proxy:", r.proxy);
        console.log("ProxyAdmin:", r.admin);
    }
}
