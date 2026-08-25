// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {ResolvePegInTestBase} from "./ResolvePegInTestBase.sol";
import {IPegInCommitFirst} from "../../src/interfaces/IPegInCommitFirst.sol";
import {BtcTransactionReader} from "../../src/libraries/BtcTransactionReader.sol";
import {PegInDerivation} from "../../src/libraries/PegInDerivation.sol";
import {IPauseRegistry} from "../../src/interfaces/IPauseRegistry.sol";
import {Flyover} from "../../src/libraries/Flyover.sol";

contract ResolvePegInTest is ResolvePegInTestBase {
    address internal registrant;
    bytes internal rawTx;
    bytes32 internal btcTxHash;
    uint256 internal bridgeRelease;

    function setUp() public override {
        super.setUp();
        registrant = makeAddr("registrant");
        registry.harness_seedRegistration(rskUser, registrant, 1);
        rawTx = _depositTx(rskUser, DEFAULT_AMOUNT);
        btcTxHash = _btcTxHash(rawTx);
        bridgeRelease = 6 ether;
    }

    function test_claimer_balance_after_resolve() public {
        bytes32 pegInId = _claimAndFund(rskUser, rawTx, bridgeRelease);
        uint256 registrantFee = 1e14;

        _resolve(claimer, rskUser, rawTx);

        assertEq(_balance(claimer), DEFAULT_AMOUNT - registrantFee);
        assertTrue(_isSettled(pegInId));
    }

    function test_registrant_paid_once_per_address() public {
        _claimAndFund(rskUser, rawTx, bridgeRelease);
        _resolve(claimer, rskUser, rawTx);
        assertEq(_balance(registrant), 1e14);
        assertTrue(_isRegistrantPaid(rskUser));

        bytes memory rawTx2 = _depositTx(
            rskUser,
            DEFAULT_AMOUNT,
            DEFAULT_TX_NONCE + 1
        );
        bytes32 pegInId2 = _claimAndFund(rskUser, rawTx2, bridgeRelease);
        vm.expectEmit(true, true, true, true);
        emit IPegInCommitFirst.PegInResolved(
            pegInId2,
            claimer,
            address(0),
            bridgeRelease,
            DEFAULT_AMOUNT,
            0,
            0
        );
        _resolve(claimer, rskUser, rawTx2);
        assertEq(_balance(registrant), 1e14);
        assertEq(_balance(claimer), 2 * DEFAULT_AMOUNT - 1e14);
        assertEq(_balance(claimer) + _balance(registrant), 2 * DEFAULT_AMOUNT);
    }

    function test_second_resolve_reverts_before_credit() public {
        bytes32 pegInId = _claimAndFund(rskUser, rawTx, bridgeRelease);
        _resolve(claimer, rskUser, rawTx);

        bridgeMock.setPegin{value: bridgeRelease}(_derivationHash(rskUser));
        vm.prank(claimer);
        vm.expectRevert(
            abi.encodeWithSelector(
                IPegInCommitFirst.PegInAlreadyProcessed.selector,
                pegInId
            )
        );
        pegInContract.resolvePegIn(rskUser, rawTx, hex"00", 100);
        assertEq(_balance(claimer), DEFAULT_AMOUNT - 1e14);
    }

    function test_third_party_caller_same_credits() public {
        _claimAndFund(rskUser, rawTx, bridgeRelease);
        address thirdParty = makeAddr("thirdParty");
        _resolve(thirdParty, rskUser, rawTx);
        assertGt(_balance(claimer), 0);
    }

    function test_unclaimed_reverts_without_bridge_credit() public {
        vm.prank(claimer);
        vm.expectRevert(
            abi.encodeWithSelector(
                IPegInCommitFirst.PegInNotClaimed.selector,
                _pegInId(rskUser, btcTxHash)
            )
        );
        pegInContract.resolvePegIn(rskUser, rawTx, hex"00", 100);
        assertEq(_balance(claimer), 0);
    }

    function test_witness_serialized_tx_reverts() public {
        _claimAndFund(rskUser, rawTx, bridgeRelease);
        vm.prank(claimer);
        vm.expectRevert(
            BtcTransactionReader.WitnessSerializedTxNotAccepted.selector
        );
        pegInContract.resolvePegIn(rskUser, WITNESS_MARKED_TX, hex"00", 100);
        assertEq(_balance(claimer), 0);
    }

    function test_wrong_tx_for_address_reverts_unclaimed() public {
        bytes memory wrongRawTx = _depositTx(
            rskUser,
            DEFAULT_AMOUNT,
            DEFAULT_TX_NONCE + 99
        );
        bytes32 wrongPegInId = _pegInId(rskUser, _btcTxHash(wrongRawTx));
        _claimAndFund(rskUser, rawTx, bridgeRelease);
        vm.prank(claimer);
        vm.expectRevert(
            abi.encodeWithSelector(
                IPegInCommitFirst.PegInNotClaimed.selector,
                wrongPegInId
            )
        );
        pegInContract.resolvePegIn(rskUser, wrongRawTx, hex"00", 100);
    }

    function test_bridge_error_leaves_balances_unchanged() public {
        _claimAndFund(rskUser, rawTx, bridgeRelease);
        bridgeMock.setPeginError(-900);
        int256 result = _resolve(claimer, rskUser, rawTx);
        assertEq(result, -900);
        assertEq(_balance(claimer), 0);
        assertFalse(_isSettled(_pegInId(rskUser, btcTxHash)));
    }

    function test_registrant_fee_clamped_to_fee_at_claim() public {
        configurations.setRegistrantFee(1 ether);
        _claimAndFund(rskUser, rawTx, bridgeRelease);
        uint256 fee = _expectedFee(DEFAULT_AMOUNT);
        _resolve(claimer, rskUser, rawTx);
        assertEq(_balance(registrant), fee);
    }

    function test_event_fields_match_credits() public {
        bytes32 pegInId = _claimAndFund(rskUser, rawTx, bridgeRelease);
        uint256 claimerPayout = DEFAULT_AMOUNT - 1e14;
        vm.expectEmit(true, true, true, true);
        emit IPegInCommitFirst.PegInResolved(
            pegInId,
            claimer,
            registrant,
            bridgeRelease,
            claimerPayout,
            1e14,
            0
        );
        _resolve(claimer, rskUser, rawTx);
    }

    function test_hard_pause_blocks_resolve() public {
        _claimAndFund(rskUser, rawTx, bridgeRelease);
        vm.prank(owner);
        pauseRegistry.setPauseLevel(
            IPauseRegistry.PauseLevel.Hard,
            "resolve hard pause"
        );
        vm.prank(claimer);
        vm.expectRevert(Flyover.EnforcedPause.selector);
        pegInContract.resolvePegIn(rskUser, rawTx, hex"00", 100);
    }

    function test_bridge_args_use_placeholder_getters() public pure {
        assertEq(
            PegInDerivation.getRefundPlaceholderBtcAddress(false).length,
            21
        );
        assertEq(PegInDerivation.getLpPlaceholderBtcAddress(false).length, 21);
    }
}
