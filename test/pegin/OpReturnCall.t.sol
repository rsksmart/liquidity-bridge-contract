// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {E4TestBase} from "./E4TestBase.sol";
import {PegInContract} from "../../src/PegInContract.sol";
import {CallTarget, RevertingTarget} from "./E4Destinations.sol";

/// @title OpReturnCall
/// @notice E4.2: OP_RETURN-driven SC-call peg-in vs plain peg-in, and the reverting-destination path.
contract OpReturnCallTest is E4TestBase {
    uint256 internal constant AMOUNT = 2 ether;
    uint256 internal constant MAX_GAS_FEE = 200000; // gas budget for the SC call

    function setUp() public {
        _deployAll();
        _register(user, AMOUNT);
        bridge.setConfirmations(6);
    }

    function test_ScCall_InvokesDestinationWithNetAmount() public {
        CallTarget target = new CallTarget();
        // Keep the whole OP_RETURN within the 80-byte budget: 20 + 32 + 4 = 56 bytes.
        bytes memory callData = hex"01020304";
        bytes memory opReturn = _opReturn(address(target), MAX_GAS_FEE, callData);

        uint256 net = AMOUNT - _fee(AMOUNT);
        bytes32 txHash = keccak256("sc-call");

        vm.prank(lp);
        bool ok = pegIn.requestPegIn{value: net}(user, AMOUNT, txHash, opReturn, bytes32(0), 0, _noBranches());

        assertTrue(ok, "call reported success");
        assertTrue(target.called(), "destination invoked");
        assertEq(target.received(), net, "destination received net amount (amount - fee)");
        assertEq(target.lastData(), callData, "destination received calldata");
    }

    function test_PlainPegIn_SendsToRskAddress() public {
        uint256 net = AMOUNT - _fee(AMOUNT);
        uint256 userBefore = user.balance;
        bytes32 txHash = keccak256("plain");

        vm.prank(lp);
        bool ok = pegIn.requestPegIn{value: net}(user, AMOUNT, txHash, new bytes(0), bytes32(0), 0, _noBranches());

        assertTrue(ok, "plain peg-in reports success");
        assertEq(user.balance - userBefore, net, "RSK address received net amount");
    }

    function test_RevertingDestination_RefundsRskAddress_MarksFailed_NoRevert() public {
        RevertingTarget target = new RevertingTarget();
        bytes memory opReturn = _opReturn(address(target), MAX_GAS_FEE, hex"deadbeef");

        uint256 net = AMOUNT - _fee(AMOUNT);
        uint256 userBefore = user.balance;
        bytes32 txHash = keccak256("reverting");

        vm.prank(lp);
        // The peg-in must NOT revert even though the destination reverts.
        bool ok = pegIn.requestPegIn{value: net}(user, AMOUNT, txHash, opReturn, bytes32(0), 0, _noBranches());

        assertFalse(ok, "failed call reported");
        // Funds went to the refund address (the RSK address).
        assertEq(user.balance - userBefore, net, "refund to RSK address on failed call");

        // The claim is still recorded (peg-in succeeded).
        PegInContract.PegInClaim memory claim = pegIn.getPegInClaim(user, txHash);
        assertEq(claim.claimer, lp, "peg-in still claimed");
        assertFalse(claim.resolved, "not yet resolved");
    }
}
