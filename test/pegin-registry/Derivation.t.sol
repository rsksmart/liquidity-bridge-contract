// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {PegInRegistryTestBase} from "./PegInRegistryTestBase.sol";
import {IPegInAddressRegistry} from "../../src/interfaces/IPegInAddressRegistry.sol";

/// @title Derivation tests (E2.2)
/// @notice Determinism, distinctness, and a fixed off-chain fixture vector.
contract DerivationTest is PegInRegistryTestBase {
    // Off-chain vector for rskAddr = 0x0000000000000000000000000000000000000abc against the
    // default RegistryBridgeMock redeem script, computed with the locked scheme:
    //   derivationValue = keccak256(abi.encodePacked("FLYOVER_PEGIN_V1", rskAddr))
    //   flyover = 0x20 <derivationValue> 0x75 <redeemScript>
    //   segwit  = 0x00 0x20 sha256(flyover)
    //   address = base58check P2SH(segwit) for the network
    address internal constant FIXTURE_RSK = 0x0000000000000000000000000000000000000aBc;
    bytes internal constant FIXTURE_TESTNET_ADDRESS =
        hex"c465e2519fcfd8e8f17bb35347261271ad75caa29c754165a5";
    bytes internal constant FIXTURE_MAINNET_ADDRESS =
        hex"0565e2519fcfd8e8f17bb35347261271ad75caa29caf31a39d";

    function test_DeterministicPerAddress() public {
        _deploy(false);
        (bytes memory a1, ) = registry.getPegInAddress(FIXTURE_RSK);
        (bytes memory a2, ) = registry.getPegInAddress(FIXTURE_RSK);
        assertEq(a1, a2, "same rskAddr derives the same address across calls");
    }

    function test_DifferentAddressesDiffer() public {
        _deploy(false);
        (bytes memory a, ) = registry.getPegInAddress(address(0x1111));
        (bytes memory b, ) = registry.getPegInAddress(address(0x2222));
        assertTrue(keccak256(a) != keccak256(b), "different rskAddr derive different addresses");
    }

    function test_MatchesTestnetFixtureVector() public {
        _deploy(false);
        (bytes memory addr, IPegInAddressRegistry.Encoding enc) = registry.getPegInAddress(FIXTURE_RSK);
        assertEq(addr, FIXTURE_TESTNET_ADDRESS, "derived testnet address matches off-chain vector");
        assertEq(uint256(enc), uint256(IPegInAddressRegistry.Encoding.BASE58), "encoding is BASE58");
    }

    function test_MatchesMainnetFixtureVector() public {
        _deploy(true);
        (bytes memory addr, ) = registry.getPegInAddress(FIXTURE_RSK);
        assertEq(addr, FIXTURE_MAINNET_ADDRESS, "derived mainnet address matches off-chain vector");
    }
}
