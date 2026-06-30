// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {PegInRegistryTestBase} from "./PegInRegistryTestBase.sol";
import {PegInAddressRegistry} from "../../src/PegInAddressRegistry.sol";
import {IPegInAddressRegistry} from "../../src/interfaces/IPegInAddressRegistry.sol";

/// @title Registration tests (E2.4)
/// @notice Read-only deposit-gating: registration validates (without consuming) that a confirmed
/// BTC tx pays the address derived for the RSK address. Settlement stays in resolvePegIn.
contract RegisterTest is PegInRegistryTestBase {
    address internal constant USER = address(0xCAFE);
    address internal constant OTHER = address(0xD00D);
    address internal constant WATCHTOWER = address(0xBEEF);

    event AddressRegistered(address indexed addr, bytes32 indexed registrationRoot);

    function setUp() public {
        _deploy(false);
    }

    function _emptyBranches() internal pure returns (bytes32[] memory) {
        return new bytes32[](0);
    }

    function test_ValidDepositRegistersAndEmits() public {
        bytes32 expectedRoot = keccak256(abi.encodePacked(bytes32(0), USER));
        vm.expectEmit(true, true, false, true, address(registry));
        emit AddressRegistered(USER, expectedRoot);

        vm.prank(USER);
        registry.registerAddress(USER, _btcTxForAddr(USER), bytes32(0), 0, _emptyBranches());

        assertTrue(registry.isRegistered(USER), "isRegistered true");
        assertEq(registry.getRegistrationBlock(USER), block.number, "records block");
        assertEq(registry.getRegistrationCount(), 1, "count incremented");
        assertEq(registry.getRegistrationRoot(), expectedRoot, "root updated");
    }

    function test_OutputPaysDifferentAddressReverts() public {
        // Tx pays the address derived for OTHER, but we try to register USER.
        bytes memory wrongTx = _btcTxForAddr(OTHER);
        vm.expectRevert(
            abi.encodeWithSelector(PegInAddressRegistry.DepositAddressMismatch.selector, USER)
        );
        vm.prank(USER);
        registry.registerAddress(USER, wrongTx, bytes32(0), 0, _emptyBranches());
    }

    function test_InsufficientConfirmationsReverts() public {
        bytes memory tx_ = _btcTxForAddr(USER);
        bridge.setConfirmations(0);
        vm.expectRevert(
            abi.encodeWithSelector(PegInAddressRegistry.InvalidDepositProof.selector, USER, int256(0))
        );
        vm.prank(USER);
        registry.registerAddress(USER, tx_, bytes32(0), 0, _emptyBranches());
    }

    function test_NegativeConfirmationsReverts() public {
        // Bridge does not know the tx/block: returns a negative error code.
        bytes memory tx_ = _btcTxForAddr(USER);
        bridge.setConfirmations(-1);
        vm.expectRevert(
            abi.encodeWithSelector(PegInAddressRegistry.InvalidDepositProof.selector, USER, int256(-1))
        );
        vm.prank(USER);
        registry.registerAddress(USER, tx_, bytes32(0), 0, _emptyBranches());
    }

    function test_PermissionlessCaller() public {
        // A caller other than USER registers USER with a valid deposit proof. No signature.
        bytes memory tx_ = _btcTxForAddr(USER);
        vm.prank(WATCHTOWER);
        registry.registerAddress(USER, tx_, bytes32(0), 0, _emptyBranches());
        assertTrue(registry.isRegistered(USER), "third party can register on behalf of USER");
    }

    function test_DoubleRegisterReverts() public {
        bytes memory tx_ = _btcTxForAddr(USER);
        vm.prank(USER);
        registry.registerAddress(USER, tx_, bytes32(0), 0, _emptyBranches());

        vm.expectRevert(
            abi.encodeWithSelector(PegInAddressRegistry.AlreadyRegistered.selector, USER)
        );
        vm.prank(USER);
        registry.registerAddress(USER, tx_, bytes32(0), 0, _emptyBranches());
    }
}
