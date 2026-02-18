// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import "lib/forge-std/src/Test.sol";
import "lib/forge-std/src/console.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {CollateralManagementContract} from "../../src/CollateralManagement.sol";
import {FlyoverDiscovery} from "../../src/FlyoverDiscovery.sol";
import {PegInContract} from "../../src/PegInContract.sol";
import {PegOutContract} from "../../src/PegOutContract.sol";
import {Flyover} from "../../src/libraries/Flyover.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {BridgeMock} from "../../src/test-contracts/BridgeMock.sol";

/**
 * @title DeployFlyoverTest
 * @notice Test for the DeployFlyover deployment pattern
 * @dev Tests full deployment of all Flyover contracts and role setup
 */
contract DeployFlyoverTest is Test {
    HelperConfig public helperConfig;
    BridgeMock public bridgeMock;

    // Deployed contracts
    CollateralManagementContract public collateralManagement;
    FlyoverDiscovery public discovery;
    PegInContract public pegInContract;
    PegOutContract public pegOutContract;
    address public proxyAdmin;

    function setUp() public {
        helperConfig = new HelperConfig();
        bridgeMock = new BridgeMock();
    }

    /// @notice Deploy all contracts inline (mirrors DeployFlyover script)
    function _deployAll(
        address deployer,
        HelperConfig.FlyoverConfig memory cfg
    ) internal {
        // Single ProxyAdmin for all contracts
        proxyAdmin = address(new ProxyAdmin(deployer));

        // 1) CollateralManagement
        _deployCollateralManagement(deployer, cfg);

        // 2) FlyoverDiscovery
        _deployFlyoverDiscovery(deployer, cfg);

        // 3) PegInContract
        _deployPegIn(deployer, cfg);

        // 4) PegOutContract
        _deployPegOut(deployer, cfg);
    }

    function _deployCollateralManagement(
        address deployer,
        HelperConfig.FlyoverConfig memory cfg
    ) private {
        address impl = address(new CollateralManagementContract());
        bytes memory initData = abi.encodeCall(
            CollateralManagementContract.initialize,
            (
                deployer,
                cfg.adminDelay,
                cfg.minimumCollateral,
                cfg.resignDelayBlocks,
                cfg.rewardPercentage
            )
        );
        address proxy = address(
            new TransparentUpgradeableProxy(impl, proxyAdmin, initData)
        );
        collateralManagement = CollateralManagementContract(payable(proxy));
    }

    function _deployFlyoverDiscovery(
        address deployer,
        HelperConfig.FlyoverConfig memory cfg
    ) private {
        address impl = address(new FlyoverDiscovery());
        bytes memory initData = abi.encodeCall(
            FlyoverDiscovery.initialize,
            (deployer, cfg.adminDelay, address(collateralManagement))
        );
        address proxy = address(
            new TransparentUpgradeableProxy(impl, proxyAdmin, initData)
        );
        discovery = FlyoverDiscovery(proxy);
    }

    function _deployPegIn(
        address deployer,
        HelperConfig.FlyoverConfig memory cfg
    ) private {
        address impl = address(new PegInContract());
        bytes memory initData = abi.encodeCall(
            PegInContract.initialize,
            (
                deployer,
                payable(address(bridgeMock)),
                cfg.dustThreshold,
                cfg.minimumPegIn,
                address(collateralManagement),
                cfg.mainnet
            )
        );
        address proxy = address(
            new TransparentUpgradeableProxy(impl, proxyAdmin, initData)
        );
        pegInContract = PegInContract(payable(proxy));
    }

    function _deployPegOut(
        address deployer,
        HelperConfig.FlyoverConfig memory cfg
    ) private {
        address impl = address(new PegOutContract());
        bytes memory initData = abi.encodeCall(
            PegOutContract.initialize,
            (
                deployer,
                payable(address(bridgeMock)),
                cfg.dustThreshold,
                address(collateralManagement),
                cfg.mainnet,
                cfg.btcBlockTime
            )
        );
        address proxy = address(
            new TransparentUpgradeableProxy(impl, proxyAdmin, initData)
        );
        pegOutContract = PegOutContract(payable(proxy));
    }

    function test_FullDeploymentFlow() public {
        console.log("\n=== TEST FULL FLYOVER DEPLOYMENT ===\n");

        HelperConfig.FlyoverConfig memory cfg = helperConfig.getFlyoverConfig();
        address deployer = address(this);

        console.log("Deploying all Flyover contracts...");
        _deployAll(deployer, cfg);

        // Verify all contracts deployed
        console.log("\n1. Verifying CollateralManagement...");
        assertTrue(
            address(collateralManagement) != address(0),
            "CM should not be zero"
        );
        console.log("   Proxy:", address(collateralManagement));

        console.log("\n2. Verifying FlyoverDiscovery...");
        assertTrue(address(discovery) != address(0), "FD should not be zero");
        console.log("   Proxy:", address(discovery));

        console.log("\n3. Verifying PegInContract...");
        assertTrue(
            address(pegInContract) != address(0),
            "PI should not be zero"
        );
        console.log("   Proxy:", address(pegInContract));

        console.log("\n4. Verifying PegOutContract...");
        assertTrue(
            address(pegOutContract) != address(0),
            "PO should not be zero"
        );
        console.log("   Proxy:", address(pegOutContract));

        console.log("\n[PASS] All contracts deployed successfully!");
    }

    function test_RoleSetup() public {
        console.log("\n=== TEST ROLE SETUP ===\n");

        HelperConfig.FlyoverConfig memory cfg = helperConfig.getFlyoverConfig();
        address deployer = address(this);

        _deployAll(deployer, cfg);

        bytes32 collateralAdderRole = collateralManagement.COLLATERAL_ADDER();
        bytes32 collateralSlasherRole = collateralManagement
            .COLLATERAL_SLASHER();

        // Setup roles
        console.log("Setting up roles...");
        collateralManagement.grantRole(collateralAdderRole, address(discovery));
        collateralManagement.grantRole(
            collateralSlasherRole,
            address(pegInContract)
        );
        collateralManagement.grantRole(
            collateralSlasherRole,
            address(pegOutContract)
        );

        // Verify FlyoverDiscovery has COLLATERAL_ADDER
        console.log("1. Checking FlyoverDiscovery has COLLATERAL_ADDER...");
        assertTrue(
            collateralManagement.hasRole(
                collateralAdderRole,
                address(discovery)
            ),
            "FlyoverDiscovery should have COLLATERAL_ADDER"
        );
        console.log("   FlyoverDiscovery has COLLATERAL_ADDER: true");

        // Verify PegInContract has COLLATERAL_SLASHER
        console.log("\n2. Checking PegInContract has COLLATERAL_SLASHER...");
        assertTrue(
            collateralManagement.hasRole(
                collateralSlasherRole,
                address(pegInContract)
            ),
            "PegInContract should have COLLATERAL_SLASHER"
        );
        console.log("   PegInContract has COLLATERAL_SLASHER: true");

        // Verify PegOutContract has COLLATERAL_SLASHER
        console.log("\n3. Checking PegOutContract has COLLATERAL_SLASHER...");
        assertTrue(
            collateralManagement.hasRole(
                collateralSlasherRole,
                address(pegOutContract)
            ),
            "PegOutContract should have COLLATERAL_SLASHER"
        );
        console.log("   PegOutContract has COLLATERAL_SLASHER: true");

        console.log("\n[PASS] All roles set up correctly!");
    }

    function test_ContractsAreInitializedCorrectly() public {
        console.log("\n=== TEST CONTRACTS INITIALIZED CORRECTLY ===\n");

        HelperConfig.FlyoverConfig memory cfg = helperConfig.getFlyoverConfig();
        address deployer = address(this);

        _deployAll(deployer, cfg);

        // Check CollateralManagement
        console.log("1. CollateralManagement:");
        assertEq(
            collateralManagement.getMinCollateral(),
            cfg.minimumCollateral,
            "Min collateral mismatch"
        );
        assertEq(
            collateralManagement.getResignDelayInBlocks(),
            cfg.resignDelayBlocks,
            "Resign delay mismatch"
        );
        console.log(
            "   Min Collateral:",
            collateralManagement.getMinCollateral()
        );
        console.log(
            "   Resign Delay:",
            collateralManagement.getResignDelayInBlocks()
        );
        console.log("   Version:", collateralManagement.VERSION());

        // Check FlyoverDiscovery
        console.log("\n2. FlyoverDiscovery:");
        assertEq(
            discovery.lastProviderId(),
            0,
            "Initial provider ID should be 0"
        );
        console.log("   Last Provider ID:", discovery.lastProviderId());

        // Check PegInContract
        console.log("\n3. PegInContract:");
        assertEq(
            pegInContract.getMinPegIn(),
            cfg.minimumPegIn,
            "Min PegIn mismatch"
        );
        assertEq(
            pegInContract.dustThreshold(),
            cfg.dustThreshold,
            "Dust threshold mismatch"
        );
        console.log("   Min PegIn:", pegInContract.getMinPegIn());
        console.log("   Dust Threshold:", pegInContract.dustThreshold());
        console.log("   Version:", pegInContract.VERSION());

        // Check PegOutContract
        console.log("\n4. PegOutContract:");
        assertEq(
            pegOutContract.btcBlockTime(),
            cfg.btcBlockTime,
            "BTC block time mismatch"
        );
        assertEq(
            pegOutContract.dustThreshold(),
            cfg.dustThreshold,
            "Dust threshold mismatch"
        );
        console.log("   BTC Block Time:", pegOutContract.btcBlockTime());
        console.log("   Dust Threshold:", pegOutContract.dustThreshold());
        console.log("   Version:", pegOutContract.VERSION());

        console.log("\n[PASS] All contracts initialized correctly!");
    }

    function test_EndToEndProviderRegistration() public {
        console.log("\n=== TEST END-TO-END PROVIDER REGISTRATION ===\n");

        HelperConfig.FlyoverConfig memory cfg = helperConfig.getFlyoverConfig();
        address deployer = address(this);

        _deployAll(deployer, cfg);

        // Setup roles
        bytes32 collateralAdderRole = collateralManagement.COLLATERAL_ADDER();
        collateralManagement.grantRole(collateralAdderRole, address(discovery));

        // Create a test provider
        address provider = makeAddr("provider");
        uint256 collateralAmount = cfg.minimumCollateral;
        vm.deal(provider, collateralAmount);

        console.log("1. Registering provider...");
        console.log("   Provider address:", provider);
        console.log("   Collateral amount:", collateralAmount);

        vm.prank(provider);
        uint256 providerId = discovery.register{value: collateralAmount}(
            "Test Provider",
            "https://api.test.com",
            true,
            Flyover.ProviderType.PegIn
        );

        console.log("   Provider registered with ID:", providerId);
        assertEq(providerId, 1, "First provider should have ID 1");

        // Verify collateral was added
        console.log("\n2. Verifying collateral...");
        uint256 pegInCollateral = collateralManagement.getPegInCollateral(
            provider
        );
        assertEq(
            pegInCollateral,
            collateralAmount,
            "Collateral should be recorded"
        );
        console.log("   PegIn Collateral:", pegInCollateral);

        // Verify provider is operational
        console.log("\n3. Checking operational status...");
        bool isOperational = discovery.isOperational(
            Flyover.ProviderType.PegIn,
            provider
        );
        assertTrue(isOperational, "Provider should be operational");
        console.log("   Is Operational:", isOperational);

        console.log("\n[PASS] End-to-end provider registration works!");
    }

    function test_AdminRolesGrantedToDeployer() public {
        console.log("\n=== TEST ADMIN ROLES GRANTED TO DEPLOYER ===\n");

        HelperConfig.FlyoverConfig memory cfg = helperConfig.getFlyoverConfig();
        address deployer = address(this);

        _deployAll(deployer, cfg);

        bytes32 defaultAdminRole = collateralManagement.DEFAULT_ADMIN_ROLE();

        console.log(
            "Checking DEFAULT_ADMIN_ROLE for deployer on all contracts..."
        );

        assertTrue(
            collateralManagement.hasRole(defaultAdminRole, deployer),
            "CM: Deployer should have admin"
        );
        console.log("  CollateralManagement: true");

        assertTrue(
            discovery.hasRole(defaultAdminRole, deployer),
            "FD: Deployer should have admin"
        );
        console.log("  FlyoverDiscovery: true");

        assertTrue(
            pegInContract.hasRole(defaultAdminRole, deployer),
            "PI: Deployer should have admin"
        );
        console.log("  PegInContract: true");

        assertTrue(
            pegOutContract.hasRole(defaultAdminRole, deployer),
            "PO: Deployer should have admin"
        );
        console.log("  PegOutContract: true");

        console.log("\n[PASS] Deployer has admin role on all contracts!");
    }
}
