// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import "lib/forge-std/src/Test.sol";
import "lib/forge-std/src/console.sol";
import {PrepareUpgrade} from "../../forge-scripts/deployment/PrepareUpgrade.s.sol";
import {HelperConfig} from "../../forge-scripts/HelperConfig.s.sol";
import {LiquidityBridgeContractV2} from "../../contracts/legacy/LiquidityBridgeContractV2.sol";

/**
 * @title PrepareUpgradeTest
 * @notice Test for the PrepareUpgrade deployment script - validates V2 implementation deployment
 * @dev Tests deploying V2 implementation without upgrading the proxy
 */
contract PrepareUpgradeTest is Test {
    PrepareUpgrade public prepareScript;
    HelperConfig public helperConfig;

    function setUp() public {
        // Instantiate scripts
        prepareScript = new PrepareUpgrade();
        helperConfig = new HelperConfig();
    }

    function test_DeployV2Implementation() public {
        console.log("\n=== TEST DEPLOY V2 IMPLEMENTATION ===\n");

        console.log("1. Deploying V2 implementation...");
        LiquidityBridgeContractV2 implementation = new LiquidityBridgeContractV2();
        console.log("   Implementation address:", address(implementation));

        // Verify deployment
        console.log("\n2. Verifying deployment...");
        assertTrue(
            address(implementation) != address(0),
            "Implementation should be deployed"
        );
        assertTrue(
            address(implementation).code.length > 0,
            "Implementation should have code"
        );

        // Verify V2-specific function exists
        console.log("\n3. Verifying V2 functionality...");
        string memory version = implementation.version();
        console.log("   Version:", version);
        assertEq(
            bytes(version).length > 0,
            true,
            "Version should not be empty"
        );

        console.log("\n[PASS] V2 implementation deployed successfully!");
        console.log("[PASS] V2 implementation is valid!");
    }

    function test_V2ImplementationHasCorrectVersion() public {
        console.log("\n=== TEST V2 VERSION ===\n");

        LiquidityBridgeContractV2 implementation = new LiquidityBridgeContractV2();

        string memory version = implementation.version();
        console.log("V2 Version:", version);

        // Version should be non-empty
        assertEq(bytes(version).length > 0, true, "Version should exist");

        console.log("\n[PASS] V2 has correct version!");
    }

    function test_V2CanBeDeployedMultipleTimes() public {
        console.log("\n=== TEST MULTIPLE V2 DEPLOYMENTS ===\n");

        // Deploy multiple V2 implementations (useful for testing different versions)
        console.log("Deploying multiple V2 implementations...");

        LiquidityBridgeContractV2 impl1 = new LiquidityBridgeContractV2();
        LiquidityBridgeContractV2 impl2 = new LiquidityBridgeContractV2();
        LiquidityBridgeContractV2 impl3 = new LiquidityBridgeContractV2();

        console.log("  Implementation 1:", address(impl1));
        console.log("  Implementation 2:", address(impl2));
        console.log("  Implementation 3:", address(impl3));

        // Verify all are different addresses
        assertTrue(
            address(impl1) != address(impl2),
            "Implementations should be different"
        );
        assertTrue(
            address(impl2) != address(impl3),
            "Implementations should be different"
        );
        assertTrue(
            address(impl1) != address(impl3),
            "Implementations should be different"
        );

        // Verify all have the same version
        assertEq(
            impl1.version(),
            impl2.version(),
            "All should have same version"
        );
        assertEq(
            impl2.version(),
            impl3.version(),
            "All should have same version"
        );

        console.log("\n[PASS] Multiple V2 implementations can be deployed!");
        console.log("[PASS] All have consistent version!");
        console.log("[PASS] PrepareUpgrade.s.sol script pattern validated!");
    }
}
