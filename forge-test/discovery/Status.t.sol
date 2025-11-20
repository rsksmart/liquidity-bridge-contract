// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {DiscoveryTestBase} from "./DiscoveryTestBase.sol";
import {IFlyoverDiscovery} from "../../contracts/interfaces/IFlyoverDiscovery.sol";
import {Flyover} from "../../contracts/libraries/Flyover.sol";

contract StatusTest is DiscoveryTestBase {
    address public stranger;

    function setUp() public {
        deployDiscovery();
        setupProviders();

        // Create stranger account
        stranger = makeAddr("stranger");
        vm.deal(stranger, 100 ether);
    }

    // ============ setProviderStatus tests ============

    function test_SetProviderStatus_AllowsProviderToDisableAndEnableItself()
        public
    {
        // Disable provider
        vm.prank(pegOutLp);
        discovery.setProviderStatus(2, false);

        Flyover.LiquidityProvider memory provider = discovery.getProvider(
            pegOutLp
        );
        assertFalse(provider.status, "Provider should be disabled");

        // Enable provider
        vm.prank(pegOutLp);
        discovery.setProviderStatus(2, true);

        provider = discovery.getProvider(pegOutLp);
        assertTrue(provider.status, "Provider should be enabled");
    }

    function test_SetProviderStatus_AllowsOwnerToToggleProviderStatus() public {
        // Owner disables provider
        vm.prank(owner);
        discovery.setProviderStatus(1, false);

        Flyover.LiquidityProvider memory provider = discovery.getProvider(
            pegInLp
        );
        assertFalse(provider.status, "Provider should be disabled");

        // Owner enables provider
        vm.prank(owner);
        discovery.setProviderStatus(1, true);

        provider = discovery.getProvider(pegInLp);
        assertTrue(provider.status, "Provider should be enabled");
    }

    function test_SetProviderStatus_RevertsForUnauthorizedAddress() public {
        vm.prank(stranger);
        vm.expectRevert(
            abi.encodeWithSelector(
                IFlyoverDiscovery.NotAuthorized.selector,
                stranger
            )
        );
        discovery.setProviderStatus(1, false);
    }
}
