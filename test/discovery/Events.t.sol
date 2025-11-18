// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {DiscoveryTestBase} from "./DiscoveryTestBase.sol";
import {IFlyoverDiscovery} from "../../src/interfaces/IFlyoverDiscovery.sol";
import {Flyover} from "../../src/libraries/Flyover.sol";

contract EventsTest is DiscoveryTestBase {
    address public newLp;

    function setUp() public {
        deployDiscovery();

        // Create additional test account
        newLp = makeAddr("newLp");
        vm.deal(newLp, 100 ether);
    }

    // ============ Register event tests ============

    function test_Register_EmitsRegisterWithIdSenderAndAmount() public {
        // Register a new provider and check event emission
        vm.prank(newLp);
        vm.expectEmit(true, true, true, true);
        emit IFlyoverDiscovery.Register(1, newLp, MIN_COLLATERAL);
        discovery.register{value: MIN_COLLATERAL}(
            "N",
            "U",
            true,
            Flyover.ProviderType.PegIn
        );
    }

    // ============ ProviderStatusSet event tests ============

    function test_ProviderStatusSet_EmitsWhenTogglingStatus() public {
        // Setup providers first
        setupProviders();

        // Toggle status for pegOutLp (id = 2)
        vm.prank(pegOutLp);
        vm.expectEmit(true, true, false, true);
        emit IFlyoverDiscovery.ProviderStatusSet(2, false);
        discovery.setProviderStatus(2, false);
    }
}
