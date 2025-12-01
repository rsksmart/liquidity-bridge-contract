// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {DiscoveryFuzzTestBase} from "./DiscoveryFuzzTestBase.sol";
import {IFlyoverDiscovery} from "../../../src/interfaces/IFlyoverDiscovery.sol";
import {Flyover} from "../../../src/libraries/Flyover.sol";

/// @title FlyoverDiscovery Update Fuzz Tests
/// @notice Fuzz tests for provider update functionality
contract DiscoveryUpdateFuzzTest is DiscoveryFuzzTestBase {
    address public stranger;

    function setUp() public {
        deployDiscovery();
        setupProviders();

        stranger = makeAddr("stranger");
        vm.deal(stranger, 100 ether);

        fuzzUser = makeAddr("fuzzUser");
        vm.deal(fuzzUser, 100 ether);
    }

    // ============ Successful Update Tests ============

    /// @notice Fuzz test: Provider can update its name and URL
    function testFuzz_UpdateProvider_SucceedsWithValidData(
        bytes32 nameSeed,
        bytes32 urlSeed
    ) public {
        string memory newName = generateFuzzString(nameSeed, 1, 50);
        string memory newUrl = generateFuzzString(urlSeed, 1, 100);

        vm.prank(pegInLp);
        vm.expectEmit(true, false, false, true);
        emit IFlyoverDiscovery.ProviderUpdate(pegInLp, newName, newUrl);
        discovery.updateProvider(newName, newUrl);

        Flyover.LiquidityProvider memory updated = discovery.getProvider(pegInLp);
        assertEq(updated.name, newName, "Name should be updated");
        assertEq(updated.apiBaseUrl, newUrl, "URL should be updated");
    }

    /// @notice Fuzz test: Multiple updates work correctly
    function testFuzz_UpdateProvider_MultipleUpdatesWork(uint8 updateCount) public {
        updateCount = uint8(bound(updateCount, 1, 10));

        for (uint8 i = 0; i < updateCount; i++) {
            string memory newName = string(abi.encodePacked("Name_", i));
            string memory newUrl = string(abi.encodePacked("url_", i));

            vm.prank(pegInLp);
            discovery.updateProvider(newName, newUrl);

            Flyover.LiquidityProvider memory updated = discovery.getProvider(pegInLp);
            assertEq(updated.name, newName, "Name should match after update");
            assertEq(updated.apiBaseUrl, newUrl, "URL should match after update");
        }
    }

    /// @notice Fuzz test: Update preserves other provider fields
    function testFuzz_UpdateProvider_PreservesOtherFields(
        bytes32 nameSeed,
        bytes32 urlSeed
    ) public {
        // Get original values
        Flyover.LiquidityProvider memory before = discovery.getProvider(pegInLp);

        string memory newName = generateFuzzString(nameSeed, 1, 50);
        string memory newUrl = generateFuzzString(urlSeed, 1, 100);

        vm.prank(pegInLp);
        discovery.updateProvider(newName, newUrl);

        Flyover.LiquidityProvider memory after_ = discovery.getProvider(pegInLp);

        // Name and URL should change
        assertEq(after_.name, newName, "Name should be updated");
        assertEq(after_.apiBaseUrl, newUrl, "URL should be updated");

        // Other fields should remain unchanged
        assertEq(after_.id, before.id, "ID should remain unchanged");
        assertEq(after_.providerAddress, before.providerAddress, "Address should remain unchanged");
        assertEq(after_.status, before.status, "Status should remain unchanged");
        assertEq(uint256(after_.providerType), uint256(before.providerType), "Type should remain unchanged");
    }

    // ============ Invalid Data Tests ============

    /// @notice Fuzz test: Empty name reverts
    function testFuzz_UpdateProvider_RevertsOnEmptyName(bytes32 urlSeed) public {
        string memory url = generateFuzzString(urlSeed, 1, 100);

        vm.prank(pegInLp);
        vm.expectRevert(
            abi.encodeWithSelector(
                IFlyoverDiscovery.InvalidProviderData.selector,
                "",
                url
            )
        );
        discovery.updateProvider("", url);
    }

    /// @notice Fuzz test: Empty URL reverts
    function testFuzz_UpdateProvider_RevertsOnEmptyUrl(bytes32 nameSeed) public {
        string memory name = generateFuzzString(nameSeed, 1, 100);

        vm.prank(pegInLp);
        vm.expectRevert(
            abi.encodeWithSelector(
                IFlyoverDiscovery.InvalidProviderData.selector,
                name,
                ""
            )
        );
        discovery.updateProvider(name, "");
    }

    // ============ Authorization Tests ============

    /// @notice Fuzz test: Unregistered address cannot update
    function testFuzz_UpdateProvider_RevertsForUnregistered(
        bytes32 nameSeed,
        bytes32 urlSeed
    ) public {
        string memory name = generateFuzzString(nameSeed, 1, 50);
        string memory url = generateFuzzString(urlSeed, 1, 100);

        vm.prank(stranger);
        vm.expectRevert(
            abi.encodeWithSelector(
                Flyover.ProviderNotRegistered.selector,
                stranger
            )
        );
        discovery.updateProvider(name, url);
    }

    // ============ Event Emission Tests ============

    /// @notice Fuzz test: Update emits correct event
    function testFuzz_UpdateProvider_EmitsCorrectEvent(
        bytes32 nameSeed,
        bytes32 urlSeed
    ) public {
        string memory newName = generateFuzzString(nameSeed, 1, 50);
        string memory newUrl = generateFuzzString(urlSeed, 1, 100);

        vm.prank(pegOutLp);
        vm.expectEmit(true, false, false, true);
        emit IFlyoverDiscovery.ProviderUpdate(pegOutLp, newName, newUrl);
        discovery.updateProvider(newName, newUrl);
    }

    // ============ String Boundary Tests ============

    /// @notice Fuzz test: Single character name and URL work
    function testFuzz_UpdateProvider_SingleCharacterStrings(uint8 nameChar, uint8 urlChar) public {
        // Ensure printable ASCII
        nameChar = uint8(bound(nameChar, 33, 126));
        urlChar = uint8(bound(urlChar, 33, 126));

        string memory name = string(abi.encodePacked(bytes1(nameChar)));
        string memory url = string(abi.encodePacked(bytes1(urlChar)));

        vm.prank(pegInLp);
        discovery.updateProvider(name, url);

        Flyover.LiquidityProvider memory updated = discovery.getProvider(pegInLp);
        assertEq(updated.name, name, "Single char name should work");
        assertEq(updated.apiBaseUrl, url, "Single char URL should work");
    }

    /// @notice Fuzz test: Long strings work
    function testFuzz_UpdateProvider_LongStrings(
        bytes32 seed1,
        bytes32 seed2,
        bytes32 seed3,
        bytes32 seed4
    ) public {
        // Create long strings by concatenating
        string memory name = string(abi.encodePacked(
            generateFuzzString(seed1, 50, 100),
            generateFuzzString(seed2, 50, 100)
        ));
        string memory url = string(abi.encodePacked(
            generateFuzzString(seed3, 50, 100),
            generateFuzzString(seed4, 50, 100)
        ));

        vm.prank(pegInLp);
        discovery.updateProvider(name, url);

        Flyover.LiquidityProvider memory updated = discovery.getProvider(pegInLp);
        assertEq(updated.name, name, "Long name should work");
        assertEq(updated.apiBaseUrl, url, "Long URL should work");
    }

    // ============ Update After Status Change Tests ============

    /// @notice Fuzz test: Update works even when provider is disabled
    function testFuzz_UpdateProvider_WorksWhenDisabled(
        bytes32 nameSeed,
        bytes32 urlSeed
    ) public {
        string memory newName = generateFuzzString(nameSeed, 1, 50);
        string memory newUrl = generateFuzzString(urlSeed, 1, 100);

        // Disable provider
        vm.prank(pegInLp);
        discovery.setProviderStatus(1, false);

        // Update should still work
        vm.prank(pegInLp);
        discovery.updateProvider(newName, newUrl);

        Flyover.LiquidityProvider memory updated = discovery.getProvider(pegInLp);
        assertEq(updated.name, newName, "Name should be updated");
        assertEq(updated.apiBaseUrl, newUrl, "URL should be updated");
        assertFalse(updated.status, "Status should still be disabled");
    }
}
