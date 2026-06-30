// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {CollateralTestBase} from "./CollateralTestBase.sol";

/// @title Registered-LP enumeration tests (E3.1)
/// @notice Asserts the registered-LP set reflects register/resign/withdrawal and that
/// the registration block is recorded.
contract RegistryTest is CollateralTestBase {
    function setUp() public {
        deployCollateralManagement();
        setupRoles();
    }

    function _addPegIn(address lp, uint256 amount) internal {
        vm.deal(lp, amount);
        vm.prank(adder);
        collateralManagement.addPegInCollateralTo{value: amount}(lp);
    }

    function test_Set_LpAppearsAfterRegistration() public {
        address lp = makeAddr("lpA");
        assertEq(collateralManagement.registeredLPCount(), 0, "set should start empty");
        assertFalse(collateralManagement.isRegisteredLP(lp), "lp not yet registered");

        _addPegIn(lp, BASE_COLLATERAL);

        assertTrue(collateralManagement.isRegisteredLP(lp), "lp should be in the set");
        assertEq(collateralManagement.registeredLPCount(), 1, "set size should be 1");
    }

    function test_Set_RegistrationBlockRecorded() public {
        address lp = makeAddr("lpBlock");
        vm.roll(12345);
        _addPegIn(lp, BASE_COLLATERAL);
        assertEq(
            collateralManagement.getRegistrationBlock(lp),
            12345,
            "registrationBlock should equal block at registration"
        );
    }

    function test_Set_TopUpDoesNotResetRegistrationBlock() public {
        address lp = makeAddr("lpTopUp");
        vm.roll(100);
        _addPegIn(lp, BASE_COLLATERAL);
        assertEq(collateralManagement.getRegistrationBlock(lp), 100);

        vm.roll(200);
        _addPegIn(lp, BASE_COLLATERAL);
        // Still the original registration block; count unchanged.
        assertEq(collateralManagement.getRegistrationBlock(lp), 100, "block must not reset on top-up");
        assertEq(collateralManagement.registeredLPCount(), 1, "no duplicate set entry");
    }

    function test_Set_LpRemovedAfterResign() public {
        address lp = makeAddr("lpResign");
        _addPegIn(lp, BASE_COLLATERAL);
        assertTrue(collateralManagement.isRegisteredLP(lp));

        vm.prank(lp);
        collateralManagement.resign();

        assertFalse(collateralManagement.isRegisteredLP(lp), "lp removed from set on resign");
        assertEq(collateralManagement.registeredLPCount(), 0, "set empty after resign");
        assertEq(collateralManagement.getRegistrationBlock(lp), 0, "registration block cleared");
    }

    function test_Set_LpRemovedAfterFullWithdrawal() public {
        address lp = makeAddr("lpWithdraw");
        _addPegIn(lp, BASE_COLLATERAL);

        vm.prank(lp);
        collateralManagement.resign();
        // Advance past the resign delay so withdrawal is allowed.
        vm.roll(block.number + TEST_RESIGN_DELAY_BLOCKS + 1);

        vm.prank(lp);
        collateralManagement.withdrawCollateral();

        assertFalse(collateralManagement.isRegisteredLP(lp), "lp removed after full withdrawal");
        assertEq(collateralManagement.registeredLPCount(), 0, "set empty after withdrawal");
        assertEq(collateralManagement.getPegInCollateral(lp), 0, "collateral drained");
    }

    function test_Set_MultipleLps() public {
        address a = makeAddr("multiA");
        address b = makeAddr("multiB");
        _addPegIn(a, BASE_COLLATERAL);
        _addPegIn(b, BASE_COLLATERAL);
        assertEq(collateralManagement.registeredLPCount(), 2, "two distinct LPs");

        vm.prank(a);
        collateralManagement.resign();
        assertEq(collateralManagement.registeredLPCount(), 1, "one LP after a resigns");
        assertTrue(collateralManagement.isRegisteredLP(b), "b still registered");
        assertFalse(collateralManagement.isRegisteredLP(a), "a removed");
    }
}
