// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {DiscoveryTestBase} from "./DiscoveryTestBase.sol";
import {Flyover} from "../../src/libraries/Flyover.sol";

contract ListingFilterTest is DiscoveryTestBase {
    function setUp() public {
        deployDiscovery();
    }

    // ============ Listing filters tests ============

    function test_GetProviders_ListsOnlyEnabledProvidersAfterDeactivationWindow()
        public
    {
        setupProviders();

        // Initially all 3 providers should be listed
        Flyover.LiquidityProvider[] memory providers = discovery.getProviders();
        assertEq(providers.length, 3, "Should have 3 providers");
        assertEq(providers[0].id, 1, "Provider 1 ID");
        assertEq(providers[1].id, 2, "Provider 2 ID");
        assertEq(providers[2].id, 3, "Provider 3 ID");

        // Disable provider with id 2
        vm.prank(pegOutLp);
        discovery.setProviderStatus(2, false);

        // Still listed (status false) while inside the deactivation window
        providers = discovery.getProviders();
        assertEq(providers.length, 3, "Disabled LP listed inside window");
        assertFalse(
            providers[1].status,
            "Listed LP 2 must report status false"
        );

        // Now only 2 providers should be listed
        vm.roll(block.number + TEST_RESIGN_DELAY_BLOCKS);
        providers = discovery.getProviders();
        assertEq(providers.length, 2, "Should have 2 enabled providers");
        assertEq(providers[0].id, 1, "Provider 1 ID");
        assertEq(providers[1].id, 3, "Provider 3 ID");
    }

    /// @notice A deactivated LP stays listed until `deactivationBlock + resignDelay`, exclusive
    function test_GetProviders_DeactivatedListedUntilWindowEnds() public {
        setupProviders();
        vm.prank(pegOutLp);
        discovery.setProviderStatus(2, false);
        uint256 deactivatedAt = block.number;

        vm.roll(deactivatedAt + TEST_RESIGN_DELAY_BLOCKS - 1);
        assertEq(discovery.getProviders().length, 3, "Listed at window - 1");

        vm.roll(deactivatedAt + TEST_RESIGN_DELAY_BLOCKS);
        assertEq(discovery.getProviders().length, 2, "Dropped at window");
    }

    /// @notice Re-enabling clears the clock; a later deactivation starts a new window
    function test_GetProviders_ReenableClearsDeactivationClock() public {
        setupProviders();
        vm.prank(pegOutLp);
        discovery.setProviderStatus(2, false);
        vm.roll(block.number + TEST_RESIGN_DELAY_BLOCKS);
        assertEq(discovery.getProviders().length, 2);

        vm.prank(pegOutLp);
        discovery.setProviderStatus(2, true);
        assertEq(discovery.getProviders().length, 3);

        vm.roll(block.number + 10);
        vm.prank(pegOutLp);
        discovery.setProviderStatus(2, false);
        vm.roll(block.number + TEST_RESIGN_DELAY_BLOCKS - 1);
        assertEq(
            discovery.getProviders().length,
            3,
            "New window from second deactivation"
        );
    }

    /// @notice Repeating status=false does not refresh the deactivation clock
    function test_GetProviders_RepeatedDeactivationDoesNotRefreshClock()
        public
    {
        setupProviders();
        vm.prank(pegOutLp);
        discovery.setProviderStatus(2, false);
        uint256 deactivatedAt = block.number;

        vm.roll(deactivatedAt + TEST_RESIGN_DELAY_BLOCKS - 1);
        vm.prank(pegOutLp);
        discovery.setProviderStatus(2, false);

        vm.roll(deactivatedAt + TEST_RESIGN_DELAY_BLOCKS);
        assertEq(discovery.getProviders().length, 2);
    }

    /// @notice An LP registered with status=false has no deactivation block and is not listed
    function test_GetProviders_RegisteredInactiveIsNotListed() public {
        address lp = makeAddr("inactiveLp");
        vm.deal(lp, 10 ether);
        vm.prank(lp, lp);
        discovery.register{value: MIN_COLLATERAL}(
            "Inactive",
            "lp.com",
            false,
            Flyover.ProviderType.PegOut
        );
        vm.prank(owner);
        discovery.approveRegistration(lp);
        assertEq(discovery.getProviders().length, 0);
    }

    /// @notice Admin deactivation starts the same clock as self-deactivation
    function test_GetProviders_AdminDeactivationStartsClock() public {
        setupProviders();
        vm.prank(owner);
        discovery.setProviderStatus(2, false);
        assertEq(discovery.getProviders().length, 3);
        vm.roll(block.number + TEST_RESIGN_DELAY_BLOCKS);
        assertEq(discovery.getProviders().length, 2);
    }

    /// @notice getProviders lists only LPs whose collateral meets the current minimum (not only > 0)
    function test_GetProviders_ExcludesProvidersWhenCollateralBelowMinimum()
        public
    {
        setupProviders();
        assertEq(discovery.getProviders().length, 3);

        vm.prank(owner);
        collateralManagement.setMinCollateral(1 ether);

        assertTrue(
            collateralManagement.isRegistered(
                Flyover.ProviderType.PegIn,
                pegInLp
            ),
            "peg-in LP should still be registered with non-zero collateral"
        );
        assertFalse(
            collateralManagement.isCollateralSufficient(
                Flyover.ProviderType.PegIn,
                pegInLp
            ),
            "peg-in LP collateral is below the new minimum"
        );

        Flyover.LiquidityProvider[] memory providers = discovery.getProviders();
        assertEq(
            providers.length,
            0,
            "No provider meets the raised minimum while staying listed"
        );
    }

    // ============ Listing edge cases tests ============

    function test_GetProviders_ListsProvidersImmediatelyAfterRegistration()
        public
    {
        address lp = makeAddr("newLp");
        vm.deal(lp, 100 ether);

        vm.prank(lp, lp);
        discovery.register{value: MIN_COLLATERAL}(
            "N",
            "U",
            true,
            Flyover.ProviderType.PegIn
        );

        vm.prank(owner);
        discovery.approveRegistration(lp);

        Flyover.LiquidityProvider[] memory providers = discovery.getProviders();
        assertEq(providers.length, 1, "Should have 1 provider");
        assertEq(
            providers[0].providerAddress,
            lp,
            "Provider address should match"
        );
    }

    function test_GetProviders_ReturnsProvidersOrderedById() public {
        address a = makeAddr("lpA");
        address b = makeAddr("lpB");
        address c = makeAddr("lpC");

        vm.deal(a, 100 ether);
        vm.deal(b, 100 ether);
        vm.deal(c, 100 ether);

        vm.prank(a, a);
        discovery.register{value: MIN_COLLATERAL}(
            "A",
            "U1",
            true,
            Flyover.ProviderType.PegIn
        );
        vm.prank(owner);
        discovery.approveRegistration(a);

        vm.prank(b, b);
        discovery.register{value: MIN_COLLATERAL}(
            "B",
            "U2",
            true,
            Flyover.ProviderType.PegIn
        );
        vm.prank(owner);
        discovery.approveRegistration(b);

        vm.prank(c, c);
        discovery.register{value: MIN_COLLATERAL}(
            "C",
            "U3",
            true,
            Flyover.ProviderType.PegIn
        );
        vm.prank(owner);
        discovery.approveRegistration(c);

        Flyover.LiquidityProvider[] memory providers = discovery.getProviders();
        assertEq(providers.length, 3, "Should have 3 providers");
        assertEq(providers[0].id, 1, "Provider 1 ID");
        assertEq(providers[1].id, 2, "Provider 2 ID");
        assertEq(providers[2].id, 3, "Provider 3 ID");
    }
}
