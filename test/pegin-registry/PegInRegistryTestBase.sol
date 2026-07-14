// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {PegInAddressRegistry} from "../../src/PegInAddressRegistry.sol";
import {PegInAddressRegistryHarness} from "./PegInAddressRegistryHarness.sol";
import {RegistryBridgeMock} from "./RegistryBridgeMock.sol";

/// @title PegInRegistryTestBase
/// @notice Shared proxy deploy setup for PegInAddressRegistry read tests.
abstract contract PegInRegistryTestBase is Test {
    uint48 internal constant ADMIN_DELAY = 0;

    address internal constant PEGIN_CONTRACT =
        address(0x00000000000000000000000000000000C0FFEE01);

    address internal owner = address(0xA11CE);
    address internal stranger = address(0xB0B);

    PegInAddressRegistryHarness internal registry;
    RegistryBridgeMock internal bridge;

    function _deploy(bool mainnet) internal {
        bridge = new RegistryBridgeMock();
        PegInAddressRegistryHarness impl = new PegInAddressRegistryHarness();
        bytes memory initData = abi.encodeCall(
            PegInAddressRegistry.initialize,
            (owner, ADMIN_DELAY, address(bridge), mainnet)
        );
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), initData);
        registry = PegInAddressRegistryHarness(payable(address(proxy)));
        vm.prank(owner);
        registry.setPegInContract(PEGIN_CONTRACT);
    }

    function _deployUnwired(
        bool mainnet
    ) internal returns (PegInAddressRegistryHarness r) {
        if (address(bridge) == address(0)) bridge = new RegistryBridgeMock();
        PegInAddressRegistryHarness impl = new PegInAddressRegistryHarness();
        bytes memory initData = abi.encodeCall(
            PegInAddressRegistry.initialize,
            (owner, ADMIN_DELAY, address(bridge), mainnet)
        );
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), initData);
        r = PegInAddressRegistryHarness(payable(address(proxy)));
    }

    function _seedRegistration(
        address addr,
        address registrant,
        uint96 registrationBlock
    ) internal {
        registry.harness_seedRegistration(addr, registrant, registrationBlock);
    }

    function _seedRegistrationRoot(bytes32 root) internal {
        registry.harness_seedRegistrationRoot(root);
    }

    function _addressVersionByte(
        bytes memory payload
    ) internal pure returns (bytes1) {
        require(payload.length > 0, "empty payload");
        return payload[0];
    }
}
