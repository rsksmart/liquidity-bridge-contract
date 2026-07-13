// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {PegInRegistryTestBase} from "./PegInRegistryTestBase.sol";
import {IPegInAddressRegistry} from "../../src/interfaces/IPegInAddressRegistry.sol";
import {IPauseRegistry} from "../../src/interfaces/IPauseRegistry.sol";
import {Flyover} from "../../src/libraries/Flyover.sol";
import {BtcUtils} from "@rsksmart/btc-transaction-solidity-helper/contracts/BtcUtils.sol";

/// @title PegInAddressRegistry write-path tests
contract RegisterTest is PegInRegistryTestBase {
    address internal constant FIXTURE_RSK =
        0x0000000000000000000000000000000000000aBc;
    address internal constant OTHER_RSK =
        0x0000000000000000000000000000000000000deF;

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
            _emptyHashes()
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
            _emptyHashes()
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
            _emptyHashes()
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
        bytes32[] memory hashes = _emptyHashes();
        _programProof(txBytes, BLOCK_HASH, MERKLE_PATH, hashes);
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
            hashes
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
            _emptyHashes()
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
            _emptyHashes()
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
        bytes memory txBytes = _buildDepositTx(
            _depositPkScript(FIXTURE_RSK),
            10_000
        );
        bytes32[] memory hashes = _emptyHashes();
        _programProof(txBytes, BLOCK_HASH, MERKLE_PATH, hashes);
        vm.expectEmit(true, true, true, true);
        emit IPegInAddressRegistry.AddressRegistered(
            FIXTURE_RSK,
            stranger,
            expectedRoot
        );
        vm.prank(stranger);
        registry.registerAddress(
            FIXTURE_RSK,
            txBytes,
            BLOCK_HASH,
            MERKLE_PATH,
            hashes
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
            _emptyHashes()
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
            _emptyHashes()
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
            _emptyHashes()
        );
        assertFalse(registry.isRegistered(FIXTURE_RSK));
        (, IPegInAddressRegistry.Encoding enc) = registry.getPegInAddress(
            FIXTURE_RSK
        );
        assertEq(uint256(enc), uint256(IPegInAddressRegistry.Encoding.BASE58));
    }

    // S1 — dedicated happy path: false → register → true + record + event
    function test_happy_path_isRegistered_record_and_event() public {
        _deploy(false);
        assertFalse(registry.isRegistered(FIXTURE_RSK));
        bytes32 expectedRoot = _foldRoot(bytes32(0), FIXTURE_RSK);
        bytes memory txBytes = _buildDepositTx(
            _depositPkScript(FIXTURE_RSK),
            10_000
        );
        bytes32[] memory hashes = _emptyHashes();
        _programProof(txBytes, BLOCK_HASH, MERKLE_PATH, hashes);
        vm.expectEmit(true, true, true, true);
        emit IPegInAddressRegistry.AddressRegistered(
            FIXTURE_RSK,
            stranger,
            expectedRoot
        );
        vm.prank(stranger);
        registry.registerAddress(
            FIXTURE_RSK,
            txBytes,
            BLOCK_HASH,
            MERKLE_PATH,
            hashes
        );
        assertTrue(registry.isRegistered(FIXTURE_RSK));
        IPegInAddressRegistry.Registration memory reg = registry
            .getRegistration(FIXTURE_RSK);
        assertEq(reg.registrant, stranger);
        assertEq(reg.registrationBlock, uint96(block.number));
        assertEq(registry.getRegistrationRoot(), expectedRoot);
    }

    // S2 — negative confirmations
    function test_revert_when_negative_confirmations() public {
        _deploy(false);
        bridge.setConfirmations(-1);
        bytes memory txBytes = _buildDepositTx(
            _depositPkScript(FIXTURE_RSK),
            10_000
        );
        bytes32[] memory hashes = _emptyHashes();
        _programProof(txBytes, BLOCK_HASH, MERKLE_PATH, hashes);
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
            hashes
        );
    }

    // S3 — write path with unset pegInContract
    function test_revert_register_when_pegInContract_unset() public {
        registry = _deployUnwired(false);
        bytes memory txBytes = _buildDepositTx(
            hex"a914111111111111111111111111111111111111111187",
            10_000
        );
        vm.expectRevert(IPegInAddressRegistry.PegInContractNotSet.selector);
        registry.registerAddress(
            FIXTURE_RSK,
            txBytes,
            BLOCK_HASH,
            MERKLE_PATH,
            _emptyHashes()
        );
    }

    // S4 — explicit non-owner/non-admin caller
    function test_permissionless_caller_registers() public {
        _deploy(false);
        address watchtower = address(0xBEEF);
        assertTrue(watchtower != owner);
        assertFalse(
            registry.hasRole(registry.DEFAULT_ADMIN_ROLE(), watchtower)
        );
        assertFalse(pauseRegistry.hasRole(pauseRegistry.PAUSER_ROLE(), watchtower));
        _register(FIXTURE_RSK, 10_000, watchtower);
        assertTrue(registry.isRegistered(FIXTURE_RSK));
        IPegInAddressRegistry.Registration memory reg = registry
            .getRegistration(FIXTURE_RSK);
        assertEq(reg.registrant, watchtower);
    }

    // S7 — programmed-proof identity mismatch with confs >= 1
    function test_revert_when_proof_identity_mismatches() public {
        _deploy(false);
        bridge.setConfirmations(6);
        bytes memory txBytes = _buildDepositTx(
            _depositPkScript(FIXTURE_RSK),
            10_000
        );
        bytes32[] memory hashes = _emptyHashes();
        bytes32 realTxHash = BtcUtils.hashBtcTx(txBytes);
        // Program a different txHash than the one the registry will pass.
        bridge.setExpectedProof(
            bytes32(uint256(0xDEAD)),
            BLOCK_HASH,
            MERKLE_PATH,
            hashes
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                IPegInAddressRegistry.DepositNotConfirmed.selector,
                realTxHash
            )
        );
        registry.registerAddress(
            FIXTURE_RSK,
            txBytes,
            BLOCK_HASH,
            MERKLE_PATH,
            hashes
        );
    }

    // S8 — zero tx/block hash rejected by mock (no stored confs)
    function test_mock_rejects_zero_tx_or_block_hash() public {
        _deploy(false);
        bridge.setConfirmations(6);
        bytes memory txBytes = _buildDepositTx(
            _depositPkScript(FIXTURE_RSK),
            10_000
        );
        bytes32[] memory hashes = _emptyHashes();
        bytes32 txHash = BtcUtils.hashBtcTx(txBytes);
        _programProof(txBytes, BLOCK_HASH, MERKLE_PATH, hashes);

        assertEq(
            bridge.getBtcTransactionConfirmations(
                bytes32(0),
                BLOCK_HASH,
                MERKLE_PATH,
                hashes
            ),
            -1
        );
        assertEq(
            bridge.getBtcTransactionConfirmations(
                txHash,
                bytes32(0),
                MERKLE_PATH,
                hashes
            ),
            -1
        );
        assertEq(
            bridge.getBtcTransactionConfirmations(
                txHash,
                BLOCK_HASH,
                MERKLE_PATH,
                hashes
            ),
            6
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                IPegInAddressRegistry.DepositNotConfirmed.selector,
                txHash
            )
        );
        registry.registerAddress(
            FIXTURE_RSK,
            txBytes,
            bytes32(0),
            MERKLE_PATH,
            hashes
        );
    }
}
