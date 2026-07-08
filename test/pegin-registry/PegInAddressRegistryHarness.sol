// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {PegInAddressRegistry} from "../../src/PegInAddressRegistry.sol";
import {IPegInAddressRegistry} from "../../src/interfaces/IPegInAddressRegistry.sol";

/// @title PegInAddressRegistryHarness
/// @notice Test-only harness exposing storage seed helpers for read-surface tests.
contract PegInAddressRegistryHarness is PegInAddressRegistry {
    function harness_seedRegistration(address addr, address registrant, uint96 registrationBlock) external {
        PegInAddressRegistryStorage storage $ = _getStorage();
        $.registrations[addr] =
            IPegInAddressRegistry.Registration({registrant: registrant, registrationBlock: registrationBlock});
    }

    function harness_seedRegistrationRoot(bytes32 root) external {
        PegInAddressRegistryStorage storage $ = _getStorage();
        $.registrationRoot = root;
    }
}
