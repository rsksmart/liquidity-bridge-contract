// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {PegInRegistryTestBase} from "./PegInRegistryTestBase.sol";
import {PegInAddressRegistry} from "../../src/PegInAddressRegistry.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

/// @title Scaffolding tests (E2.1)
/// @notice Deploy + initialize-once + storage namespace.
contract ScaffoldingTest is PegInRegistryTestBase {
    function setUp() public {
        _deploy(false);
    }

    function test_DeploysAndInitializes() public view {
        assertEq(address(registry.getBridge()), address(bridge), "bridge wired");
        assertEq(registry.getRegistrationCount(), 0, "count starts at zero");
        assertEq(registry.getRegistrationRoot(), bytes32(0), "root starts at zero");
        assertTrue(registry.hasRole(registry.DEFAULT_ADMIN_ROLE(), owner), "admin role set");
    }

    function test_SecondInitializeReverts() public {
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        registry.initialize(owner, ADMIN_DELAY, address(bridge), false);
    }

    /// @notice The storage struct resolves to the declared ERC-7201 namespace slot
    /// (keccak256(abi.encode(uint256(keccak256("rsk.flyover.PegInAddressRegistry")) - 1)) & ~0xff).
    function test_StorageNamespaceSlot() public pure {
        bytes32 expected = keccak256(
            abi.encode(uint256(keccak256("rsk.flyover.PegInAddressRegistry")) - 1)
        ) & ~bytes32(uint256(0xff));
        assertEq(
            expected,
            0x0704e3acad2c0308b9997bc861208a21efddaa710005747040bdddc7b9400f00,
            "ERC-7201 slot matches the declared constant"
        );
    }
}
