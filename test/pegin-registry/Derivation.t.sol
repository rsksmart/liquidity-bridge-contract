// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {PegInRegistryTestBase} from "./PegInRegistryTestBase.sol";
import {PegInAddressRegistry} from "../../src/PegInAddressRegistry.sol";
import {IPegInAddressRegistry} from "../../src/interfaces/IPegInAddressRegistry.sol";

/// @title Derivation tests (E2.2)
/// @notice Determinism, distinctness, a reverts-until-wired guard, and a fixed off-chain fixture
/// vector for the BRIDGE-COMPATIBLE plain-P2SH scheme (EB.1).
contract DerivationTest is PegInRegistryTestBase {
    // Off-chain vector for rskAddr = 0x0000000000000000000000000000000000000abc against the default
    // RegistryBridgeMock redeem script and PEGIN_CONTRACT, computed with the bridge-compatible scheme:
    //   argsHash = keccak256("FLYOVER_PEGIN_V1" ++ rskAddr)
    //   dv       = keccak256(argsHash ++ REFUND_PLACEHOLDER ++ bytes20(PEGIN_CONTRACT) ++ LP_PLACEHOLDER)
    //   flyover  = 0x20 <dv> 0x75 <redeemScript>
    //   address  = base58check( version ++ HASH160(flyover) )   (PLAIN P2SH)
    address internal constant FIXTURE_RSK = 0x0000000000000000000000000000000000000aBc;
    bytes internal constant FIXTURE_TESTNET_ADDRESS =
        hex"c453239f29b16aa66c9a5e3ec7f2b1de034fe0dea79440b320";
    bytes internal constant FIXTURE_MAINNET_ADDRESS =
        hex"0553239f29b16aa66c9a5e3ec7f2b1de034fe0dea72259d920";

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

    function test_RevertsUntilPegInContractWired() public {
        // Deploy WITHOUT wiring the PegInContract: the derivation must revert clearly.
        registry = _deployUnwired(false);
        vm.expectRevert(PegInAddressRegistry.PegInContractNotSet.selector);
        registry.getPegInAddress(FIXTURE_RSK);
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
