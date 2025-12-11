// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Script, console} from "lib/forge-std/src/Script.sol";

import {HelperConfig} from "../HelperConfig.s.sol";

import {PegInContract} from "../../src/PegInContract.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";

/// @title DeployPegIn
/// @notice Deploys the PegInContract with proxy pattern
/// @dev Requires CollateralManagement to be deployed first
contract DeployPegIn is Script {
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

        // Get the CollateralManagement proxy address from environment
        address collateralManagementProxy = vm.envAddress(
            "COLLATERAL_MANAGEMENT_PROXY"
        );
        require(
            collateralManagementProxy != address(0),
            "COLLATERAL_MANAGEMENT_PROXY must be set"
        );

        vm.startBroadcast(deployerKey);

        DeploymentResult memory result = deploy(
            deployer,
            cfg,
            collateralManagementProxy
        );

        vm.stopBroadcast();

        return result;
    }

    /// @notice Deploys PegInContract with the given configuration
    /// @param defaultAdmin The address that will be the default admin
    /// @param cfg The Flyover configuration
    /// @param collateralManagementProxy The address of the CollateralManagement proxy
    /// @return result The deployment result containing implementation, proxy, and admin addresses
    function deploy(
        address defaultAdmin,
        HelperConfig.FlyoverConfig memory cfg,
        address collateralManagementProxy
    ) public returns (DeploymentResult memory result) {
        // 1) Deploy implementation
        PegInContract implementation = new PegInContract();
        console.log("PegInContract implementation:", address(implementation));

        // 2) Deploy Proxy Admin
        ProxyAdmin admin = new ProxyAdmin(defaultAdmin);
        console.log("PegInContract ProxyAdmin:", address(admin));

        // 3) Prepare initializer calldata
        bytes memory initData = abi.encodeCall(
            PegInContract.initialize,
            (
                defaultAdmin,
                payable(cfg.bridge),
                cfg.dustThreshold,
                cfg.minimumPegIn,
                collateralManagementProxy,
                cfg.mainnet,
                cfg.daoFeePercentage,
                cfg.daoFeeCollector
            )
        );

        // 4) Deploy TransparentUpgradeableProxy with initializer
        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(
            address(implementation),
            address(admin),
            initData
        );
        console.log("PegInContract proxy:", address(proxy));

        // Sanity check
        PegInContract pegIn = PegInContract(payable(address(proxy)));
        console.log("PegInContract version:", pegIn.VERSION());
        console.log("PegInContract minPegIn:", pegIn.getMinPegIn());

        result = DeploymentResult({
            implementation: address(implementation),
            proxy: address(proxy),
            admin: address(admin)
        });
    }
}
