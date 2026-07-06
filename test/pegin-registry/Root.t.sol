// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {PegInRegistryTestBase} from "./PegInRegistryTestBase.sol";

/// @title Registration root tests (E2.3)
/// @notice The running-hash accumulator folds registrations in order, and order matters.
contract RootTest is PegInRegistryTestBase {
    address internal constant A = address(0xAAAA);
    address internal constant B = address(0xBBBB);

    function setUp() public {
        _deploy(false);
    }

    function test_RootFoldsInOrder() public {
        _registerWithDeposit(A, address(0x1));
        _registerWithDeposit(B, address(0x2));

        bytes32 expected = keccak256(
            abi.encodePacked(
                keccak256(abi.encodePacked(bytes32(0), A)),
                B
            )
        );
        assertEq(registry.getRegistrationRoot(), expected, "root == H(H(0||A)||B)");
    }

    function test_OrderMatters() public {
        // A then B
        _registerWithDeposit(A, address(0x1));
        _registerWithDeposit(B, address(0x2));
        bytes32 rootAB = registry.getRegistrationRoot();

        // Fresh registry: B then A
        _deploy(false);
        _registerWithDeposit(B, address(0x2));
        _registerWithDeposit(A, address(0x1));
        bytes32 rootBA = registry.getRegistrationRoot();

        assertTrue(rootAB != rootBA, "A-then-B root differs from B-then-A");
    }
}
