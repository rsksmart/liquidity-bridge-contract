// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import "lib/forge-std/src/Test.sol";
import "lib/forge-std/src/console.sol";
import {DeployPegOut} from "../../script/deployment/DeployPegOut.s.sol";
import {DeployCollateralManagement} from "../../script/deployment/DeployCollateralManagement.s.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {PegOutContract} from "../../src/PegOutContract.sol";
import {CollateralManagementContract} from "../../src/CollateralManagement.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";

/**
 * @title DeployPegOutTest
 * @notice Test for the DeployPegOut deployment script
 * @dev Tests deployment and integration with CollateralManagement
 */
contract DeployPegOutTest is Test {
    DeployPegOut public deployScript;
    DeployCollateralManagement public deployCMScript;
    HelperConfig public helperConfig;

    address public collateralManagementProxy;

    function setUp() public {
        deployScript = new DeployPegOut();
        deployCMScript = new DeployCollateralManagement();
        helperConfig = new HelperConfig();

        // Deploy CollateralManagement first (dependency)
        HelperConfig.FlyoverConfig memory cfg = helperConfig.getFlyoverConfig();
        DeployCollateralManagement.DeploymentResult memory cmResult = deployCMScript.deploy(address(this), cfg);
        collateralManagementProxy = cmResult.proxy;

        console.log("Setup: CollateralManagement deployed at:", collateralManagementProxy);
    }

    function test_DeploymentFlow() public {
        console.log("\n=== TEST PEG OUT DEPLOYMENT ===\n");

        HelperConfig.FlyoverConfig memory cfg = helperConfig.getFlyoverConfig();
        address deployer = address(this);

        console.log("1. Deploying PegOutContract implementation...");
        PegOutContract implementation = new PegOutContract();
        console.log("   Implementation deployed at:", address(implementation));

        console.log("\n2. Deploying Proxy Admin...");
        ProxyAdmin admin = new ProxyAdmin(deployer);
        console.log("   Admin deployed at:", address(admin));

        console.log("\n3. Preparing initializer calldata...");
        bytes memory initData = abi.encodeCall(
            PegOutContract.initialize,
            (
                deployer,
                payable(cfg.bridge),
                cfg.dustThreshold,
                collateralManagementProxy,
                cfg.mainnet,
                cfg.btcBlockTime,
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
        PegOutContract pegOut = PegOutContract(payable(address(proxy)));

        assertEq(pegOut.dustThreshold(), cfg.dustThreshold, "Dust threshold mismatch");
        assertEq(pegOut.btcBlockTime(), cfg.btcBlockTime, "BTC block time mismatch");

        console.log("   Dust Threshold:", pegOut.dustThreshold());
        console.log("   BTC Block Time:", pegOut.btcBlockTime());
        console.log("   Version:", pegOut.VERSION());

        console.log("\n[PASS] PegOutContract deployment flow executed successfully!");
    }

    function test_DeployUsingScript() public {
        console.log("\n=== TEST DEPLOY USING SCRIPT ===\n");

        HelperConfig.FlyoverConfig memory cfg = helperConfig.getFlyoverConfig();
        address deployer = address(this);

        DeployPegOut.DeploymentResult memory result = deployScript.deploy(
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
        PegOutContract pegOut = PegOutContract(payable(result.proxy));
        assertEq(pegOut.btcBlockTime(), cfg.btcBlockTime, "BTC block time mismatch");

        console.log("\n[PASS] DeployPegOut script works correctly!");
    }

    function test_IntegrationWithCollateralManagement() public {
        console.log("\n=== TEST INTEGRATION WITH COLLATERAL MANAGEMENT ===\n");

        HelperConfig.FlyoverConfig memory cfg = helperConfig.getFlyoverConfig();
        address deployer = address(this);

        // Deploy PegOut
        DeployPegOut.DeploymentResult memory poResult = deployScript.deploy(
            deployer,
            cfg,
            collateralManagementProxy
        );

        PegOutContract pegOut = PegOutContract(payable(poResult.proxy));
        CollateralManagementContract cm = CollateralManagementContract(payable(collateralManagementProxy));

        // Grant COLLATERAL_SLASHER role to PegOut
        bytes32 collateralSlasherRole = cm.COLLATERAL_SLASHER();
        cm.grantRole(collateralSlasherRole, poResult.proxy);

        console.log("Granted COLLATERAL_SLASHER to PegOutContract");
        assertTrue(cm.hasRole(collateralSlasherRole, poResult.proxy), "PegOut should have COLLATERAL_SLASHER");

        console.log("\n[PASS] Integration with CollateralManagement verified!");
    }

    function test_RolesAreSetCorrectly() public {
        console.log("\n=== TEST ROLES ARE SET CORRECTLY ===\n");

        HelperConfig.FlyoverConfig memory cfg = helperConfig.getFlyoverConfig();
        address deployer = address(this);

        DeployPegOut.DeploymentResult memory result = deployScript.deploy(
            deployer,
            cfg,
            collateralManagementProxy
        );

        PegOutContract pegOut = PegOutContract(payable(result.proxy));

        // Check deployer has DEFAULT_ADMIN_ROLE
        bytes32 defaultAdminRole = pegOut.DEFAULT_ADMIN_ROLE();
        assertTrue(pegOut.hasRole(defaultAdminRole, deployer), "Deployer should have DEFAULT_ADMIN_ROLE");

        console.log("  Deployer has DEFAULT_ADMIN_ROLE: true");

        console.log("\n[PASS] Roles are set correctly!");
    }

    function test_DaoConfigurationSet() public {
        console.log("\n=== TEST DAO CONFIGURATION ===\n");

        HelperConfig.FlyoverConfig memory cfg = helperConfig.getFlyoverConfig();
        address deployer = address(this);

        DeployPegOut.DeploymentResult memory result = deployScript.deploy(
            deployer,
            cfg,
            collateralManagementProxy
        );

        PegOutContract pegOut = PegOutContract(payable(result.proxy));

        console.log("  DAO Fee Percentage:", pegOut.getFeePercentage());
        console.log("  DAO Fee Collector:", pegOut.getFeeCollector());

        assertEq(pegOut.getFeePercentage(), cfg.daoFeePercentage, "DAO fee percentage mismatch");
        assertEq(pegOut.getFeeCollector(), cfg.daoFeeCollector, "DAO fee collector mismatch");

        console.log("\n[PASS] DAO configuration set correctly!");
    }
}
