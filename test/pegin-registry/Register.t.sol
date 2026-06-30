// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {PegInRegistryTestBase} from "./PegInRegistryTestBase.sol";
import {PegInAddressRegistry} from "../../src/PegInAddressRegistry.sol";
import {IPegInAddressRegistry} from "../../src/interfaces/IPegInAddressRegistry.sol";

/// @title Registration tests (E2.4)
/// @notice Deposit-gated, permissionless registration plus the view getters.
contract RegisterTest is PegInRegistryTestBase {
    address internal constant USER = address(0xCAFE);
    address internal constant WATCHTOWER = address(0xBEEF);

    event AddressRegistered(address indexed addr, bytes32 indexed registrationRoot);

    function setUp() public {
        _deploy(false);
    }

    function test_ValidDepositRegisters() public {
        bridge.setPegin{value: 1 ether}(_derivationValue(USER));

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

    function test_InvalidProofReverts() public {
        // No setPegin: the mock returns a bridge error (-303), so registration must revert.
        vm.expectRevert(
            abi.encodeWithSelector(PegInAddressRegistry.InvalidDepositProof.selector, USER, int256(-303))
        );
        vm.prank(USER);
        registry.registerAddress(USER, hex"00", 1, hex"00");

        assertFalse(registry.isRegistered(USER), "nothing registered on invalid proof");
        assertEq(registry.getRegistrationCount(), 0, "count unchanged");
    }

    function test_PermissionlessCaller() public {
        // A caller other than USER registers USER with a valid deposit, no signature.
        bridge.setPegin{value: 1 ether}(_derivationValue(USER));
        vm.prank(WATCHTOWER);
        registry.registerAddress(USER, hex"00", 1, hex"00");

        assertTrue(registry.isRegistered(USER), "third party can register on behalf of USER");
    }

    function test_DoubleRegisterReverts() public {
        bridge.setPegin{value: 1 ether}(_derivationValue(USER));
        vm.prank(USER);
        registry.registerAddress(USER, hex"00", 1, hex"00");

        bridge.setPegin{value: 1 ether}(_derivationValue(USER));
        vm.expectRevert(
            abi.encodeWithSelector(PegInAddressRegistry.AlreadyRegistered.selector, USER)
        );
        vm.prank(USER);
        registry.registerAddress(USER, hex"00", 1, hex"00");
    }
}
