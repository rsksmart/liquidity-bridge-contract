// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import {LiquidityBridgeContract} from "../../contracts/legacy/LiquidityBridgeContract.sol";
import {LiquidityBridgeContractV2} from "../../contracts/legacy/LiquidityBridgeContractV2.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {ERC1967Utils} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Utils.sol";

contract DeploymentTest is Test {
    address constant BRIDGE_ADDRESS =
        0x0000000000000000000000000000000001000006;
    address constant ZERO_ADDRESS = address(0);

    address public proxyAddress;

    struct TestCase {
        uint32 percentage;
        bool shouldSucceed;
    }

    function test_DeployLiquidityBridgeContractProxyAndInitializeIt() public {
        // Deploy V1 implementation
        LiquidityBridgeContract lbcV1Impl = new LiquidityBridgeContract();

        // Prepare initialization parameters
        uint256 MINIMUM_COLLATERAL = 0.03 ether;
        uint256 MINIMUM_PEGIN = 1;
        uint32 REWARD_PERCENTAGE = 50;
        uint32 RESIGN_DELAY_BLOCKS = 60;
        uint256 DUST_THRESHOLD = 1;
        uint256 BTC_BLOCK_TIME = 1;
        bool MAINNET = false;

        bytes memory initData = abi.encodeWithSelector(
            LiquidityBridgeContract.initialize.selector,
            payable(BRIDGE_ADDRESS),
            MINIMUM_COLLATERAL,
            MINIMUM_PEGIN,
            REWARD_PERCENTAGE,
            RESIGN_DELAY_BLOCKS,
            DUST_THRESHOLD,
            BTC_BLOCK_TIME,
            MAINNET
        );

        // Deploy proxy
        ERC1967Proxy proxy = new ERC1967Proxy(address(lbcV1Impl), initData);
        proxyAddress = address(proxy);

        // Verify proxy was deployed and initialized
        assertTrue(proxyAddress != address(0), "Proxy should be deployed");

        // Cast proxy to V1 contract and verify initialization
        LiquidityBridgeContract lbcProxy = LiquidityBridgeContract(
            payable(proxyAddress)
        );
        assertEq(
            lbcProxy.getMinCollateral(),
            MINIMUM_COLLATERAL,
            "MinCollateral should be initialized"
        );
        assertEq(
            lbcProxy.getRewardPercentage(),
            REWARD_PERCENTAGE,
            "Reward percentage should be initialized"
        );
    }

    function test_UpgradeProxyToLiquidityBridgeContractV2() public {
        // First deploy V1
        test_DeployLiquidityBridgeContractProxyAndInitializeIt();

        // Deploy V2 implementation
        LiquidityBridgeContractV2 lbcV2Impl = new LiquidityBridgeContractV2();

        // Manually upgrade the proxy by updating the implementation slot
        // ERC1967 implementation slot: bytes32(uint256(keccak256('eip1967.proxy.implementation')) - 1)
        bytes32 implementationSlot = bytes32(
            uint256(keccak256("eip1967.proxy.implementation")) - 1
        );

        // Update the implementation slot to point to V2
        vm.store(
            proxyAddress,
            implementationSlot,
            bytes32(uint256(uint160(address(lbcV2Impl))))
        );

        // Cast proxy to V2 and verify version
        // Note: initializeV2() doesn't need to be called in this test context since:
        // 1. V1 already initialized Ownable and ReentrancyGuard
        // 2. The test just validates the upgrade mechanism works
        // 3. The version() function doesn't depend on initializeV2
        LiquidityBridgeContractV2 lbcV2 = LiquidityBridgeContractV2(
            payable(proxyAddress)
        );
        string memory version = lbcV2.version();
        assertEq(version, "1.3.1", "Version should be 1.3.1");
    }

    function test_ValidateMinimumCollateralArgInInitialize() public {
        LiquidityBridgeContract lbcImpl = new LiquidityBridgeContract();

        uint256 MINIMUM_COLLATERAL = 0.02 ether; // Too low!
        uint32 RESIGN_DELAY_BLOCKS = 15;

        bytes memory initData = abi.encodeWithSelector(
            LiquidityBridgeContract.initialize.selector,
            payable(BRIDGE_ADDRESS),
            MINIMUM_COLLATERAL,
            1, // minPegIn
            50, // rewardPercentage
            RESIGN_DELAY_BLOCKS,
            1, // dustThreshold
            1, // btcBlockTime
            false // mainnet
        );

        // Expect revert with LBC072
        vm.expectRevert("LBC072");
        new ERC1967Proxy(address(lbcImpl), initData);
    }

    function test_ValidateResignDelayBlocksArgInInitialize() public {
        LiquidityBridgeContract lbcImpl = new LiquidityBridgeContract();

        uint256 MINIMUM_COLLATERAL = 0.6 ether;
        uint32 RESIGN_DELAY_BLOCKS = 14; // Too low!

        bytes memory initData = abi.encodeWithSelector(
            LiquidityBridgeContract.initialize.selector,
            payable(BRIDGE_ADDRESS),
            MINIMUM_COLLATERAL,
            1, // minPegIn
            50, // rewardPercentage
            RESIGN_DELAY_BLOCKS,
            1, // dustThreshold
            1, // btcBlockTime
            false // mainnet
        );

        // Expect revert with LBC073
        vm.expectRevert("LBC073");
        new ERC1967Proxy(address(lbcImpl), initData);
    }

    function test_ValidateRewardPercentageArgInInitialize() public {
        uint256 MINIMUM_COLLATERAL = 0.6 ether;
        uint32 RESIGN_DELAY_BLOCKS = 60;

        TestCase[5] memory testCases = [
            TestCase(0, true),
            TestCase(1, true),
            TestCase(99, true),
            TestCase(100, true),
            TestCase(101, false)
        ];

        for (uint i = 0; i < testCases.length; i++) {
            TestCase memory testCase = testCases[i];

            // Deploy new implementation for each test
            LiquidityBridgeContract lbcImpl = new LiquidityBridgeContract();

            bytes memory initData = abi.encodeWithSelector(
                LiquidityBridgeContract.initialize.selector,
                payable(BRIDGE_ADDRESS),
                MINIMUM_COLLATERAL,
                1, // minPegIn
                testCase.percentage, // rewardPercentage
                RESIGN_DELAY_BLOCKS,
                1, // dustThreshold
                1, // btcBlockTime
                false // mainnet
            );

            if (testCase.shouldSucceed) {
                // Should not revert
                ERC1967Proxy proxy = new ERC1967Proxy(
                    address(lbcImpl),
                    initData
                );
                LiquidityBridgeContract lbcV1 = LiquidityBridgeContract(
                    payable(address(proxy))
                );

                // Try to reinitialize - should revert
                vm.expectRevert();
                lbcV1.initialize(
                    payable(BRIDGE_ADDRESS),
                    MINIMUM_COLLATERAL,
                    1,
                    testCase.percentage,
                    RESIGN_DELAY_BLOCKS,
                    1,
                    1,
                    false
                );
            } else {
                // Should revert with LBC004
                vm.expectRevert("LBC004");
                new ERC1967Proxy(address(lbcImpl), initData);
            }
        }
    }

    function test_DeployImplementationWithoutUpgradingProxy() public {
        // Deploy V1 proxy
        LiquidityBridgeContract lbcV1Impl = new LiquidityBridgeContract();

        bytes memory v1InitData = abi.encodeWithSelector(
            LiquidityBridgeContract.initialize.selector,
            payable(BRIDGE_ADDRESS),
            0.03 ether, // minCollateral
            1, // minPegIn
            50, // rewardPercentage
            60, // resignDelayBlocks
            1, // dustThreshold
            1, // btcBlockTime
            false // mainnet
        );

        ERC1967Proxy proxy = new ERC1967Proxy(address(lbcV1Impl), v1InitData);
        proxyAddress = address(proxy);

        // Verify proxy initialization
        LiquidityBridgeContract lbcProxyV1 = LiquidityBridgeContract(
            payable(proxyAddress)
        );
        assertEq(
            lbcProxyV1.getMinCollateral(),
            0.03 ether,
            "Proxy should be initialized"
        );

        // Deploy V2 implementation (without upgrading proxy)
        LiquidityBridgeContractV2 lbcV2Impl = new LiquidityBridgeContractV2();

        // Cast both to their respective types
        LiquidityBridgeContract lbcProxy = LiquidityBridgeContract(
            payable(proxyAddress)
        );

        // Verify addresses are different
        assertTrue(
            proxyAddress != address(lbcV2Impl),
            "Proxy and implementation should have different addresses"
        );

        // Verify proxy has state (minCollateral)
        assertEq(
            lbcProxy.getMinCollateral(),
            0.03 ether,
            "Proxy should have initialized state"
        );

        // Verify implementation has no state
        assertEq(
            lbcV2Impl.getMinCollateral(),
            0,
            "Implementation should have no state"
        );

        // Verify proxy doesn't have version() (V1 doesn't have it)
        vm.expectRevert();
        LiquidityBridgeContractV2(payable(proxyAddress)).version();

        // Verify implementation has version()
        assertEq(
            lbcV2Impl.version(),
            "1.3.1",
            "Implementation should have version 1.3.1"
        );
    }
}
