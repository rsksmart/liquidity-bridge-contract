// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {PegInRegistryTestBase} from "./PegInRegistryTestBase.sol";
import {PegInAddressRegistry} from "../../src/PegInAddressRegistry.sol";

/// @title PegInAddressRegistry federation / batch tests
contract FederationTest is PegInRegistryTestBase {
    address internal constant FIXTURE_RSK =
        0x0000000000000000000000000000000000000aBc;

    // R2 bounds — batch cap
    function test_batch_reverts_over_max() public {
        _deploy(false);
        address[] memory addrs = new address[](101);
        for (uint256 i = 0; i < 101; ++i) {
            addrs[i] = address(uint160(i + 1));
        }
        vm.expectRevert(
            abi.encodeWithSelector(
                PegInAddressRegistry.BatchTooLarge.selector,
                101,
                100
            )
        );
        registry.getPegInAddresses(addrs);
    }

    function test_batch_returns_matching_singles() public {
        _deploy(false);
        address[] memory addrs = new address[](2);
        addrs[0] = FIXTURE_RSK;
        addrs[1] = address(0x2222);
        (bytes[] memory batch, ) = registry.getPegInAddresses(addrs);
        (bytes memory single0, ) = registry.getPegInAddress(FIXTURE_RSK);
        (bytes memory single1, ) = registry.getPegInAddress(address(0x2222));
        assertEq(batch[0], single0);
        assertEq(batch[1], single1);
    }

    // S6 — federation / powpeg rotation yields a new derived address (A6)
    function test_federation_change_yields_new_address() public {
        _deploy(false);
        (bytes memory beforeChange, ) = registry.getPegInAddress(FIXTURE_RSK);

        bytes memory newRedeem = abi.encodePacked(
            hex"5221037c8a5e4f5a8e7b1c9d0e2f3a4b5c6d7e8f90112233445566778899aabbccddeeff",
            hex"2103aabbccddeeff00112233445566778899aabbccddeeff00112233445566778899",
            hex"52ae"
        );
        bridge.setRedeemScript(newRedeem);

        (bytes memory afterChange, ) = registry.getPegInAddress(FIXTURE_RSK);
        assertTrue(keccak256(beforeChange) != keccak256(afterChange));
    }
}
