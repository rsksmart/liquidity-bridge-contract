// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {PegInRegistryTestBase} from "./PegInRegistryTestBase.sol";
import {PegInAddressRegistry} from "../../src/PegInAddressRegistry.sol";
import {IPegInAddressRegistry} from "../../src/interfaces/IPegInAddressRegistry.sol";
import {PegInDerivation} from "../../src/libraries/PegInDerivation.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {OpCodes} from "@rsksmart/btc-transaction-solidity-helper/contracts/OpCodes.sol";

/// @title PegInAddressRegistry derivation / fixture / init tests
contract DerivationTest is PegInRegistryTestBase {
    address internal constant FIXTURE_RSK = 0x0000000000000000000000000000000000000aBc;
    bytes internal constant FIXTURE_TESTNET_ADDRESS = hex"c453239f29b16aa66c9a5e3ec7f2b1de034fe0dea79440b320";
    bytes internal constant FIXTURE_MAINNET_ADDRESS = hex"0553239f29b16aa66c9a5e3ec7f2b1de034fe0dea72259d920";

    // R1 — deterministic derivation
    function test_derive_deterministic_same_rskAddr() public {
        _deploy(false);
        (bytes memory a1,) = registry.getPegInAddress(FIXTURE_RSK);
        (bytes memory a2,) = registry.getPegInAddress(FIXTURE_RSK);
        assertEq(a1, a2);
    }

    // R2 — distinct addresses
    function test_derive_distinct_rskAddrs() public {
        _deploy(false);
        (bytes memory a,) = registry.getPegInAddress(address(0x1111));
        (bytes memory b,) = registry.getPegInAddress(address(0x2222));
        assertTrue(keccak256(a) != keccak256(b));
    }

    // R3 — network version bytes
    function test_testnet_prefix_0xC4() public {
        _deploy(false);
        (bytes memory addr,) = registry.getPegInAddress(FIXTURE_RSK);
        assertEq(addr, FIXTURE_TESTNET_ADDRESS);
        assertEq(_addressVersionByte(addr), bytes1(0xC4));
    }

    function test_mainnet_prefix_0x05() public {
        _deploy(true);
        (bytes memory addr,) = registry.getPegInAddress(FIXTURE_RSK);
        assertEq(addr, FIXTURE_MAINNET_ADDRESS);
        assertEq(_addressVersionByte(addr), bytes1(0x05));
    }

    // R4 — unset pegInContract
    function test_revert_when_pegInContract_unset() public {
        registry = _deployUnwired(false);
        vm.expectRevert(PegInAddressRegistry.PegInContractNotSet.selector);
        registry.getPegInAddress(FIXTURE_RSK);
    }

    // R5 — isRegistered
    function test_isRegistered_false_when_unseeded() public {
        _deploy(false);
        assertFalse(registry.isRegistered(FIXTURE_RSK));
    }

    function test_isRegistered_true_when_block_set() public {
        _deploy(false);
        _seedRegistration(FIXTURE_RSK, stranger, uint96(42));
        assertTrue(registry.isRegistered(FIXTURE_RSK));
    }

    // R6 — getRegistration struct
    function test_getRegistration_returns_struct() public {
        _deploy(false);
        _seedRegistration(FIXTURE_RSK, stranger, uint96(99));
        IPegInAddressRegistry.Registration memory reg = registry.getRegistration(FIXTURE_RSK);
        assertEq(reg.registrant, stranger);
        assertEq(reg.registrationBlock, 99);
    }

    // R8 — admin-only setPegInContract
    function test_setPegInContract_admin_only() public {
        _deploy(false);
        address newPegIn = address(0xDEAD);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, stranger, registry.DEFAULT_ADMIN_ROLE()
            )
        );
        vm.prank(stranger);
        registry.setPegInContract(newPegIn);

        vm.expectEmit(true, true, true, true);
        emit PegInAddressRegistry.PegInContractSet(PEGIN_CONTRACT, newPegIn);
        vm.prank(owner);
        registry.setPegInContract(newPegIn);
    }

    // R9 — getPegInContract
    function test_getPegInContract_returns_stored() public {
        _deploy(false);
        assertEq(registry.getPegInContract(), PEGIN_CONTRACT);
    }

    // R10 — ERC-7201 namespace
    function test_storage_layout_erc7201() public pure {
        bytes32 expected =
            keccak256(abi.encode(uint256(keccak256("rsk.flyover.PegInAddressRegistry")) - 1)) & ~bytes32(uint256(0xff));
        assertEq(expected, 0x0704e3acad2c0308b9997bc861208a21efddaa710005747040bdddc7b9400f00);
    }

    // R11 — ABI artifacts exist after build (selector smoke)
    function test_abi_provenance_recorded() public {
        _deploy(false);
        assertEq(registry.VERSION(), "1.0.0");
        assertEq(registry.MAX_PEGIN_ADDRESS_BATCH(), 100);
    }

    function test_deploys_and_initializes() public {
        _deploy(false);
        assertEq(address(registry.getBridge()), address(bridge));
        assertEq(registry.getRegistrationRoot(), bytes32(0));
        assertTrue(registry.hasRole(registry.DEFAULT_ADMIN_ROLE(), owner));
    }

    function test_second_initialize_reverts() public {
        _deploy(false);
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        registry.initialize(owner, ADMIN_DELAY, address(bridge), false);
    }

    function test_encoding_is_base58() public {
        _deploy(false);
        (, IPegInAddressRegistry.Encoding enc) = registry.getPegInAddress(FIXTURE_RSK);
        assertEq(uint256(enc), uint256(IPegInAddressRegistry.Encoding.BASE58));
    }

    // Tripwire — documents the known scheme divergence flagged in Copilot review
    // r3542766572. The temporary mock PegInDerivation derives a PLAIN P2SH payload
    // (HASH160 of the flyover redeem script), while PegInContract.validatePegInDepositAddress
    // derives a nested P2SH-P2WSH payload (HASH160 of OP_0 <32-byte sha256(redeemScript)>),
    // so the two produce DIFFERENT deposit addresses. This asserts that expected
    // incompatibility. When FLY-2436 reconciles the schemes (or intentionally moves to
    // plain P2SH), this test must be revisited as an explicit cross-contract decision.
    function test_derivation_scheme_differs_from_pegin_contract() public {
        _deploy(false);
        bytes memory powpeg = bridge.getActivePowpegRedeemScript();
        bytes32 dv = PegInDerivation.derivationValue(FIXTURE_RSK, PEGIN_CONTRACT);
        bytes memory redeem = PegInDerivation.flyoverRedeemScript(dv, powpeg);

        bytes20 mockPlainP2sh = PegInDerivation.flyoverScriptHash(redeem);
        bytes memory segwitScript = bytes.concat(OpCodes.OP_0, OpCodes.OP_PUSHBYTES_32, sha256(redeem));
        bytes20 canonicalNestedP2sh = ripemd160(abi.encodePacked(sha256(segwitScript)));

        assertTrue(mockPlainP2sh != canonicalNestedP2sh);
    }
}
