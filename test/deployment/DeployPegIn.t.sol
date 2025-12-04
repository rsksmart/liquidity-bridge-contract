// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import "lib/forge-std/src/Test.sol";
import "lib/forge-std/src/console.sol";
import {DeployPegIn} from "../../script/deployment/DeployPegIn.s.sol";
import {DeployCollateralManagement} from "../../script/deployment/DeployCollateralManagement.s.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {PegInContract} from "../../src/PegInContract.sol";
import {CollateralManagementContract} from "../../src/CollateralManagement.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";

/**
 * @title DeployPegInTest
 * @notice Test for the DeployPegIn deployment script
 * @dev Tests deployment and integration with CollateralManagement
 */
contract DeployPegInTest is Test {
    DeployPegIn public deployScript;
    DeployCollateralManagement public deployCMScript;
    HelperConfig public helperConfig;

    address public collateralManagementProxy;

    function setUp() public {
        deployScript = new DeployPegIn();
        deployCMScript = new DeployCollateralManagement();
        helperConfig = new HelperConfig();

        // Deploy CollateralManagement first (dependency)
        HelperConfig.FlyoverConfig memory cfg = helperConfig.getFlyoverConfig();
        DeployCollateralManagement.DeploymentResult memory cmResult = deployCMScript.deploy(address(this), cfg);
        collateralManagementProxy = cmResult.proxy;

        console.log("Setup: CollateralManagement deployed at:", collateralManagementProxy);
    }

    function test_DeploymentFlow() public {
        console.log("\n=== TEST PEG IN DEPLOYMENT ===\n");

        HelperConfig.FlyoverConfig memory cfg = helperConfig.getFlyoverConfig();
        address deployer = address(this);

        console.log("1. Deploying PegInContract implementation...");
        PegInContract implementation = new PegInContract();
        console.log("   Implementation deployed at:", address(implementation));

        console.log("\n2. Deploying Proxy Admin...");
        ProxyAdmin admin = new ProxyAdmin(deployer);
        console.log("   Admin deployed at:", address(admin));

        console.log("\n3. Preparing initializer calldata...");
        bytes memory initData = abi.encodeCall(
            PegInContract.initialize,
            (
                deployer,
                payable(cfg.bridge),
                cfg.dustThreshold,
                cfg.minimumPegIn,
                collateralManagementProxy,
                cfg.mainnet,
                cfg.daoFeePercentage,
                cfg.daoFeeCollector
            )
        );
        console.log("   Init data length:", initData.length);

        console.log("\n4. Deploying Proxy...");
        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(
            address(implementation),
            address(admin),
            initData
        );
        console.log("   Proxy deployed at:", address(proxy));

        console.log("\n5. Verifying deployment...");
        PegInContract pegIn = PegInContract(payable(address(proxy)));

        assertEq(pegIn.getMinPegIn(), cfg.minimumPegIn, "Min PegIn mismatch");
        assertEq(pegIn.dustThreshold(), cfg.dustThreshold, "Dust threshold mismatch");

        console.log("   Min PegIn:", pegIn.getMinPegIn());
        console.log("   Dust Threshold:", pegIn.dustThreshold());
        console.log("   Version:", pegIn.VERSION());

        console.log("\n[PASS] PegInContract deployment flow executed successfully!");
    }

    function test_DeployUsingScript() public {
        console.log("\n=== TEST DEPLOY USING SCRIPT ===\n");

        HelperConfig.FlyoverConfig memory cfg = helperConfig.getFlyoverConfig();
        address deployer = address(this);

        DeployPegIn.DeploymentResult memory result = deployScript.deploy(
            deployer,
            cfg,
            collateralManagementProxy
        );

        console.log("Deployment Result:");
        console.log("  Implementation:", result.implementation);
        console.log("  Proxy:", result.proxy);
        console.log("  Admin:", result.admin);

        assertTrue(result.implementation != address(0), "Implementation should not be zero");
        assertTrue(result.proxy != address(0), "Proxy should not be zero");
        assertTrue(result.admin != address(0), "Admin should not be zero");

        // Verify contract is initialized
        PegInContract pegIn = PegInContract(payable(result.proxy));
        assertEq(pegIn.getMinPegIn(), cfg.minimumPegIn, "Min PegIn mismatch");

        console.log("\n[PASS] DeployPegIn script works correctly!");
    }

    function test_IntegrationWithCollateralManagement() public {
        console.log("\n=== TEST INTEGRATION WITH COLLATERAL MANAGEMENT ===\n");

        HelperConfig.FlyoverConfig memory cfg = helperConfig.getFlyoverConfig();
        address deployer = address(this);

        // Deploy PegIn
        DeployPegIn.DeploymentResult memory piResult = deployScript.deploy(
            deployer,
            cfg,
            collateralManagementProxy
        );

        PegInContract pegIn = PegInContract(payable(piResult.proxy));
        CollateralManagementContract cm = CollateralManagementContract(payable(collateralManagementProxy));

        // Grant COLLATERAL_SLASHER role to PegIn
        bytes32 collateralSlasherRole = cm.COLLATERAL_SLASHER();
        cm.grantRole(collateralSlasherRole, piResult.proxy);

        console.log("Granted COLLATERAL_SLASHER to PegInContract");
        assertTrue(cm.hasRole(collateralSlasherRole, piResult.proxy), "PegIn should have COLLATERAL_SLASHER");

        console.log("\n[PASS] Integration with CollateralManagement verified!");
    }

    function test_RolesAreSetCorrectly() public {
        console.log("\n=== TEST ROLES ARE SET CORRECTLY ===\n");

        HelperConfig.FlyoverConfig memory cfg = helperConfig.getFlyoverConfig();
        address deployer = address(this);

        DeployPegIn.DeploymentResult memory result = deployScript.deploy(
            deployer,
            cfg,
            collateralManagementProxy
        );

        PegInContract pegIn = PegInContract(payable(result.proxy));

        // Check deployer has DEFAULT_ADMIN_ROLE
        bytes32 defaultAdminRole = pegIn.DEFAULT_ADMIN_ROLE();
        assertTrue(pegIn.hasRole(defaultAdminRole, deployer), "Deployer should have DEFAULT_ADMIN_ROLE");

        console.log("  Deployer has DEFAULT_ADMIN_ROLE: true");

        console.log("\n[PASS] Roles are set correctly!");
    }

    function test_DaoConfigurationSet() public {
        console.log("\n=== TEST DAO CONFIGURATION ===\n");

        HelperConfig.FlyoverConfig memory cfg = helperConfig.getFlyoverConfig();
        address deployer = address(this);

        DeployPegIn.DeploymentResult memory result = deployScript.deploy(
            deployer,
            cfg,
            collateralManagementProxy
        );

        PegInContract pegIn = PegInContract(payable(result.proxy));

        console.log("  DAO Fee Percentage:", pegIn.getFeePercentage());
        console.log("  DAO Fee Collector:", pegIn.getFeeCollector());

        assertEq(pegIn.getFeePercentage(), cfg.daoFeePercentage, "DAO fee percentage mismatch");
        assertEq(pegIn.getFeeCollector(), cfg.daoFeeCollector, "DAO fee collector mismatch");

        console.log("\n[PASS] DAO configuration set correctly!");
    }
}
