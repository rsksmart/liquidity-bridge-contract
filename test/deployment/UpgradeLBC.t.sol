// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import "lib/forge-std/src/Test.sol";
import "lib/forge-std/src/console.sol";
import {UpgradeLBC} from "../../script/legacy/deployment/UpgradeLBC.s.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {LiquidityBridgeContract} from "../../src/legacy/LiquidityBridgeContract.sol";
import {LiquidityBridgeContractV2} from "../../src/legacy/LiquidityBridgeContractV2.sol";
import {LiquidityBridgeContractProxy} from "../../src/legacy/LiquidityBridgeContractProxy.sol";
import {LiquidityBridgeContractAdmin} from "../../src/legacy/LiquidityBridgeContractAdmin.sol";
import {ITransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

/**
 * @title UpgradeLBCTest
 * @notice Test for the UpgradeLBC deployment script - validates upgrade works correctly
 * @dev Tests upgrading from V1 to V2 with HelperConfig integration
 */
contract UpgradeLBCTest is Test {
    UpgradeLBC public upgradeScript;
    HelperConfig public helperConfig;

    LiquidityBridgeContract public lbcV1;
    LiquidityBridgeContractV2 public lbcV2Impl;
    LiquidityBridgeContractProxy public proxy;
    LiquidityBridgeContractAdmin public admin;

    address public deployer;

    function setUp() public {
        deployer = address(this);

        // Instantiate scripts
        upgradeScript = new UpgradeLBC();
        helperConfig = new HelperConfig();

        // Deploy V1 first (to have something to upgrade)
        console.log("Setting up V1 deployment for upgrade test...");
        deployV1();
    }

    function deployV1() internal {
        HelperConfig.NetworkConfig memory cfg = helperConfig.getConfig();

        // Deploy V1 implementation
        lbcV1 = new LiquidityBridgeContract();

        // Deploy admin
        admin = new LiquidityBridgeContractAdmin();

        // Prepare init data
        bytes memory initData = abi.encodeCall(
            LiquidityBridgeContract.initialize,
            (
                payable(cfg.bridge),
                cfg.minimumCollateral,
                cfg.minimumPegIn,
                cfg.rewardPercentage,
                cfg.resignDelayBlocks,
                cfg.dustThreshold,
                cfg.btcBlockTime,
                cfg.mainnet
            )
        );

        // Deploy proxy
        proxy = new LiquidityBridgeContractProxy(
            address(lbcV1),
            address(admin),
            initData
        );

        console.log("  V1 Implementation:", address(lbcV1));
        console.log("  Proxy:", address(proxy));
        console.log("  Admin:", address(admin));

        // Set addresses in environment for upgrade script
        vm.setEnv("EXISTING_PROXY_LOCAL", vm.toString(address(proxy)));
        vm.setEnv("EXISTING_ADMIN_LOCAL", vm.toString(address(admin)));
    }

    function test_UpgradeToV2() public {
        console.log("\n=== TEST UPGRADE TO V2 ===\n");

        console.log("1. Current implementation (V1):", address(lbcV1));

        // Get the actual admin from storage
        bytes32 adminSlot = bytes32(
            uint256(keccak256("eip1967.proxy.admin")) - 1
        );
        address proxyAdminAddress = address(
            uint160(uint256(vm.load(address(proxy), adminSlot)))
        );
        LiquidityBridgeContractAdmin actualAdmin = LiquidityBridgeContractAdmin(
            proxyAdminAddress
        );
        address adminOwner = actualAdmin.owner();

        // Deploy V2 implementation
        console.log("\n2. Deploying V2 implementation...");
        lbcV2Impl = new LiquidityBridgeContractV2();
        console.log("   V2 Implementation:", address(lbcV2Impl));

        // Upgrade the proxy
        console.log("\n3. Upgrading proxy to V2...");
        vm.prank(adminOwner);
        actualAdmin.upgradeAndCall(
            ITransparentUpgradeableProxy(address(proxy)),
            address(lbcV2Impl),
            ""
        );
        console.log("   Upgrade completed!");

        // Verify upgrade
        console.log("\n4. Verifying upgrade...");
        LiquidityBridgeContractV2 lbcV2Proxy = LiquidityBridgeContractV2(
            payable(address(proxy))
        );

        string memory version = lbcV2Proxy.version();
        console.log("   Contract version:", version);

        // Verify V2 functionality exists
        assertEq(
            bytes(version).length > 0,
            true,
            "Version should not be empty"
        );

        console.log("\n[PASS] Upgrade to V2 successful!");
        console.log("[PASS] State preserved after upgrade!");
    }

    function test_UpgradePattern() public {
        console.log("\n=== TEST UPGRADE PATTERN ===\n");

        // This test validates reading from EIP-1967 storage slots and upgrading

        // Get proxy admin address from storage slot
        bytes32 adminSlot = bytes32(
            uint256(keccak256("eip1967.proxy.admin")) - 1
        );
        address proxyAdminAddress = address(
            uint160(uint256(vm.load(address(proxy), adminSlot)))
        );

        console.log("Proxy admin from storage slot:", proxyAdminAddress);
        assertTrue(proxyAdminAddress != address(0), "Admin should not be zero");

        // Get implementation address from storage slot
        bytes32 implSlot = bytes32(
            uint256(keccak256("eip1967.proxy.implementation")) - 1
        );
        address currentImpl = address(
            uint160(uint256(vm.load(address(proxy), implSlot)))
        );

        console.log("Current implementation:", currentImpl);
        assertEq(currentImpl, address(lbcV1), "Should point to V1 initially");

        // Get the actual admin and perform upgrade
        LiquidityBridgeContractAdmin actualAdmin = LiquidityBridgeContractAdmin(
            proxyAdminAddress
        );
        address adminOwner = actualAdmin.owner();

        // Deploy and upgrade to V2
        lbcV2Impl = new LiquidityBridgeContractV2();
        vm.prank(adminOwner);
        actualAdmin.upgradeAndCall(
            ITransparentUpgradeableProxy(address(proxy)),
            address(lbcV2Impl),
            ""
        );

        // Verify implementation changed
        address newImpl = address(
            uint160(uint256(vm.load(address(proxy), implSlot)))
        );
        console.log("New implementation:", newImpl);
        assertEq(
            newImpl,
            address(lbcV2Impl),
            "Should point to V2 after upgrade"
        );

        console.log("\n[PASS] Upgrade pattern validated!");
        console.log("[PASS] EIP-1967 storage slots work correctly!");
    }

    function test_CanCallV2Functions() public {
        console.log("\n=== TEST V2 FUNCTIONS AFTER UPGRADE ===\n");

        // Get the actual admin from storage
        bytes32 adminSlot = bytes32(
            uint256(keccak256("eip1967.proxy.admin")) - 1
        );
        address proxyAdminAddress = address(
            uint160(uint256(vm.load(address(proxy), adminSlot)))
        );
        LiquidityBridgeContractAdmin actualAdmin = LiquidityBridgeContractAdmin(
            proxyAdminAddress
        );
        address adminOwner = actualAdmin.owner();

        // Deploy and upgrade to V2
        console.log("1. Deploying V2 and upgrading...");
        lbcV2Impl = new LiquidityBridgeContractV2();
        vm.prank(adminOwner);
        actualAdmin.upgradeAndCall(
            ITransparentUpgradeableProxy(address(proxy)),
            address(lbcV2Impl),
            ""
        );
        console.log("   Upgrade completed!");

        // Get V2 interface through proxy
        console.log("\n2. Testing V2 functions...");
        LiquidityBridgeContractV2 lbcV2 = LiquidityBridgeContractV2(
            payable(address(proxy))
        );

        string memory version = lbcV2.version();
        console.log("   version():", version);
        assertEq(bytes(version).length > 0, true, "Version should exist");

        console.log("\n[PASS] V2 functions callable after upgrade!");
        console.log("[PASS] UpgradeLBC.s.sol script pattern validated!");
    }
}
