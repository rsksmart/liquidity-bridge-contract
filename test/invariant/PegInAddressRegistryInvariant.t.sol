// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {console} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {PegInAddressRegistryFuzzTestBase} from "../fuzz/pegin/PegInAddressRegistryFuzzTestBase.sol";
import {PegInAddressRegistryHandler} from "./handlers/PegInAddressRegistryHandler.sol";
import {IPegInAddressRegistry} from "../../src/interfaces/IPegInAddressRegistry.sol";

/// @title PegInAddressRegistry Invariant Tests
contract PegInAddressRegistryInvariantTest is PegInAddressRegistryFuzzTestBase {
    PegInAddressRegistryHandler public handler;

    function setUp() public {
        deployPegInAddressRegistry();

        handler = new PegInAddressRegistryHandler(
            registry,
            pauseRegistry,
            owner
        );

        targetContract(address(handler));

        bytes4[] memory selectors = new bytes4[](6);
        selectors[0] = handler.registerAddress.selector;
        selectors[1] = handler.registerAddress_duplicate.selector;
        selectors[2] = handler.registerAddress_zero.selector;
        selectors[3] = handler.pauseSoft.selector;
        selectors[4] = handler.unpause.selector;
        selectors[5] = handler.registerWhilePaused.selector;
        targetSelector(
            FuzzSelector({addr: address(handler), selectors: selectors})
        );
    }

    // ============ Safety invariants ============

    function invariant_RegistryHoldsNoRBTC() public view {
        assertEq(
            address(registry).balance,
            0,
            "INVARIANT VIOLATED: Registry holds RBTC"
        );
    }

    function invariant_NoHandlerViolations() public view {
        assertEq(
            handler.ghost_invariantViolations(),
            0,
            "INVARIANT VIOLATED: Forbidden registration succeeded"
        );
    }

    // ============ Registration state invariants ============

    function invariant_RegistrationCountMatchesGhostSet() public view {
        assertEq(
            registry.getRegistrationCount(),
            handler.getRegisteredCount(),
            "INVARIANT VIOLATED: Registration count mismatch"
        );
    }

    function invariant_RegisteredIffBlockNonZero() public view {
        uint256 count = handler.getRegisteredCount();
        for (uint256 i = 0; i < count; ++i) {
            address addr = handler.getRegisteredAddress(i);
            assertTrue(
                registry.isRegistered(addr),
                "INVARIANT VIOLATED: Ghost address not registered"
            );
            assertTrue(
                registry.getRegistrationBlock(addr) != 0,
                "INVARIANT VIOLATED: Registered address has zero block"
            );
        }
    }

    function invariant_RegistrationRootMatchesGhostReplay() public view {
        assertEq(
            registry.getRegistrationRoot(),
            handler.ghost_computeRegistrationRoot(),
            "INVARIANT VIOLATED: Registration root mismatch"
        );
    }

    function invariant_RegistrationBlockImmutable() public view {
        uint256 count = handler.getRegisteredCount();
        for (uint256 i = 0; i < count; ++i) {
            address addr = handler.getRegisteredAddress(i);
            assertEq(
                registry.getRegistrationBlock(addr),
                handler.ghost_registrationBlocks(addr),
                "INVARIANT VIOLATED: Registration block changed"
            );
            assertLe(
                registry.getRegistrationBlock(addr),
                block.number,
                "INVARIANT VIOLATED: Registration block in the future"
            );
        }
    }

    function invariant_RegistrantMatchesGhost() public view {
        uint256 count = handler.getRegisteredCount();
        for (uint256 i = 0; i < count; ++i) {
            address addr = handler.getRegisteredAddress(i);
            assertEq(
                registry.getRegistrant(addr),
                handler.ghost_registrants(addr),
                "INVARIANT VIOLATED: Registrant mismatch"
            );
        }
    }

    function invariant_ListedAddressesStayRegistered() public view {
        uint256 count = handler.getRegisteredCount();
        for (uint256 i = 0; i < count; ++i) {
            address addr = handler.getRegisteredAddress(i);
            assertTrue(
                registry.isRegistered(addr),
                "INVARIANT VIOLATED: Previously registered address lost"
            );
        }
    }

    // ============ Derivation invariants ============

    function invariant_DerivationMatchesGhostForAllKnownAddresses()
        public
        view
    {
        uint256 count = handler.getRegisteredCount();
        if (count == 0) return;

        address[] memory addrs = new address[](count);
        for (uint256 i = 0; i < count; ++i) {
            addrs[i] = handler.getRegisteredAddress(i);
        }

        (
            bytes[] memory batch,
            IPegInAddressRegistry.Encoding batchEncoding
        ) = registry.getPegInAddresses(addrs);

        assertEq(
            uint8(batchEncoding),
            uint8(IPegInAddressRegistry.Encoding.BASE58)
        );

        for (uint256 i = 0; i < count; ++i) {
            (
                bytes memory single,
                IPegInAddressRegistry.Encoding singleEncoding
            ) = registry.getPegInAddress(addrs[i]);
            assertEq(keccak256(batch[i]), keccak256(single));
            assertEq(
                uint8(singleEncoding),
                uint8(IPegInAddressRegistry.Encoding.BASE58)
            );
            assertEq(single.length, 25);
        }
    }

    function invariant_callSummary() public view {
        console.log("\n--- PegInAddressRegistry Invariant Summary ---");
        console.log("Registered addresses:", handler.getRegisteredCount());
        console.log("On-chain count:", registry.getRegistrationCount());
        console.log(
            "Registration root:",
            uint256(registry.getRegistrationRoot())
        );
        console.log("Registry balance:", address(registry).balance);
        console.log(
            "Invariant violations:",
            handler.ghost_invariantViolations()
        );
        console.log("--------------------------------------------\n");
    }
}
