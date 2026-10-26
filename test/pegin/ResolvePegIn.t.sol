// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {ResolvePegInTestBase} from "./ResolvePegInTestBase.sol";
import {Vm} from "forge-std/Vm.sol";
import {IPegInCommitFirst} from "../../src/interfaces/IPegInCommitFirst.sol";
import {IBridge} from "../../src/interfaces/IBridge.sol";
import {WalletMock} from "../../src/test-contracts/WalletMock.sol";
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
            bridgeRelease - DEFAULT_AMOUNT
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
            bridgeRelease - DEFAULT_AMOUNT
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

    function test_soft_pause_allows_resolve() public {
        bytes32 pegInId = _claimAndFund(rskUser, rawTx, bridgeRelease);
        vm.prank(owner);
        pauseRegistry.setPauseLevel(
            IPauseRegistry.PauseLevel.Soft,
            "resolve soft pause"
        );

        _resolve(claimer, rskUser, rawTx);

        assertTrue(_isSettled(pegInId));
        assertEq(_balance(claimer), DEFAULT_AMOUNT - 1e14);
    }

    function test_release_equal_to_owed_sends_nothing_to_user() public {
        _claimAndFund(rskUser, rawTx, DEFAULT_AMOUNT);
        uint256 userBefore = rskUser.balance;

        vm.recordLogs();
        _resolve(claimer, rskUser, rawTx);

        assertEq(_balance(claimer), DEFAULT_AMOUNT - 1e14);
        assertEq(_balance(registrant), 1e14);
        assertEq(rskUser.balance, userBefore);
        assertFalse(_remainderRefundEmitted());
    }

    function test_release_above_owed_sends_remainder_to_user() public {
        bytes32 pegInId = _claimAndFund(rskUser, rawTx, bridgeRelease);
        uint256 remainder = bridgeRelease - DEFAULT_AMOUNT;
        uint256 userBefore = rskUser.balance;

        vm.expectEmit(true, true, true, true);
        emit IPegInCommitFirst.UserRemainderRefunded(
            pegInId,
            rskUser,
            remainder,
            true
        );
        _resolve(claimer, rskUser, rawTx);

        assertEq(rskUser.balance - userBefore, remainder);
        assertEq(_balance(claimer), DEFAULT_AMOUNT - 1e14);
        _assertReleaseFullyAssigned(
            bridgeRelease,
            rskUser.balance - userBefore
        );
    }

    function test_release_below_owed_caps_claimer_and_registrant() public {
        uint256 release = 4 ether;
        bytes32 pegInId = _claimAndFund(rskUser, rawTx, release);
        uint256 userBefore = rskUser.balance;

        vm.expectEmit(true, true, true, true);
        emit IPegInCommitFirst.PegInResolved(
            pegInId,
            claimer,
            registrant,
            release,
            release - 1e14,
            1e14,
            0
        );
        _resolve(claimer, rskUser, rawTx);

        assertEq(_balance(claimer) + _balance(registrant), release);
        assertEq(rskUser.balance, userBefore);
    }

    function test_release_below_registrant_fee_caps_registrant() public {
        uint256 release = 5e13;
        _claimAndFund(rskUser, rawTx, release);

        _resolve(claimer, rskUser, rawTx);

        assertEq(_balance(registrant), release);
        assertEq(_balance(claimer), 0);
    }

    function test_dust_remainder_is_credited_to_claimer() public {
        uint256 release = DEFAULT_AMOUNT + TEST_DUST_THRESHOLD;
        bytes32 pegInId = _claimAndFund(rskUser, rawTx, release);
        uint256 userBefore = rskUser.balance;

        vm.recordLogs();
        vm.expectEmit(true, true, true, true);
        emit IPegInCommitFirst.PegInResolved(
            pegInId,
            claimer,
            registrant,
            release,
            DEFAULT_AMOUNT - 1e14 + TEST_DUST_THRESHOLD,
            1e14,
            0
        );
        _resolve(claimer, rskUser, rawTx);

        assertEq(rskUser.balance, userBefore);
        assertFalse(_remainderRefundEmitted());
        _assertReleaseFullyAssigned(release, 0);
    }

    function test_failed_user_send_credits_user_balance() public {
        WalletMock wallet = new WalletMock();
        address walletAddr = address(wallet);
        registry.harness_seedRegistration(walletAddr, registrant, 1);
        bytes memory walletTx = _depositTx(walletAddr, DEFAULT_AMOUNT);
        bytes32 pegInId = _claimAndFund(walletAddr, walletTx, bridgeRelease);
        uint256 remainder = bridgeRelease - DEFAULT_AMOUNT;
        wallet.setRejectFunds(true);

        vm.expectEmit(true, true, true, true);
        emit IPegInCommitFirst.UserRemainderRefunded(
            pegInId,
            walletAddr,
            remainder,
            false
        );
        vm.expectEmit(true, true, true, true);
        emit IPegInCommitFirst.PegInResolved(
            pegInId,
            claimer,
            registrant,
            bridgeRelease,
            DEFAULT_AMOUNT - 1e14,
            1e14,
            0
        );
        _resolve(claimer, walletAddr, walletTx);

        assertEq(_balance(claimer), DEFAULT_AMOUNT - 1e14);
        assertEq(_balance(walletAddr), remainder);
        _assertReleaseFullyAssigned(bridgeRelease, _balance(walletAddr));

        wallet.setRejectFunds(false);
        uint256 walletBefore = walletAddr.balance;
        wallet.execute(
            address(pegInContract),
            0,
            abi.encodeCall(pegInContract.withdraw, (remainder))
        );
        assertEq(walletAddr.balance - walletBefore, remainder);
        assertEq(_balance(walletAddr), 0);
    }

    function test_refused_payment_settles_fee_only() public {
        uint256 fee = _expectedFee(DEFAULT_AMOUNT);
        uint256 net = DEFAULT_AMOUNT - fee;
        (
            address recipient,
            bytes memory depositTx
        ) = _registerRefusingRecipient();
        bytes32 pegInId = _claimAndFund(recipient, depositTx, bridgeRelease);
        assertEq(_balance(claimer), net, "fronted RBTC credited at claim");

        vm.expectEmit(true, true, true, true);
        emit IPegInCommitFirst.PegInResolved(
            pegInId,
            claimer,
            registrant,
            bridgeRelease,
            fee - 1e14,
            1e14,
            0
        );
        _resolve(claimer, recipient, depositTx);

        assertEq(
            _balance(claimer) - net,
            fee - 1e14,
            "settlement credits only the fee"
        );
        assertEq(_balance(recipient), bridgeRelease - fee);
        assertTrue(_isSettled(pegInId));
    }

    function test_bridge_flag_true_after_paid_claim() public {
        _claimAndFund(rskUser, rawTx, bridgeRelease);

        _expectBridgeFlag(rskUser, rawTx, true);
        _resolve(claimer, rskUser, rawTx);
    }

    function test_bridge_flag_true_when_fee_equals_amount() public {
        configurations.setFee(DEFAULT_AMOUNT, 0);
        bytes32 pegInId = _requestPegInTx(claimer, rskUser, rawTx, 0);
        bridgeMock.setPegin{value: bridgeRelease}(_derivationHash(rskUser));
        (, uint256 frontedAmount, , ) = _readClaim(pegInId);
        assertEq(frontedAmount, 0, "paid claim with nothing fronted");

        _expectBridgeFlag(rskUser, rawTx, true);
        _resolve(claimer, rskUser, rawTx);
    }

    function test_bridge_flag_false_after_refused_claim() public {
        (
            address recipient,
            bytes memory depositTx
        ) = _registerRefusingRecipient();
        _claimAndFund(recipient, depositTx, bridgeRelease);

        _expectBridgeFlag(recipient, depositTx, false);
        _resolve(claimer, recipient, depositTx);
    }

    function _expectBridgeFlag(
        address rskAddr,
        bytes memory depositTx,
        bool shouldTransferToContract
    ) private {
        vm.expectCall(
            address(bridgeMock),
            abi.encodeCall(
                IBridge.registerFastBridgeBtcTransaction,
                (
                    depositTx,
                    100,
                    hex"00",
                    _derivationHash(rskAddr),
                    PegInDerivation.getRefundPlaceholderBtcAddress(
                        IS_MAINNET_DEPLOYMENT
                    ),
                    payable(address(pegInContract)),
                    PegInDerivation.getLpPlaceholderBtcAddress(
                        IS_MAINNET_DEPLOYMENT
                    ),
                    shouldTransferToContract
                )
            )
        );
    }

    function _assertReleaseFullyAssigned(
        uint256 release,
        uint256 userReceived
    ) private view {
        assertEq(
            _balance(claimer) + _balance(registrant) + userReceived,
            release
        );
    }

    function _remainderRefundEmitted() private returns (bool) {
        Vm.Log[] memory logs = vm.getRecordedLogs();
        for (uint256 i = 0; i < logs.length; i++) {
            if (
                logs[i].topics[0] ==
                IPegInCommitFirst.UserRemainderRefunded.selector
            ) {
                return true;
            }
        }
        return false;
    }

    function test_bridge_args_use_placeholder_getters() public pure {
        assertEq(
            PegInDerivation.getRefundPlaceholderBtcAddress(false).length,
            21
        );
        assertEq(PegInDerivation.getLpPlaceholderBtcAddress(false).length, 21);
    }
}
