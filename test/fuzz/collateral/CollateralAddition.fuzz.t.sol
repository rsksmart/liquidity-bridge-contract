// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {CollateralFuzzTestBase} from "./CollateralFuzzTestBase.sol";
import {ICollateralManagement} from "../../../src/interfaces/ICollateralManagement.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {Flyover} from "../../../src/libraries/Flyover.sol";

/// @title CollateralManagement Addition Fuzz Tests
/// @notice Fuzz tests for adding collateral functionality
contract CollateralAdditionFuzzTest is CollateralFuzzTestBase {
    function setUp() public {
        deployCollateralManagement();
        setupRoles();

        fuzzUser = makeAddr("fuzzUser");
        vm.deal(fuzzUser, 1000 ether);
    }

    // ============ addPegInCollateralTo Tests ============

    /// @notice Fuzz test: Adder can add PegIn collateral to any address
    function testFuzz_AddPegInCollateralTo_AdderCanAddToAnyAddress(
        address recipient,
        uint256 amount
    ) public {
        vm.assume(recipient != address(0));
        amount = bound(amount, 0.001 ether, 50 ether);

        uint256 collateralBefore = collateralManagement.getPegInCollateral(
            recipient
        );

        vm.prank(adder);
        vm.expectEmit(true, true, false, true);
        emit ICollateralManagement.PegInCollateralAdded(recipient, amount);
        collateralManagement.addPegInCollateralTo{value: amount}(recipient);

        assertEq(
            collateralManagement.getPegInCollateral(recipient),
            collateralBefore + amount,
            "Collateral should increase"
        );
    }

    /// @notice Fuzz test: Multiple additions accumulate correctly
    function testFuzz_AddPegInCollateralTo_AccumulatesMultipleAdditions(
        uint64 amount1,
        uint64 amount2,
        uint64 amount3
    ) public {
        amount1 = uint64(bound(amount1, 0.001 ether, 10 ether));
        amount2 = uint64(bound(amount2, 0.001 ether, 10 ether));
        amount3 = uint64(bound(amount3, 0.001 ether, 10 ether));

        uint256 expectedTotal = uint256(amount1) +
            uint256(amount2) +
            uint256(amount3);

        vm.startPrank(adder);
        collateralManagement.addPegInCollateralTo{value: amount1}(fuzzUser);
        collateralManagement.addPegInCollateralTo{value: amount2}(fuzzUser);
        collateralManagement.addPegInCollateralTo{value: amount3}(fuzzUser);
        vm.stopPrank();

        assertEq(
            collateralManagement.getPegInCollateral(fuzzUser),
            expectedTotal,
            "Collateral should equal sum of additions"
        );
    }

    /// @notice Fuzz test: Non-adder cannot add collateral
    function testFuzz_AddPegInCollateralTo_RevertsForNonAdder(
        address nonAdder,
        uint256 amount
    ) public {
        vm.assume(nonAdder != adder);
        vm.assume(nonAdder != address(0));
        amount = bound(amount, 0.001 ether, 10 ether);
        vm.deal(nonAdder, 100 ether);

        bytes32 adderRole = collateralManagement.COLLATERAL_ADDER();

        vm.prank(nonAdder);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                nonAdder,
                adderRole
            )
        );
        collateralManagement.addPegInCollateralTo{value: amount}(fuzzUser);
    }

    // ============ addPegOutCollateralTo Tests ============

    /// @notice Fuzz test: Adder can add PegOut collateral to any address
    function testFuzz_AddPegOutCollateralTo_AdderCanAddToAnyAddress(
        address recipient,
        uint256 amount
    ) public {
        vm.assume(recipient != address(0));
        amount = bound(amount, 0.001 ether, 50 ether);

        uint256 collateralBefore = collateralManagement.getPegOutCollateral(
            recipient
        );

        vm.prank(adder);
        vm.expectEmit(true, true, false, true);
        emit ICollateralManagement.PegOutCollateralAdded(recipient, amount);
        collateralManagement.addPegOutCollateralTo{value: amount}(recipient);

        assertEq(
            collateralManagement.getPegOutCollateral(recipient),
            collateralBefore + amount,
            "Collateral should increase"
        );
    }

    /// @notice Fuzz test: Multiple PegOut additions accumulate correctly
    function testFuzz_AddPegOutCollateralTo_AccumulatesMultipleAdditions(
        uint64 amount1,
        uint64 amount2,
        uint64 amount3
    ) public {
        amount1 = uint64(bound(amount1, 0.001 ether, 10 ether));
        amount2 = uint64(bound(amount2, 0.001 ether, 10 ether));
        amount3 = uint64(bound(amount3, 0.001 ether, 10 ether));

        uint256 expectedTotal = uint256(amount1) +
            uint256(amount2) +
            uint256(amount3);

        vm.startPrank(adder);
        collateralManagement.addPegOutCollateralTo{value: amount1}(fuzzUser);
        collateralManagement.addPegOutCollateralTo{value: amount2}(fuzzUser);
        collateralManagement.addPegOutCollateralTo{value: amount3}(fuzzUser);
        vm.stopPrank();

        assertEq(
            collateralManagement.getPegOutCollateral(fuzzUser),
            expectedTotal,
            "Collateral should equal sum of additions"
        );
    }

    /// @notice Fuzz test: Non-adder cannot add PegOut collateral
    function testFuzz_AddPegOutCollateralTo_RevertsForNonAdder(
        address nonAdder,
        uint256 amount
    ) public {
        vm.assume(nonAdder != adder);
        vm.assume(nonAdder != address(0));
        amount = bound(amount, 0.001 ether, 10 ether);
        vm.deal(nonAdder, 100 ether);

        bytes32 adderRole = collateralManagement.COLLATERAL_ADDER();

        vm.prank(nonAdder);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                nonAdder,
                adderRole
            )
        );
        collateralManagement.addPegOutCollateralTo{value: amount}(fuzzUser);
    }

    // ============ addPegInCollateral (self-add) Tests ============

    /// @notice Fuzz test: Registered provider can add PegIn collateral to self
    function testFuzz_AddPegInCollateral_RegisteredProviderCanAddToSelf(
        uint256 initialAmount,
        uint256 additionalAmount
    ) public {
        initialAmount = bound(initialAmount, 0.1 ether, 10 ether);
        additionalAmount = bound(additionalAmount, 0.001 ether, 10 ether);

        // First register by having adder add initial collateral
        vm.prank(adder);
        collateralManagement.addPegInCollateralTo{value: initialAmount}(
            fuzzUser
        );

        // Now provider can add more
        vm.prank(fuzzUser);
        vm.expectEmit(true, true, false, true);
        emit ICollateralManagement.PegInCollateralAdded(
            fuzzUser,
            additionalAmount
        );
        collateralManagement.addPegInCollateral{value: additionalAmount}();

        assertEq(
            collateralManagement.getPegInCollateral(fuzzUser),
            initialAmount + additionalAmount,
            "Collateral should be sum of initial and additional"
        );
    }

    /// @notice Fuzz test: Unregistered address cannot add PegIn collateral to self
    function testFuzz_AddPegInCollateral_RevertsForUnregistered(
        uint256 amount
    ) public {
        amount = bound(amount, 0.001 ether, 10 ether);

        vm.prank(fuzzUser);
        vm.expectRevert(
            abi.encodeWithSelector(
                Flyover.ProviderNotRegistered.selector,
                fuzzUser
            )
        );
        collateralManagement.addPegInCollateral{value: amount}();
    }

    // ============ addPegOutCollateral (self-add) Tests ============

    /// @notice Fuzz test: Registered provider can add PegOut collateral to self
    function testFuzz_AddPegOutCollateral_RegisteredProviderCanAddToSelf(
        uint256 initialAmount,
        uint256 additionalAmount
    ) public {
        initialAmount = bound(initialAmount, 0.1 ether, 10 ether);
        additionalAmount = bound(additionalAmount, 0.001 ether, 10 ether);

        // First register by having adder add initial collateral
        vm.prank(adder);
        collateralManagement.addPegOutCollateralTo{value: initialAmount}(
            fuzzUser
        );

        // Now provider can add more
        vm.prank(fuzzUser);
        vm.expectEmit(true, true, false, true);
        emit ICollateralManagement.PegOutCollateralAdded(
            fuzzUser,
            additionalAmount
        );
        collateralManagement.addPegOutCollateral{value: additionalAmount}();

        assertEq(
            collateralManagement.getPegOutCollateral(fuzzUser),
            initialAmount + additionalAmount,
            "Collateral should be sum of initial and additional"
        );
    }

    /// @notice Fuzz test: Unregistered address cannot add PegOut collateral to self
    function testFuzz_AddPegOutCollateral_RevertsForUnregistered(
        uint256 amount
    ) public {
        amount = bound(amount, 0.001 ether, 10 ether);

        vm.prank(fuzzUser);
        vm.expectRevert(
            abi.encodeWithSelector(
                Flyover.ProviderNotRegistered.selector,
                fuzzUser
            )
        );
        collateralManagement.addPegOutCollateral{value: amount}();
    }

    // ============ Contract Balance Tests ============

    /// @notice Fuzz test: Contract balance increases correctly
    function testFuzz_AddCollateral_ContractBalanceIncreases(
        uint128 pegInAmount,
        uint128 pegOutAmount
    ) public {
        pegInAmount = uint128(bound(pegInAmount, 0.001 ether, 50 ether));
        pegOutAmount = uint128(bound(pegOutAmount, 0.001 ether, 50 ether));

        uint256 balanceBefore = address(collateralManagement).balance;

        vm.startPrank(adder);
        collateralManagement.addPegInCollateralTo{value: pegInAmount}(fuzzUser);
        collateralManagement.addPegOutCollateralTo{value: pegOutAmount}(
            fuzzUser
        );
        vm.stopPrank();

        assertEq(
            address(collateralManagement).balance,
            balanceBefore + pegInAmount + pegOutAmount,
            "Contract balance should increase by total added"
        );
    }

    // ============ Registration Status Tests ============

    /// @notice Fuzz test: Adding collateral makes provider registered
    function testFuzz_AddCollateral_MakesProviderRegistered(
        uint256 amount
    ) public {
        amount = bound(amount, TEST_MIN_COLLATERAL, 50 ether);

        assertFalse(
            collateralManagement.isRegistered(
                Flyover.ProviderType.PegIn,
                fuzzUser
            ),
            "Should not be registered initially"
        );

        vm.prank(adder);
        collateralManagement.addPegInCollateralTo{value: amount}(fuzzUser);

        assertTrue(
            collateralManagement.isRegistered(
                Flyover.ProviderType.PegIn,
                fuzzUser
            ),
            "Should be registered after adding collateral"
        );
    }

    /// @notice Fuzz test: Adding sufficient collateral makes collateral sufficient
    function testFuzz_AddCollateral_MakesCollateralSufficient(
        uint256 amount
    ) public {
        amount = bound(amount, TEST_MIN_COLLATERAL, 50 ether);

        assertFalse(
            collateralManagement.isCollateralSufficient(
                Flyover.ProviderType.PegIn,
                fuzzUser
            ),
            "Should not be sufficient initially"
        );

        vm.prank(adder);
        collateralManagement.addPegInCollateralTo{value: amount}(fuzzUser);

        assertTrue(
            collateralManagement.isCollateralSufficient(
                Flyover.ProviderType.PegIn,
                fuzzUser
            ),
            "Should be sufficient after adding >= min collateral"
        );
    }

    /// @notice Fuzz test: Adding less than minimum does not make collateral sufficient
    function testFuzz_AddCollateral_BelowMinNotSufficient(
        uint256 amount
    ) public {
        amount = bound(amount, 1 wei, TEST_MIN_COLLATERAL - 1);

        vm.prank(adder);
        collateralManagement.addPegInCollateralTo{value: amount}(fuzzUser);

        // Is registered (has > 0 collateral)
        assertTrue(
            collateralManagement.isRegistered(
                Flyover.ProviderType.PegIn,
                fuzzUser
            ),
            "Should be registered with any collateral"
        );

        // But not sufficient
        assertFalse(
            collateralManagement.isCollateralSufficient(
                Flyover.ProviderType.PegIn,
                fuzzUser
            ),
            "Should not be sufficient with < min collateral"
        );
    }

    // ============ Receive Rejection Tests ============

    /// @notice Fuzz test: Direct ETH transfer to contract reverts
    function testFuzz_Receive_RevertsOnDirectTransfer(uint256 amount) public {
        amount = bound(amount, 1 wei, 10 ether);

        vm.prank(fuzzUser);
        (bool success, bytes memory returnData) = address(collateralManagement)
            .call{value: amount}("");

        // Low-level calls don't bubble up reverts - they return success=false
        assertFalse(success, "Direct ETH transfer should fail");

        // Verify the revert reason matches PaymentNotAllowed
        assertEq(
            bytes4(returnData),
            Flyover.PaymentNotAllowed.selector,
            "Should revert with PaymentNotAllowed"
        );
    }
}
