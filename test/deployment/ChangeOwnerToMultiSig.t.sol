// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import "lib/forge-std/src/Test.sol";
import "lib/forge-std/src/console.sol";
import {ChangeOwnerToMultiSig} from "../../script/legacy/deployment/ChangeOwnerToMultiSig.s.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {LiquidityBridgeContract} from "../../src/legacy/LiquidityBridgeContract.sol";
import {LiquidityBridgeContractProxy} from "../../src/legacy/LiquidityBridgeContractProxy.sol";
import {LiquidityBridgeContractAdmin} from "../../src/legacy/LiquidityBridgeContractAdmin.sol";

/**
 * @title ChangeOwnerToMultiSigTest
 * @notice Test for the ChangeOwnerToMultiSig deployment script
 * @dev Tests ownership transfer pattern to multisig
 */
contract ChangeOwnerToMultiSigTest is Test {
    ChangeOwnerToMultiSig public changeOwnerScript;
    HelperConfig public helperConfig;

    LiquidityBridgeContract public lbc;
    LiquidityBridgeContractProxy public proxy;
    LiquidityBridgeContractAdmin public admin;

    address public currentOwner;
    address public newOwner;

    function setUp() public {
        currentOwner = address(this);
        newOwner = makeAddr("multisig");

        // Instantiate scripts
        changeOwnerScript = new ChangeOwnerToMultiSig();
        helperConfig = new HelperConfig();

        // Deploy LBC with proxy for testing ownership transfer
        console.log("Setting up LBC deployment...");
        deployLBC();
    }

    function deployLBC() internal {
        HelperConfig.NetworkConfig memory cfg = helperConfig.getConfig();

        // Deploy implementation
        lbc = new LiquidityBridgeContract();

        // Deploy admin
        admin = new LiquidityBridgeContractAdmin();

        // Deploy proxy
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

        proxy = new LiquidityBridgeContractProxy(
            address(lbc),
            address(admin),
            initData
        );

        console.log("  Proxy:", address(proxy));
        console.log("  Admin:", address(admin));
        console.log("  Implementation:", address(lbc));
    }

    function test_OwnershipTransferPattern() public {
        console.log("\n=== TEST OWNERSHIP TRANSFER PATTERN ===\n");

        // Get proxy as LBC contract
        LiquidityBridgeContract lbcProxy = LiquidityBridgeContract(
            payable(address(proxy))
        );

        console.log("1. Verifying current ownership...");
        address currentContractOwner = lbcProxy.owner();
        console.log("   Current contract owner:", currentContractOwner);
        assertEq(
            currentContractOwner,
            currentOwner,
            "Initial owner should be test contract"
        );

        address currentAdminOwner = admin.owner();
        console.log("   Current admin owner:", currentAdminOwner);
        assertEq(
            currentAdminOwner,
            currentOwner,
            "Admin owner should be test contract"
        );

        // Transfer contract ownership
        console.log("\n2. Transferring contract ownership...");
        lbcProxy.transferOwnership(newOwner);
        address newContractOwner = lbcProxy.owner();
        console.log("   New contract owner:", newContractOwner);
        assertEq(
            newContractOwner,
            newOwner,
            "Contract ownership should be transferred"
        );

        // Transfer admin ownership
        console.log("\n3. Transferring admin ownership...");
        admin.transferOwnership(newOwner);
        address newAdminOwner = admin.owner();
        console.log("   New admin owner:", newAdminOwner);
        assertEq(
            newAdminOwner,
            newOwner,
            "Admin ownership should be transferred"
        );

        // Verify new owner can perform owner operations
        address testAddress = makeAddr("testAddress");
        vm.prank(newOwner);
        lbcProxy.transferOwnership(testAddress);
        address verifiedOwner = lbcProxy.owner();
        assertEq(
            verifiedOwner,
            testAddress,
            "New owner should be able to transfer ownership"
        );

        // Transfer back to newOwner for further testing
        vm.prank(testAddress);
        lbcProxy.transferOwnership(newOwner);
        assertEq(
            lbcProxy.owner(),
            newOwner,
            "Ownership should be transferred back to newOwner"
        );

        // Verify old owner cannot perform owner operations
        vm.prank(currentOwner);
        vm.expectRevert(); // Should revert with "Ownable: caller is not the owner"
        lbcProxy.transferOwnership(makeAddr("anotherAddress"));

        // Verify old admin owner cannot perform admin operations
        vm.prank(currentOwner);
        vm.expectRevert(); // Should revert with "Ownable: caller is not the owner"
        admin.transferOwnership(makeAddr("anotherAddress"));
    }

    function test_CannotTransferToZeroAddress() public {
        console.log("\n=== TEST CANNOT TRANSFER TO ZERO ADDRESS ===\n");

        LiquidityBridgeContract lbcProxy = LiquidityBridgeContract(
            payable(address(proxy))
        );

        // Should revert when transferring to zero address
        vm.expectRevert();
        lbcProxy.transferOwnership(address(0));

        console.log("[PASS] Cannot transfer to zero address!");
    }

    function test_OnlyOwnerCanTransferOwnership() public {
        console.log("\n=== TEST ONLY OWNER CAN TRANSFER ===\n");

        LiquidityBridgeContract lbcProxy = LiquidityBridgeContract(
            payable(address(proxy))
        );

        address nonOwner = makeAddr("nonOwner");

        // Should revert when non-owner tries to transfer
        vm.prank(nonOwner);
        vm.expectRevert();
        lbcProxy.transferOwnership(newOwner);

        console.log("[PASS] Only owner can transfer ownership!");
        console.log("[PASS] ChangeOwnerToMultiSig.s.sol pattern validated!");
    }
}
