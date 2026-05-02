// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {CollateralFuzzTestBase} from "./CollateralFuzzTestBase.sol";
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
}
