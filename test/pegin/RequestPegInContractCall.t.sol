// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {ResolvePegInTestBase} from "./ResolvePegInTestBase.sol";
import {IPegInCommitFirst} from "../../src/interfaces/IPegInCommitFirst.sol";
import {RecordingDestination, RevertingDestination, GasBurningDestination, ReentrantDestination, LargeReturnDestination} from "./CallDestinationMocks.sol";

/// @title requestPegIn contract call and call gas fee, and their settlement
contract RequestPegInContractCallTest is ResolvePegInTestBase {
    uint32 internal constant CALL_GAS = 100_000;
    uint256 internal constant GAS_PRICE = 0.06 gwei;
    bytes internal constant CALL_DATA = hex"d0e30db0"; // deposit()

    RecordingDestination internal recorder;

    function setUp() public override {
        super.setUp();
        configurations.setClaimGasFee(CLAIM_GAS_FEE);
        recorder = new RecordingDestination();
        vm.txGasPrice(GAS_PRICE);
    }

    // ---- helpers ----

    function _expected() internal pure returns (uint256) {
        return DEFAULT_AMOUNT - _expectedFee(DEFAULT_AMOUNT) - CLAIM_GAS_FEE;
    }

    function _callTx(
        address destination,
        uint32 maxGasLimit
    ) internal view returns (bytes memory) {
        return
            _depositTxWithCall(
                rskUser,
                DEFAULT_AMOUNT,
                destination,
                maxGasLimit,
                CALL_DATA
            );
    }

    function _claimSuccess(bytes32 pegInId) internal view returns (bool) {
        return
            (uint256(
                vm.load(address(pegInContract), bytes32(_claimSlot(pegInId)))
            ) >> 160) &
                0xff ==
            1;
    }

    // ---- the call ----

    function test_call_deliversValueAndCallData_andRecordsTheFee() public {
        bytes memory depositTx = _callTx(address(recorder), CALL_GAS);
        bytes32 pegInId = _pegInIdForTx(rskUser, depositTx);
        uint256 callGasFee = uint256(CALL_GAS) * GAS_PRICE;
        uint256 netToUser = _expected() - callGasFee;

        vm.expectEmit(true, true, true, true);
        emit IPegInCommitFirst.PegInRequested(
            pegInId,
            claimer,
            rskUser,
            DEFAULT_AMOUNT,
            netToUser,
            true,
            address(recorder),
            callGasFee
        );
        _requestPegInTx(claimer, rskUser, depositTx, _expected());

        assertEq(
            recorder.receivedValue(),
            netToUser,
            "destination gets expected - callGasFee"
        );
        assertEq(
            recorder.receivedData(),
            CALL_DATA,
            "callData is delivered unchanged"
        );
        assertEq(
            rskUser.balance,
            0,
            "rskAddr is not paid when the call succeeds"
        );
        (, uint256 frontedAmount, uint256 feeAtClaim, ) = _readClaim(pegInId);
        assertEq(frontedAmount, netToUser);
        assertEq(feeAtClaim, _expectedFee(DEFAULT_AMOUNT));
        assertEq(_readGasFeeAtClaim(pegInId), CLAIM_GAS_FEE + callGasFee);
        assertEq(
            _balance(claimer),
            callGasFee,
            "the LP gets back the part of msg.value not forwarded"
        );
        assertTrue(_claimSuccess(pegInId));
    }

    function test_call_destinationGetsAtLeastMaxGasLimit() public {
        _requestPegInTx(
            claimer,
            rskUser,
            _callTx(address(recorder), CALL_GAS),
            _expected()
        );
        assertGe(recorder.gasAtEntry(), CALL_GAS);
    }

    function test_callGasFee_followsTheTransactionGasPrice() public {
        vm.txGasPrice(1 gwei);
        bytes memory depositTx = _callTx(address(recorder), CALL_GAS);
        bytes32 pegInId = _pegInIdForTx(rskUser, depositTx);
        _requestPegInTx(claimer, rskUser, depositTx, _expected());
        assertEq(
            _readGasFeeAtClaim(pegInId),
            CLAIM_GAS_FEE + uint256(CALL_GAS) * 1 gwei
        );
    }

    function test_callGasFeeAboveExpected_reverts() public {
        uint256 gasPrice = _expected() / CALL_GAS + 1;
        vm.txGasPrice(gasPrice);
        bytes memory depositTx = _callTx(address(recorder), CALL_GAS);
        vm.expectRevert(
            abi.encodeWithSelector(
                IPegInCommitFirst.CallGasFeeTooHigh.selector,
                uint256(CALL_GAS) * gasPrice,
                _expected()
            )
        );
        _requestPegInTx(claimer, rskUser, depositTx, _expected());
    }

    function test_tooLittleGas_revertsInsufficientCallGas() public {
        bytes memory depositTx = _callTx(address(recorder), CALL_GAS);
        uint256 value = _expected();
        vm.prank(claimer);
        vm.expectPartialRevert(IPegInCommitFirst.InsufficientCallGas.selector);
        pegInContract.requestPegIn{value: value, gas: 300_000}(
            rskUser,
            depositTx,
            bytes32(0),
            0,
            _emptyBranch()
        );
    }

    /// @notice Whatever gas the LP sends, a claim that goes through gave the destination its full
    /// maxGasLimit, and the call succeeded
    /// @dev Unlike Rootstock, the test EVM keeps back 1/64 of the gas left at a CALL. CALL_GAS is
    /// small enough for the reserve to absorb that 1/64 as well, so the test checks the Rootstock
    /// property on the test EVM.
    function testFuzz_lpGas_neverStarvesTheCall(uint256 lpGas) public {
        lpGas = bound(lpGas, 300_000, 1_500_000);
        bytes memory depositTx = _callTx(address(recorder), CALL_GAS);
        bytes32 pegInId = _pegInIdForTx(rskUser, depositTx);
        uint256 value = _expected();

        vm.prank(claimer);
        try
            pegInContract.requestPegIn{value: value, gas: lpGas}(
                rskUser,
                depositTx,
                bytes32(0),
                0,
                _emptyBranch()
            )
        {
            assertTrue(
                _claimSuccess(pegInId),
                "a claim that goes through made a successful call"
            );
            assertGe(
                recorder.gasAtEntry(),
                CALL_GAS,
                "the destination got its full maxGasLimit"
            );
        } catch {
            assertEq(recorder.calls(), 0);
        }
    }

    // ---- the call fails ----

    function _assertFailedCall(address destination) internal {
        bytes memory depositTx = _callTx(destination, CALL_GAS);
        bytes32 pegInId = _pegInIdForTx(rskUser, depositTx);
        uint256 callGasFee = uint256(CALL_GAS) * GAS_PRICE;

        vm.expectEmit(true, true, true, true);
        emit IPegInCommitFirst.PegInRequested(
            pegInId,
            claimer,
            rskUser,
            DEFAULT_AMOUNT,
            _expected() - callGasFee,
            false,
            destination,
            callGasFee
        );
        _requestPegInTx(claimer, rskUser, depositTx, _expected());

        assertFalse(_claimSuccess(pegInId));
        (, uint256 frontedAmount, , ) = _readClaim(pegInId);
        assertEq(frontedAmount, 0);
        assertEq(
            _readGasFeeAtClaim(pegInId),
            CLAIM_GAS_FEE + callGasFee,
            "the LP is still owed the call gas fee"
        );
        assertEq(_balance(claimer), _expected(), "the LP keeps all it fronted");
        assertEq(destination.balance, 0);
    }

    function test_revertingDestination_marksTheClaimFailed() public {
        _assertFailedCall(address(new RevertingDestination()));
    }

    function test_gasBurningDestination_marksTheClaimFailed() public {
        _assertFailedCall(address(new GasBurningDestination()));
    }

    function test_reentrantDestination_marksTheClaimFailed() public {
        _assertFailedCall(
            address(new ReentrantDestination(address(pegInContract)))
        );
    }

    function test_largeReturn_doesNotBreakTheClaim() public {
        LargeReturnDestination destination = new LargeReturnDestination();
        bytes memory depositTx = _callTx(address(destination), CALL_GAS);
        bytes32 pegInId = _pegInIdForTx(rskUser, depositTx);
        _requestPegInTx(claimer, rskUser, depositTx, _expected());
        assertTrue(_claimSuccess(pegInId));
    }

    function test_addressOnlyPayload_sendsTheValue() public {
        address wallet = makeAddr("secondAddress");
        bytes memory depositTx = _depositTxWithCall(
            rskUser,
            DEFAULT_AMOUNT,
            wallet,
            2300,
            ""
        );
        _requestPegInTx(claimer, rskUser, depositTx, _expected());
        assertEq(wallet.balance, _expected() - 2300 * GAS_PRICE);
    }

    // ---- amounts ----

    /// @notice The value sent plus the call gas fee is what the LP fronts, and the LP's share at
    /// settlement is the same as without a call
    function testFuzz_amounts_addUp(
        uint32 maxGasLimit,
        uint64 gasPrice
    ) public {
        maxGasLimit = uint32(bound(maxGasLimit, 1, DEFAULT_MAX_CALL_GAS));
        gasPrice = uint64(bound(gasPrice, 0, _expected() / maxGasLimit));
        vm.txGasPrice(gasPrice);
        // A plain address accepts RBTC with any gas, so the call always succeeds
        address wallet = makeAddr("wallet");
        bytes memory depositTx = _depositTxWithCall(
            rskUser,
            DEFAULT_AMOUNT,
            wallet,
            maxGasLimit,
            ""
        );
        bytes32 pegInId = _pegInIdForTx(rskUser, depositTx);

        _requestPegInTx(claimer, rskUser, depositTx, _expected());

        uint256 callGasFee = uint256(maxGasLimit) * gasPrice;
        (, uint256 frontedAmount, uint256 feeAtClaim, ) = _readClaim(pegInId);
        assertEq(wallet.balance + callGasFee, _expected());
        assertEq(
            frontedAmount + feeAtClaim + _readGasFeeAtClaim(pegInId),
            DEFAULT_AMOUNT
        );
    }

    // ---- settlement ----

    function test_settle_afterFailedCall_repaysOnlyTheFees_andPaysTheRestToRskAddr()
        public
    {
        RevertingDestination destination = new RevertingDestination();
        bytes memory depositTx = _callTx(address(destination), CALL_GAS);
        uint256 callGasFee = uint256(CALL_GAS) * GAS_PRICE;
        uint256 fees = _expectedFee(DEFAULT_AMOUNT) +
            CLAIM_GAS_FEE +
            callGasFee;
        bytes32 pegInId = _claimAndFund(rskUser, depositTx, DEFAULT_AMOUNT);
        uint256 registrantFee = 1e14;

        _resolve(thirdPartyCaller(), rskUser, depositTx);

        assertTrue(_isSettled(pegInId));
        assertEq(_balance(claimer), _expected() + fees - registrantFee);
        assertEq(
            rskUser.balance,
            DEFAULT_AMOUNT - fees,
            "rskAddr, the refund address, gets the rest"
        );
    }

    function thirdPartyCaller() internal returns (address) {
        return makeAddr("thirdParty");
    }
}
