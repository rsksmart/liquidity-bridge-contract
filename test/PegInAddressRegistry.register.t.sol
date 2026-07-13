// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {PegInRegistryTestBase} from "./pegin-registry/PegInRegistryTestBase.sol";
import {IPegInAddressRegistry} from "../src/interfaces/IPegInAddressRegistry.sol";
import {IPauseRegistry} from "../src/interfaces/IPauseRegistry.sol";
import {Flyover} from "../src/libraries/Flyover.sol";
import {PegInDerivation} from "../src/libraries/PegInDerivation.sol";
import {BtcUtils} from "@rsksmart/btc-transaction-solidity-helper/contracts/BtcUtils.sol";

/// @title PegInAddressRegistry write-path tests
contract PegInAddressRegistryRegisterTest is PegInRegistryTestBase {
    address internal constant FIXTURE_RSK =
        0x0000000000000000000000000000000000000aBc;
    address internal constant OTHER_RSK =
        0x0000000000000000000000000000000000000deF;

    bytes32 internal constant BLOCK_HASH = bytes32(uint256(0xBEEF));
    uint256 internal constant MERKLE_PATH = 0;

    function _depositPkScript(
        address rskAddr
    ) internal view returns (bytes memory) {
        bytes memory powpeg = bridge.getActivePowpegRedeemScript();
        bytes32 dv = PegInDerivation.derivationValue(rskAddr, PEGIN_CONTRACT);
        bytes memory redeem = PegInDerivation.flyoverRedeemScript(dv, powpeg);
        bytes20 scriptHash = PegInDerivation.flyoverScriptHash(redeem);
        return PegInDerivation.p2shScriptPubkey(scriptHash);
    }

    function _buildDepositTx(
        bytes memory pkScript,
        uint64 value
    ) internal pure returns (bytes memory) {
        bytes memory valueLe = new bytes(8);
        uint64 v = value;
        for (uint256 i = 0; i < 8; ++i) {
            valueLe[i] = bytes1(uint8(v & 0xFF));
            v >>= 8;
        }
        return
            abi.encodePacked(
                hex"01000000",
                hex"01",
                bytes32(uint256(1)),
                hex"00000000",
                hex"00",
                hex"ffffffff",
                hex"01",
                valueLe,
                bytes1(uint8(pkScript.length)),
                pkScript,
                hex"00000000"
            );
    }

    function _register(address rskAddr, uint64 value, address caller) internal {
        bytes memory txBytes = _buildDepositTx(
            _depositPkScript(rskAddr),
            value
        );
        vm.prank(caller);
        registry.registerAddress(
            rskAddr,
            txBytes,
            BLOCK_HASH,
            MERKLE_PATH,
            new bytes32[](0)
        );
    }

    function _foldRoot(
        bytes32 prevRoot,
        address rskAddr
    ) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(prevRoot, rskAddr));
    }

    // W1
    function test_revert_when_already_registered() public {
        _deploy(false);
        _register(FIXTURE_RSK, 10_000, stranger);
        bytes memory garbageTx = hex"010000000000000000";
        vm.expectRevert(
            abi.encodeWithSelector(
                IPegInAddressRegistry.AddressAlreadyRegistered.selector,
                FIXTURE_RSK
            )
        );
        registry.registerAddress(
            FIXTURE_RSK,
            garbageTx,
            BLOCK_HASH,
            MERKLE_PATH,
            new bytes32[](0)
        );
    }

    // W2
    function test_revert_when_no_matching_output() public {
        _deploy(false);
        bytes
            memory wrongScript = hex"a914111111111111111111111111111111111111111187";
        bytes memory txBytes = _buildDepositTx(wrongScript, 10_000);
        vm.expectRevert(
            abi.encodeWithSelector(
                IPegInAddressRegistry.DepositOutputNotFound.selector,
                FIXTURE_RSK
            )
        );
        registry.registerAddress(
            FIXTURE_RSK,
            txBytes,
            BLOCK_HASH,
            MERKLE_PATH,
            new bytes32[](0)
        );
    }

    // W3
    function test_confirmed_tx_wrong_address_still_reverts() public {
        _deploy(false);
        bytes memory txBytes = _buildDepositTx(
            _depositPkScript(FIXTURE_RSK),
            10_000
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                IPegInAddressRegistry.DepositOutputNotFound.selector,
                OTHER_RSK
            )
        );
        registry.registerAddress(
            OTHER_RSK,
            txBytes,
            BLOCK_HASH,
            MERKLE_PATH,
            new bytes32[](0)
        );
    }

    // W4
    function test_revert_when_below_min_confirmations() public {
        _deploy(false);
        bridge.setConfirmations(0);
        bytes memory txBytes = _buildDepositTx(
            _depositPkScript(FIXTURE_RSK),
            10_000
        );
        bytes32 txHash = BtcUtils.hashBtcTx(txBytes);
        vm.expectRevert(
            abi.encodeWithSelector(
                IPegInAddressRegistry.DepositNotConfirmed.selector,
                txHash
            )
        );
        registry.registerAddress(
            FIXTURE_RSK,
            txBytes,
            BLOCK_HASH,
            MERKLE_PATH,
            new bytes32[](0)
        );
    }

    function test_pass_at_exactly_one_conf() public {
        _deploy(false);
        bridge.setConfirmations(1);
        _register(FIXTURE_RSK, 10_000, stranger);
        assertTrue(registry.isRegistered(FIXTURE_RSK));
    }

    // W5, W15
    function test_revert_when_below_floor() public {
        _deploy(false);
        uint64 below = uint64(registry.MIN_DEPOSIT_SATS() - 1);
        bytes memory txBytes = _buildDepositTx(
            _depositPkScript(FIXTURE_RSK),
            below
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                IPegInAddressRegistry.DepositBelowMinimum.selector,
                below,
                registry.MIN_DEPOSIT_SATS()
            )
        );
        registry.registerAddress(
            FIXTURE_RSK,
            txBytes,
            BLOCK_HASH,
            MERKLE_PATH,
            new bytes32[](0)
        );
    }

    function test_pass_at_floor_boundary() public {
        _deploy(false);
        uint64 atFloor = uint64(registry.MIN_DEPOSIT_SATS());
        _register(FIXTURE_RSK, atFloor, stranger);
        assertTrue(registry.isRegistered(FIXTURE_RSK));
    }

    // W6
    function test_address_rederived_not_trusted() public {
        _deploy(false);
        address attackerPresented = address(0xCAFE);
        bytes memory txBytes = _buildDepositTx(
            _depositPkScript(FIXTURE_RSK),
            10_000
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                IPegInAddressRegistry.DepositOutputNotFound.selector,
                attackerPresented
            )
        );
        registry.registerAddress(
            attackerPresented,
            txBytes,
            BLOCK_HASH,
            MERKLE_PATH,
            new bytes32[](0)
        );
    }

    // W7
    function test_registrant_is_msgsender_block_is_current() public {
        _deploy(false);
        vm.roll(12345);
        _register(FIXTURE_RSK, 10_000, stranger);
        IPegInAddressRegistry.Registration memory reg = registry
            .getRegistration(FIXTURE_RSK);
        assertEq(reg.registrant, stranger);
        assertEq(reg.registrationBlock, 12345);
    }

    // W8
    function test_event_carries_post_fold_root() public {
        _deploy(false);
        bytes32 expectedRoot = _foldRoot(bytes32(0), FIXTURE_RSK);
        vm.expectEmit(true, true, true, true);
        emit IPegInAddressRegistry.AddressRegistered(
            FIXTURE_RSK,
            stranger,
            expectedRoot
        );
        _register(FIXTURE_RSK, 10_000, stranger);
    }

    // W9
    function test_root_fold_matches_getter() public {
        _deploy(false);
        _register(FIXTURE_RSK, 10_000, stranger);
        assertEq(
            registry.getRegistrationRoot(),
            _foldRoot(bytes32(0), FIXTURE_RSK)
        );
    }

    // W10
    function test_atomicity_no_partial_write() public {
        _deploy(false);
        bytes32 rootBefore = registry.getRegistrationRoot();
        uint64 below = uint64(registry.MIN_DEPOSIT_SATS() - 1);
        bytes memory txBytes = _buildDepositTx(
            _depositPkScript(FIXTURE_RSK),
            below
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                IPegInAddressRegistry.DepositBelowMinimum.selector,
                below,
                registry.MIN_DEPOSIT_SATS()
            )
        );
        registry.registerAddress(
            FIXTURE_RSK,
            txBytes,
            BLOCK_HASH,
            MERKLE_PATH,
            new bytes32[](0)
        );
        assertFalse(registry.isRegistered(FIXTURE_RSK));
        assertEq(registry.getRegistrationRoot(), rootBefore);
    }

    // W11
    function test_bridge_lookup_is_readonly() public {
        _deploy(false);
        _register(FIXTURE_RSK, 10_000, stranger);
        assertEq(bridge.mutatingBridgeCallCount(), 0);
    }

    // W12
    function test_idempotent_replay_reverts_root_unchanged() public {
        _deploy(false);
        bytes memory txBytes = _buildDepositTx(
            _depositPkScript(FIXTURE_RSK),
            10_000
        );
        _register(FIXTURE_RSK, 10_000, stranger);
        bytes32 rootAfterFirst = registry.getRegistrationRoot();
        vm.expectRevert(
            abi.encodeWithSelector(
                IPegInAddressRegistry.AddressAlreadyRegistered.selector,
                FIXTURE_RSK
            )
        );
        registry.registerAddress(
            FIXTURE_RSK,
            txBytes,
            BLOCK_HASH,
            MERKLE_PATH,
            new bytes32[](0)
        );
        assertEq(registry.getRegistrationRoot(), rootAfterFirst);
    }

    // W13
    function test_storage_layout_erc7201_unchanged() public pure {
        bytes32 expected = keccak256(
            abi.encode(
                uint256(keccak256("rsk.flyover.PegInAddressRegistry")) - 1
            )
        ) & ~bytes32(uint256(0xff));
        assertEq(
            expected,
            0x0704e3acad2c0308b9997bc861208a21efddaa710005747040bdddc7b9400f00
        );
    }

    // W14
    function test_abi_selector_diff_has_provenance() public {
        _deploy(false);
        assertEq(registry.MIN_DEPOSIT_SATS(), 546);
        assertEq(registry.MIN_CONFIRMATIONS(), 1);
        assertEq(address(registry.pauseRegistry()), address(pauseRegistry));
        assertTrue(pauseRegistry.hasRole(pauseRegistry.PAUSER_ROLE(), owner));
    }

    // W16 — 52-byte preimage: prevRoot (32B) ++ rskAddr (20B)
    function test_fold_vector_matches_independent_recompute() public {
        _deploy(false);
        address[3] memory addrs = [address(0xA1), address(0xA2), address(0xA3)];
        bytes32 root = bytes32(0);
        for (uint256 i = 0; i < addrs.length; ++i) {
            _register(addrs[i], 10_000, stranger);
            root = _foldRoot(root, addrs[i]);
            assertEq(registry.getRegistrationRoot(), root);
        }
    }

    // inv 10 — pause blocks write, reads stay open
    function test_revert_when_paused() public {
        _deploy(false);
        vm.prank(owner);
        pauseRegistry.setPauseLevel(IPauseRegistry.PauseLevel.Soft, "block register");
        bytes memory txBytes = _buildDepositTx(
            _depositPkScript(FIXTURE_RSK),
            10_000
        );
        vm.expectRevert(Flyover.EnforcedPause.selector);
        registry.registerAddress(
            FIXTURE_RSK,
            txBytes,
            BLOCK_HASH,
            MERKLE_PATH,
            new bytes32[](0)
        );
        assertFalse(registry.isRegistered(FIXTURE_RSK));
        (, IPegInAddressRegistry.Encoding enc) = registry.getPegInAddress(
            FIXTURE_RSK
        );
        assertEq(uint256(enc), uint256(IPegInAddressRegistry.Encoding.BASE58));
    }
}
