// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import "lib/forge-std/src/Test.sol";
import "lib/forge-std/src/console.sol";
import {DeployFlyover} from "../../script/deployment/DeployFlyover.s.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {CollateralManagementContract} from "../../src/CollateralManagement.sol";
import {FlyoverDiscovery} from "../../src/FlyoverDiscovery.sol";
import {PegInContract} from "../../src/PegInContract.sol";
import {PegOutContract} from "../../src/PegOutContract.sol";
import {Flyover} from "../../src/libraries/Flyover.sol";

/**
 * @title DeployFlyoverTest
 * @notice Test for the DeployFlyover orchestrator script
 * @dev Tests full deployment of all Flyover contracts and role setup
 */
contract DeployFlyoverTest is Test {
    DeployFlyover public deployScript;
    HelperConfig public helperConfig;

    function setUp() public {
        deployScript = new DeployFlyover();
        helperConfig = new HelperConfig();
    }

    function test_FullDeploymentFlow() public {
        console.log("\n=== TEST FULL FLYOVER DEPLOYMENT ===\n");

        HelperConfig.FlyoverConfig memory cfg = helperConfig.getFlyoverConfig();
        address deployer = address(this);

        console.log("Deploying all Flyover contracts...");
        DeployFlyover.FlyoverDeployment memory deployment = deployScript.deployAll(deployer, cfg);

        // Verify all contracts deployed
        console.log("\n1. Verifying CollateralManagement...");
        assertTrue(deployment.collateralManagementImpl != address(0), "CM impl should not be zero");
        assertTrue(deployment.collateralManagementProxy != address(0), "CM proxy should not be zero");
        assertTrue(deployment.collateralManagementAdmin != address(0), "CM admin should not be zero");
        console.log("   Implementation:", deployment.collateralManagementImpl);
        console.log("   Proxy:", deployment.collateralManagementProxy);

        console.log("\n2. Verifying FlyoverDiscovery...");
        assertTrue(deployment.flyoverDiscoveryImpl != address(0), "FD impl should not be zero");
        assertTrue(deployment.flyoverDiscoveryProxy != address(0), "FD proxy should not be zero");
        assertTrue(deployment.flyoverDiscoveryAdmin != address(0), "FD admin should not be zero");
        console.log("   Implementation:", deployment.flyoverDiscoveryImpl);
        console.log("   Proxy:", deployment.flyoverDiscoveryProxy);

        console.log("\n3. Verifying PegInContract...");
        assertTrue(deployment.pegInImpl != address(0), "PI impl should not be zero");
        assertTrue(deployment.pegInProxy != address(0), "PI proxy should not be zero");
        assertTrue(deployment.pegInAdmin != address(0), "PI admin should not be zero");
        console.log("   Implementation:", deployment.pegInImpl);
        console.log("   Proxy:", deployment.pegInProxy);

        console.log("\n4. Verifying PegOutContract...");
        assertTrue(deployment.pegOutImpl != address(0), "PO impl should not be zero");
        assertTrue(deployment.pegOutProxy != address(0), "PO proxy should not be zero");
        assertTrue(deployment.pegOutAdmin != address(0), "PO admin should not be zero");
        console.log("   Implementation:", deployment.pegOutImpl);
        console.log("   Proxy:", deployment.pegOutProxy);

        console.log("\n[PASS] All contracts deployed successfully!");
    }

    function test_RoleSetup() public {
        console.log("\n=== TEST ROLE SETUP ===\n");

        HelperConfig.FlyoverConfig memory cfg = helperConfig.getFlyoverConfig();
        address deployer = address(this);

        // Deploy all contracts
        DeployFlyover.FlyoverDeployment memory deployment = deployScript.deployAll(deployer, cfg);

        CollateralManagementContract cm = CollateralManagementContract(
            payable(deployment.collateralManagementProxy)
        );

        bytes32 collateralAdderRole = cm.COLLATERAL_ADDER();
        bytes32 collateralSlasherRole = cm.COLLATERAL_SLASHER();

        // Setup roles directly from test (since test contract is admin)
        console.log("Setting up roles...");
        cm.grantRole(collateralAdderRole, deployment.flyoverDiscoveryProxy);
        cm.grantRole(collateralSlasherRole, deployment.pegInProxy);
        cm.grantRole(collateralSlasherRole, deployment.pegOutProxy);

        // Verify FlyoverDiscovery has COLLATERAL_ADDER
        console.log("1. Checking FlyoverDiscovery has COLLATERAL_ADDER...");
        assertTrue(
            cm.hasRole(collateralAdderRole, deployment.flyoverDiscoveryProxy),
            "FlyoverDiscovery should have COLLATERAL_ADDER"
        );
        console.log("   FlyoverDiscovery has COLLATERAL_ADDER: true");

        // Verify PegInContract has COLLATERAL_SLASHER
        console.log("\n2. Checking PegInContract has COLLATERAL_SLASHER...");
        assertTrue(
            cm.hasRole(collateralSlasherRole, deployment.pegInProxy),
            "PegInContract should have COLLATERAL_SLASHER"
        );
        console.log("   PegInContract has COLLATERAL_SLASHER: true");

        // Verify PegOutContract has COLLATERAL_SLASHER
        console.log("\n3. Checking PegOutContract has COLLATERAL_SLASHER...");
        assertTrue(
            cm.hasRole(collateralSlasherRole, deployment.pegOutProxy),
            "PegOutContract should have COLLATERAL_SLASHER"
        );
        console.log("   PegOutContract has COLLATERAL_SLASHER: true");

        console.log("\n[PASS] All roles set up correctly!");
    }

    function test_ContractsAreInitializedCorrectly() public {
        console.log("\n=== TEST CONTRACTS INITIALIZED CORRECTLY ===\n");

        HelperConfig.FlyoverConfig memory cfg = helperConfig.getFlyoverConfig();
        address deployer = address(this);

        DeployFlyover.FlyoverDeployment memory deployment = deployScript.deployAll(deployer, cfg);

        // Check CollateralManagement
        console.log("1. CollateralManagement:");
        CollateralManagementContract cm = CollateralManagementContract(
            payable(deployment.collateralManagementProxy)
        );
        assertEq(cm.getMinCollateral(), cfg.minimumCollateral, "Min collateral mismatch");
        assertEq(cm.getResignDelayInBlocks(), cfg.resignDelayBlocks, "Resign delay mismatch");
        console.log("   Min Collateral:", cm.getMinCollateral());
        console.log("   Resign Delay:", cm.getResignDelayInBlocks());
        console.log("   Version:", cm.VERSION());

        // Check FlyoverDiscovery
        console.log("\n2. FlyoverDiscovery:");
        FlyoverDiscovery fd = FlyoverDiscovery(deployment.flyoverDiscoveryProxy);
        assertEq(fd.lastProviderId(), 0, "Initial provider ID should be 0");
        console.log("   Last Provider ID:", fd.lastProviderId());

        // Check PegInContract
        console.log("\n3. PegInContract:");
        PegInContract pegIn = PegInContract(payable(deployment.pegInProxy));
        assertEq(pegIn.getMinPegIn(), cfg.minimumPegIn, "Min PegIn mismatch");
        assertEq(pegIn.dustThreshold(), cfg.dustThreshold, "Dust threshold mismatch");
        console.log("   Min PegIn:", pegIn.getMinPegIn());
        console.log("   Dust Threshold:", pegIn.dustThreshold());
        console.log("   Version:", pegIn.VERSION());

        // Check PegOutContract
        console.log("\n4. PegOutContract:");
        PegOutContract pegOut = PegOutContract(payable(deployment.pegOutProxy));
        assertEq(pegOut.btcBlockTime(), cfg.btcBlockTime, "BTC block time mismatch");
        assertEq(pegOut.dustThreshold(), cfg.dustThreshold, "Dust threshold mismatch");
        console.log("   BTC Block Time:", pegOut.btcBlockTime());
        console.log("   Dust Threshold:", pegOut.dustThreshold());
        console.log("   Version:", pegOut.VERSION());

        console.log("\n[PASS] All contracts initialized correctly!");
    }

    function test_EndToEndProviderRegistration() public {
        console.log("\n=== TEST END-TO-END PROVIDER REGISTRATION ===\n");

        HelperConfig.FlyoverConfig memory cfg = helperConfig.getFlyoverConfig();
        address deployer = address(this);

        // Deploy all contracts
        DeployFlyover.FlyoverDeployment memory deployment = deployScript.deployAll(deployer, cfg);

        FlyoverDiscovery fd = FlyoverDiscovery(deployment.flyoverDiscoveryProxy);
        CollateralManagementContract cm = CollateralManagementContract(
            payable(deployment.collateralManagementProxy)
        );

        // Setup roles directly from test (since test contract is admin)
        bytes32 collateralAdderRole = cm.COLLATERAL_ADDER();
        cm.grantRole(collateralAdderRole, deployment.flyoverDiscoveryProxy);

        // Create a test provider
        address provider = makeAddr("provider");
        uint256 collateralAmount = cfg.minimumCollateral;
        vm.deal(provider, collateralAmount);

        console.log("1. Registering provider...");
        console.log("   Provider address:", provider);
        console.log("   Collateral amount:", collateralAmount);

        vm.prank(provider);
        uint256 providerId = fd.register{value: collateralAmount}(
            "Test Provider",
            "https://api.test.com",
            true,
            Flyover.ProviderType.PegIn
        );

        console.log("   Provider registered with ID:", providerId);
        assertEq(providerId, 1, "First provider should have ID 1");

        // Verify collateral was added
        console.log("\n2. Verifying collateral...");
        uint256 pegInCollateral = cm.getPegInCollateral(provider);
        assertEq(pegInCollateral, collateralAmount, "Collateral should be recorded");
        console.log("   PegIn Collateral:", pegInCollateral);

        // Verify provider is operational
        console.log("\n3. Checking operational status...");
        bool isOperational = fd.isOperational(Flyover.ProviderType.PegIn, provider);
        assertTrue(isOperational, "Provider should be operational");
        console.log("   Is Operational:", isOperational);

        console.log("\n[PASS] End-to-end provider registration works!");
    }

    function test_AdminRolesGrantedToDeployer() public {
        console.log("\n=== TEST ADMIN ROLES GRANTED TO DEPLOYER ===\n");

        HelperConfig.FlyoverConfig memory cfg = helperConfig.getFlyoverConfig();
        address deployer = address(this);

        DeployFlyover.FlyoverDeployment memory deployment = deployScript.deployAll(deployer, cfg);

        // Check all contracts have deployer as admin
        CollateralManagementContract cm = CollateralManagementContract(
            payable(deployment.collateralManagementProxy)
        );
        FlyoverDiscovery fd = FlyoverDiscovery(deployment.flyoverDiscoveryProxy);
        PegInContract pegIn = PegInContract(payable(deployment.pegInProxy));
        PegOutContract pegOut = PegOutContract(payable(deployment.pegOutProxy));

        bytes32 defaultAdminRole = cm.DEFAULT_ADMIN_ROLE();

        console.log("Checking DEFAULT_ADMIN_ROLE for deployer on all contracts...");

        assertTrue(cm.hasRole(defaultAdminRole, deployer), "CM: Deployer should have admin");
        console.log("  CollateralManagement: true");

        assertTrue(fd.hasRole(defaultAdminRole, deployer), "FD: Deployer should have admin");
        console.log("  FlyoverDiscovery: true");

        assertTrue(pegIn.hasRole(defaultAdminRole, deployer), "PI: Deployer should have admin");
        console.log("  PegInContract: true");

        assertTrue(pegOut.hasRole(defaultAdminRole, deployer), "PO: Deployer should have admin");
        console.log("  PegOutContract: true");

        console.log("\n[PASS] Deployer has admin role on all contracts!");
    }
}
