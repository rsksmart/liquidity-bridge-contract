// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {DiscoveryTestBase} from "./DiscoveryTestBase.sol";
import {IFlyoverDiscovery} from "../../src/interfaces/IFlyoverDiscovery.sol";
import {Flyover} from "../../src/libraries/Flyover.sol";

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

    function test_UpdateProvider_UpdatesNameAndApiBaseUrlAndEmitsEvent()
        public
    {
        string memory newName = "Modified Name";
        string memory newUrl = "https://modified.example";

        vm.prank(fullLp);
        vm.expectEmit(true, false, false, true);
        emit IFlyoverDiscovery.ProviderUpdate(fullLp, newName, newUrl);
        discovery.updateProvider(newName, newUrl);

        Flyover.LiquidityProvider memory updated = discovery.getProvider(
            fullLp
        );
        assertEq(updated.name, newName, "Name should be updated");
        assertEq(updated.apiBaseUrl, newUrl, "URL should be updated");
    }

    function test_UpdateProvider_RevertsOnInvalidInput() public {
        // Empty name
        vm.prank(fullLp);
        vm.expectRevert(
            providerDataLengthOutOfBoundsData(0, bytes("x").length)
        );
        discovery.updateProvider("", "x");

        // Empty URL
        vm.prank(fullLp);
        vm.expectRevert(
            providerDataLengthOutOfBoundsData(bytes("x").length, 0)
        );
        discovery.updateProvider("x", "");
    }

    function test_UpdateProvider_RevertsWhenNameExceedsMaxLength() public {
        string memory tooLongName = makeStringOfLength(
            MAX_PROVIDER_NAME_LENGTH + 1
        );
        string memory validUrl = "x";

        vm.prank(fullLp);
        vm.expectRevert(
            providerDataLengthOutOfBoundsData(
                MAX_PROVIDER_NAME_LENGTH + 1,
                bytes(validUrl).length
            )
        );
        discovery.updateProvider(tooLongName, validUrl);
    }

    function test_UpdateProvider_RevertsWhenApiBaseUrlExceedsMaxLength()
        public
    {
        string memory validName = "x";
        string memory tooLongUrl = makeStringOfLength(
            MAX_PROVIDER_API_BASE_URL_LENGTH + 1
        );

        vm.prank(fullLp);
        vm.expectRevert(
            providerDataLengthOutOfBoundsData(
                bytes(validName).length,
                MAX_PROVIDER_API_BASE_URL_LENGTH + 1
            )
        );
        discovery.updateProvider(validName, tooLongUrl);
    }

    function test_UpdateProvider_AcceptsDataAtMaxLength() public {
        string memory name = makeStringOfLength(MAX_PROVIDER_NAME_LENGTH);
        string memory url = makeStringOfLength(
            MAX_PROVIDER_API_BASE_URL_LENGTH
        );

        vm.prank(fullLp);
        discovery.updateProvider(name, url);

        Flyover.LiquidityProvider memory p = discovery.getProvider(fullLp);
        assertEq(bytes(p.name).length, MAX_PROVIDER_NAME_LENGTH);
        assertEq(bytes(p.apiBaseUrl).length, MAX_PROVIDER_API_BASE_URL_LENGTH);
    }

    function test_UpdateProvider_RevertsIfUnregisteredAddressCallsUpdate()
        public
    {
        vm.prank(stranger);
        vm.expectRevert(
            abi.encodeWithSelector(
                Flyover.ProviderNotRegistered.selector,
                stranger
            )
        );
        discovery.updateProvider("n", "u");
    }
}
