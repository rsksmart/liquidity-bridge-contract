// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {RequestPegInTestBase} from "./RequestPegInTestBase.sol";
import {IPegInCommitFirst} from "../../src/interfaces/IPegInCommitFirst.sol";

/// @title requestPegIn fee edge-case tests
/// @notice Fee computed correctly at the configured amount bounds, and a fee that meets or
/// exceeds the amount reverts cleanly with IncorrectFronting(0, msg.value) (no underflow panic).
contract RequestPegInFeeEdgesTest is RequestPegInTestBase {
    function test_feeEdges_minAmountBoundary() public {
        uint256 amount = TEST_MIN_PEGIN;
        uint256 fee = _expectedFee(amount);
        uint256 net = amount - fee;
        bytes memory btcTx = _depositTx(rskUser, amount);
        bytes32 pegInId = _pegInIdForTx(rskUser, btcTx);

        uint256 userBefore = rskUser.balance;
        _requestPegInTx(claimer, rskUser, btcTx, net);

        assertEq(
            rskUser.balance,
            userBefore + net,
            "net delivered at min amount"
        );
        (, uint256 frontedAmount, uint256 feeAtClaim, ) = _readClaim(pegInId);
        assertEq(frontedAmount, net, "fronted at min amount");
        assertEq(feeAtClaim, fee, "fee at min amount");
    }

    function test_feeEdges_maxAmountBoundary() public {
        uint256 amount = DEFAULT_MAX_AMOUNT;
        uint256 fee = _expectedFee(amount);
        uint256 net = amount - fee;
        bytes memory btcTx = _depositTx(rskUser, amount);
        bytes32 pegInId = _pegInIdForTx(rskUser, btcTx);

        vm.deal(claimer, amount);
        uint256 userBefore = rskUser.balance;
        _requestPegInTx(claimer, rskUser, btcTx, net);

        assertEq(
            rskUser.balance,
            userBefore + net,
            "net delivered at max amount"
        );
        (, uint256 frontedAmount, uint256 feeAtClaim, ) = _readClaim(pegInId);
        assertEq(frontedAmount, net, "fronted at max amount");
        assertEq(feeAtClaim, fee, "fee at max amount");
    }

    function test_feeEdges_aboveMaxAmount_frontsMaxAmount() public {
        uint256 amount = 150 ether;
        uint256 cap = DEFAULT_MAX_AMOUNT;
        uint256 fee = _expectedFee(cap);
        uint256 net = cap - fee;
        bytes memory btcTx = _depositTx(rskUser, amount);
        bytes32 pegInId = _pegInIdForTx(rskUser, btcTx);

        vm.deal(claimer, 200 ether);
        uint256 claimerBefore = claimer.balance;
        uint256 userBefore = rskUser.balance;

        vm.expectEmit(true, true, true, true);
        emit IPegInCommitFirst.PegInRequested(
            pegInId,
            claimer,
            rskUser,
            amount,
            net,
            true
        );
        _requestPegInTx(claimer, rskUser, btcTx, net);

        assertEq(rskUser.balance, userBefore + net, "net delivered at cap");
        assertEq(claimer.balance, claimerBefore - net, "claimer fronted cap");
        (, uint256 frontedAmount, uint256 feeAtClaim, ) = _readClaim(pegInId);
        assertEq(frontedAmount, net, "fronted at cap");
        assertEq(feeAtClaim, fee, "fee on capped amount");
    }

    function test_feeEdges_oneSatAboveMaxAmount_isCapped() public {
        uint256 amount = DEFAULT_MAX_AMOUNT + 1e10;
        uint256 cap = DEFAULT_MAX_AMOUNT;
        uint256 fee = _expectedFee(cap);
        uint256 net = cap - fee;
        bytes memory btcTx = _depositTx(rskUser, amount);
        bytes32 pegInId = _pegInIdForTx(rskUser, btcTx);

        vm.deal(claimer, 200 ether);
        _requestPegInTx(claimer, rskUser, btcTx, net);

        (, uint256 frontedAmount, uint256 feeAtClaim, ) = _readClaim(pegInId);
        assertEq(frontedAmount, net, "fronted at cap");
        assertEq(feeAtClaim, fee, "fee on capped amount");
    }

    function test_feeEdges_tierMaxAmountIsNotTheCap() public {
        uint256 amount = DEFAULT_AMOUNT;
        uint256 highTierConfirmations = 40;
        _applyTwoTierConfiguration(1 ether, 2, highTierConfirmations);
        bridgeMock.setConfirmations(int256(highTierConfirmations));
        uint256 fee = _expectedFee(amount);
        uint256 net = amount - fee;
        bytes memory btcTx = _depositTx(rskUser, amount);
        bytes32 pegInId = _pegInIdForTx(rskUser, btcTx);

        _requestPegInTx(claimer, rskUser, btcTx, net);

        (, uint256 frontedAmount, uint256 feeAtClaim, ) = _readClaim(pegInId);
        assertEq(frontedAmount, net, "fronted in full above the tier max");
        assertEq(feeAtClaim, fee, "fee on full amount");
    }

    function test_feeEdges_amountBelowFee_revertsWithoutUnderflow() public {
        uint256 amount = DEFAULT_AMOUNT;
        // Fee strictly greater than the amount: amount < fee path -> IncorrectFronting(0, msg.value).
        configurations.setFee(amount + 1, 0);
        uint256 sentValue = 1;
        bytes memory btcTx = _depositTx(rskUser, amount);

        vm.prank(claimer);
        vm.expectRevert(
            abi.encodeWithSelector(
                IPegInCommitFirst.IncorrectFronting.selector,
                0,
                sentValue
            )
        );
        pegInContract.requestPegIn{value: sentValue}(
            rskUser,
            btcTx,
            bytes32(0),
            0,
            _emptyBranch()
        );
    }
}
