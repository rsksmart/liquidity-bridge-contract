// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {DiscoveryTestBase} from "./DiscoveryTestBase.sol";
import {Flyover} from "../../contracts/libraries/Flyover.sol";

contract GettersTest is DiscoveryTestBase {
    function setUp() public {
        deployDiscovery();
        setupProviders();
    }

    // ============ getProviders function tests ============

    function test_GetProviders_ListsRegisteredProvidersWithCorrectFields() public view {
        Flyover.LiquidityProvider[] memory providers = discovery.getProviders();

        // Check we have 3 providers
        assertEq(providers.length, 3, "Should have 3 providers");

        // Check first provider (pegInLp)
        assertEq(providers[0].id, 1, "Provider 1 ID should be 1");
        assertEq(providers[0].providerAddress, pegInLp, "Provider 1 address should match");
        assertEq(providers[0].name, "Pegin Provider", "Provider 1 name should match");
        assertEq(providers[0].apiBaseUrl, "lp1.com", "Provider 1 API URL should match");
        assertTrue(providers[0].status, "Provider 1 status should be true");
        assertEq(uint256(providers[0].providerType), uint256(Flyover.ProviderType.PegIn), "Provider 1 type should be PegIn");

        // Check second provider (pegOutLp)
        assertEq(providers[1].id, 2, "Provider 2 ID should be 2");
        assertEq(providers[1].providerAddress, pegOutLp, "Provider 2 address should match");
        assertEq(providers[1].name, "PegOut Provider", "Provider 2 name should match");
        assertEq(providers[1].apiBaseUrl, "lp2.com", "Provider 2 API URL should match");
        assertTrue(providers[1].status, "Provider 2 status should be true");
        assertEq(uint256(providers[1].providerType), uint256(Flyover.ProviderType.PegOut), "Provider 2 type should be PegOut");

        // Check third provider (fullLp)
        assertEq(providers[2].id, 3, "Provider 3 ID should be 3");
        assertEq(providers[2].providerAddress, fullLp, "Provider 3 address should match");
        assertEq(providers[2].name, "Full Provider", "Provider 3 name should match");
        assertEq(providers[2].apiBaseUrl, "lp3.com", "Provider 3 API URL should match");
        assertTrue(providers[2].status, "Provider 3 status should be true");
        assertEq(uint256(providers[2].providerType), uint256(Flyover.ProviderType.Both), "Provider 3 type should be Both");
    }

    // ============ getProvider function tests ============

    function test_GetProvider_GetsProviderByAddress() public view {
        Flyover.LiquidityProvider memory provider = discovery.getProvider(pegOutLp);

        assertEq(provider.id, 2, "Provider ID should be 2");
        assertEq(provider.providerAddress, pegOutLp, "Provider address should match");
        assertEq(provider.name, "PegOut Provider", "Provider name should match");
        assertEq(provider.apiBaseUrl, "lp2.com", "Provider API URL should match");
        assertTrue(provider.status, "Provider status should be true");
        assertEq(uint256(provider.providerType), uint256(Flyover.ProviderType.PegOut), "Provider type should be PegOut");
    }

    function test_GetProvider_RevertsWhenGettingNonExistingProvider() public {
        address nonLp = makeAddr("nonLp");

        vm.expectRevert(
            abi.encodeWithSelector(Flyover.ProviderNotRegistered.selector, nonLp)
        );
        discovery.getProvider(nonLp);
    }
}
