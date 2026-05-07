// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

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

        FlyoverDeployment memory d = _deployAll(defaultAdmin, cfg);
        _setupRoles(d);

        vm.stopBroadcast();

        _log(d);
        return d;
    }

    function _deployAll(
        address defaultAdmin,
        HelperConfig.FlyoverConfig memory cfg
    ) private returns (FlyoverDeployment memory d) {
        // 0) PauseRegistry (shared by all)
        PauseRegistry prImpl = new PauseRegistry();
        d.pauseRegistryProxy = address(
            new TransparentUpgradeableProxy(
                address(prImpl),
                defaultAdmin,
                abi.encodeCall(
                    prImpl.initialize,
                    (cfg.adminDelay, defaultAdmin)
                )
            )
        );
        d.pauseRegistryProxyAdmin = ProxyReader.readAdmin(
            vm,
            d.pauseRegistryProxy
        );

        // 1) CollateralManagement
        d.collateralManagementImpl = address(
            new CollateralManagementContract()
        );
        d.collateralManagementProxy = address(
            new TransparentUpgradeableProxy(
                d.collateralManagementImpl,
                defaultAdmin,
                abi.encodeCall(
                    CollateralManagementContract.initialize,
                    (
                        defaultAdmin,
                        cfg.adminDelay,
                        cfg.minimumCollateral,
                        cfg.resignDelayBlocks,
                        cfg.rewardPercentage,
                        PauseRegistry(d.pauseRegistryProxy)
                    )
                )
            )
        );
        d.collateralManagementProxyAdmin = ProxyReader.readAdmin(
            vm,
            d.collateralManagementProxy
        );

        // 2) FlyoverDiscovery
        d.flyoverDiscoveryImpl = address(new FlyoverDiscovery());
        d.flyoverDiscoveryProxy = address(
            new TransparentUpgradeableProxy(
                d.flyoverDiscoveryImpl,
                defaultAdmin,
                abi.encodeCall(
                    FlyoverDiscovery.initialize,
                    (
                        defaultAdmin,
                        cfg.adminDelay,
                        d.collateralManagementProxy,
                        PauseRegistry(d.pauseRegistryProxy)
                    )
                )
            )
        );
        d.flyoverDiscoveryProxyAdmin = ProxyReader.readAdmin(
            vm,
            d.flyoverDiscoveryProxy
        );

        // 3) PegInContract
        d.pegInImpl = address(new PegInContract());
        d.pegInProxy = address(
            new TransparentUpgradeableProxy(
                d.pegInImpl,
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
                        PauseRegistry(d.pauseRegistryProxy)
                    )
                )
            )
        );
        d.pegInProxyAdmin = ProxyReader.readAdmin(vm, d.pegInProxy);

        // 4) PegOutContract
        d.pegOutImpl = address(new PegOutContract());
        d.pegOutProxy = address(
            new TransparentUpgradeableProxy(
                d.pegOutImpl,
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
                        PauseRegistry(d.pauseRegistryProxy)
                    )
                )
            )
        );
        d.pegOutProxyAdmin = ProxyReader.readAdmin(vm, d.pegOutProxy);
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
