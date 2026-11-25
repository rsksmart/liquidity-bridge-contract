// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {RequestPegInContractCallTestBase} from "./RequestPegInContractCallTestBase.sol";
import {IPegInCommitFirst} from "../../src/interfaces/IPegInCommitFirst.sol";
import {RevertingDestination, GasBurningDestination, ReentrantDestination, LargeReturnDestination} from "./CallDestinationMocks.sol";

/// @title requestPegIn contract call and call gas fee, and their settlement
contract RequestPegInContractCallTest is RequestPegInContractCallTestBase {
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

    /// @notice The destination re-enters during the call, and only the reentrancy guard stops
    /// it: the destination succeeds only when the re-entry fails with ReentrancyGuardReentrantCall
    function test_reentrantDestination_isBlockedByTheGuard() public {
        ReentrantDestination destination = new ReentrantDestination(
            address(pegInContract)
        );
        bytes memory depositTx = _callTx(address(destination), CALL_GAS);
        bytes32 pegInId = _pegInIdForTx(rskUser, depositTx);

        _requestPegInTx(claimer, rskUser, depositTx, _expected());

        assertTrue(destination.reentryBlockedByGuard());
        assertTrue(_claimSuccess(pegInId));
        assertEq(
            address(destination).balance,
            _expected() - uint256(CALL_GAS) * GAS_PRICE
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
