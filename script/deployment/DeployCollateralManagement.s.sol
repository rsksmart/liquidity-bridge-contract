// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Script, console} from "lib/forge-std/src/Script.sol";

import {HelperConfig} from "../HelperConfig.s.sol";

import {CollateralManagementContract} from "../../src/CollateralManagement.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";

/// @title DeployCollateralManagement
/// @notice Deploys the CollateralManagement contract with proxy pattern
/// @dev Must be deployed first as other Flyover contracts depend on it
contract DeployCollateralManagement is Script {
    struct DeploymentResult {
        address implementation;
        address proxy;
        address admin;
    }

    function run() external returns (DeploymentResult memory) {
        HelperConfig helper = new HelperConfig();
        HelperConfig.FlyoverConfig memory cfg = helper.getFlyoverConfig();

        uint256 deployerKey = helper.getDeployerPrivateKey();
        address deployer = vm.rememberKey(deployerKey);

        vm.startBroadcast(deployerKey);

        DeploymentResult memory result = deploy(deployer, cfg);

        vm.stopBroadcast();

        return result;
    }

    /// @notice Deploys CollateralManagement with the given configuration
    /// @param defaultAdmin The address that will be the default admin
    /// @param cfg The Flyover configuration
    /// @return result The deployment result containing implementation, proxy, and admin addresses
    function deploy(
        address defaultAdmin,
        HelperConfig.FlyoverConfig memory cfg
    ) public returns (DeploymentResult memory result) {
        // 1) Deploy implementation
        CollateralManagementContract implementation = new CollateralManagementContract();
        console.log(
            "CollateralManagement implementation:",
            address(implementation)
        );

        // 2) Deploy Proxy Admin
        ProxyAdmin admin = new ProxyAdmin(defaultAdmin);
        console.log("CollateralManagement ProxyAdmin:", address(admin));

        // 3) Prepare initializer calldata
        bytes memory initData = abi.encodeCall(
            CollateralManagementContract.initialize,
            (
                defaultAdmin,
                cfg.adminDelay,
                cfg.minimumCollateral,
                cfg.resignDelayBlocks,
                cfg.rewardPercentage
            )
        );

        // 4) Deploy TransparentUpgradeableProxy with initializer
        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(
            address(implementation),
            address(admin),
            initData
        );
        console.log("CollateralManagement proxy:", address(proxy));

        // Sanity check
        CollateralManagementContract cm = CollateralManagementContract(
            payable(address(proxy))
        );
        console.log("CollateralManagement version:", cm.VERSION());
        console.log("Min collateral:", cm.getMinCollateral());

        result = DeploymentResult({
            implementation: address(implementation),
            proxy: address(proxy),
            admin: address(admin)
        });
    }
}
