// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Script, console} from "lib/forge-std/src/Script.sol";

import {HelperConfig} from "../HelperConfig.s.sol";

import {CollateralManagementContract} from "../../src/CollateralManagement.sol";
import {FlyoverDiscovery} from "../../src/FlyoverDiscovery.sol";
import {PegInContract} from "../../src/PegInContract.sol";
import {PegOutContract} from "../../src/PegOutContract.sol";

import {DeployCollateralManagement} from "./DeployCollateralManagement.s.sol";
import {DeployFlyoverDiscovery} from "./DeployFlyoverDiscovery.s.sol";
import {DeployPegIn} from "./DeployPegIn.s.sol";
import {DeployPegOut} from "./DeployPegOut.s.sol";

/// @title DeployFlyover
/// @notice Orchestrates the deployment of all Flyover contracts and sets up roles
/// @dev Deploys in order: CollateralManagement -> FlyoverDiscovery -> PegIn -> PegOut -> Roles
contract DeployFlyover is Script {
    struct FlyoverDeployment {
        address collateralManagementImpl;
        address collateralManagementProxy;
        address collateralManagementAdmin;
        address flyoverDiscoveryImpl;
        address flyoverDiscoveryProxy;
        address flyoverDiscoveryAdmin;
        address pegInImpl;
        address pegInProxy;
        address pegInAdmin;
        address pegOutImpl;
        address pegOutProxy;
        address pegOutAdmin;
    }

    function run() external returns (FlyoverDeployment memory) {
        HelperConfig helper = new HelperConfig();
        HelperConfig.FlyoverConfig memory cfg = helper.getFlyoverConfig();

        uint256 deployerKey = helper.getDeployerPrivateKey();
        address deployer = vm.rememberKey(deployerKey);

        vm.startBroadcast(deployerKey);

        FlyoverDeployment memory deployment = deployAll(deployer, cfg);
        setupRoles(deployment);

        vm.stopBroadcast();

        logDeployment(deployment);

        return deployment;
    }

    /// @notice Deploys all Flyover contracts
    /// @param defaultAdmin The address that will be the default admin for all contracts
    /// @param cfg The Flyover configuration
    /// @return deployment The deployment result containing all contract addresses
    function deployAll(
        address defaultAdmin,
        HelperConfig.FlyoverConfig memory cfg
    ) public returns (FlyoverDeployment memory deployment) {
        // 1) Deploy CollateralManagement first (no dependencies)
        console.log("=== Deploying CollateralManagement ===");
        DeployCollateralManagement deployerCM = new DeployCollateralManagement();
        DeployCollateralManagement.DeploymentResult memory cmResult = deployerCM
            .deploy(defaultAdmin, cfg);
        deployment.collateralManagementImpl = cmResult.implementation;
        deployment.collateralManagementProxy = cmResult.proxy;
        deployment.collateralManagementAdmin = cmResult.admin;

        // 2) Deploy FlyoverDiscovery (requires CollateralManagement)
        console.log("");
        console.log("=== Deploying FlyoverDiscovery ===");
        DeployFlyoverDiscovery deployerFD = new DeployFlyoverDiscovery();
        DeployFlyoverDiscovery.DeploymentResult memory fdResult = deployerFD
            .deploy(defaultAdmin, cfg, deployment.collateralManagementProxy);
        deployment.flyoverDiscoveryImpl = fdResult.implementation;
        deployment.flyoverDiscoveryProxy = fdResult.proxy;
        deployment.flyoverDiscoveryAdmin = fdResult.admin;

        // 3) Deploy PegInContract (requires CollateralManagement)
        console.log("");
        console.log("=== Deploying PegInContract ===");
        DeployPegIn deployerPI = new DeployPegIn();
        DeployPegIn.DeploymentResult memory piResult = deployerPI.deploy(
            defaultAdmin,
            cfg,
            deployment.collateralManagementProxy
        );
        deployment.pegInImpl = piResult.implementation;
        deployment.pegInProxy = piResult.proxy;
        deployment.pegInAdmin = piResult.admin;

        // 4) Deploy PegOutContract (requires CollateralManagement)
        console.log("");
        console.log("=== Deploying PegOutContract ===");
        DeployPegOut deployerPO = new DeployPegOut();
        DeployPegOut.DeploymentResult memory poResult = deployerPO.deploy(
            defaultAdmin,
            cfg,
            deployment.collateralManagementProxy
        );
        deployment.pegOutImpl = poResult.implementation;
        deployment.pegOutProxy = poResult.proxy;
        deployment.pegOutAdmin = poResult.admin;
    }

    /// @notice Sets up cross-contract roles required for the Flyover system
    /// @param deployment The deployment result containing all contract addresses
    function setupRoles(FlyoverDeployment memory deployment) public {
        console.log("");
        console.log("=== Setting up roles ===");

        CollateralManagementContract cm = CollateralManagementContract(
            payable(deployment.collateralManagementProxy)
        );

        // Grant COLLATERAL_ADDER to FlyoverDiscovery
        // This allows FlyoverDiscovery to add collateral when LPs register
        bytes32 collateralAdderRole = cm.COLLATERAL_ADDER();
        cm.grantRole(collateralAdderRole, deployment.flyoverDiscoveryProxy);
        console.log(
            "Granted COLLATERAL_ADDER to FlyoverDiscovery:",
            deployment.flyoverDiscoveryProxy
        );

        // Grant COLLATERAL_SLASHER to PegInContract
        // This allows PegInContract to slash collateral when penalizing LPs
        bytes32 collateralSlasherRole = cm.COLLATERAL_SLASHER();
        cm.grantRole(collateralSlasherRole, deployment.pegInProxy);
        console.log(
            "Granted COLLATERAL_SLASHER to PegInContract:",
            deployment.pegInProxy
        );

        // Grant COLLATERAL_SLASHER to PegOutContract
        // This allows PegOutContract to slash collateral when penalizing LPs
        cm.grantRole(collateralSlasherRole, deployment.pegOutProxy);
        console.log(
            "Granted COLLATERAL_SLASHER to PegOutContract:",
            deployment.pegOutProxy
        );
    }

    /// @notice Logs the deployment addresses
    /// @param deployment The deployment result containing all contract addresses
    function logDeployment(FlyoverDeployment memory deployment) internal view {
        console.log("");
        console.log("========================================");
        console.log("        FLYOVER DEPLOYMENT SUMMARY       ");
        console.log("========================================");
        console.log("");
        console.log("CollateralManagement:");
        console.log(
            "  Version:",
            CollateralManagementContract(
                payable(deployment.collateralManagementProxy)
            ).VERSION()
        );
        console.log("  Implementation:", deployment.collateralManagementImpl);
        console.log("  Proxy:", deployment.collateralManagementProxy);
        console.log("  Admin:", deployment.collateralManagementAdmin);
        console.log("");
        console.log("FlyoverDiscovery:");
        console.log(
            "  Version:",
            FlyoverDiscovery(deployment.flyoverDiscoveryProxy).VERSION()
        );
        console.log("  Implementation:", deployment.flyoverDiscoveryImpl);
        console.log("  Proxy:", deployment.flyoverDiscoveryProxy);
        console.log("  Admin:", deployment.flyoverDiscoveryAdmin);
        console.log("");
        console.log("PegInContract:");
        console.log(
            "  Version:",
            PegInContract(payable(deployment.pegInProxy)).VERSION()
        );
        console.log("  Implementation:", deployment.pegInImpl);
        console.log("  Proxy:", deployment.pegInProxy);
        console.log("  Admin:", deployment.pegInAdmin);
        console.log("");
        console.log("PegOutContract:");
        console.log(
            "  Version:",
            PegOutContract(payable(deployment.pegOutProxy)).VERSION()
        );
        console.log("  Implementation:", deployment.pegOutImpl);
        console.log("  Proxy:", deployment.pegOutProxy);
        console.log("  Admin:", deployment.pegOutAdmin);
        console.log("");
        console.log("========================================");
    }
}
