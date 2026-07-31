// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {console} from "forge-std/Test.sol";
import {DiscoveryTestBase} from "../discovery/DiscoveryTestBase.sol";
import {DiscoveryHandler} from "./handlers/DiscoveryHandler.sol";
import {Flyover} from "../../src/libraries/Flyover.sol";

/// @title FlyoverDiscovery Invariant Tests
/// @notice Tests critical invariants for the FlyoverDiscovery contract
contract DiscoveryInvariantTest is DiscoveryTestBase {
    DiscoveryHandler public handler;

    function setUp() public {
        deployDiscovery();

        handler = new DiscoveryHandler(discovery, collateralManagement, owner);

        targetContract(address(handler));

        bytes4[] memory selectors = new bytes4[](6);
        selectors[0] = handler.registerProvider.selector;
        selectors[1] = handler.pendingRegisterWithdraw.selector;
        selectors[2] = handler.toggleStatus.selector;
        selectors[3] = handler.resignProvider.selector;
        selectors[4] = handler.withdrawProvider.selector;
        selectors[5] = handler.updateProviderInfo.selector;
        targetSelector(
            FuzzSelector({addr: address(handler), selectors: selectors})
        );
    }

    // ============ Invariant Tests ============

    /// @notice Discovery contract should never hold RBTC — all forwarded to CollateralManagement
    function invariant_DiscoveryHoldsNoRBTC() public view {
        assertEq(
            address(discovery).balance,
            0,
            "INVARIANT VIOLATED: Discovery holds RBTC"
        );
    }

    /// @notice Provider ID counter should match the last id issued by handlers
    function invariant_ProviderIdMonotonic() public view {
        if (handler.ghost_lastProviderId() == 0) return;

        assertEq(
            discovery.getProvidersId(),
            handler.ghost_lastProviderId(),
            "INVARIANT VIOLATED: Provider ID counter mismatch"
        );
    }

    /// @notice Every provider returned by getProviders() must be operational
    function invariant_ListedProvidersAreOperational() public view {
        Flyover.LiquidityProvider[] memory listed = discovery.getProviders();

        for (uint256 i = 0; i < listed.length; i++) {
            assertTrue(
                listed[i].status,
                "INVARIANT VIOLATED: Listed provider has status false"
            );

            assertTrue(
                collateralManagement.isCollateralSufficient(
                    listed[i].providerType,
                    listed[i].providerAddress
                ),
                "INVARIANT VIOLATED: Listed provider collateral insufficient"
            );
        }
    }

    /// @notice Approved operational providers must appear in getProviders()
    function invariant_ApprovedOperationalProvidersAreListed() public view {
        uint256 count = handler.getRegisteredCount();
        for (uint256 i = 0; i < count; i++) {
            (
                address addr,
                ,
                Flyover.ProviderType providerType,
                bool statusSet,
                bool withdrawn
            ) = handler.getProviderInfo(i);

            if (
                !withdrawn &&
                statusSet &&
                collateralManagement.isCollateralSufficient(providerType, addr)
            ) {
                assertTrue(
                    _isListed(addr),
                    "INVARIANT VIOLATED: Operational provider missing from listing"
                );
            }
        }
    }

    /// @notice getProviders() returns unique provider ids and addresses
    function invariant_NoDuplicateListing() public view {
        Flyover.LiquidityProvider[] memory listed = discovery.getProviders();

        for (uint256 i = 0; i < listed.length; i++) {
            for (uint256 j = i + 1; j < listed.length; j++) {
                assertTrue(
                    listed[i].id != listed[j].id,
                    "INVARIANT VIOLATED: Duplicate provider id in listing"
                );
                assertTrue(
                    listed[i].providerAddress != listed[j].providerAddress,
                    "INVARIANT VIOLATED: Duplicate provider address in listing"
                );
            }
        }
    }

    /// @notice Listing size is bounded by approved minus withdrawn providers
    function invariant_ListingIndependentOfLastProviderId() public view {
        uint256 approved = handler.ghost_approvedCount();
        uint256 withdrawn = handler.ghost_withdrawnCount();

        assertGe(
            approved,
            withdrawn,
            "INVARIANT VIOLATED: Withdrawn count exceeds approved count"
        );
        assertLe(
            discovery.getProviders().length,
            approved - withdrawn,
            "INVARIANT VIOLATED: Listing larger than active approved providers"
        );
    }

    /// @notice Withdrawn providers must not appear in getProviders()
    function invariant_WithdrawnProvidersNotListed() public view {
        uint256 count = handler.getRegisteredCount();
        for (uint256 i = 0; i < count; i++) {
            (address addr, , , , bool withdrawn) = handler.getProviderInfo(i);
            if (withdrawn) {
                assertFalse(
                    _isListed(addr),
                    "INVARIANT VIOLATED: Withdrawn provider still listed"
                );
            }
        }
    }

    /// @notice isOperational must equal (status && isCollateralSufficient) for all tracked providers
    function invariant_IsOperationalConsistency() public view {
        uint256 count = handler.getRegisteredCount();
        for (uint256 i = 0; i < count; i++) {
            (
                address addr,
                ,
                Flyover.ProviderType providerType,
                bool statusSet,
                bool withdrawn
            ) = handler.getProviderInfo(i);

            if (!withdrawn) {
                bool operational = discovery.isOperational(providerType, addr);
                bool sufficient = collateralManagement.isCollateralSufficient(
                    providerType,
                    addr
                );
                bool expected = statusSet && sufficient;

                assertEq(
                    operational,
                    expected,
                    "INVARIANT VIOLATED: isOperational mismatch"
                );
            }
        }
    }

    /// @notice Every registered provider should have collateral >= minCollateral for their type
    function invariant_CollateralMatchesRegistration() public view {
        uint256 count = handler.getRegisteredCount();
        uint256 minCol = collateralManagement.getMinCollateral();

        for (uint256 i = 0; i < count; i++) {
            (
                address addr,
                ,
                Flyover.ProviderType providerType,
                ,
                bool withdrawn
            ) = handler.getProviderInfo(i);

            bool supportsPegin = providerType == Flyover.ProviderType.PegIn ||
                providerType == Flyover.ProviderType.Both;
            bool supportsPegout = providerType == Flyover.ProviderType.PegOut ||
                providerType == Flyover.ProviderType.Both;

            if (!withdrawn && supportsPegin) {
                assertGe(
                    collateralManagement.getPegInCollateral(addr),
                    minCol,
                    "INVARIANT VIOLATED: PegIn collateral below minimum"
                );
            }
            if (!withdrawn && supportsPegout) {
                assertGe(
                    collateralManagement.getPegOutCollateral(addr),
                    minCol,
                    "INVARIANT VIOLATED: PegOut collateral below minimum"
                );
            }
        }
    }

    function invariant_callSummary() public view {
        console.log("\n--- Discovery Invariant Summary ---");
        console.log("Registered providers:", handler.ghost_totalRegistered());
        console.log("Approved providers:", handler.ghost_approvedCount());
        console.log("Withdrawn providers:", handler.ghost_withdrawnCount());
        console.log("Pending withdrawn:", handler.ghost_pendingWithdrawn());
        console.log("Last provider ID:", handler.ghost_lastProviderId());
        console.log("Listed providers:", discovery.getProviders().length);
        console.log("Discovery balance:", address(discovery).balance);
        console.log(
            "CollateralMgmt balance:",
            address(collateralManagement).balance
        );
        console.log("----------------------------------\n");
    }

    function _isListed(address provider) private view returns (bool) {
        Flyover.LiquidityProvider[] memory listed = discovery.getProviders();
        for (uint256 i = 0; i < listed.length; i++) {
            if (listed[i].providerAddress == provider) return true;
        }
        return false;
    }
}
