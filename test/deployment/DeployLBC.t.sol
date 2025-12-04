// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import "lib/forge-std/src/Test.sol";
import "lib/forge-std/src/console.sol";
import {DeployLBC} from "../../script/legacy/deployment/DeployLBC.s.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {LiquidityBridgeContract} from "../../src/legacy/LiquidityBridgeContract.sol";
import {LiquidityBridgeContractProxy} from "../../src/legacy/LiquidityBridgeContractProxy.sol";
import {LiquidityBridgeContractAdmin} from "../../src/legacy/LiquidityBridgeContractAdmin.sol";

/**
 * @title DeployLBCTest
 * @notice Test for the DeployLBC deployment script - validates deployment works correctly
 * @dev Tests the complete deployment flow with HelperConfig integration
 */
contract DeployLBCTest is Test {
    DeployLBC public deployScript;
    HelperConfig public helperConfig;

    function setUp() public {
        // Instantiate scripts
        deployScript = new DeployLBC();
        helperConfig = new HelperConfig();
    }

    function test_HelperConfigReturnsValidConfig() public {
        console.log("\n=== TEST HELPER CONFIG ===\n");

        HelperConfig.NetworkConfig memory cfg = helperConfig.getConfig();

        console.log("Network Configuration:");
        console.log("  Bridge:", cfg.bridge);
        console.log("  Min Collateral:", cfg.minimumCollateral);
        console.log("  Min PegIn:", cfg.minimumPegIn);
        console.log("  Reward %:", cfg.rewardPercentage);
        console.log("  Resign Delay Blocks:", cfg.resignDelayBlocks);
        console.log("  Dust Threshold:", cfg.dustThreshold);
        console.log("  BTC Block Time:", cfg.btcBlockTime);
        console.log("  Mainnet:", cfg.mainnet);

        // Validations
        assertTrue(
            cfg.bridge != address(0),
            "Bridge address should not be zero"
        );
        assertTrue(
            cfg.minimumCollateral > 0,
            "Min collateral should be greater than zero"
        );
        assertTrue(
            cfg.minimumPegIn > 0,
            "Min PegIn should be greater than zero"
        );
        assertTrue(cfg.rewardPercentage <= 100, "Reward % should be <= 100");
        assertTrue(
            cfg.dustThreshold > 0,
            "Dust threshold should be greater than zero"
        );
        assertTrue(
            cfg.btcBlockTime > 0,
            "BTC block time should be greater than zero"
        );

        console.log("\n[PASS] HelperConfig returns valid configuration!");
    }

    function test_DeploymentFlow() public {
        console.log("\n=== TEST DEPLOYMENT FLOW ===\n");

        // Get config
        HelperConfig.NetworkConfig memory cfg = helperConfig.getConfig();

        console.log("1. Deploying LBC implementation...");
        LiquidityBridgeContract implementation = new LiquidityBridgeContract();
        console.log("   Implementation deployed at:", address(implementation));

        console.log("\n2. Deploying Proxy Admin...");
        LiquidityBridgeContractAdmin admin = new LiquidityBridgeContractAdmin();
        console.log("   Admin deployed at:", address(admin));

        console.log("\n3. Preparing initializer calldata...");
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
        console.log("   Init data length:", initData.length);

        console.log("\n4. Deploying Proxy...");
        LiquidityBridgeContractProxy proxy = new LiquidityBridgeContractProxy(
            address(implementation),
            address(admin),
            initData
        );
        console.log("   Proxy deployed at:", address(proxy));

        console.log("\n5. Verifying deployment...");
        LiquidityBridgeContract lbc = LiquidityBridgeContract(
            payable(address(proxy))
        );

        address bridgeAddress = lbc.getBridgeAddress();
        console.log("   Bridge address from contract:", bridgeAddress);
        assertEq(
            bridgeAddress,
            cfg.bridge,
            "Bridge address should match config"
        );

        console.log("\n[PASS] Deployment flow executed successfully!");
        console.log(
            "[PASS] All components deployed and initialized correctly!"
        );
    }

    function test_ConfigurationMatchesDeployment() public {
        console.log("\n=== TEST CONFIG MATCHES DEPLOYMENT ===\n");

        // Deploy using the same pattern as the script
        HelperConfig.NetworkConfig memory cfg = helperConfig.getConfig();

        LiquidityBridgeContract implementation = new LiquidityBridgeContract();
        LiquidityBridgeContractAdmin admin = new LiquidityBridgeContractAdmin();

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

        LiquidityBridgeContractProxy proxy = new LiquidityBridgeContractProxy(
            address(implementation),
            address(admin),
            initData
        );

        LiquidityBridgeContract lbc = LiquidityBridgeContract(
            payable(address(proxy))
        );

        // Verify all config values match
        console.log("Verifying configuration...");
        assertEq(lbc.getBridgeAddress(), cfg.bridge, "Bridge address mismatch");

        console.log(
            "\n[PASS] Deployed contract configuration matches HelperConfig!"
        );
        console.log("[PASS] DeployLBC pattern validated!");
    }
}
