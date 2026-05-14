// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {CollateralTestBase} from "./CollateralTestBase.sol";
import {CollateralManagementContract} from "../../src/CollateralManagement.sol";
import {ICollateralManagement} from "../../src/interfaces/ICollateralManagement.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Flyover} from "../../src/libraries/Flyover.sol";

contract ConfigurationTest is CollateralTestBase {
    address public notOwner;

    function setUp() public {
        deployCollateralManagement();

        // Create additional test accounts
        notOwner = makeAddr("notOwner");
        vm.deal(notOwner, 100 ether);
    }

    // ============ receive function tests ============

    function test_Receive_RejectsAnyRBTCSentToContract() public {
        address payable contractAddress = payable(
            address(collateralManagement)
        );

        // Owner cannot send RBTC directly
        vm.prank(owner);
        vm.expectRevert(
            abi.encodeWithSelector(Flyover.PaymentNotAllowed.selector)
        );
        (bool success, ) = contractAddress.call{value: ONE_RBTC}("");
        success; // Suppress warning

        // Any other account cannot send RBTC directly
        vm.prank(notOwner);
        vm.expectRevert(
            abi.encodeWithSelector(Flyover.PaymentNotAllowed.selector)
        );
        (success, ) = contractAddress.call{value: ONE_RBTC}("");
        success; // Suppress warning
    }

    // ============ initialize function tests ============

    function test_Initialize_InitializesProperly() public view {
        // Check VERSION
        assertEq(
            collateralManagement.VERSION(),
            "1.0.0",
            "VERSION should be 1.0.0"
        );

        // Check minCollateral
        assertEq(
            collateralManagement.getMinCollateral(),
            TEST_MIN_COLLATERAL,
            "MinCollateral should match"
        );

        // Check resignDelayInBlocks
        assertEq(
            collateralManagement.getResignDelayInBlocks(),
            TEST_RESIGN_DELAY_BLOCKS,
            "ResignDelayInBlocks should match"
        );

        // Check rewardPercentage
        assertEq(
            collateralManagement.getRewardPercentage(),
            TEST_REWARD_PERCENTAGE,
            "RewardPercentage should match"
        );

        // Check owner
        assertEq(collateralManagement.owner(), owner, "Owner should match");

        // Check penalties
        assertEq(
            collateralManagement.getPenalties(),
            0,
            "Penalties should be 0"
        );
    }

    function test_Initialize_AllowsInitializeOnlyOnce() public {
        vm.expectRevert(abi.encodeWithSignature("InvalidInitialization()"));
        collateralManagement.initialize(
            owner,
            TEST_DEFAULT_ADMIN_DELAY,
            TEST_MIN_COLLATERAL,
            TEST_RESIGN_DELAY_BLOCKS,
            TEST_REWARD_PERCENTAGE,
            pauseRegistry
        );
    }

    function test_Initialize_RevertsWhenCalledOnImplementation() public {
        CollateralManagementContract implementation = new CollateralManagementContract();

        vm.expectRevert(abi.encodeWithSignature("InvalidInitialization()"));
        implementation.initialize(
            owner,
            TEST_DEFAULT_ADMIN_DELAY,
            TEST_MIN_COLLATERAL,
            TEST_RESIGN_DELAY_BLOCKS,
            TEST_REWARD_PERCENTAGE,
            pauseRegistry
        );
    }

    function test_Initialize_RevertsWhenRewardPercentageExceedsMaximum()
        public
    {
        uint256 invalidRewardPercentage = collateralManagement
            .TOTAL_REWARD_PERCENTAGE() + 1;
        CollateralManagementContract implementation = new CollateralManagementContract();
        bytes memory initData = abi.encodeCall(
            CollateralManagementContract.initialize,
            (
                owner,
                TEST_DEFAULT_ADMIN_DELAY,
                TEST_MIN_COLLATERAL,
                TEST_RESIGN_DELAY_BLOCKS,
                invalidRewardPercentage,
                pauseRegistry
            )
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                ICollateralManagement.InvalidRewardPercentage.selector,
                collateralManagement.TOTAL_REWARD_PERCENTAGE(),
                invalidRewardPercentage
            )
        );
        new ERC1967Proxy(address(implementation), initData);
    }

    function test_Initialize_RevertsWhenMinCollateralIsZero() public {
        CollateralManagementContract implementation = new CollateralManagementContract();
        bytes memory initData = abi.encodeCall(
            CollateralManagementContract.initialize,
            (
                owner,
                TEST_DEFAULT_ADMIN_DELAY,
                0,
                TEST_RESIGN_DELAY_BLOCKS,
                TEST_REWARD_PERCENTAGE,
                pauseRegistry
            )
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                ICollateralManagement.InvalidMinCollateral.selector,
                uint256(0)
            )
        );
        new ERC1967Proxy(address(implementation), initData);
    }

    function test_Initialize_AllowsMinimumBoundaryMinCollateral() public {
        CollateralManagementContract implementation = new CollateralManagementContract();
        uint256 minOneWei = 1;
        bytes memory initData = abi.encodeCall(
            CollateralManagementContract.initialize,
            (
                owner,
                TEST_DEFAULT_ADMIN_DELAY,
                minOneWei,
                TEST_RESIGN_DELAY_BLOCKS,
                TEST_REWARD_PERCENTAGE,
                pauseRegistry
            )
        );

        ERC1967Proxy proxy = new ERC1967Proxy(
            address(implementation),
            initData
        );
        CollateralManagementContract cm = CollateralManagementContract(
            payable(address(proxy))
        );
        assertEq(cm.getMinCollateral(), minOneWei);
    }

    function test_Initialize_AllowsMaximumBoundary() public {
        uint256 maxRewardPercentage = collateralManagement
            .TOTAL_REWARD_PERCENTAGE();
        CollateralManagementContract implementation = new CollateralManagementContract();
        bytes memory initData = abi.encodeCall(
            CollateralManagementContract.initialize,
            (
                owner,
                TEST_DEFAULT_ADMIN_DELAY,
                TEST_MIN_COLLATERAL,
                TEST_RESIGN_DELAY_BLOCKS,
                maxRewardPercentage,
                pauseRegistry
            )
        );

        ERC1967Proxy proxy = new ERC1967Proxy(
            address(implementation),
            initData
        );
        CollateralManagementContract collateralManagementWithMaxReward = CollateralManagementContract(
                payable(address(proxy))
            );

        assertEq(
            collateralManagementWithMaxReward.getRewardPercentage(),
            maxRewardPercentage,
            "Initialize should accept maximum basis points value"
        );
    }

    // ============ setRewardPercentage function tests ============

    function test_SetRewardPercentage_OnlyAllowsOwnerToModify() public {
        bytes32 defaultAdminRole = collateralManagement.DEFAULT_ADMIN_ROLE();

        vm.prank(notOwner);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                notOwner,
                defaultAdminRole
            )
        );
        collateralManagement.setRewardPercentage(50);
    }

    function test_SetRewardPercentage_ModifiesProperly() public {
        uint256 oldRewardPercentage = collateralManagement
            .getRewardPercentage();
        uint256 newRewardPercentage = 55;

        vm.prank(owner);
        vm.expectEmit(true, true, false, false);
        emit CollateralManagementContract.RewardPercentageSet(
            oldRewardPercentage,
            newRewardPercentage
        );
        collateralManagement.setRewardPercentage(newRewardPercentage);

        assertEq(
            collateralManagement.getRewardPercentage(),
            newRewardPercentage,
            "RewardPercentage should be updated"
        );
    }

    function test_SetRewardPercentage_RevertsWhenExceedingMaximum() public {
        uint256 initialRewardPercentage = collateralManagement
            .getRewardPercentage();
        uint256 invalidRewardPercentage = collateralManagement
            .TOTAL_REWARD_PERCENTAGE() + 1;

        vm.startPrank(owner);
        vm.expectRevert(
            abi.encodeWithSelector(
                ICollateralManagement.InvalidRewardPercentage.selector,
                collateralManagement.TOTAL_REWARD_PERCENTAGE(),
                invalidRewardPercentage
            )
        );
        collateralManagement.setRewardPercentage(invalidRewardPercentage);
        vm.stopPrank();

        assertEq(
            collateralManagement.getRewardPercentage(),
            initialRewardPercentage,
            "RewardPercentage should remain unchanged after revert"
        );
    }

    function test_SetRewardPercentage_AllowsMaximumBoundary() public {
        uint256 oldRewardPercentage = collateralManagement
            .getRewardPercentage();
        uint256 maxRewardPercentage = collateralManagement
            .TOTAL_REWARD_PERCENTAGE();

        vm.prank(owner);
        vm.expectEmit(true, true, false, false);
        emit CollateralManagementContract.RewardPercentageSet(
            oldRewardPercentage,
            maxRewardPercentage
        );
        collateralManagement.setRewardPercentage(maxRewardPercentage);

        assertEq(
            collateralManagement.getRewardPercentage(),
            maxRewardPercentage,
            "RewardPercentage should accept maximum basis points value"
        );
    }

    // ============ setResignDelayInBlocks function tests ============

    function test_SetResignDelayInBlocks_OnlyAllowsOwnerToModify() public {
        bytes32 defaultAdminRole = collateralManagement.DEFAULT_ADMIN_ROLE();

        vm.prank(notOwner);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                notOwner,
                defaultAdminRole
            )
        );
        collateralManagement.setResignDelayInBlocks(123);
    }

    function test_SetResignDelayInBlocks_ModifiesProperly() public {
        uint256 oldResignDelay = collateralManagement.getResignDelayInBlocks();
        uint256 newResignDelay = 321;

        vm.prank(owner);
        vm.expectEmit(true, true, false, false);
        emit CollateralManagementContract.ResignDelayInBlocksSet(
            oldResignDelay,
            newResignDelay
        );
        collateralManagement.setResignDelayInBlocks(newResignDelay);

        assertEq(
            collateralManagement.getResignDelayInBlocks(),
            newResignDelay,
            "ResignDelayInBlocks should be updated"
        );
    }

    // ============ setMinCollateral function tests ============

    function test_SetMinCollateral_OnlyAllowsOwnerToModify() public {
        bytes32 defaultAdminRole = collateralManagement.DEFAULT_ADMIN_ROLE();

        vm.prank(notOwner);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                notOwner,
                defaultAdminRole
            )
        );
        collateralManagement.setMinCollateral(1);
    }

    function test_SetMinCollateral_ModifiesProperly() public {
        uint256 oldMinCollateral = collateralManagement.getMinCollateral();
        uint256 newMinCollateral = 11;

        vm.prank(owner);
        vm.expectEmit(true, true, false, false);
        emit CollateralManagementContract.MinCollateralSet(
            oldMinCollateral,
            newMinCollateral
        );
        collateralManagement.setMinCollateral(newMinCollateral);

        assertEq(
            collateralManagement.getMinCollateral(),
            newMinCollateral,
            "MinCollateral should be updated"
        );
    }

    function test_SetMinCollateral_RevertsWhenMinCollateralIsZero() public {
        uint256 currentMin = collateralManagement.getMinCollateral();

        vm.prank(owner);
        vm.expectRevert(
            abi.encodeWithSelector(
                ICollateralManagement.InvalidMinCollateral.selector,
                uint256(0)
            )
        );
        collateralManagement.setMinCollateral(0);

        assertEq(
            collateralManagement.getMinCollateral(),
            currentMin,
            "MinCollateral should be unchanged after revert"
        );
    }

    function test_SetMinCollateral_AllowsMinimumBoundary() public {
        vm.prank(owner);
        collateralManagement.setMinCollateral(1);
        assertEq(collateralManagement.getMinCollateral(), 1);
    }
}
