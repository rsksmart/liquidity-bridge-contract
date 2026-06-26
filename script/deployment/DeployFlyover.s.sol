// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Options} from "openzeppelin-foundry-upgrades/Options.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";

import {Script, console} from "lib/forge-std/src/Script.sol";

import {HelperConfig} from "../HelperConfig.s.sol";
import {ProxyReader} from "../helpers/ProxyReader.sol";

import {CollateralManagementContract} from "../../src/CollateralManagement.sol";
import {FlyoverDiscovery} from "../../src/FlyoverDiscovery.sol";
import {PauseRegistry} from "../../src/PauseRegistry.sol";
import {PegInContract} from "../../src/PegInContract.sol";
import {PegOutContract} from "../../src/PegOutContract.sol";

import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

/// @title DeployFlyover
/// @notice Orchestrates the deployment of all Flyover contracts and sets up roles
contract DeployFlyover is Script {
    struct FlyoverDeployment {
        address pauseRegistryImpl;
        address pauseRegistryProxy;
        address pauseRegistryProxyAdmin;
        address collateralManagementImpl;
        address collateralManagementProxy;
        address collateralManagementProxyAdmin;
        address flyoverDiscoveryImpl;
        address flyoverDiscoveryProxy;
        address flyoverDiscoveryProxyAdmin;
        address pegInImpl;
        address pegInProxy;
        address pegInProxyAdmin;
        address pegOutImpl;
        address pegOutProxy;
        address pegOutProxyAdmin;
    }

    function run() external returns (FlyoverDeployment memory) {
        HelperConfig helper = new HelperConfig();
        HelperConfig.FlyoverConfig memory cfg = helper.getFlyoverConfig();

        uint256 deployerKey = helper.getDeployerPrivateKey();
        address deployer = vm.rememberKey(deployerKey);

        address defaultAdmin = deployer;

        console.log(
            "======================== Config =========================="
        );
        console.log("Bridge:", cfg.bridge);
        console.log("Minimum Collateral:", cfg.minimumCollateral);
        console.log("Minimum PegIn:", cfg.minimumPegIn);
        console.log("Reward Percentage:", cfg.rewardPercentage);
        console.log("Resign Delay Blocks:", cfg.resignDelayBlocks);
        console.log("Dust Threshold:", cfg.dustThreshold);
        console.log("BTC Block Time:", cfg.btcBlockTime);
        console.log("Mainnet:", cfg.mainnet);
        console.log("Admin Delay:", cfg.adminDelay);
        console.log("Default Admin:", defaultAdmin);
        console.log(
            "=========================================================="
        );

        vm.startBroadcast(deployerKey);

        FlyoverDeployment memory d = _deployAll(
            defaultAdmin,
            cfg,
            helper.getOptions()
        );
        _setupRoles(d);
        _initializeV2_1_0(d);

        vm.stopBroadcast();

        _log(d);
        return d;
    }

    /// @notice Test-only helper to deploy without broadcast/env key lookup.
    /// @dev Reuses the same deployment and role wiring logic as run().
    function deployForTesting(
        address defaultAdmin,
        HelperConfig.FlyoverConfig memory cfg,
        Options memory opts
    ) external returns (FlyoverDeployment memory d) {
        d = _deployAll(defaultAdmin, cfg, opts);
        _setupRoles(d);
        _initializeV2_1_0(d);
    }

    function _deployAll(
        address defaultAdmin,
        HelperConfig.FlyoverConfig memory cfg,
        Options memory opts
    ) private returns (FlyoverDeployment memory d) {
        // 0) PauseRegistry (shared by all)
        address pauseRegistryProxy = Upgrades.deployTransparentProxy(
            "PauseRegistry.sol",
            defaultAdmin,
            abi.encodeCall(
                PauseRegistry.initialize,
                (cfg.adminDelay, defaultAdmin)
            ),
            opts
        );
        d.pauseRegistryProxy = pauseRegistryProxy;
        d.pauseRegistryImpl = ProxyReader.readImplementation(
            vm,
            pauseRegistryProxy
        );
        d.pauseRegistryProxyAdmin = ProxyReader.readAdmin(
            vm,
            pauseRegistryProxy
        );

        // 1) CollateralManagement
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
        d.collateralManagementProxy = collateralManagementProxy;
        d.collateralManagementImpl = ProxyReader.readImplementation(
            vm,
            collateralManagementProxy
        );
        d.collateralManagementProxyAdmin = ProxyReader.readAdmin(
            vm,
            d.collateralManagementProxy
        );

        // 2) FlyoverDiscovery
        address flyoverDiscoveryProxy = Upgrades.deployTransparentProxy(
            "FlyoverDiscovery.sol",
            defaultAdmin,
            abi.encodeCall(
                FlyoverDiscovery.initialize,
                (
                    defaultAdmin,
                    cfg.adminDelay,
                    d.collateralManagementProxy,
                    PauseRegistry(pauseRegistryProxy)
                )
            ),
            opts
        );
        d.flyoverDiscoveryProxy = flyoverDiscoveryProxy;
        d.flyoverDiscoveryImpl = ProxyReader.readImplementation(
            vm,
            flyoverDiscoveryProxy
        );
        d.flyoverDiscoveryProxyAdmin = ProxyReader.readAdmin(
            vm,
            flyoverDiscoveryProxy
        );

        // 3) PegInContract
        address pegInProxy = Upgrades.deployTransparentProxy(
            "PegInContract.sol",
            defaultAdmin,
            abi.encodeCall(
                PegInContract.initialize,
                (
                    defaultAdmin,
                    payable(cfg.bridge),
                    cfg.dustThreshold,
                    cfg.minimumPegIn,
                    d.collateralManagementProxy,
                    cfg.mainnet,
                    PauseRegistry(pauseRegistryProxy)
                )
            ),
            opts
        );
        d.pegInProxy = pegInProxy;
        d.pegInImpl = ProxyReader.readImplementation(vm, pegInProxy);
        d.pegInProxyAdmin = ProxyReader.readAdmin(vm, pegInProxy);

        // 4) PegOutContract
        address pegOutProxy = Upgrades.deployTransparentProxy(
            "PegOutContract.sol",
            defaultAdmin,
            abi.encodeCall(
                PegOutContract.initialize,
                (
                    defaultAdmin,
                    payable(cfg.bridge),
                    cfg.dustThreshold,
                    d.collateralManagementProxy,
                    cfg.mainnet,
                    cfg.btcBlockTime,
                    PauseRegistry(pauseRegistryProxy)
                )
            ),
            opts
        );
        d.pegOutProxy = pegOutProxy;
        d.pegOutImpl = ProxyReader.readImplementation(vm, pegOutProxy);
        d.pegOutProxyAdmin = ProxyReader.readAdmin(vm, pegOutProxy);
    }

    function _setupRoles(FlyoverDeployment memory d) private {
        CollateralManagementContract cm = CollateralManagementContract(
            payable(d.collateralManagementProxy)
        );
        bytes32 adder = cm.COLLATERAL_ADDER();
        bytes32 slasher = cm.COLLATERAL_SLASHER();

        cm.grantRole(adder, d.flyoverDiscoveryProxy);
        cm.grantRole(slasher, d.pegInProxy);
        cm.grantRole(slasher, d.pegOutProxy);
    }

    function _initializeV2_1_0(FlyoverDeployment memory d) private {
        CollateralManagementContract cm = CollateralManagementContract(
            payable(d.collateralManagementProxy)
        );
        FlyoverDiscovery discovery = FlyoverDiscovery(d.flyoverDiscoveryProxy);

        cm.initializeV2_1_0(d.flyoverDiscoveryProxy);
        discovery.initializeV2_1_0();
    }

    function _log(FlyoverDeployment memory d) private pure {
        console.log("=== FLYOVER DEPLOYMENT ===");
        console.log("PauseRegistry proxy:", d.pauseRegistryProxy);
        console.log("PauseRegistry ProxyAdmin:", d.pauseRegistryProxyAdmin);
        console.log("CollateralManagement impl:", d.collateralManagementImpl);
        console.log("CollateralManagement proxy:", d.collateralManagementProxy);
        console.log(
            "CollateralManagement ProxyAdmin:",
            d.collateralManagementProxyAdmin
        );
        console.log("FlyoverDiscovery impl:", d.flyoverDiscoveryImpl);
        console.log("FlyoverDiscovery proxy:", d.flyoverDiscoveryProxy);
        console.log(
            "FlyoverDiscovery ProxyAdmin:",
            d.flyoverDiscoveryProxyAdmin
        );
        console.log("PegInContract impl:", d.pegInImpl);
        console.log("PegInContract proxy:", d.pegInProxy);
        console.log("PegInContract ProxyAdmin:", d.pegInProxyAdmin);
        console.log("PegOutContract impl:", d.pegOutImpl);
        console.log("PegOutContract proxy:", d.pegOutProxy);
        console.log("PegOutContract ProxyAdmin:", d.pegOutProxyAdmin);
    }
}
