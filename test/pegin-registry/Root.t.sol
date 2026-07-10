// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {PegInRegistryTestBase} from "./PegInRegistryTestBase.sol";

/// @title PegInAddressRegistry registration-root tests
contract RootTest is PegInRegistryTestBase {
    address internal constant FIXTURE_RSK = 0x0000000000000000000000000000000000000aBc;

    // W9
    function test_root_fold_matches_getter() public {
        _deploy(false);
        _register(FIXTURE_RSK, 10_000, stranger);
        assertEq(registry.getRegistrationRoot(), _foldRoot(bytes32(0), FIXTURE_RSK));
    }

    // W16 — 52-byte preimage: prevRoot (32B) ++ rskAddr (20B)
    function test_fold_vector_matches_independent_recompute() public {
        _deploy(false);
        address[3] memory addrs = [address(0xA1), address(0xA2), address(0xA3)];
        bytes32 root = bytes32(0);
        for (uint256 i = 0; i < addrs.length; ++i) {
            _register(addrs[i], 10_000, stranger);
            root = _foldRoot(root, addrs[i]);
            assertEq(registry.getRegistrationRoot(), root);
        }
    }

    // S5 — root order dependence
    function test_root_order_matters() public {
        address a = address(0xAAAA);
        address b = address(0xBBBB);

        _deploy(false);
        _register(a, 10_000, stranger);
        _register(b, 10_000, stranger);
        bytes32 rootAB = registry.getRegistrationRoot();

        _deploy(false);
        _register(b, 10_000, stranger);
        _register(a, 10_000, stranger);
        bytes32 rootBA = registry.getRegistrationRoot();

        assertTrue(rootAB != rootBA);
        assertEq(rootAB, _foldRoot(_foldRoot(bytes32(0), a), b));
        assertEq(rootBA, _foldRoot(_foldRoot(bytes32(0), b), a));
    }

    // R7 — registration root fold
    function test_getRegistrationRoot_fold() public {
        _deploy(false);
        bytes32 root = keccak256(abi.encodePacked(bytes32(0), FIXTURE_RSK));
        _seedRegistrationRoot(root);
        assertEq(registry.getRegistrationRoot(), root);
    }
}
