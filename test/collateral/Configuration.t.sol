// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {CollateralTestBase} from "./CollateralTestBase.sol";
import {CollateralManagementContract} from "../../src/CollateralManagement.sol";
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
            TEST_REWARD_PERCENTAGE
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
}
