// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {PegInRegistryTestBase} from "./PegInRegistryTestBase.sol";

/// @title Federation + batch getter tests (E2.5)
/// @notice Batch derivation matches the single getter, and a powpeg change re-derives.
contract FederationTest is PegInRegistryTestBase {
    address internal constant A = address(0x1111);
    address internal constant B = address(0x2222);

    function setUp() public {
        _deploy(false);
    }

    function test_BatchGetterMatchesSingle() public view {
        (bytes memory sa, ) = registry.getPegInAddress(A);
        (bytes memory sb, ) = registry.getPegInAddress(B);

        address[] memory addrs = new address[](2);
        addrs[0] = A;
        addrs[1] = B;
        (bytes[] memory batch, ) = registry.getPegInAddresses(addrs);

        assertEq(batch.length, 2, "two results");
        assertEq(batch[0], sa, "batch[0] == single A");
        assertEq(batch[1], sb, "batch[1] == single B");
    }

    function test_FederationChangeYieldsNewAddress() public {
        (bytes memory before, ) = registry.getPegInAddress(A);

        // Simulate a powpeg composition change: a different active redeem script.
        bytes memory newRedeem = abi.encodePacked(
            hex"5221037c8a5e4f5a8e7b1c9d0e2f3a4b5c6d7e8f90112233445566778899aabbccddeeff",
            hex"2103aabbccddeeff00112233445566778899aabbccddeeff00112233445566778899",
            hex"52ae"
        );
        bridge.setRedeemScript(newRedeem);

        (bytes memory afterChange, ) = registry.getPegInAddress(A);
        assertTrue(
            keccak256(before) != keccak256(afterChange),
            "same rskAddr derives a different address after a powpeg change"
        );
    }
}
