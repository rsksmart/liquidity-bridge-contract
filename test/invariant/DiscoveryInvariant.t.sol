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

        bytes4[] memory selectors = new bytes4[](3);
        selectors[0] = handler.registerProvider.selector;
        selectors[1] = handler.toggleStatus.selector;
        selectors[2] = handler.updateProviderInfo.selector;
        targetSelector(
            FuzzSelector({addr: address(handler), selectors: selectors})
        );
    }

    // ============ Invariant Tests ============

    /// @notice Discovery contract should never hold ETH — all forwarded to CollateralManagement
    function invariant_DiscoveryHoldsNoETH() public view {
        assertEq(
            address(discovery).balance,
            0,
            "INVARIANT VIOLATED: Discovery holds ETH"
        );
    }

    /// @notice Provider ID counter should match total registrations and never decrease
    function invariant_ProviderIdMonotonic() public view {
        uint256 registered = handler.ghost_totalRegistered();
        if (registered == 0) return;

        assertEq(
            discovery.getProvidersId(),
            registered,
            "INVARIANT VIOLATED: Provider ID counter mismatch"
        );
    }

    /// @notice Every provider returned by getProviders() must be registered and have status enabled
    function invariant_GetProvidersConsistency() public view {
        Flyover.LiquidityProvider[] memory listed = discovery.getProviders();

        for (uint256 i = 0; i < listed.length; i++) {
            assertTrue(
                listed[i].status,
                "INVARIANT VIOLATED: Listed provider has status false"
            );

            assertTrue(
                collateralManagement.isRegistered(
                    listed[i].providerType,
                    listed[i].providerAddress
                ),
                "INVARIANT VIOLATED: Listed provider not registered in CollateralManagement"
            );
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
                bool statusSet
            ) = handler.getProviderInfo(i);

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

    /// @notice Every registered provider should have collateral >= minCollateral for their type
    function invariant_CollateralMatchesRegistration() public view {
        uint256 count = handler.getRegisteredCount();
        uint256 minCol = collateralManagement.getMinCollateral();

        for (uint256 i = 0; i < count; i++) {
            (address addr, , Flyover.ProviderType providerType, ) = handler
                .getProviderInfo(i);

            if (
                providerType == Flyover.ProviderType.PegIn ||
                providerType == Flyover.ProviderType.Both
            ) {
                assertGe(
                    collateralManagement.getPegInCollateral(addr),
                    minCol,
                    "INVARIANT VIOLATED: PegIn collateral below minimum"
                );
            }
            if (
                providerType == Flyover.ProviderType.PegOut ||
                providerType == Flyover.ProviderType.Both
            ) {
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
        console.log("Last provider ID:", handler.ghost_lastProviderId());
        console.log("Listed providers:", discovery.getProviders().length);
        console.log("Discovery balance:", address(discovery).balance);
        console.log(
            "CollateralMgmt balance:",
            address(collateralManagement).balance
        );
        console.log("----------------------------------\n");
    }
}
