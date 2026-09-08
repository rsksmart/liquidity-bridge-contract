// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {RequestPegInTestBase} from "./RequestPegInTestBase.sol";
import {IPegInCommitFirst} from "../../src/interfaces/IPegInCommitFirst.sol";
import {IBridge} from "../../src/interfaces/IBridge.sol";
import {BtcTransactionReader} from "../../src/libraries/BtcTransactionReader.sol";

/// @title One deposit, two serializations
/// @notice A segwit deposit has two legal serializations (BIP144), and BtcUtils treats them
/// inconsistently — correctly, on both sides:
///   - getOutputs detects the segwit marker+flag and skips it, so it reads the SAME real output
///     from both serializations. Same amount either way.
///   - hashBtcTx double-sha256s whatever bytes it is given, so the witness serialization hashes to
///     the WTXID, not the txid.
///
/// So the two presentations of one deposit yield two different pegInIds, and the already-processed
/// guard — keyed on the hash — waves the second one through.
///
/// `requestPegIn` now rejects the witness serialization at its own boundary, before hashing. The
/// real bridge would also reject it (a wtxid is not in a merkle tree built from txids), but that is
/// a collaborator we do not own, so these tests assert OUR revert and prove the bridge is never
/// reached. The txid-aware BridgeMock stays: without it the suite still cannot see WHICH hash the
/// contract asks the bridge about, which is a separate blind spot and the last test here.
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

    /// @notice The premise the whole suite rests on: same parsed output, different hash.
    /// @dev Tests raw hashing, not the entry point, so the new guard does not apply here.
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
            _pegInIdForTx(rskUser, stripped) != _pegInIdForTx(rskUser, witness),
            "so the two presentations get different pegInIds"
        );
    }

    // ------------------------------------------------------------------
    // The double-claim, stopped at our boundary
    // ------------------------------------------------------------------

    /// @notice The exploit this guard exists for, run in the WEAKEST environment: a hash-blind
    /// bridge that hands out confirmations for any hash at all, including a wtxid no merkle tree
    /// contains. Before the guard this test claimed one deposit twice for full value. Now the
    /// second presentation never gets far enough to be confirmed by anything.
    function test_hashBlindMock_cannotClaimOneDepositTwice() public {
        (
            bytes memory stripped,
            bytes memory witness
        ) = _twoSerializationsOfOneDeposit();
        uint256 net = DEFAULT_AMOUNT - _expectedFee(DEFAULT_AMOUNT);

        // Blanket confirmations for every hash — the mock's weakest mode, and the one that used to
        // let the wtxid through.
        bridgeMock.setConfirmations(int256(DEFAULT_TIER_CONFIRMATIONS));

        uint256 userBefore = rskUser.balance;

        // Claim 1: the honest, witness-stripped presentation.
        bytes32 firstId = _requestPegInTx(claimer, rskUser, stripped, net);
        (address firstClaimer, uint256 firstFronted, , ) = _readClaim(firstId);
        assertEq(firstClaimer, claimer, "claim 1 written");
        assertEq(firstFronted, net, "claim 1 fronted full net");

        // Claim 2: the SAME deposit, re-serialized with a witness. Rejected by us, not by the
        // bridge, and not by the already-processed guard (which cannot see it — different hash).
        vm.prank(claimer);
        vm.expectRevert(
            BtcTransactionReader.WitnessSerializedTxNotAccepted.selector
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

    /// @notice Rejection is ours, and it lands before the bridge is consulted at all.
    /// @dev Both bridge reads on the claim path are asserted absent: the powpeg script
    /// `_readPegInAmount` derives against, and the confirmation lookup after it.
    function test_witnessTx_rejectedBeforeAnyBridgeCall() public {
        (, bytes memory witness) = _twoSerializationsOfOneDeposit();
        uint256 net = DEFAULT_AMOUNT - _expectedFee(DEFAULT_AMOUNT);

        bridgeMock.setConfirmations(int256(DEFAULT_TIER_CONFIRMATIONS));

        vm.expectCall(
            address(bridgeMock),
            abi.encodeWithSelector(
                IBridge.getActivePowpegRedeemScript.selector
            ),
            0
        );
        vm.expectCall(
            address(bridgeMock),
            abi.encodeWithSelector(
                IBridge.getBtcTransactionConfirmations.selector
            ),
            0
        );

        vm.prank(claimer);
        vm.expectRevert(
            BtcTransactionReader.WitnessSerializedTxNotAccepted.selector
        );
        pegInContract.requestPegIn{value: net}(
            rskUser,
            witness,
            "",
            bytes32(0),
            0,
            _emptyBranch()
        );
    }

    /// @notice The witness-stripped presentation of the very same deposit still succeeds. The
    /// guard discriminates on serialization, not on the deposit.
    function test_strippedPresentationOfTheSameDepositStillSucceeds() public {
        (bytes memory stripped, ) = _twoSerializationsOfOneDeposit();
        uint256 net = DEFAULT_AMOUNT - _expectedFee(DEFAULT_AMOUNT);

        bridgeMock.setConfirmationsFor(
            this.hashTx(stripped),
            int256(DEFAULT_TIER_CONFIRMATIONS)
        );

        uint256 userBefore = rskUser.balance;
        bytes32 pegInId = _requestPegInTx(claimer, rskUser, stripped, net);

        (address writtenClaimer, uint256 fronted, , ) = _readClaim(pegInId);
        assertEq(writtenClaimer, claimer, "honest claim written");
        assertEq(fronted, net, "fronted full net");
        assertEq(rskUser.balance, userBefore + net, "user delivered once");
    }

    /// @notice A truncated transaction reverts with a reason, not an out-of-bounds panic.
    /// @dev Five bytes is one short of the marker+flag the guard reads.
    function test_txShorterThanSixBytes_revertsInvalidBtcTransaction() public {
        uint256 net = DEFAULT_AMOUNT - _expectedFee(DEFAULT_AMOUNT);

        vm.prank(claimer);
        vm.expectRevert(BtcTransactionReader.InvalidBtcTransaction.selector);
        pegInContract.requestPegIn{value: net}(
            rskUser,
            hex"0100000001",
            "",
            bytes32(0),
            0,
            _emptyBranch()
        );
    }

    /// @notice Negative control: a LEGACY transaction whose sixth byte happens to be 0x01 is not
    /// mistaken for a witness serialization.
    /// @dev The prevout txid begins at offset 5, so a nonce whose most-significant byte is 0x01
    /// puts 0x01 there. What keeps the guard exact is offset 4 — the input-count compactSize, 0x01
    /// here and never 0x00 in a valid transaction. A check that looked at the wrong offset, or at
    /// only one of the two bytes, would reject this deposit.
    function test_legacyTxWithLeading01Outpoint_isNotRejected() public {
        uint256 nonce = 1 << 248; // bytes32(nonce)[0] == 0x01
        bytes memory btcTx = _depositTx(rskUser, DEFAULT_AMOUNT, nonce);
        assertEq(btcTx[4], bytes1(0x01), "input count sits at offset 4");
        assertEq(btcTx[5], bytes1(0x01), "and the outpoint starts with 0x01");

        uint256 net = DEFAULT_AMOUNT - _expectedFee(DEFAULT_AMOUNT);
        bridgeMock.setConfirmationsFor(
            this.hashTx(btcTx),
            int256(DEFAULT_TIER_CONFIRMATIONS)
        );

        bytes32 pegInId = _requestPegInTx(claimer, rskUser, btcTx, net);
        (address writtenClaimer, , , ) = _readClaim(pegInId);
        assertEq(writtenClaimer, claimer, "legacy deposit claimed normally");
    }

    // ------------------------------------------------------------------
    // The other blind spot the txid-aware mock closed
    // ------------------------------------------------------------------

    /// @notice Independent of segwit: with a txid-aware mock the suite can observe that
    /// requestPegIn asks the bridge about the hash it derived from the presented bytes. Confirm a
    /// DIFFERENT hash and the claim must still fail.
    /// @dev This one is a legacy transaction and MUST reach the bridge — the rejection under test
    /// is the bridge's, and that is the point. Only witness-serialized bytes are stopped earlier.
    function test_txidAwareMock_pinsWhichHashIsProven() public {
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
