// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {DiscoveryFuzzTestBase} from "./DiscoveryFuzzTestBase.sol";
import {Flyover} from "../../../src/libraries/Flyover.sol";

/// @title FlyoverDiscovery Active Listing Fuzz Tests
/// @notice Fuzz tests for v2.1.0 active-provider indexing and listing behavior
contract DiscoveryActiveListingFuzzTest is DiscoveryFuzzTestBase {
    function setUp() public {
        deployDiscovery();
        setupProviders();
    }

    function _isListed(address provider) internal view returns (bool) {
        Flyover.LiquidityProvider[] memory providers = discovery.getProviders();
        for (uint256 i = 0; i < providers.length; ++i) {
            if (providers[i].providerAddress == provider) return true;
        }
        return false;
    }

    function _addressForProviderId(
        uint256 providerId
    ) internal view returns (address) {
        if (providerId == 1) return pegInLp;
        if (providerId == 2) return pegOutLp;
        return fullLp;
    }

    /// @notice Sybil pending cycles inflate lastProviderId but not getProviders()
    function testFuzz_GetProviders_IgnoresInflatedLastProviderId(
        uint8 sybilCount
    ) public {
        sybilCount = uint8(bound(sybilCount, 0, 20));

        for (uint8 i = 0; i < sybilCount; ++i) {
            address lp = makeAddr(string.concat("sybil", vm.toString(i)));
            vm.deal(lp, 100 ether);
            vm.prank(lp, lp);
            discovery.register{value: MIN_COLLATERAL}(
                "Pending",
                "url",
                true,
                Flyover.ProviderType.PegIn
            );
            vm.prank(lp);
            discovery.withdrawRegisterRequest();
        }

        address realLp = makeAddr("realLp");
        vm.deal(realLp, 100 ether);
        vm.prank(realLp, realLp);
        discovery.register{value: MIN_COLLATERAL}(
            "Real",
            "url",
            true,
            Flyover.ProviderType.PegIn
        );
        vm.prank(owner);
        discovery.approveRegistration(realLp);

        assertEq(discovery.getProvidersId(), 4 + uint256(sybilCount));
        assertEq(discovery.getProviders().length, 4);
        assertTrue(_isListed(realLp));
    }

    /// @notice Pending registrations never appear in getProviders()
    function testFuzz_GetProviders_ExcludesPendingRegistrations(
        uint8 providerTypeRaw,
        uint256 extraCollateral
    ) public {
        Flyover.ProviderType providerType = getValidProviderType(
            providerTypeRaw
        );
        extraCollateral = bound(extraCollateral, 0, 5 ether);
        uint256 collateral = getRequiredCollateral(providerType) +
            extraCollateral;

        address lp = makeAddr("pendingLp");
        vm.deal(lp, collateral + 1 ether);
        vm.prank(lp, lp);
        discovery.register{value: collateral}(
            "Pending",
            "url",
            true,
            providerType
        );

        assertFalse(_isListed(lp));
    }

    /// @notice Approved providers appear in listing iff status and collateral are sufficient
    function testFuzz_ApproveRegistration_AddsToListing(
        uint8 providerTypeRaw,
        bool initialStatus,
        uint256 extraCollateral
    ) public {
        Flyover.ProviderType providerType = getValidProviderType(
            providerTypeRaw
        );
        extraCollateral = bound(extraCollateral, 0, 5 ether);
        uint256 collateral = getRequiredCollateral(providerType) +
            extraCollateral;

        address lp = makeAddr("approvedLp");
        vm.deal(lp, collateral + 1 ether);
        vm.prank(lp, lp);
        discovery.register{value: collateral}(
            "Approved",
            "url",
            initialStatus,
            providerType
        );
        vm.prank(owner);
        discovery.approveRegistration(lp);

        bool sufficient = collateralManagement.isCollateralSufficient(
            providerType,
            lp
        );
        assertEq(_isListed(lp), initialStatus && sufficient);
    }

    /// @notice Every listed provider satisfies _shouldBeListed
    function testFuzz_GetProviders_EntriesSatisfyShouldBeListed(
        uint8 disableCount,
        uint256 newMinCollateral
    ) public {
        disableCount = uint8(bound(disableCount, 0, 3));
        newMinCollateral = bound(newMinCollateral, 1, 2 ether);

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

        vm.prank(owner);
        collateralManagement.setMinCollateral(newMinCollateral);

        Flyover.LiquidityProvider[] memory providers = discovery.getProviders();
        for (uint256 i = 0; i < providers.length; ++i) {
            assertTrue(providers[i].status);
            assertTrue(
                collateralManagement.isCollateralSufficient(
                    providers[i].providerType,
                    providers[i].providerAddress
                )
            );
        }
    }

    /// @notice getProviders never returns duplicate ids or addresses
    function testFuzz_GetProviders_NoDuplicateProviderIds(
        uint8 newProviders
    ) public {
        newProviders = uint8(bound(newProviders, 0, 10));

        for (uint8 i = 0; i < newProviders; ++i) {
            address provider = createFundedEOA(
                string(abi.encodePacked("dupCheck_", vm.toString(i)))
            );
            registerProvider(
                provider,
                string(abi.encodePacked("P_", vm.toString(i))),
                string(abi.encodePacked("url_", vm.toString(i))),
                true,
                Flyover.ProviderType.PegIn,
                MIN_COLLATERAL
            );
        }

        Flyover.LiquidityProvider[] memory providers = discovery.getProviders();
        for (uint256 i = 0; i < providers.length; ++i) {
            for (uint256 j = i + 1; j < providers.length; ++j) {
                assertTrue(providers[i].id != providers[j].id);
                assertTrue(
                    providers[i].providerAddress != providers[j].providerAddress
                );
            }
        }
    }

    /// @notice Full collateral withdrawal removes provider from listing
    function testFuzz_WithdrawCollateral_RemovesFromListing(
        uint256 providerId
    ) public {
        providerId = bound(providerId, 1, 3);
        address lp = _addressForProviderId(providerId);

        vm.prank(lp);
        collateralManagement.resign();
        vm.roll(block.number + TEST_RESIGN_DELAY_BLOCKS);
        vm.prank(lp);
        collateralManagement.withdrawCollateral();

        assertFalse(_isListed(lp));
    }

    /// @notice Re-register after withdraw restores listing
    function testFuzz_WithdrawAndReregister_RestoresListing(
        uint256 providerId
    ) public {
        providerId = bound(providerId, 1, 3);
        address lp = _addressForProviderId(providerId);

        vm.prank(lp);
        collateralManagement.resign();
        vm.roll(block.number + TEST_RESIGN_DELAY_BLOCKS);
        vm.prank(lp);
        collateralManagement.withdrawCollateral();
        assertFalse(_isListed(lp));

        registerProvider(
            lp,
            "ReRegistered",
            "url",
            true,
            Flyover.ProviderType.PegIn,
            MIN_COLLATERAL
        );
        assertTrue(_isListed(lp));
    }

    /// @notice Raising min collateral only filters listing, never adds providers
    function testFuzz_SetMinCollateral_FiltersListing(
        uint256 newMinCollateral
    ) public {
        uint256 initialListed = discovery.getProviders().length;
        newMinCollateral = bound(newMinCollateral, 1, 5 ether);

        vm.prank(owner);
        collateralManagement.setMinCollateral(newMinCollateral);

        Flyover.LiquidityProvider[] memory providers = discovery.getProviders();
        assertLe(providers.length, initialListed);

        for (uint256 i = 0; i < providers.length; ++i) {
            assertTrue(
                collateralManagement.isCollateralSufficient(
                    providers[i].providerType,
                    providers[i].providerAddress
                )
            );
        }
    }

    /// @notice Resign filters listing without changing lastProviderId
    function testFuzz_Resign_FiltersListingWithoutRemovingIndex(
        uint256 providerId
    ) public {
        providerId = bound(providerId, 1, 3);
        address lp = _addressForProviderId(providerId);
        uint256 lastIdBefore = discovery.getProvidersId();

        vm.prank(lp);
        collateralManagement.resign();

        assertFalse(_isListed(lp));
        assertEq(discovery.getProvidersId(), lastIdBefore);
    }
}
