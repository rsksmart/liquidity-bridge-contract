// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {PegInAddressRegistry} from "../../src/PegInAddressRegistry.sol";
import {RegistryBridgeMock} from "./RegistryBridgeMock.sol";

/// @title PegInRegistryTestBase
/// @notice Shared setup for the PegInAddressRegistry test suite: deploys the registry behind
/// an ERC1967 proxy against a swappable bridge mock.
abstract contract PegInRegistryTestBase is Test {
    uint48 internal constant ADMIN_DELAY = 0;

    address internal owner = address(0xA11CE);

    PegInAddressRegistry internal registry;
    RegistryBridgeMock internal bridge;

    function _deploy(bool mainnet) internal {
        bridge = new RegistryBridgeMock();
        PegInAddressRegistry impl = new PegInAddressRegistry();
        bytes memory initData = abi.encodeCall(
            PegInAddressRegistry.initialize,
            (owner, ADMIN_DELAY, address(bridge), mainnet)
        );
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), initData);
        registry = PegInAddressRegistry(payable(address(proxy)));
    }

    /// @notice The locked derivation value the bridge keys the fast-bridge deposit on.
    function _derivationValue(address addr) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(registryDomain(), addr));
    }

    function registryDomain() internal pure returns (bytes memory) {
        return "FLYOVER_PEGIN_V1";
    }

    /// @notice Funds a proven deposit for `addr` on the mock and registers it as `caller`.
    function _registerWithDeposit(address addr, address caller, uint256 amount) internal {
        vm.deal(address(this), address(this).balance + amount);
        bridge.setPegin{value: amount}(_derivationValue(addr));
        vm.prank(caller);
        registry.registerAddress(addr, hex"00", 1, hex"00");
    }
}
