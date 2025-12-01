// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {DiscoveryFuzzTestBase} from "./DiscoveryFuzzTestBase.sol";
import {IFlyoverDiscovery} from "../../../src/interfaces/IFlyoverDiscovery.sol";
import {Flyover} from "../../../src/libraries/Flyover.sol";

/// @title FlyoverDiscovery Status Fuzz Tests
/// @notice Fuzz tests for provider status management functionality
contract DiscoveryStatusFuzzTest is DiscoveryFuzzTestBase {
    address public stranger;

    function setUp() public {
        deployDiscovery();
        setupProviders();

        stranger = makeAddr("stranger");
        vm.deal(stranger, 100 ether);

        fuzzUser = makeAddr("fuzzUser");
        vm.deal(fuzzUser, 100 ether);
    }

    // ============ Authorization Tests ============

    /// @notice Fuzz test: Provider can toggle its own status
    function testFuzz_SetProviderStatus_ProviderCanToggleOwnStatus(
        bool newStatus
    ) public {
        // Provider 1 (pegInLp) toggles status
        vm.prank(pegInLp);
        vm.expectEmit(true, true, false, true);
        emit IFlyoverDiscovery.ProviderStatusSet(1, newStatus);
        discovery.setProviderStatus(1, newStatus);

        Flyover.LiquidityProvider memory provider = discovery.getProvider(pegInLp);
        assertEq(provider.status, newStatus, "Status should be updated");
    }

    /// @notice Fuzz test: Owner can toggle any provider's status
    function testFuzz_SetProviderStatus_OwnerCanToggleAnyStatus(
        uint256 providerId,
        bool newStatus
    ) public {
        providerId = bound(providerId, 1, 3);

        vm.prank(owner);
        vm.expectEmit(true, true, false, true);
        emit IFlyoverDiscovery.ProviderStatusSet(providerId, newStatus);
        discovery.setProviderStatus(providerId, newStatus);
    }

    /// @notice Fuzz test: Stranger cannot toggle provider status
    function testFuzz_SetProviderStatus_RevertsForStranger(
        uint256 providerId,
        bool newStatus
    ) public {
        providerId = bound(providerId, 1, 3);

        vm.prank(stranger);
        vm.expectRevert(
            abi.encodeWithSelector(
                IFlyoverDiscovery.NotAuthorized.selector,
                stranger
            )
        );
        discovery.setProviderStatus(providerId, newStatus);
    }

    /// @notice Fuzz test: Provider cannot toggle other provider's status
    function testFuzz_SetProviderStatus_ProviderCannotToggleOther(
        bool newStatus
    ) public {
        // pegInLp (provider 1) tries to toggle pegOutLp's status (provider 2)
        vm.prank(pegInLp);
        vm.expectRevert(
            abi.encodeWithSelector(
                IFlyoverDiscovery.NotAuthorized.selector,
                pegInLp
            )
        );
        discovery.setProviderStatus(2, newStatus);
    }

    // ============ Status Toggle Cycle Tests ============

    /// @notice Fuzz test: Multiple status toggles work correctly
    function testFuzz_SetProviderStatus_MultipleTogglesWorkCorrectly(
        uint8 toggleCount
    ) public {
        toggleCount = uint8(bound(toggleCount, 1, 20));
        bool currentStatus = true; // Initial status

        for (uint8 i = 0; i < toggleCount; i++) {
            bool newStatus = !currentStatus;

            vm.prank(pegInLp);
            discovery.setProviderStatus(1, newStatus);

            Flyover.LiquidityProvider memory provider = discovery.getProvider(pegInLp);
            assertEq(provider.status, newStatus, "Status should match after toggle");

            currentStatus = newStatus;
        }
    }

    /// @notice Fuzz test: Setting same status multiple times is idempotent
    function testFuzz_SetProviderStatus_IdempotentStatusSet(
        bool status,
        uint8 repeatCount
    ) public {
        repeatCount = uint8(bound(repeatCount, 1, 10));

        for (uint8 i = 0; i < repeatCount; i++) {
            vm.prank(pegInLp);
            discovery.setProviderStatus(1, status);

            Flyover.LiquidityProvider memory provider = discovery.getProvider(pegInLp);
            assertEq(provider.status, status, "Status should remain same");
        }
    }

    // ============ Listing Filter Tests ============

    /// @notice Fuzz test: Disabled providers are not listed
    function testFuzz_SetProviderStatus_DisabledProvidersNotListed(
        uint256 providerIdToDisable
    ) public {
        providerIdToDisable = bound(providerIdToDisable, 1, 3);

        // Get initial provider count
        Flyover.LiquidityProvider[] memory initialProviders = discovery.getProviders();
        uint256 initialCount = initialProviders.length;
        assertEq(initialCount, 3, "Should start with 3 providers");

        // Disable one provider
        address providerAddress;
        if (providerIdToDisable == 1) providerAddress = pegInLp;
        else if (providerIdToDisable == 2) providerAddress = pegOutLp;
        else providerAddress = fullLp;

        vm.prank(providerAddress);
        discovery.setProviderStatus(providerIdToDisable, false);

        // Check listing
        Flyover.LiquidityProvider[] memory providers = discovery.getProviders();
        assertEq(providers.length, 2, "Should have 2 providers after disabling one");

        // Verify the disabled provider is not in the list
        for (uint256 i = 0; i < providers.length; i++) {
            assertTrue(
                providers[i].id != providerIdToDisable,
                "Disabled provider should not be in list"
            );
        }
    }

    /// @notice Fuzz test: Re-enabled providers appear in listing
    function testFuzz_SetProviderStatus_ReenabledProvidersListed(
        uint256 providerIdToToggle
    ) public {
        providerIdToToggle = bound(providerIdToToggle, 1, 3);

        address providerAddress;
        if (providerIdToToggle == 1) providerAddress = pegInLp;
        else if (providerIdToToggle == 2) providerAddress = pegOutLp;
        else providerAddress = fullLp;

        // Disable
        vm.prank(providerAddress);
        discovery.setProviderStatus(providerIdToToggle, false);

        Flyover.LiquidityProvider[] memory afterDisable = discovery.getProviders();
        assertEq(afterDisable.length, 2, "Should have 2 providers after disable");

        // Re-enable
        vm.prank(providerAddress);
        discovery.setProviderStatus(providerIdToToggle, true);

        Flyover.LiquidityProvider[] memory afterEnable = discovery.getProviders();
        assertEq(afterEnable.length, 3, "Should have 3 providers after re-enable");
    }

    // ============ Event Emission Tests ============

    /// @notice Fuzz test: Status change emits correct event
    function testFuzz_SetProviderStatus_EmitsCorrectEvent(
        uint256 providerId,
        bool status
    ) public {
        providerId = bound(providerId, 1, 3);

        vm.prank(owner);
        vm.expectEmit(true, true, false, true);
        emit IFlyoverDiscovery.ProviderStatusSet(providerId, status);
        discovery.setProviderStatus(providerId, status);
    }

    // ============ Non-Existent Provider Tests ============

    /// @notice Fuzz test: Setting status on non-existent provider ID
    function testFuzz_SetProviderStatus_NonExistentProviderIdDoesNotRevert(
        uint256 nonExistentId,
        bool status
    ) public {
        // IDs 0 or > lastProviderId (3) don't correspond to registered providers
        vm.assume(nonExistentId == 0 || nonExistentId > 3);
        nonExistentId = bound(nonExistentId, 4, 1000);

        // Note: The contract doesn't explicitly check if providerId exists,
        // so this will succeed but the status change has no effect
        // since the provider address won't match any registered provider
        vm.prank(owner);
        // This should work because owner can set any providerId
        discovery.setProviderStatus(nonExistentId, status);
    }

}
