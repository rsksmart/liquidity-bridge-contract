// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {PegInRegistryTestBase} from "./PegInRegistryTestBase.sol";
import {PegInAddressRegistry} from "../../src/PegInAddressRegistry.sol";
import {IPegInAddressRegistry} from "../../src/interfaces/IPegInAddressRegistry.sol";

/// @title Registration tests (E2.4)
/// @notice PoC: record-only, permissionless registration plus the view getters.
/// Deposit-gating that validates (without consuming) the BTC deposit is follow-up
/// hardening; the deposit is validated downstream at requestPegIn / resolvePegIn.
contract RegisterTest is PegInRegistryTestBase {
    address internal constant USER = address(0xCAFE);
    address internal constant WATCHTOWER = address(0xBEEF);

    event AddressRegistered(address indexed addr, bytes32 indexed registrationRoot);

    function setUp() public {
        _deploy(false);
    }

    function test_RegistersRecordOnly() public {
        bytes32 expectedRoot = keccak256(abi.encodePacked(bytes32(0), USER));
        vm.expectEmit(true, true, false, true, address(registry));
        emit AddressRegistered(USER, expectedRoot);

        vm.prank(USER);
        registry.registerAddress(USER, hex"00", 1, hex"00");

        assertTrue(registry.isRegistered(USER), "isRegistered true");
        assertEq(registry.getRegistrationBlock(USER), block.number, "records block");
        assertEq(registry.getRegistrationCount(), 1, "count incremented");
        assertEq(registry.getRegistrationRoot(), expectedRoot, "root updated");
    }

    function test_NoDepositProofNeeded() public {
        // PoC record-only: registration succeeds without any bridge-validated deposit proof.
        vm.prank(USER);
        registry.registerAddress(USER, hex"", 0, hex"");
        assertTrue(registry.isRegistered(USER), "registers without a deposit proof");
        assertEq(registry.getRegistrationCount(), 1, "count incremented");
    }

    function test_PermissionlessCaller() public {
        // A caller other than USER registers USER, no signature, no deposit.
        vm.prank(WATCHTOWER);
        registry.registerAddress(USER, hex"00", 1, hex"00");
        assertTrue(registry.isRegistered(USER), "third party can register on behalf of USER");
    }

    function test_DoubleRegisterReverts() public {
        vm.prank(USER);
        registry.registerAddress(USER, hex"00", 1, hex"00");

        vm.expectRevert(
            abi.encodeWithSelector(PegInAddressRegistry.AlreadyRegistered.selector, USER)
        );
        vm.prank(USER);
        registry.registerAddress(USER, hex"00", 1, hex"00");
    }
}
