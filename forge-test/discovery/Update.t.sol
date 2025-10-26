// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {DiscoveryTestBase} from "./DiscoveryTestBase.sol";
import {IFlyoverDiscovery} from "../../contracts/interfaces/IFlyoverDiscovery.sol";
import {Flyover} from "../../contracts/libraries/Flyover.sol";

contract UpdateTest is DiscoveryTestBase {
    address public stranger;

    function setUp() public {
        deployDiscovery();
        setupProviders();

        // Create stranger account
        stranger = makeAddr("stranger");
        vm.deal(stranger, 100 ether);
    }

    // ============ updateProvider tests ============

    function test_UpdateProvider_UpdatesNameAndApiBaseUrlAndEmitsEvent() public {
        string memory newName = "Modified Name";
        string memory newUrl = "https://modified.example";

        vm.prank(fullLp);
        vm.expectEmit(true, false, false, true);
        emit IFlyoverDiscovery.ProviderUpdate(fullLp, newName, newUrl);
        discovery.updateProvider(newName, newUrl);

        Flyover.LiquidityProvider memory updated = discovery.getProvider(fullLp);
        assertEq(updated.name, newName, "Name should be updated");
        assertEq(updated.apiBaseUrl, newUrl, "URL should be updated");
    }

    function test_UpdateProvider_RevertsOnInvalidInput() public {
        // Empty name
        vm.prank(fullLp);
        vm.expectRevert(
            abi.encodeWithSelector(IFlyoverDiscovery.InvalidProviderData.selector, "", "x")
        );
        discovery.updateProvider("", "x");

        // Empty URL
        vm.prank(fullLp);
        vm.expectRevert(
            abi.encodeWithSelector(IFlyoverDiscovery.InvalidProviderData.selector, "x", "")
        );
        discovery.updateProvider("x", "");
    }

    function test_UpdateProvider_RevertsIfUnregisteredAddressCallsUpdate() public {
        vm.prank(stranger);
        vm.expectRevert(
            abi.encodeWithSelector(Flyover.ProviderNotRegistered.selector, stranger)
        );
        discovery.updateProvider("n", "u");
    }
}
