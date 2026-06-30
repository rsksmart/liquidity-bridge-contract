// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {PegInAddressRegistryFuzzTestBase} from "./PegInAddressRegistryFuzzTestBase.sol";
import {PegInAddressRegistry} from "../../../src/PegInAddressRegistry.sol";
import {IPegInAddressRegistry} from "../../../src/interfaces/IPegInAddressRegistry.sol";
import {Flyover} from "../../../src/libraries/Flyover.sol";

/// @title PegInAddressRegistry Fuzz Tests
contract PegInAddressRegistryFuzzTest is PegInAddressRegistryFuzzTestBase {
    function setUp() public {
        deployPegInAddressRegistry();
    }

    // ============ Registration fuzz tests ============

    function testFuzz_Register_RevertsOnZeroAddress(uint256) public {
        vm.expectRevert(
            abi.encodeWithSelector(Flyover.InvalidAddress.selector, address(0))
        );
        registry.registerAddress(address(0));
    }

    function testFuzz_Register_RevertsWhenAlreadyRegistered(
        uint256 seed
    ) public {
        address addr = address(uint160(seed));
        vm.assume(addr != address(0));

        registry.registerAddress(addr);

        vm.expectRevert(
            abi.encodeWithSelector(
                PegInAddressRegistry.AlreadyRegistered.selector,
                addr
            )
        );
        registry.registerAddress(addr);
    }

    function testFuzz_Register_StoresRegistrant(
        uint256 addrSeed,
        uint256 registrantSeed
    ) public {
        address addr = address(uint160(addrSeed));
        address registrant = address(uint160(registrantSeed));
        vm.assume(addr != address(0));
        vm.assume(registrant != address(0));

        vm.prank(registrant);
        registry.registerAddress(addr);

        assertEq(registry.getRegistrant(addr), registrant);
    }

    function testFuzz_RegistrationRoot_MatchesOrderedReplay(
        uint256 seed,
        uint256 count
    ) public {
        address[] memory addrs = generateUniqueAddresses(seed, count);
        for (uint256 i = 0; i < addrs.length; ++i) {
            registry.registerAddress(addrs[i]);
        }

        assertEq(registry.getRegistrationCount(), addrs.length);
        assertEq(
            registry.getRegistrationRoot(),
            computeRegistrationRoot(addrs)
        );
    }

    // ============ Derivation fuzz tests ============

    function testFuzz_GetPegInAddress_Deterministic(uint256 seed) public view {
        address addr = address(uint160(seed));

        (bytes memory first, ) = registry.getPegInAddress(addr);
        (bytes memory second, ) = registry.getPegInAddress(addr);

        assertEq(keccak256(first), keccak256(second));
    }

    function testFuzz_GetPegInAddress_OutputLength25(uint256 seed) public view {
        address addr = address(uint160(seed));
        (bytes memory derivationAddress, ) = registry.getPegInAddress(addr);
        assertEq(derivationAddress.length, 25);
    }

    function testFuzz_GetPegInAddress_IndependentOfRegistration(
        uint256 seed
    ) public {
        address addr = address(uint160(seed));
        vm.assume(addr != address(0));

        (
            bytes memory before,
            IPegInAddressRegistry.Encoding encodingBefore
        ) = registry.getPegInAddress(addr);

        registry.registerAddress(addr);

        (
            bytes memory afterReg,
            IPegInAddressRegistry.Encoding encodingAfter
        ) = registry.getPegInAddress(addr);

        assertEq(keccak256(before), keccak256(afterReg));
        assertEq(
            uint8(encodingBefore),
            uint8(IPegInAddressRegistry.Encoding.BASE58)
        );
        assertEq(
            uint8(encodingAfter),
            uint8(IPegInAddressRegistry.Encoding.BASE58)
        );
    }

    function testFuzz_GetPegInAddresses_MatchesSingle(
        uint256 seed,
        uint256 count
    ) public view {
        address[] memory addrs = generateUniqueAddresses(seed, count);

        (
            bytes[] memory batch,
            IPegInAddressRegistry.Encoding batchEncoding
        ) = registry.getPegInAddresses(addrs);

        assertEq(batch.length, addrs.length);
        for (uint256 i = 0; i < addrs.length; ++i) {
            (
                bytes memory single,
                IPegInAddressRegistry.Encoding singleEncoding
            ) = registry.getPegInAddress(addrs[i]);
            assertEq(keccak256(batch[i]), keccak256(single));
            assertEq(uint8(batchEncoding), uint8(singleEncoding));
        }
        assertEq(
            uint8(batchEncoding),
            uint8(IPegInAddressRegistry.Encoding.BASE58)
        );
    }

    function testFuzz_GetPegInAddress_DifferentAddrsDifferentOutput(
        uint256 seedA,
        uint256 seedB
    ) public view {
        address addrA = address(uint160(seedA));
        address addrB = address(uint160(seedB));
        vm.assume(addrA != addrB);

        (bytes memory derivationA, ) = registry.getPegInAddress(addrA);
        (bytes memory derivationB, ) = registry.getPegInAddress(addrB);

        assertTrue(keccak256(derivationA) != keccak256(derivationB));
    }
}
