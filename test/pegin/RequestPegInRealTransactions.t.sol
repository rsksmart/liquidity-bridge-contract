// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {RequestPegInTestBase} from "./RequestPegInTestBase.sol";
import {IPegInCommitFirst} from "../../src/interfaces/IPegInCommitFirst.sol";
import {Flyover} from "../../src/libraries/Flyover.sol";

/// @title requestPegIn against real Bitcoin transactions
/// @notice The other requestPegIn suites build their deposits with `_buildTx`: one input, an empty
/// scriptSig, one output, a nonce where the prevout txid goes. That shape is convenient and it is
/// nothing like a transaction off the chain. It cannot fail the way a real one can — several
/// inputs each carrying a ~110-byte scriptSig, the deposit sitting at output 1 or 2 behind a change
/// output, an OP_RETURN alongside it, values that are not round numbers, and length prefixes for
/// all of it that the output walk has to step over correctly.
///
/// So this suite claims against real transactions, taken from fixtures already in this repo:
/// - Two real Bitcoin transactions that the legacy `registerPegIn` tests use as Flyover peg-in
///   deposits ([test/legacy/PegIn.t.sol]). Both spend P2SH-wrapped-segwit inputs and pay P2SH
///   outputs — the same output type a commit-first deposit address is — so their shape is the
///   closest thing available to the transaction this contract will be handed in production.
/// - A real P2PKH transaction carrying a 64-byte OP_RETURN payload, from
///   [test/libraries/BtcUtils.t.sol].
///
/// All three are canonically serialized (no segwit marker), so the txid `BtcUtils.hashBtcTx`
/// returns is the real one — pinned below, and asserted, so a corrupted paste fails loudly
/// instead of quietly testing a transaction that never existed.
///
/// Used two ways. As-is they pay nobody this protocol derives, which is the attacker's "any
/// confirmed txid off the chain" — the case the DoS depended on. Spliced, one output's
/// scriptPubkey is swapped for the derived deposit script and every other byte is left alone,
/// which puts a real deposit inside a real transaction and asserts the amount read back is that
/// output's real value.
contract RequestPegInRealTransactionsTest is RequestPegInTestBase {
    // ---- real transaction 1: mainnet Flyover deposit, 2 inputs, 2 P2SH outputs ----

    bytes32 private constant _TXID_2IN =
        0xde221070e8b4896c5542159fd12a139f7b1d378f4a8d04dd1b94ac8fb99cb834;
    bytes private constant _SCRIPT_2IN_OUT0 =
        hex"a9149fa51efd2954990e4974e7b13468fb8be54512d887";
    bytes private constant _SCRIPT_2IN_OUT1 =
        hex"a914b979999438ade0fdd2cf303fca55ea29aec2392b87";
    uint64 private constant _SATS_2IN_OUT0 = 530_135;
    uint64 private constant _SATS_2IN_OUT1 = 468_269;

    // ---- real transaction 2: mainnet Flyover deposit, 1 input, 2 P2SH outputs ----

    bytes32 private constant _TXID_1IN =
        0xca62143692e4bde275a7c185678e08341ca783dcd258a78cf00182a31b051e9a;
    bytes private constant _SCRIPT_1IN_OUT0 =
        hex"a9141b67149e474f0d7757181f4db89257f27a64738387";
    uint64 private constant _SATS_1IN_OUT0 = 810_134;

    // ---- real transaction 3: P2PKH plus a 64-byte OP_RETURN ----

    bytes32 private constant _TXID_OP_RETURN =
        0x03c4522ef958f724a7d2ffef04bd534d9eca74ffc0b28308797d2853bc323ba6;
    bytes private constant _SCRIPT_OP_RETURN_OUT0 =
        hex"76a9143c5f66fe733e0ad361805b3053f23212e5755c8d88ac";
    uint64 private constant _SATS_OP_RETURN_OUT0 = 60_000_000;

    /// @notice Real transaction: 2 inputs with P2SH-wrapped-segwit scriptSigs, 2 P2SH outputs of
    /// 530135 and 468269 satoshis.
    function _realDeposit2In() private pure returns (bytes memory) {
        return
            hex"020000000212bebc8ba671aa9af2e3984af89366b5594ed115dbbaef64a41e8650cd4a53ea00"
            hex"00000017160014fe7b123124c87300e8ba30f0e2eafdd8e1f2b337ffffffff046d8f4e5fa8"
            hex"d6cc5fa23c50640249461b646e8a4722c9cfbfbff00c049d559f0000000017160014fe7b12"
            hex"3124c87300e8ba30f0e2eafdd8e1f2b337ffffffff02d71608000000000017a9149fa51efd"
            hex"2954990e4974e7b13468fb8be54512d8872d2507000000000017a914b979999438ade0fdd2"
            hex"cf303fca55ea29aec2392b8700000000";
    }

    /// @notice Real transaction: 1 input, 2 P2SH outputs of 810134 and 88850 satoshis.
    function _realDeposit1In() private pure returns (bytes memory) {
        return
            hex"010000000148e9e71dafee5a901be4eceb5aca361c083481b70496f4e3da71e5d969add182"
            hex"0000000017160014b88ef07cd7bcc022b6d73c4764ce5db0887d5b05ffffffff02965c0c00"
            hex"0000000017a9141b67149e474f0d7757181f4db89257f27a64738387125b01000000000017"
            hex"a914785c3e807e54dc41251d6377da0673123fa87bc88700000000";
    }

    /// @notice Real transaction: 1 input with a 106-byte scriptSig, a 0.6 BTC P2PKH output and a
    /// zero-value 64-byte OP_RETURN.
    function _realP2pkhWithOpReturn() private pure returns (bytes memory) {
        return
            hex"0100000001013503c427ba46058d2d8ac9221a2f6fd50734a69f19dae65420191e3ada2d40"
            hex"000000006a47304402205d047dbd8c49aea5bd0400b85a57b2da7e139cec632fb138b7bee1"
            hex"d382fd70ca02201aa529f59b4f66fdf86b0728937a91a40962aedd3f6e30bce5208fec0464"
            hex"d54901210255507b238c6f14735a7abe96a635058da47b05b61737a610bef757f009eea2a4"
            hex"ffffffff0200879303000000001976a9143c5f66fe733e0ad361805b3053f23212e5755c8d"
            hex"88ac0000000000000000426a4039383439343464353830393231353663356131396439363562"
            hex"39613735383530326536646263326439353337333135656266343839373336333134656233"
            hex"343700000000";
    }

    // ---- fixture integrity ----

    /// @notice Pins each fixture to the txid its bytes really hash to. If a fixture is ever
    /// truncated or mis-pasted, this fails here rather than turning the suite below into a test of
    /// some transaction that does not exist.
    function test_realTx_hashToTheirPinnedTxids() public view {
        assertEq(
            this.hashTx(_realDeposit2In()),
            _TXID_2IN,
            "2-input Flyover deposit txid"
        );
        assertEq(
            this.hashTx(_realDeposit1In()),
            _TXID_1IN,
            "1-input Flyover deposit txid"
        );
        assertEq(
            this.hashTx(_realP2pkhWithOpReturn()),
            _TXID_OP_RETURN,
            "P2PKH-with-OP_RETURN txid"
        );
    }

    // ---- real transactions that pay nobody we derive ----

    /// @notice A real Flyover deposit, but derived under the legacy quote flow for someone else.
    /// It is confirmed, it pays real P2SH outputs, and it must still be refused: no output pays
    /// the address derived for rskAddr. This is the shape of the original attack, with a txid that
    /// is genuinely on chain rather than one built for the test.
    function test_realTx_flyoverDepositForSomeoneElse_reverts() public {
        _assertRealTxIsRefused(_realDeposit2In(), _TXID_2IN);
    }

    function test_realTx_singleInputFlyoverDeposit_reverts() public {
        _assertRealTxIsRefused(_realDeposit1In(), _TXID_1IN);
    }

    /// @notice A real transaction with no P2SH output at all: the output walk has to step over a
    /// 25-byte P2PKH script and a 66-byte OP_RETURN and report no match, not misread either as a
    /// deposit.
    function test_realTx_p2pkhWithOpReturn_reverts() public {
        _assertRealTxIsRefused(_realP2pkhWithOpReturn(), _TXID_OP_RETURN);
    }

    // ---- real transactions carrying a real deposit ----

    /// @notice Deposit at output 0 of a 2-input transaction, with a real P2SH change output behind
    /// it. The amount read is that output's real value, 530135 satoshis, not the fixture's round
    /// 5 ether.
    function test_realTx_depositAtFirstOutput_readsThatOutputsValue() public {
        _assertReadsAmount(
            _payToDepositInstead(_realDeposit2In(), _SCRIPT_2IN_OUT0),
            _SATS_2IN_OUT0
        );
    }

    /// @notice Deposit at output 1, behind a real 23-byte P2SH output the walk has to step over
    /// first. The synthetic fixtures always put the deposit at output 0, so this is the first
    /// assertion that a non-zero output index is read correctly at all.
    function test_realTx_depositAtSecondOutput_readsThatOutputsValue() public {
        _assertReadsAmount(
            _payToDepositInstead(_realDeposit2In(), _SCRIPT_2IN_OUT1),
            _SATS_2IN_OUT1
        );
    }

    function test_realTx_depositInSingleInputTransaction_readsThatOutputsValue()
        public
    {
        _assertReadsAmount(
            _payToDepositInstead(_realDeposit1In(), _SCRIPT_1IN_OUT0),
            _SATS_1IN_OUT0
        );
    }

    /// @notice Deposit alongside a real OP_RETURN. Also the one case where the spliced script is
    /// SHORTER than the one it replaces (23 bytes over a 25-byte P2PKH), so the output that
    /// follows shifts and the walk has to find it from the rewritten length prefix.
    function test_realTx_depositBesideRealOpReturn_readsTheDepositValue()
        public
    {
        _assertReadsAmount(
            _payToDepositInstead(
                _realP2pkhWithOpReturn(),
                _SCRIPT_OP_RETURN_OUT0
            ),
            _SATS_OP_RETURN_OUT0
        );
    }

    /// @notice Both outputs of a real transaction pay the derived deposit address. Today the
    /// amount is output 0's value alone (530135 sats), NOT the 998404 the two sum to.
    ///
    /// This is the open question {BtcTransactionReader-findFirstOutputPaying} records, pinned so it
    /// cannot change silently: if first-match ever becomes sum, this test fails and forces the
    /// registry — which reads the same helper as a minimum-deposit gate — to be moved in the same
    /// change. A user whose wallet splits a deposit across two outputs to the same address is
    /// currently credited only the first.
    function test_realTx_twoOutputsPayTheDeposit_readsOnlyTheFirst() public {
        bytes memory spliced = _payToDepositInstead(
            _payToDepositInstead(_realDeposit2In(), _SCRIPT_2IN_OUT0),
            _SCRIPT_2IN_OUT1
        );

        assertEq(
            uint256(_SATS_2IN_OUT0) + uint256(_SATS_2IN_OUT1),
            998_404,
            "fixture self-check: the two outputs sum to 998404 sats"
        );
        _assertReadsAmount(spliced, _SATS_2IN_OUT0);
    }

    // ---- assertions ----

    /// @notice Claims `realTx` for rskUser and asserts it is refused for having no output that
    /// pays the derived deposit address, under its real txid.
    function _assertRealTxIsRefused(
        bytes memory realTx,
        bytes32 expectedTxid
    ) private {
        bytes32 pegInId = _pegInId(rskUser, expectedTxid);
        uint256 userBefore = rskUser.balance;

        vm.prank(claimer);
        vm.expectRevert(
            abi.encodeWithSelector(
                IPegInCommitFirst.DepositOutputNotFound.selector,
                rskUser,
                expectedTxid
            )
        );
        pegInContract.requestPegIn{value: 1 wei}(
            rskUser,
            realTx,
            "",
            bytes32(0),
            0,
            _emptyBranch()
        );

        _assertNoClaim(pegInId);
        assertEq(
            rskUser.balance,
            userBefore,
            "no delivery on a transaction that pays us nothing"
        );
    }

    /// @notice Claims `btcTx` and asserts the amount the contract read is `expectedSats` scaled to
    /// wei, by requiring the event to carry it and the fronting equality to hold against it. Both
    /// are checked against a satoshi count written down here, never one re-derived from the
    /// transaction by the code under test.
    function _assertReadsAmount(
        bytes memory btcTx,
        uint64 expectedSats
    ) private {
        uint256 expectedAmount = uint256(expectedSats) *
            Flyover.SAT_TO_WEI_CONVERSION;
        uint256 net = expectedAmount - _expectedFee(expectedAmount);
        bytes32 pegInId = _pegInIdForTx(rskUser, btcTx);
        uint256 userBefore = rskUser.balance;

        vm.expectEmit(true, true, true, true);
        emit IPegInCommitFirst.PegInRequested(
            pegInId,
            claimer,
            rskUser,
            expectedAmount,
            net,
            true
        );
        _requestPegInTx(claimer, rskUser, btcTx, net);

        (
            address claimerAddr,
            uint256 frontedAmount,
            uint256 feeAtClaim,

        ) = _readClaim(pegInId);
        assertEq(claimerAddr, claimer, "claim recorded to the claimer");
        assertEq(
            frontedAmount,
            net,
            "fronted amount is the real deposit minus the fee"
        );
        assertEq(
            feeAtClaim,
            _expectedFee(expectedAmount),
            "fee computed on the real amount"
        );
        assertEq(
            rskUser.balance - userBefore,
            net,
            "user received the real deposit minus the fee"
        );
    }

    function _assertNoClaim(bytes32 pegInId) private view {
        (
            address claimerAddr,
            uint256 frontedAmount,
            ,
            uint256 requestBlock
        ) = _readClaim(pegInId);
        assertEq(claimerAddr, address(0), "no claimer recorded");
        assertEq(frontedAmount, 0, "no fronted amount recorded");
        assertEq(requestBlock, 0, "no request block recorded");
    }

    // ---- splicing ----

    /// @notice Rewrites the output currently paying `originalScript` to pay the deposit script
    /// derived for rskUser instead, leaving every other byte of the real transaction as it is.
    /// @dev Both scripts are well under 0xfd bytes, so the output's length prefix stays a single
    /// byte and only its value changes. The transaction stops being a valid spend, which does not
    /// matter here: requestPegIn parses outputs and takes confirmations from the bridge, and the
    /// bridge is mocked.
    function _payToDepositInstead(
        bytes memory realTx,
        bytes memory originalScript
    ) private view returns (bytes memory) {
        return
            _replaceOnce(
                realTx,
                abi.encodePacked(
                    bytes1(uint8(originalScript.length)),
                    originalScript
                ),
                abi.encodePacked(
                    bytes1(uint8(_depositPkScript(rskUser).length)),
                    _depositPkScript(rskUser)
                )
            );
    }

    /// @notice Replaces the one occurrence of `needle` in `haystack` with `replacement`.
    /// @dev Reverts unless the needle occurs exactly once, so a fixture whose output script is
    /// ambiguous (or absent, after an edit) fails the test instead of splicing the wrong bytes.
    function _replaceOnce(
        bytes memory haystack,
        bytes memory needle,
        bytes memory replacement
    ) private pure returns (bytes memory out) {
        uint256 at;
        uint256 count;
        for (uint256 i = 0; i + needle.length <= haystack.length; ++i) {
            bool hit = true;
            for (uint256 j = 0; j < needle.length; ++j) {
                if (haystack[i + j] != needle[j]) {
                    hit = false;
                    break;
                }
            }
            if (hit) {
                if (count == 0) {
                    at = i;
                }
                ++count;
            }
        }
        require(count == 1, "fixture: output script must occur exactly once");

        out = new bytes(haystack.length - needle.length + replacement.length);
        uint256 k;
        for (uint256 i = 0; i < at; ++i) {
            out[k++] = haystack[i];
        }
        for (uint256 i = 0; i < replacement.length; ++i) {
            out[k++] = replacement[i];
        }
        for (uint256 i = at + needle.length; i < haystack.length; ++i) {
            out[k++] = haystack[i];
        }
    }
}
