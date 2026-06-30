// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {CollateralTestBase} from "./CollateralTestBase.sol";
import {CollateralManagementContract} from "../../src/CollateralManagement.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";

/// @title Grace window config and bootstrap safety tests (E3.3)
contract GraceTest is CollateralTestBase {
    uint256 constant GRACE = 100; // DEFAULT_GRACE_WINDOW

    function setUp() public {
        deployCollateralManagement();
        setupRoles();
    }

    function _addPegIn(address lp, uint256 amount) internal {
        vm.deal(lp, amount);
        vm.prank(adder);
        collateralManagement.addPegInCollateralTo{value: amount}(lp);
    }

    function test_Config_DefaultGraceWindow() public view {
        assertEq(collateralManagement.getGraceWindow(), GRACE, "default grace window is 100 blocks");
    }

    function test_Config_SetGraceWindow() public {
        vm.prank(owner);
        collateralManagement.setGraceWindow(250);
        assertEq(collateralManagement.getGraceWindow(), 250, "grace window updated");
    }

    function test_Config_SetGraceWindowOnlyAdmin() public {
        address stranger = makeAddr("stranger");
        bytes32 adminRole = collateralManagement.DEFAULT_ADMIN_ROLE();
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                stranger,
                adminRole
            )
        );
        vm.prank(stranger);
        collateralManagement.setGraceWindow(250);
    }

    /// @notice Boundary: an LP at exactly registrationBlock + graceWindow is still in grace
    /// (skipped), and one block later it becomes eligible.
    function test_Grace_BoundaryAtRegistrationBlockPlusGraceWindow() public {
        address lp = makeAddr("boundaryLp");
        vm.roll(1000);
        _addPegIn(lp, 1 ether);
        uint256 regBlock = collateralManagement.getRegistrationBlock(lp);

        // At exactly regBlock + GRACE: still in grace -> no eligible collateral -> revert.
        vm.roll(regBlock + GRACE);
        vm.prank(slasher);
        vm.expectRevert(CollateralManagementContract.NoEligibleCollateral.selector);
        collateralManagement.globalSlash(0.01 ether);
        assertEq(collateralManagement.getPegInCollateral(lp), 1 ether, "not slashed at boundary block");

        // One block later: eligible, gets slashed.
        vm.roll(regBlock + GRACE + 1);
        uint256 total = 0.01 ether;
        vm.prank(slasher);
        collateralManagement.globalSlash(total);
        assertEq(
            collateralManagement.getPegInCollateral(lp),
            1 ether - total,
            "slashed one block past the boundary"
        );
    }

    /// @notice Few-LP bootstrap case: one offline (eligible, past grace) LP and one freshly
    /// registered (in-grace) LP. The fresh LP must not be slashed.
    function test_Grace_BootstrapFreshLpNotSlashed() public {
        // Offline LP, registered long ago (past grace).
        address offline = makeAddr("offlineLp");
        vm.roll(500);
        _addPegIn(offline, 5 ether);
        vm.roll(500 + GRACE + 1);

        // Freshly registered LP (the only non-failing one), inside its grace window.
        address fresh = makeAddr("bootstrapFresh");
        _addPegIn(fresh, 5 ether);

        uint256 freshBefore = collateralManagement.getPegInCollateral(fresh);
        uint256 offlineBefore = collateralManagement.getPegInCollateral(offline);

        uint256 total = 0.03 ether;
        vm.prank(slasher);
        collateralManagement.globalSlash(total);

        assertEq(
            collateralManagement.getPegInCollateral(fresh),
            freshBefore,
            "fresh in-grace LP must not be slashed during bootstrap"
        );
        // The offline LP absorbs the whole total (only eligible LP).
        assertEq(
            offlineBefore - collateralManagement.getPegInCollateral(offline),
            total,
            "offline eligible LP absorbs the total"
        );
    }
}
