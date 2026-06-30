// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {PegInAddressRegistry} from "../../../src/PegInAddressRegistry.sol";
import {PauseRegistry} from "../../../src/PauseRegistry.sol";
import {BridgeMock} from "../../../src/test-contracts/BridgeMock.sol";

/// @title Base contract for PegInAddressRegistry fuzz tests
abstract contract PegInAddressRegistryFuzzTestBase is Test {
    PegInAddressRegistry public registry;
    PauseRegistry public pauseRegistry;
    BridgeMock public bridge;

    address public owner;

    /// @notice Deploy PegInAddressRegistry with PauseRegistry and BridgeMock
    function deployPegInAddressRegistry() internal {
        owner = makeAddr("owner");

        PauseRegistry prImpl = new PauseRegistry();
        ERC1967Proxy prProxy = new ERC1967Proxy(
            address(prImpl),
            abi.encodeCall(prImpl.initialize, (uint48(0), owner))
        );
        pauseRegistry = PauseRegistry(payable(address(prProxy)));

        bridge = new BridgeMock();

        PegInAddressRegistry implementation = new PegInAddressRegistry();
        bytes memory initData = abi.encodeCall(
            PegInAddressRegistry.initialize,
            (owner, payable(address(bridge)), false, address(pauseRegistry))
        );
        ERC1967Proxy proxy = new ERC1967Proxy(
            address(implementation),
            initData
        );
        registry = PegInAddressRegistry(address(proxy));
    }

    /// @notice Replays the ordered registration root accumulator off-chain
    function computeRegistrationRoot(
        address[] memory addrs
    ) internal pure returns (bytes32 root) {
        for (uint256 i = 0; i < addrs.length; ++i) {
            root = keccak256(abi.encodePacked(root, addrs[i]));
        }
    }

    /// @notice Builds a bounded list of unique non-zero addresses from a fuzz seed
    function generateUniqueAddresses(
        uint256 seed,
        uint256 count
    ) internal pure returns (address[] memory addrs) {
        count = bound(count, 1, 16);
        addrs = new address[](count);
        uint256 found;
        for (uint256 i = 0; found < count && i < count * 4; ++i) {
            address candidate = address(
                uint160(uint256(keccak256(abi.encode(seed, i))))
            );
            if (candidate != address(0) && isUnique(addrs, candidate)) {
                addrs[found] = candidate;
                ++found;
            }
        }
        assembly {
            mstore(addrs, found)
        }
    }

    function isUnique(
        address[] memory addrs,
        address candidate
    ) private pure returns (bool) {
        for (uint256 i = 0; i < addrs.length; ++i) {
            if (addrs[i] == candidate) return false;
        }
        return true;
    }
}
