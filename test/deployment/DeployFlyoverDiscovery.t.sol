// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import "lib/forge-std/src/Test.sol";
import "lib/forge-std/src/console.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {ProxyReader} from "../../script/helpers/ProxyReader.sol";
import {FlyoverDiscovery} from "../../src/FlyoverDiscovery.sol";
import {CollateralManagementContract} from "../../src/CollateralManagement.sol";
import {PauseRegistry} from "../../src/PauseRegistry.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {TransparentUpgradeableProxy, ITransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";

/**
 * @title DeployFlyoverDiscoveryTest
 * @notice Test for FlyoverDiscovery deployment
 * @dev Tests deployment and integration with CollateralManagement
 */
contract DeployFlyoverDiscoveryTest is Test {
    HelperConfig public helperConfig;

    address public collateralManagementProxy;
    address public pauseRegistryProxy;

    function setUp() public {
        helperConfig = new HelperConfig();

        // Deploy PauseRegistry and CollateralManagement first (dependency)
        HelperConfig.FlyoverConfig memory cfg = helperConfig.getFlyoverConfig();
        address deployer = address(this);
        PauseRegistry prImpl = new PauseRegistry();
        pauseRegistryProxy = address(
            new TransparentUpgradeableProxy(
                address(prImpl),
                deployer,
                abi.encodeCall(prImpl.initialize, (0, deployer))
            )
        );

        address cmImpl = address(new CollateralManagementContract());
        collateralManagementProxy = address(
            new TransparentUpgradeableProxy(
                cmImpl,
                deployer,
                abi.encodeCall(
                    CollateralManagementContract.initialize,
                    (
                        deployer,
                        cfg.adminDelay,
                        cfg.minimumCollateral,
                        cfg.resignDelayBlocks,
                        cfg.rewardPercentage,
                        PauseRegistry(pauseRegistryProxy)
                    )
                )
            )
        );

        console.log(
            "Setup: CollateralManagement deployed at:",
            collateralManagementProxy
        );
    }

    function _initializeV2_1_0(address discoveryProxy) internal {
        CollateralManagementContract(payable(collateralManagementProxy))
            .initializeV2_1_0(discoveryProxy);
        FlyoverDiscovery(discoveryProxy).initializeV2_1_0();
    }

    function test_DeploymentFlow() public {
        console.log("\n=== TEST FLYOVER DISCOVERY DEPLOYMENT ===\n");

        HelperConfig.FlyoverConfig memory cfg = helperConfig.getFlyoverConfig();
        address deployer = address(this);

        console.log("1. Deploying FlyoverDiscovery implementation...");
        FlyoverDiscovery implementation = new FlyoverDiscovery();
        console.log("   Implementation deployed at:", address(implementation));

        console.log("\n2. Preparing initializer calldata...");
        bytes memory initData = abi.encodeCall(
            FlyoverDiscovery.initialize,
            (
                deployer,
                cfg.adminDelay,
                collateralManagementProxy,
                PauseRegistry(pauseRegistryProxy)
            )
        );
        console.log("   Init data length:", initData.length);

        console.log("\n3. Deploying Proxy...");
        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(
            address(implementation),
            deployer,
            initData
        );
        console.log("   Proxy deployed at:", address(proxy));
        address discoveryProxyAdmin = ProxyReader.readAdmin(vm, address(proxy));
        console.log("   ProxyAdmin:", discoveryProxyAdmin);

        _initializeV2_1_0(address(proxy));

        console.log("\n4. Verifying deployment...");
        FlyoverDiscovery fd = FlyoverDiscovery(address(proxy));

        assertEq(fd.lastProviderId(), 0, "Initial provider ID should be 0");

        address pauseRegistryProxyAdmin = ProxyReader.readAdmin(
            vm,
            pauseRegistryProxy
        );
        address cmProxyAdmin = ProxyReader.readAdmin(
            vm,
            collateralManagementProxy
        );
        assertEq(
            Ownable(pauseRegistryProxyAdmin).owner(),
            deployer,
            "PauseRegistry ProxyAdmin owner mismatch"
        );
        assertEq(
            Ownable(cmProxyAdmin).owner(),
            deployer,
            "CollateralManagement ProxyAdmin owner mismatch"
        );
        assertEq(
            Ownable(discoveryProxyAdmin).owner(),
            deployer,
            "FlyoverDiscovery ProxyAdmin owner mismatch"
        );
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
        address proxy = address(
            new TransparentUpgradeableProxy(
                impl,
                deployer,
                abi.encodeCall(
                    FlyoverDiscovery.initialize,
                    (
                        deployer,
                        cfg.adminDelay,
                        collateralManagementProxy,
                        PauseRegistry(pauseRegistryProxy)
                    )
                )
            )
        );

        _initializeV2_1_0(proxy);

        address proxyAdminAddr = ProxyReader.readAdmin(vm, proxy);
        console.log("Deployment Result:");
        console.log("  Implementation:", impl);
        console.log("  Proxy:", proxy);
        console.log("  ProxyAdmin:", proxyAdminAddr);

        assertTrue(impl != address(0), "Implementation should not be zero");
        assertTrue(proxy != address(0), "Proxy should not be zero");
        assertEq(
            Ownable(proxyAdminAddr).owner(),
            deployer,
            "ProxyAdmin owner mismatch"
        );

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
        address fdProxy = address(
            new TransparentUpgradeableProxy(
                impl,
                deployer,
                abi.encodeCall(
                    FlyoverDiscovery.initialize,
                    (
                        deployer,
                        cfg.adminDelay,
                        collateralManagementProxy,
                        PauseRegistry(pauseRegistryProxy)
                    )
                )
            )
        );

        _initializeV2_1_0(fdProxy);

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

        assertEq(
            Ownable(ProxyReader.readAdmin(vm, fdProxy)).owner(),
            deployer,
            "FlyoverDiscovery ProxyAdmin owner mismatch"
        );

        console.log("\n[PASS] Integration with CollateralManagement verified!");
    }

    function test_RolesAreSetCorrectly() public {
        console.log("\n=== TEST ROLES ARE SET CORRECTLY ===\n");

        HelperConfig.FlyoverConfig memory cfg = helperConfig.getFlyoverConfig();
        address deployer = address(this);

        // Inline deployment
        address impl = address(new FlyoverDiscovery());
        address proxy = address(
            new TransparentUpgradeableProxy(
                impl,
                deployer,
                abi.encodeCall(
                    FlyoverDiscovery.initialize,
                    (
                        deployer,
                        cfg.adminDelay,
                        collateralManagementProxy,
                        PauseRegistry(pauseRegistryProxy)
                    )
                )
            )
        );

        _initializeV2_1_0(proxy);

        FlyoverDiscovery fd = FlyoverDiscovery(proxy);

        // Check deployer has DEFAULT_ADMIN_ROLE
        bytes32 defaultAdminRole = fd.DEFAULT_ADMIN_ROLE();
        assertTrue(
            fd.hasRole(defaultAdminRole, deployer),
            "Deployer should have DEFAULT_ADMIN_ROLE"
        );

        assertEq(
            Ownable(ProxyReader.readAdmin(vm, proxy)).owner(),
            deployer,
            "FlyoverDiscovery ProxyAdmin owner mismatch"
        );

        console.log("  Deployer has DEFAULT_ADMIN_ROLE: true");

        console.log("\n[PASS] Roles are set correctly!");
    }

    function test_ContractIsUpgradeable() public {
        console.log("\n=== CONTRACT IS UPGRADEABLE ===\n");

        HelperConfig.FlyoverConfig memory cfg = helperConfig.getFlyoverConfig();
        address deployer = address(this);

        address impl = address(new FlyoverDiscovery());
        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(
            impl,
            deployer,
            abi.encodeCall(
                FlyoverDiscovery.initialize,
                (
                    deployer,
                    cfg.adminDelay,
                    collateralManagementProxy,
                    PauseRegistry(pauseRegistryProxy)
                )
            )
        );

        ProxyAdmin proxyAdmin = ProxyAdmin(
            ProxyReader.readAdmin(vm, address(proxy))
        );
        address newImplementation = address(new FlyoverDiscovery());
        assertEq(
            ProxyReader.readImplementation(vm, address(proxy)),
            impl,
            "Implementation mismatch"
        );
        proxyAdmin.upgradeAndCall(
            ITransparentUpgradeableProxy(address(proxy)),
            newImplementation,
            ""
        );
        assertEq(
            ProxyReader.readImplementation(vm, address(proxy)),
            newImplementation,
            "Implementation mismatch"
        );

        console.log("\n[PASS] Contract is upgradeable");
    }
}
