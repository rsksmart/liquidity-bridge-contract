// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {RequestPegInTestBase} from "./RequestPegInTestBase.sol";
import {IPegInCommitFirst} from "../../src/interfaces/IPegInCommitFirst.sol";

/// @title Why BridgeMock has to look at the txid
/// @notice Two examples of the SAME scenario: one real deposit presented twice, once
/// witness-stripped and once witness-serialized.
///
/// BtcUtils treats those two byte strings inconsistently, and that is correct behaviour on both
/// sides:
///   - getOutputs (line 59) detects the segwit marker+flag and skips them, so it reads the SAME
///     real output from both serializations. Same amount either way.
///   - hashBtcTx (line 272) double-sha256s whatever bytes it is given, so the witness
///     serialization hashes to the WTXID, not the txid.
///
/// So the two presentations of one deposit yield two different pegInIds. On a real chain the
/// second one is dead on arrival: the bridge checks the hash against a merkle tree built from
/// txids, and a wtxid is not in it. requestPegIn therefore reverts InsufficientConfirmations.
///
/// The current BridgeMock discards the hash argument, so the test environment cannot tell the two
/// apart, and asserts behaviour that is impossible in production.
contract BridgeMockBlindSpotTest is RequestPegInTestBase {
    /// @notice A one-input, one-output SEGWIT-serialized transaction paying `pkScript`.
    /// @dev Identical to the base's _buildTx except for the 00 01 marker+flag after the version
    /// and a one-item witness stack before the locktime. Same output, so getOutputs returns the
    /// same value; different bytes, so hashBtcTx returns a different hash.
    function _buildWitnessTx(
        bytes memory pkScript,
        uint64 valueSats,
        uint256 nonce
    ) internal pure returns (bytes memory) {
        bytes memory valueLe = new bytes(8);
        uint64 v = valueSats;
        for (uint256 i = 0; i < 8; ++i) {
            valueLe[i] = bytes1(uint8(v & 0xFF));
            v >>= 8;
        }
        return
            abi.encodePacked(
                hex"01000000", // version
                hex"0001", // segwit marker + flag
                hex"01", // input count
                bytes32(nonce), // prevout txid
                hex"00000000", // prevout index
                hex"00", // empty scriptSig
                hex"ffffffff", // sequence
                hex"01", // output count
                valueLe,
                bytes1(uint8(pkScript.length)),
                pkScript,
                hex"0102ab", // witness: 1 item, 2 bytes
                hex"00000000" // locktime
            );
    }

    /// @notice Shared setup: one deposit, two serializations of it.
    function _twoSerializationsOfOneDeposit()
        internal
        view
        returns (bytes memory stripped, bytes memory witness)
    {
        bytes memory pkScript = _depositPkScript(rskUser);
        uint64 sats = _toSats(DEFAULT_AMOUNT);
        stripped = _buildTx(pkScript, sats, DEFAULT_TX_NONCE);
        witness = _buildWitnessTx(pkScript, sats, DEFAULT_TX_NONCE);
    }

    /// @notice The premise both examples rest on: same parsed output, different hash.
    function test_premise_sameOutputDifferentHash() public view {
        (
            bytes memory stripped,
            bytes memory witness
        ) = _twoSerializationsOfOneDeposit();

        assertTrue(
            this.hashTx(stripped) != this.hashTx(witness),
            "wtxid differs from txid"
        );
        assertTrue(
            _pegInIdForTx(rskUser, stripped) !=
                _pegInIdForTx(rskUser, witness),
            "so the two presentations get different pegInIds"
        );
    }

    // ------------------------------------------------------------------
    // BAD: what the current, hash-blind BridgeMock lets you assert
    // ------------------------------------------------------------------

    /// @notice Passes today. One real deposit is claimed TWICE for full value, because the mock
    /// hands out confirmations for any hash at all — including a wtxid that no merkle tree
    /// contains. The already-processed guard does not help: it is keyed on the hash, and the two
    /// presentations hash differently.
    ///
    /// A green run here means the suite is blessing a double-claim that the real bridge rejects.
    function test_BAD_hashBlindMock_letsOneDepositBeClaimedTwice() public {
        (
            bytes memory stripped,
            bytes memory witness
        ) = _twoSerializationsOfOneDeposit();
        uint256 net = DEFAULT_AMOUNT - _expectedFee(DEFAULT_AMOUNT);

        // Blanket confirmations for every hash — the current mock's only mode.
        bridgeMock.setConfirmations(int256(DEFAULT_TIER_CONFIRMATIONS));

        uint256 userBefore = rskUser.balance;

        // Claim 1: the honest, witness-stripped presentation.
        bytes32 firstId = _requestPegInTx(claimer, rskUser, stripped, net);

        // Claim 2: the SAME deposit, re-serialized with a witness. Fresh pegInId, so the
        // already-processed check waves it through, and the mock confirms the wtxid.
        bytes32 secondId = _requestPegInTx(claimer, rskUser, witness, net);

        assertTrue(firstId != secondId, "two ids for one deposit");

        (address firstClaimer, uint256 firstFronted, , ) = _readClaim(firstId);
        (address secondClaimer, uint256 secondFronted, , ) = _readClaim(
            secondId
        );
        assertEq(firstClaimer, claimer, "claim 1 written");
        assertEq(secondClaimer, claimer, "claim 2 written for the same deposit");
        assertEq(firstFronted, net, "claim 1 fronted full net");
        assertEq(secondFronted, net, "claim 2 fronted full net");

        // The user was paid twice for a single BTC deposit.
        assertEq(
            rskUser.balance,
            userBefore + (net * 2),
            "one deposit, two full deliveries"
        );
    }

    // ------------------------------------------------------------------
    // GOOD: what a txid-aware BridgeMock lets you assert
    // ------------------------------------------------------------------

    /// @notice The same scenario against a mock that only confirms hashes it was actually given,
    /// which is what a merkle proof does. The stripped presentation succeeds; the witness
    /// presentation reverts InsufficientConfirmations(0, required) — production behaviour.
    function test_GOOD_txidAwareMock_rejectsTheSecondPresentation() public {
        (
            bytes memory stripped,
            bytes memory witness
        ) = _twoSerializationsOfOneDeposit();
        uint256 net = DEFAULT_AMOUNT - _expectedFee(DEFAULT_AMOUNT);

        // Only the real txid is in the "merkle tree". Nothing else is confirmable.
        bridgeMock.setConfirmationsFor(
            this.hashTx(stripped),
            int256(DEFAULT_TIER_CONFIRMATIONS)
        );

        uint256 userBefore = rskUser.balance;

        // Claim 1 still works: this is the transaction that is really on chain.
        bytes32 firstId = _requestPegInTx(claimer, rskUser, stripped, net);
        (address firstClaimer, , , ) = _readClaim(firstId);
        assertEq(firstClaimer, claimer, "honest claim unaffected");

        // Claim 2 is now stopped where the real bridge stops it.
        vm.prank(claimer);
        vm.expectRevert(
            abi.encodeWithSelector(
                IPegInCommitFirst.InsufficientConfirmations.selector,
                0,
                DEFAULT_TIER_CONFIRMATIONS
            )
        );
        pegInContract.requestPegIn{value: net}(
            rskUser,
            witness,
            "",
            bytes32(0),
            0,
            _emptyBranch()
        );

        (address secondClaimer, , , ) = _readClaim(
            _pegInIdForTx(rskUser, witness)
        );
        assertEq(secondClaimer, address(0), "no second claim written");
        assertEq(
            rskUser.balance,
            userBefore + net,
            "one deposit, one delivery"
        );
    }

    /// @notice The broader point, independent of segwit: with a txid-aware mock, the suite can
    /// finally observe that requestPegIn asks the bridge about the hash it derived from the
    /// presented bytes. Confirm a DIFFERENT hash and the claim must still fail.
    function test_GOOD_txidAwareMock_pinsWhichHashIsProven() public {
        bytes memory btcTx = _defaultTx();
        uint256 net = DEFAULT_AMOUNT - _expectedFee(DEFAULT_AMOUNT);

        // Confirmations exist, but for an unrelated transaction.
        bridgeMock.setConfirmationsFor(
            keccak256("some other confirmed tx"),
            int256(DEFAULT_TIER_CONFIRMATIONS)
        );

        vm.prank(claimer);
        vm.expectRevert(
            abi.encodeWithSelector(
                IPegInCommitFirst.InsufficientConfirmations.selector,
                0,
                DEFAULT_TIER_CONFIRMATIONS
            )
        );
        pegInContract.requestPegIn{value: net}(
            rskUser,
            btcTx,
            "",
            bytes32(0),
            0,
            _emptyBranch()
        );
    }
}
