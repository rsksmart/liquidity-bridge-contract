// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {DiscoveryFuzzTestBase} from "./DiscoveryFuzzTestBase.sol";
import {IFlyoverDiscovery} from "../../../src/interfaces/IFlyoverDiscovery.sol";
import {ICollateralManagement} from "../../../src/interfaces/ICollateralManagement.sol";
import {Flyover} from "../../../src/libraries/Flyover.sol";

/// @title FlyoverDiscovery Operational Fuzz Tests
/// @notice Fuzz tests for isOperational, getProviders, and getProvider functionality
contract DiscoveryOperationalFuzzTest is DiscoveryFuzzTestBase {
    function setUp() public {
        deployDiscovery();
        setupProviders();

        fuzzUser = makeAddr("fuzzUser");
        vm.deal(fuzzUser, 100 ether);
    }

    // ============ isOperational Tests ============

    /// @notice Fuzz test: Registered provider with sufficient collateral is operational
    function testFuzz_IsOperational_ReturnsTrueForValidProvider(uint8 providerTypeRaw) public view {
        Flyover.ProviderType providerType = getValidProviderType(providerTypeRaw);

        // fullLp is registered with Both type, so it's operational for any type
        bool isOp = discovery.isOperational(providerType, fullLp);

        if (providerType == Flyover.ProviderType.PegIn || providerType == Flyover.ProviderType.Both) {
            assertTrue(isOp, "fullLp should be operational for PegIn/Both");
        } else {
            // PegOut only - fullLp has both collaterals
            assertTrue(isOp, "fullLp should be operational for PegOut too");
        }
    }

    /// @notice Fuzz test: Provider with specific type is operational only for that type
    function testFuzz_IsOperational_SpecificTypeRestrictions() public view {
        // pegInLp should be operational for PegIn but not PegOut
        assertTrue(
            discovery.isOperational(Flyover.ProviderType.PegIn, pegInLp),
            "pegInLp should be operational for PegIn"
        );
        assertFalse(
            discovery.isOperational(Flyover.ProviderType.PegOut, pegInLp),
            "pegInLp should NOT be operational for PegOut"
        );

        // pegOutLp should be operational for PegOut but not PegIn
        assertTrue(
            discovery.isOperational(Flyover.ProviderType.PegOut, pegOutLp),
            "pegOutLp should be operational for PegOut"
        );
        assertFalse(
            discovery.isOperational(Flyover.ProviderType.PegIn, pegOutLp),
            "pegOutLp should NOT be operational for PegIn"
        );
    }

    /// @notice Fuzz test: Disabled provider is not operational
    function testFuzz_IsOperational_ReturnsFalseWhenDisabled(uint8 providerTypeRaw) public {
        Flyover.ProviderType providerType = getValidProviderType(providerTypeRaw);

        // Disable fullLp
        vm.prank(fullLp);
        discovery.setProviderStatus(3, false);

        bool isOp = discovery.isOperational(providerType, fullLp);
        assertFalse(isOp, "Disabled provider should not be operational");
    }

    /// @notice Fuzz test: Unregistered address is not operational
    function testFuzz_IsOperational_ReturnsFalseForUnregistered(
        address unregistered,
        uint8 providerTypeRaw
    ) public {
        vm.assume(unregistered != pegInLp && unregistered != pegOutLp && unregistered != fullLp);
        vm.assume(unregistered != address(0));
        Flyover.ProviderType providerType = getValidProviderType(providerTypeRaw);

        // This should revert because the provider is not registered
        vm.expectRevert(
            abi.encodeWithSelector(
                Flyover.ProviderNotRegistered.selector,
                unregistered
            )
        );
        discovery.isOperational(providerType, unregistered);
    }

    /// @notice Fuzz test: Re-enabled provider becomes operational again
    function testFuzz_IsOperational_BecomesOperationalAfterReenable(uint8 providerTypeRaw) public {
        Flyover.ProviderType providerType = getValidProviderType(providerTypeRaw);

        // Disable fullLp
        vm.prank(fullLp);
        discovery.setProviderStatus(3, false);
        assertFalse(discovery.isOperational(providerType, fullLp), "Should not be operational when disabled");

        // Re-enable
        vm.prank(fullLp);
        discovery.setProviderStatus(3, true);
        assertTrue(discovery.isOperational(providerType, fullLp), "Should be operational after re-enable");
    }

    // ============ getProvider Tests ============

    /// @notice Fuzz test: getProvider returns correct provider data
    function testFuzz_GetProvider_ReturnsCorrectData() public view {
        Flyover.LiquidityProvider memory provider = discovery.getProvider(pegInLp);

        assertEq(provider.id, 1, "ID should be 1");
        assertEq(provider.providerAddress, pegInLp, "Address should match");
        assertEq(provider.name, "Pegin Provider", "Name should match");
        assertEq(provider.apiBaseUrl, "lp1.com", "URL should match");
        assertTrue(provider.status, "Status should be true");
        assertEq(uint256(provider.providerType), uint256(Flyover.ProviderType.PegIn), "Type should be PegIn");
    }

    /// @notice Fuzz test: getProvider reverts for unregistered address
    function testFuzz_GetProvider_RevertsForUnregistered(address unregistered) public {
        vm.assume(unregistered != pegInLp && unregistered != pegOutLp && unregistered != fullLp);
        vm.assume(unregistered != address(0));

        vm.expectRevert(
            abi.encodeWithSelector(
                Flyover.ProviderNotRegistered.selector,
                unregistered
            )
        );
        discovery.getProvider(unregistered);
    }

    // ============ getProviders Tests ============

    /// @notice Fuzz test: getProviders returns all enabled providers
    function testFuzz_GetProviders_ReturnsAllEnabled() public view {
        Flyover.LiquidityProvider[] memory providers = discovery.getProviders();

        assertEq(providers.length, 3, "Should have 3 providers");

        // Check all providers are present
        bool foundPegIn = false;
        bool foundPegOut = false;
        bool foundFull = false;

        for (uint256 i = 0; i < providers.length; i++) {
            if (providers[i].providerAddress == pegInLp) foundPegIn = true;
            if (providers[i].providerAddress == pegOutLp) foundPegOut = true;
            if (providers[i].providerAddress == fullLp) foundFull = true;
        }

        assertTrue(foundPegIn, "pegInLp should be in list");
        assertTrue(foundPegOut, "pegOutLp should be in list");
        assertTrue(foundFull, "fullLp should be in list");
    }

    /// @notice Fuzz test: getProviders excludes disabled providers
    function testFuzz_GetProviders_ExcludesDisabled(uint8 disableCount) public {
        disableCount = uint8(bound(disableCount, 0, 3));

        // Disable specified number of providers
        if (disableCount >= 1) {
            vm.prank(pegInLp);
            discovery.setProviderStatus(1, false);
        }
        if (disableCount >= 2) {
            vm.prank(pegOutLp);
            discovery.setProviderStatus(2, false);
        }
        if (disableCount >= 3) {
            vm.prank(fullLp);
            discovery.setProviderStatus(3, false);
        }

        Flyover.LiquidityProvider[] memory providers = discovery.getProviders();
        assertEq(providers.length, 3 - disableCount, "Provider count should decrease");
    }

    /// @notice Fuzz test: getProviders returns empty for no providers
    function testFuzz_GetProviders_ReturnsEmptyWhenAllDisabled() public {
        // Disable all providers
        vm.prank(pegInLp);
        discovery.setProviderStatus(1, false);

        vm.prank(pegOutLp);
        discovery.setProviderStatus(2, false);

        vm.prank(fullLp);
        discovery.setProviderStatus(3, false);

        Flyover.LiquidityProvider[] memory providers = discovery.getProviders();
        assertEq(providers.length, 0, "Should have 0 providers");
    }

    // ============ getProvidersId Tests ============

    /// @notice Fuzz test: getProvidersId returns correct count after registrations
    function testFuzz_GetProvidersId_ReturnsCorrectCount(uint8 newProviders) public {
        newProviders = uint8(bound(newProviders, 0, 10));

        // Already have 3 providers from setupProviders()
        uint256 initialCount = discovery.getProvidersId();
        assertEq(initialCount, 3, "Should start with 3 providers");

        // Register new providers
        for (uint8 i = 0; i < newProviders; i++) {
            address provider = createFundedEOA(string(abi.encodePacked("newProvider_", i)));

            vm.prank(provider);
            discovery.register{value: MIN_COLLATERAL}(
                string(abi.encodePacked("Provider_", i)),
                string(abi.encodePacked("url_", i)),
                true,
                Flyover.ProviderType.PegIn
            );
        }

        assertEq(
            discovery.getProvidersId(),
            3 + newProviders,
            "Provider ID should increment correctly"
        );
    }

    // ============ Resigned Provider Tests ============

    /// @notice Fuzz test: Resigned provider is not listed
    function testFuzz_GetProviders_ExcludesResigned() public {
        // Resign a provider
        vm.prank(pegInLp);
        collateralManagement.resign();

        // Provider should no longer be listed because collateral is "resigned"
        Flyover.LiquidityProvider[] memory providers = discovery.getProviders();
        assertEq(providers.length, 2, "Should have 2 providers after resign");

        for (uint256 i = 0; i < providers.length; i++) {
            assertTrue(
                providers[i].providerAddress != pegInLp,
                "Resigned provider should not be in list"
            );
        }
    }

    /// @notice Fuzz test: Resigned provider is not operational
    function testFuzz_IsOperational_ReturnsFalseForResigned() public {
        // Resign a provider
        vm.prank(pegInLp);
        collateralManagement.resign();

        // Provider should not be operational
        assertFalse(
            discovery.isOperational(Flyover.ProviderType.PegIn, pegInLp),
            "Resigned provider should not be operational"
        );
    }

    // ============ Provider Order Tests ============

    /// @notice Fuzz test: Providers are returned in registration order
    function testFuzz_GetProviders_ReturnsInOrder() public view {
        Flyover.LiquidityProvider[] memory providers = discovery.getProviders();

        // Should be in ID order
        assertEq(providers[0].id, 1, "First should be ID 1");
        assertEq(providers[1].id, 2, "Second should be ID 2");
        assertEq(providers[2].id, 3, "Third should be ID 3");
    }
}
