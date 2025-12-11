// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import "lib/forge-std/src/Test.sol";
import "lib/forge-std/src/console.sol";
import {DeployFlyoverDiscovery} from "../../script/deployment/DeployFlyoverDiscovery.s.sol";
import {DeployCollateralManagement} from "../../script/deployment/DeployCollateralManagement.s.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {FlyoverDiscovery} from "../../src/FlyoverDiscovery.sol";
import {CollateralManagementContract} from "../../src/CollateralManagement.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";

/**
 * @title DeployFlyoverDiscoveryTest
 * @notice Test for the DeployFlyoverDiscovery deployment script
 * @dev Tests deployment and integration with CollateralManagement
 */
contract DeployFlyoverDiscoveryTest is Test {
    DeployFlyoverDiscovery public deployScript;
    DeployCollateralManagement public deployCMScript;
    HelperConfig public helperConfig;

    address public collateralManagementProxy;

    function setUp() public {
        deployScript = new DeployFlyoverDiscovery();
        deployCMScript = new DeployCollateralManagement();
        helperConfig = new HelperConfig();

        // Deploy CollateralManagement first (dependency)
        HelperConfig.FlyoverConfig memory cfg = helperConfig.getFlyoverConfig();
        DeployCollateralManagement.DeploymentResult
            memory cmResult = deployCMScript.deploy(address(this), cfg);
        collateralManagementProxy = cmResult.proxy;

        console.log(
            "Setup: CollateralManagement deployed at:",
            collateralManagementProxy
        );
    }

    function test_DeploymentFlow() public {
        console.log("\n=== TEST FLYOVER DISCOVERY DEPLOYMENT ===\n");

        HelperConfig.FlyoverConfig memory cfg = helperConfig.getFlyoverConfig();
        address deployer = address(this);

        console.log("1. Deploying FlyoverDiscovery implementation...");
        FlyoverDiscovery implementation = new FlyoverDiscovery();
        console.log("   Implementation deployed at:", address(implementation));

        console.log("\n2. Deploying Proxy Admin...");
        ProxyAdmin admin = new ProxyAdmin(deployer);
        console.log("   Admin deployed at:", address(admin));

        console.log("\n3. Preparing initializer calldata...");
        bytes memory initData = abi.encodeCall(
            FlyoverDiscovery.initialize,
            (deployer, cfg.adminDelay, collateralManagementProxy)
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
        FlyoverDiscovery fd = FlyoverDiscovery(address(proxy));

        assertEq(fd.lastProviderId(), 0, "Initial provider ID should be 0");
        console.log("   Last Provider ID:", fd.lastProviderId());

        console.log(
            "\n[PASS] FlyoverDiscovery deployment flow executed successfully!"
        );
    }

    function test_DeployUsingScript() public {
        console.log("\n=== TEST DEPLOY USING SCRIPT ===\n");

        HelperConfig.FlyoverConfig memory cfg = helperConfig.getFlyoverConfig();
        address deployer = address(this);

        DeployFlyoverDiscovery.DeploymentResult memory result = deployScript
            .deploy(deployer, cfg, collateralManagementProxy);

        console.log("Deployment Result:");
        console.log("  Implementation:", result.implementation);
        console.log("  Proxy:", result.proxy);
        console.log("  Admin:", result.admin);

        assertTrue(
            result.implementation != address(0),
            "Implementation should not be zero"
        );
        assertTrue(result.proxy != address(0), "Proxy should not be zero");
        assertTrue(result.admin != address(0), "Admin should not be zero");

        // Verify contract is initialized
        FlyoverDiscovery fd = FlyoverDiscovery(result.proxy);
        assertEq(fd.lastProviderId(), 0, "Initial provider ID should be 0");

        console.log("\n[PASS] DeployFlyoverDiscovery script works correctly!");
    }

    function test_IntegrationWithCollateralManagement() public {
        console.log("\n=== TEST INTEGRATION WITH COLLATERAL MANAGEMENT ===\n");

        HelperConfig.FlyoverConfig memory cfg = helperConfig.getFlyoverConfig();
        address deployer = address(this);

        // Deploy FlyoverDiscovery
        DeployFlyoverDiscovery.DeploymentResult memory fdResult = deployScript
            .deploy(deployer, cfg, collateralManagementProxy);

        FlyoverDiscovery fd = FlyoverDiscovery(fdResult.proxy);
        CollateralManagementContract cm = CollateralManagementContract(
            payable(collateralManagementProxy)
        );

        // Grant COLLATERAL_ADDER role to FlyoverDiscovery
        bytes32 collateralAdderRole = cm.COLLATERAL_ADDER();
        cm.grantRole(collateralAdderRole, fdResult.proxy);

        console.log("Granted COLLATERAL_ADDER to FlyoverDiscovery");
        assertTrue(
            cm.hasRole(collateralAdderRole, fdResult.proxy),
            "FlyoverDiscovery should have COLLATERAL_ADDER"
        );

        console.log("\n[PASS] Integration with CollateralManagement verified!");
    }

    function test_RolesAreSetCorrectly() public {
        console.log("\n=== TEST ROLES ARE SET CORRECTLY ===\n");

        HelperConfig.FlyoverConfig memory cfg = helperConfig.getFlyoverConfig();
        address deployer = address(this);

        DeployFlyoverDiscovery.DeploymentResult memory result = deployScript
            .deploy(deployer, cfg, collateralManagementProxy);

        FlyoverDiscovery fd = FlyoverDiscovery(result.proxy);

        // Check deployer has DEFAULT_ADMIN_ROLE
        bytes32 defaultAdminRole = fd.DEFAULT_ADMIN_ROLE();
        assertTrue(
            fd.hasRole(defaultAdminRole, deployer),
            "Deployer should have DEFAULT_ADMIN_ROLE"
        );

        console.log("  Deployer has DEFAULT_ADMIN_ROLE: true");

        console.log("\n[PASS] Roles are set correctly!");
    }
}
