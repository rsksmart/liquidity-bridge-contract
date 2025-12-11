// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {DiscoveryFuzzTestBase} from "./DiscoveryFuzzTestBase.sol";
import {IFlyoverDiscovery} from "../../../src/interfaces/IFlyoverDiscovery.sol";
import {Flyover} from "../../../src/libraries/Flyover.sol";

/// @title FlyoverDiscovery Registration Fuzz Tests
/// @notice Fuzz tests for provider registration functionality
contract DiscoveryRegistrationFuzzTest is DiscoveryFuzzTestBase {
    function setUp() public {
        deployDiscovery();
        fuzzUser = makeAddr("fuzzUser");
        vm.deal(fuzzUser, 1000 ether);
    }

    /// @notice Fuzz test: Insufficient collateral for Both reverts
    function testFuzz_Register_RevertsOnInsufficientCollateralBoth(
        uint256 collateral
    ) public {
        collateral = bound(collateral, 0, MIN_COLLATERAL * 2 - 1);

        vm.prank(fuzzUser);
        vm.expectRevert(
            abi.encodeWithSelector(
                IFlyoverDiscovery.InsufficientCollateral.selector,
                collateral
            )
        );
        discovery.register{value: collateral}(
            "Name",
            "url",
            true,
            Flyover.ProviderType.Both
        );
    }

    /// @notice Fuzz test: Exact minimum collateral succeeds
    function testFuzz_Register_SucceedsWithExactMinimumCollateral(
        uint8 providerTypeRaw
    ) public {
        Flyover.ProviderType providerType = getValidProviderType(
            providerTypeRaw
        );
        uint256 requiredCollateral = getRequiredCollateral(providerType);

        vm.prank(fuzzUser);
        uint256 providerId = discovery.register{value: requiredCollateral}(
            "Name",
            "url",
            true,
            providerType
        );

        assertEq(providerId, 1, "Should register successfully");
    }

    /// @notice Fuzz test: PegIn registration adds collateral only to PegIn
    function testFuzz_Register_PegInCollateralDistribution(
        uint256 extraCollateral
    ) public {
        extraCollateral = bound(extraCollateral, 0, 5 ether);
        uint256 collateral = MIN_COLLATERAL + extraCollateral;

        vm.prank(fuzzUser);
        discovery.register{value: collateral}(
            "Name",
            "url",
            true,
            Flyover.ProviderType.PegIn
        );

        assertEq(
            collateralManagement.getPegInCollateral(fuzzUser),
            collateral,
            "PegIn collateral should match"
        );
        assertEq(
            collateralManagement.getPegOutCollateral(fuzzUser),
            0,
            "PegOut collateral should be 0"
        );
    }

    /// @notice Fuzz test: PegOut registration adds collateral only to PegOut
    function testFuzz_Register_PegOutCollateralDistribution(
        uint256 extraCollateral
    ) public {
        extraCollateral = bound(extraCollateral, 0, 5 ether);
        uint256 collateral = MIN_COLLATERAL + extraCollateral;

        vm.prank(fuzzUser);
        discovery.register{value: collateral}(
            "Name",
            "url",
            true,
            Flyover.ProviderType.PegOut
        );

        assertEq(
            collateralManagement.getPegInCollateral(fuzzUser),
            0,
            "PegIn collateral should be 0"
        );
        assertEq(
            collateralManagement.getPegOutCollateral(fuzzUser),
            collateral,
            "PegOut collateral should match"
        );
    }

    /// @notice Fuzz test: Both registration splits collateral correctly
    function testFuzz_Register_BothCollateralDistribution(
        uint256 extraCollateral
    ) public {
        extraCollateral = bound(extraCollateral, 0, 5 ether);
        uint256 collateral = MIN_COLLATERAL * 2 + extraCollateral;

        vm.prank(fuzzUser);
        discovery.register{value: collateral}(
            "Name",
            "url",
            true,
            Flyover.ProviderType.Both
        );

        uint256 halfAmount = collateral / 2;
        uint256 remainder = collateral % 2;

        assertEq(
            collateralManagement.getPegInCollateral(fuzzUser),
            halfAmount + remainder,
            "PegIn collateral should be half + remainder"
        );
        assertEq(
            collateralManagement.getPegOutCollateral(fuzzUser),
            halfAmount,
            "PegOut collateral should be half"
        );
    }
}
