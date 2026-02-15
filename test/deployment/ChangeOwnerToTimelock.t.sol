// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import "lib/forge-std/src/Test.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {LiquidityBridgeContract} from "../../src/legacy/LiquidityBridgeContract.sol";
import {LiquidityBridgeContractProxy} from "../../src/legacy/LiquidityBridgeContractProxy.sol";
import {LiquidityBridgeContractAdmin} from "../../src/legacy/LiquidityBridgeContractAdmin.sol";

contract ChangeOwnerToTimelockTest is Test {
    bytes32 internal constant ADMIN_SLOT =
        0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103;

    HelperConfig public helperConfig;
    LiquidityBridgeContract public lbcImpl;
    LiquidityBridgeContractProxy public proxy;
    LiquidityBridgeContractAdmin public admin;
    TimelockController public timelock;

    address public proposer;
    address public executor;
    uint256 public minDelay;

    function setUp() public {
        helperConfig = new HelperConfig();
        proposer = makeAddr("proposer");
        executor = makeAddr("executor");
        minDelay = 7 days;

        HelperConfig.NetworkConfig memory cfg = helperConfig.getConfig();

        lbcImpl = new LiquidityBridgeContract();
        admin = new LiquidityBridgeContractAdmin();

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
            address(lbcImpl),
            address(admin),
            initData
        );

        address[] memory proposers = new address[](1);
        proposers[0] = proposer;
        address[] memory executors = new address[](1);
        executors[0] = executor;

        timelock = new TimelockController(
            minDelay,
            proposers,
            executors,
            address(0)
        );
    }

    function test_TransfersLegacyOwnershipsToTimelock() public {
        LiquidityBridgeContract lbcProxy = LiquidityBridgeContract(
            payable(address(proxy))
        );
        LiquidityBridgeContractAdmin actualAdmin = _getProxyAdmin();

        lbcProxy.transferOwnership(address(timelock));
        vm.prank(actualAdmin.owner());
        actualAdmin.transferOwnership(address(timelock));

        assertEq(lbcProxy.owner(), address(timelock), "LBC owner mismatch");
        assertEq(
            actualAdmin.owner(),
            address(timelock),
            "ProxyAdmin owner mismatch"
        );
        assertEq(timelock.getMinDelay(), minDelay, "minDelay mismatch");
        assertTrue(
            timelock.hasRole(timelock.PROPOSER_ROLE(), proposer),
            "proposer missing"
        );
        assertTrue(
            timelock.hasRole(timelock.EXECUTOR_ROLE(), executor),
            "executor missing"
        );
    }

    function test_OwnerOnlyOperationIsDelayedByTimelock() public {
        LiquidityBridgeContract lbcProxy = LiquidityBridgeContract(
            payable(address(proxy))
        );
        lbcProxy.transferOwnership(address(timelock));

        address newOwner = makeAddr("newOwner");
        bytes memory payload = abi.encodeWithSignature(
            "transferOwnership(address)",
            newOwner
        );
        bytes32 predecessor = bytes32(0);
        bytes32 salt = keccak256("owner-op");

        vm.expectRevert();
        lbcProxy.transferOwnership(newOwner);

        vm.prank(proposer);
        timelock.schedule(
            address(lbcProxy),
            0,
            payload,
            predecessor,
            salt,
            minDelay
        );

        vm.prank(executor);
        vm.expectRevert();
        timelock.execute(address(lbcProxy), 0, payload, predecessor, salt);

        vm.warp(block.timestamp + minDelay);
        vm.prank(executor);
        timelock.execute(address(lbcProxy), 0, payload, predecessor, salt);

        assertEq(lbcProxy.owner(), newOwner, "timelocked owner-op failed");
    }

    function test_ProxyAdminStoredInExpectedSlot() public {
        address proxyAdminAddress = address(
            uint160(uint256(vm.load(address(proxy), ADMIN_SLOT)))
        );
        assertTrue(proxyAdminAddress != address(0), "EIP-1967 admin missing");
    }

    function _getProxyAdmin()
        internal
        view
        returns (LiquidityBridgeContractAdmin)
    {
        address proxyAdminAddress = address(
            uint160(uint256(vm.load(address(proxy), ADMIN_SLOT)))
        );
        return LiquidityBridgeContractAdmin(proxyAdminAddress);
    }
}
