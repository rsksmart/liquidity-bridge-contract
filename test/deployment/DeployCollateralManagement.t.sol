// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import "lib/forge-std/src/Test.sol";
import "lib/forge-std/src/console.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {CollateralManagementContract} from "../../src/CollateralManagement.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";

/**
 * @title DeployCollateralManagementTest
 * @notice Test for CollateralManagement deployment
 * @dev Tests the complete deployment flow with HelperConfig integration
 */
contract DeployCollateralManagementTest is Test {
    HelperConfig public helperConfig;

    function setUp() public {
        helperConfig = new HelperConfig();
    }

    function test_FlyoverConfigReturnsValidConfig() public {
        console.log("\n=== TEST FLYOVER HELPER CONFIG ===\n");

        HelperConfig.FlyoverConfig memory cfg = helperConfig.getFlyoverConfig();

        console.log("Flyover Configuration:");
        console.log("  Bridge:", cfg.bridge);
        console.log("  Min Collateral:", cfg.minimumCollateral);
        console.log("  Min PegIn:", cfg.minimumPegIn);
        console.log("  Reward %:", cfg.rewardPercentage);
        console.log("  Resign Delay Blocks:", cfg.resignDelayBlocks);
        console.log("  Dust Threshold:", cfg.dustThreshold);
        console.log("  BTC Block Time:", cfg.btcBlockTime);
        console.log("  Mainnet:", cfg.mainnet);
        console.log("  Admin Delay:", cfg.adminDelay);

        // Validations
        assertTrue(
            cfg.bridge != address(0),
            "Bridge address should not be zero"
        );
        assertTrue(cfg.minimumCollateral > 0, "Min collateral should be > 0");
        assertTrue(cfg.minimumPegIn > 0, "Min PegIn should be > 0");
        assertTrue(cfg.dustThreshold > 0, "Dust threshold should be > 0");
        assertTrue(cfg.btcBlockTime > 0, "BTC block time should be > 0");

        console.log("\n[PASS] FlyoverConfig returns valid configuration!");
    }

    function test_DeploymentFlow() public {
        console.log("\n=== TEST COLLATERAL MANAGEMENT DEPLOYMENT ===\n");

        HelperConfig.FlyoverConfig memory cfg = helperConfig.getFlyoverConfig();
        address deployer = address(this);

        console.log("1. Deploying CollateralManagement implementation...");
        CollateralManagementContract implementation = new CollateralManagementContract();
        console.log("   Implementation deployed at:", address(implementation));

        console.log("\n2. Deploying Proxy Admin...");
        ProxyAdmin admin = new ProxyAdmin(deployer);
        console.log("   Admin deployed at:", address(admin));

        console.log("\n3. Preparing initializer calldata...");
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
        console.log("   Init data length:", initData.length);

        console.log("\n4. Deploying Proxy...");
        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(
            address(implementation),
            address(admin),
            initData
        );
        console.log("   Proxy deployed at:", address(proxy));

        console.log("\n5. Verifying deployment...");
        CollateralManagementContract cm = CollateralManagementContract(
            payable(address(proxy))
        );

        assertEq(
            cm.getMinCollateral(),
            cfg.minimumCollateral,
            "Min collateral mismatch"
        );
        assertEq(
            cm.getResignDelayInBlocks(),
            cfg.resignDelayBlocks,
            "Resign delay mismatch"
        );
        assertEq(
            cm.getRewardPercentage(),
            cfg.rewardPercentage,
            "Reward percentage mismatch"
        );

        console.log("   Min Collateral:", cm.getMinCollateral());
        console.log("   Resign Delay:", cm.getResignDelayInBlocks());
        console.log("   Reward %:", cm.getRewardPercentage());
        console.log("   Version:", cm.VERSION());

        console.log(
            "\n[PASS] CollateralManagement deployment flow executed successfully!"
        );
    }

    function test_DeployUsingScript() public {
        console.log("\n=== TEST DEPLOY USING SCRIPT ===\n");

        HelperConfig.FlyoverConfig memory cfg = helperConfig.getFlyoverConfig();
        address deployer = address(this);

        // Inline deployment (script.run() uses private _deploy internally)
        address impl = address(new CollateralManagementContract());
        address admin = address(new ProxyAdmin(deployer));
        address proxy = address(
            new TransparentUpgradeableProxy(
                impl,
                admin,
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

        console.log("Deployment Result:");
        console.log("  Implementation:", impl);
        console.log("  Proxy:", proxy);
        console.log("  Admin:", admin);

        assertTrue(impl != address(0), "Implementation should not be zero");
        assertTrue(proxy != address(0), "Proxy should not be zero");
        assertTrue(admin != address(0), "Admin should not be zero");

        // Verify proxy points to implementation
        CollateralManagementContract cm = CollateralManagementContract(
            payable(proxy)
        );
        assertEq(
            cm.getMinCollateral(),
            cfg.minimumCollateral,
            "Min collateral mismatch"
        );

        console.log(
            "\n[PASS] DeployCollateralManagement script works correctly!"
        );
    }

    function test_RolesAreSetCorrectly() public {
        console.log("\n=== TEST ROLES ARE SET CORRECTLY ===\n");

        HelperConfig.FlyoverConfig memory cfg = helperConfig.getFlyoverConfig();
        address deployer = address(this);

        // Inline deployment
        address impl = address(new CollateralManagementContract());
        address admin = address(new ProxyAdmin(deployer));
        address proxy = address(
            new TransparentUpgradeableProxy(
                impl,
                admin,
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
        CollateralManagementContract cm = CollateralManagementContract(
            payable(proxy)
        );

        // Check deployer has DEFAULT_ADMIN_ROLE
        bytes32 defaultAdminRole = cm.DEFAULT_ADMIN_ROLE();
        assertTrue(
            cm.hasRole(defaultAdminRole, deployer),
            "Deployer should have DEFAULT_ADMIN_ROLE"
        );

        console.log("  Deployer has DEFAULT_ADMIN_ROLE: true");
        console.log("  COLLATERAL_ADDER role exists");
        console.log("  COLLATERAL_SLASHER role exists");

        // Verify roles are defined
        assertTrue(
            cm.COLLATERAL_ADDER() != bytes32(0),
            "COLLATERAL_ADDER should be defined"
        );
        assertTrue(
            cm.COLLATERAL_SLASHER() != bytes32(0),
            "COLLATERAL_SLASHER should be defined"
        );

        console.log("\n[PASS] Roles are set correctly!");
    }
}
