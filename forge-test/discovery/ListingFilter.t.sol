// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {DiscoveryTestBase} from "./DiscoveryTestBase.sol";
import {Flyover} from "../../contracts/libraries/Flyover.sol";

contract ListingFilterTest is DiscoveryTestBase {
    function setUp() public {
        deployDiscovery();
    }

    // ============ Listing filters tests ============

    function test_GetProviders_ListsOnlyEnabledProviders() public {
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

        // Now only 2 providers should be listed
        providers = discovery.getProviders();
        assertEq(providers.length, 2, "Should have 2 enabled providers");
        assertEq(providers[0].id, 1, "Provider 1 ID");
        assertEq(providers[1].id, 3, "Provider 3 ID");
    }

    // ============ Listing edge cases tests ============

    function test_GetProviders_ListsProvidersImmediatelyAfterRegistration() public {
        address lp = makeAddr("newLp");
        vm.deal(lp, 100 ether);

        vm.prank(lp);
        discovery.register{value: MIN_COLLATERAL}("N", "U", true, Flyover.ProviderType.PegIn);

        // Provider is immediately listed because collateral is added automatically during registration
        Flyover.LiquidityProvider[] memory providers = discovery.getProviders();
        assertEq(providers.length, 1, "Should have 1 provider");
        assertEq(providers[0].providerAddress, lp, "Provider address should match");
    }

    function test_GetProviders_ReturnsProvidersOrderedById() public {
        address a = makeAddr("lpA");
        address b = makeAddr("lpB");
        address c = makeAddr("lpC");

        vm.deal(a, 100 ether);
        vm.deal(b, 100 ether);
        vm.deal(c, 100 ether);

        vm.prank(a);
        discovery.register{value: MIN_COLLATERAL}("A", "U1", true, Flyover.ProviderType.PegIn);

        vm.prank(b);
        discovery.register{value: MIN_COLLATERAL}("B", "U2", true, Flyover.ProviderType.PegIn);

        vm.prank(c);
        discovery.register{value: MIN_COLLATERAL}("C", "U3", true, Flyover.ProviderType.PegIn);

        Flyover.LiquidityProvider[] memory providers = discovery.getProviders();
        assertEq(providers.length, 3, "Should have 3 providers");
        assertEq(providers[0].id, 1, "Provider 1 ID");
        assertEq(providers[1].id, 2, "Provider 2 ID");
        assertEq(providers[2].id, 3, "Provider 3 ID");
    }
}
