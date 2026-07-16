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
        bytes32 pegInId = _pegInId(rskUser, DEFAULT_BTC_TX_HASH);

        uint256 userBefore = rskUser.balance;
        _requestPegIn(claimer, rskUser, amount, DEFAULT_BTC_TX_HASH, net);

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
        bytes32 pegInId = _pegInId(rskUser, DEFAULT_BTC_TX_HASH);

        vm.deal(claimer, amount);
        uint256 userBefore = rskUser.balance;
        _requestPegIn(claimer, rskUser, amount, DEFAULT_BTC_TX_HASH, net);

        assertEq(
            rskUser.balance,
            userBefore + net,
            "net delivered at max amount"
        );
        (, uint256 frontedAmount, uint256 feeAtClaim, ) = _readClaim(pegInId);
        assertEq(frontedAmount, net, "fronted at max amount");
        assertEq(feeAtClaim, fee, "fee at max amount");
    }

    function test_feeEdges_amountBelowFee_revertsWithoutUnderflow() public {
        uint256 amount = DEFAULT_AMOUNT;
        // Fee strictly greater than the amount: amount < fee path -> IncorrectFronting(0, msg.value).
        configurations.setFee(amount + 1, 0);
        uint256 sentValue = 1;

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
            amount,
            DEFAULT_BTC_TX_HASH,
            "",
            bytes32(0),
            0,
            _emptyBranch()
        );
    }
}
