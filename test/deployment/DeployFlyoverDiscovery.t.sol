// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import "lib/forge-std/src/Test.sol";
import "lib/forge-std/src/console.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {FlyoverDiscovery} from "../../src/FlyoverDiscovery.sol";
import {CollateralManagementContract} from "../../src/CollateralManagement.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";

/**
 * @title DeployFlyoverDiscoveryTest
 * @notice Test for FlyoverDiscovery deployment
 * @dev Tests deployment and integration with CollateralManagement
 */
contract DeployFlyoverDiscoveryTest is Test {
    HelperConfig public helperConfig;

    address public collateralManagementProxy;

    function setUp() public {
        helperConfig = new HelperConfig();

        // Deploy CollateralManagement first (dependency)
        HelperConfig.FlyoverConfig memory cfg = helperConfig.getFlyoverConfig();
        address deployer = address(this);

        address cmImpl = address(new CollateralManagementContract());
        address cmAdmin = address(new ProxyAdmin(deployer));
        collateralManagementProxy = address(
            new TransparentUpgradeableProxy(
                cmImpl,
                cmAdmin,
                abi.encodeCall(
                    CollateralManagementContract.initialize,
                    (
                        deployer,
                        cfg.adminDelay,
                        cfg.minimumCollateral,
                        cfg.resignDelayBlocks,
                        cfg.rewardPercentage
                    )
                )
            )
        );

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

    function test_DeployUsingInlineDeployment() public {
        console.log("\n=== TEST DEPLOY USING INLINE DEPLOYMENT ===\n");

        HelperConfig.FlyoverConfig memory cfg = helperConfig.getFlyoverConfig();
        address deployer = address(this);

        // Inline deployment
        address impl = address(new FlyoverDiscovery());
        address admin = address(new ProxyAdmin(deployer));
        address proxy = address(
            new TransparentUpgradeableProxy(
                impl,
                admin,
                abi.encodeCall(
                    FlyoverDiscovery.initialize,
                    (deployer, cfg.adminDelay, collateralManagementProxy)
                )
            )
        );

        console.log("Deployment Result:");
        console.log("  Implementation:", impl);
        console.log("  Proxy:", proxy);
        console.log("  Admin:", admin);

        assertTrue(impl != address(0), "Implementation should not be zero");
        assertTrue(proxy != address(0), "Proxy should not be zero");
        assertTrue(admin != address(0), "Admin should not be zero");

        // Verify contract is initialized
        FlyoverDiscovery fd = FlyoverDiscovery(proxy);
        assertEq(fd.lastProviderId(), 0, "Initial provider ID should be 0");

        console.log("\n[PASS] FlyoverDiscovery deployment works correctly!");
    }

    function test_IntegrationWithCollateralManagement() public {
        console.log("\n=== TEST INTEGRATION WITH COLLATERAL MANAGEMENT ===\n");

        HelperConfig.FlyoverConfig memory cfg = helperConfig.getFlyoverConfig();
        address deployer = address(this);

        // Deploy FlyoverDiscovery
        address impl = address(new FlyoverDiscovery());
        address admin = address(new ProxyAdmin(deployer));
        address fdProxy = address(
            new TransparentUpgradeableProxy(
                impl,
                admin,
                abi.encodeCall(
                    FlyoverDiscovery.initialize,
                    (deployer, cfg.adminDelay, collateralManagementProxy)
                )
            )
        );

        FlyoverDiscovery fd = FlyoverDiscovery(fdProxy);
        CollateralManagementContract cm = CollateralManagementContract(
            payable(collateralManagementProxy)
        );

        // Grant COLLATERAL_ADDER role to FlyoverDiscovery
        bytes32 collateralAdderRole = cm.COLLATERAL_ADDER();
        cm.grantRole(collateralAdderRole, fdProxy);

        console.log("Granted COLLATERAL_ADDER to FlyoverDiscovery");
        assertTrue(
            cm.hasRole(collateralAdderRole, fdProxy),
            "FlyoverDiscovery should have COLLATERAL_ADDER"
        );

        console.log("\n[PASS] Integration with CollateralManagement verified!");
    }

    function test_RolesAreSetCorrectly() public {
        console.log("\n=== TEST ROLES ARE SET CORRECTLY ===\n");

        HelperConfig.FlyoverConfig memory cfg = helperConfig.getFlyoverConfig();
        address deployer = address(this);

        // Inline deployment
        address impl = address(new FlyoverDiscovery());
        address admin = address(new ProxyAdmin(deployer));
        address proxy = address(
            new TransparentUpgradeableProxy(
                impl,
                admin,
                abi.encodeCall(
                    FlyoverDiscovery.initialize,
                    (deployer, cfg.adminDelay, collateralManagementProxy)
                )
            )
        );

        FlyoverDiscovery fd = FlyoverDiscovery(proxy);

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
