// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Script, console} from "lib/forge-std/src/Script.sol";

import {HelperConfig} from "../HelperConfig.s.sol";

import {CollateralManagementContract} from "../../src/CollateralManagement.sol";
import {FlyoverDiscovery} from "../../src/FlyoverDiscovery.sol";
import {PauseRegistry} from "../../src/PauseRegistry.sol";
import {PegInContract} from "../../src/PegInContract.sol";
import {PegOutContract} from "../../src/PegOutContract.sol";

import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";

/// @title DeployFlyover
/// @notice Orchestrates the deployment of all Flyover contracts and sets up roles
/// @dev Gas optimized: single ProxyAdmin, inlined deployment logic, linked libraries
contract DeployFlyover is Script {
    struct FlyoverDeployment {
        address pauseRegistryProxy;
        address collateralManagementImpl;
        address collateralManagementProxy;
        address flyoverDiscoveryImpl;
        address flyoverDiscoveryProxy;
        address pegInImpl;
        address pegInProxy;
        address pegOutImpl;
        address pegOutProxy;
        address proxyAdmin; // Single ProxyAdmin for all
    }

    function run() external returns (FlyoverDeployment memory) {
        HelperConfig helper = new HelperConfig();
        HelperConfig.FlyoverConfig memory cfg = helper.getFlyoverConfig();
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
        console.log(
            "=========================================================="
        );

        uint256 deployerKey = helper.getDeployerPrivateKey();
        address deployer = vm.rememberKey(deployerKey);

        vm.startBroadcast(deployerKey);

        FlyoverDeployment memory d = _deployAll(deployer, cfg);
        _setupRoles(d);

        vm.stopBroadcast();

        _log(d);
        return d;
    }

    function _deployAll(
        address defaultAdmin,
        HelperConfig.FlyoverConfig memory cfg
    ) private returns (FlyoverDeployment memory d) {
        // Single ProxyAdmin for all contracts
        d.proxyAdmin = address(new ProxyAdmin(defaultAdmin));

        // 0) PauseRegistry (shared by all)
        PauseRegistry prImpl = new PauseRegistry();
        d.pauseRegistryProxy = address(
            new TransparentUpgradeableProxy(
                address(prImpl),
                d.proxyAdmin,
                abi.encodeCall(prImpl.initialize, (0, defaultAdmin))
            )
        );

        // 1) CollateralManagement
        d.collateralManagementImpl = address(
            new CollateralManagementContract()
        );
        d.collateralManagementProxy = address(
            new TransparentUpgradeableProxy(
                d.collateralManagementImpl,
                d.proxyAdmin,
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

        // 2) FlyoverDiscovery
        d.flyoverDiscoveryImpl = address(new FlyoverDiscovery());
        d.flyoverDiscoveryProxy = address(
            new TransparentUpgradeableProxy(
                d.flyoverDiscoveryImpl,
                d.proxyAdmin,
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

        // 3) PegInContract
        d.pegInImpl = address(new PegInContract());
        d.pegInProxy = address(
            new TransparentUpgradeableProxy(
                d.pegInImpl,
                d.proxyAdmin,
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

        // 4) PegOutContract
        d.pegOutImpl = address(new PegOutContract());
        d.pegOutProxy = address(
            new TransparentUpgradeableProxy(
                d.pegOutImpl,
                d.proxyAdmin,
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
        console.log("ProxyAdmin:", d.proxyAdmin);
        console.log("PauseRegistry proxy:", d.pauseRegistryProxy);
        console.log("CollateralManagement impl:", d.collateralManagementImpl);
        console.log("CollateralManagement proxy:", d.collateralManagementProxy);
        console.log("FlyoverDiscovery impl:", d.flyoverDiscoveryImpl);
        console.log("FlyoverDiscovery proxy:", d.flyoverDiscoveryProxy);
        console.log("PegInContract impl:", d.pegInImpl);
        console.log("PegInContract proxy:", d.pegInProxy);
        console.log("PegOutContract impl:", d.pegOutImpl);
        console.log("PegOutContract proxy:", d.pegOutProxy);
    }
}
