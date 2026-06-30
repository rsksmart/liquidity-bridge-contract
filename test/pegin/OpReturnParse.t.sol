// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {E4TestBase} from "./E4TestBase.sol";
import {PegInContract} from "../../src/PegInContract.sol";
import {CallTarget} from "./E4Destinations.sol";

/// @title OpReturnParse
/// @notice E4.2: OP_RETURN parsing edge cases — malformed and oversized payloads are treated as a plain
/// peg-in (the decided breakdown stance: never revert the peg-in over a bad OP_RETURN).
contract OpReturnParseTest is E4TestBase {
    uint256 internal constant AMOUNT = 2 ether;

    function setUp() public {
        _deployAll();
        _register(user, AMOUNT);
        bridge.setConfirmations(6);
    }

    function test_WellFormed_InvokesDestination() public {
        CallTarget target = new CallTarget();
        bytes memory opReturn = _opReturn(address(target), 200000, hex"01020304");
        uint256 net = AMOUNT - _fee(AMOUNT);

        vm.prank(lp);
        bool ok = pegIn.requestPegIn{value: net}(user, AMOUNT, keccak256("wf"), opReturn, bytes32(0), 0, _noBranches());

        assertTrue(ok, "well-formed SC-call succeeds");
        assertTrue(target.called(), "destination invoked");
        assertEq(target.received(), net, "destination received the net amount");
    }

    function test_Malformed_TooShort_TreatedAsPlain() public {
        // Shorter than the 52-byte header => treated as a plain peg-in (no SC-call).
        bytes memory opReturn = hex"0102030405";
        uint256 net = AMOUNT - _fee(AMOUNT);
        uint256 userBefore = user.balance;

        vm.prank(lp);
        bool ok = pegIn.requestPegIn{value: net}(user, AMOUNT, keccak256("short"), opReturn, bytes32(0), 0, _noBranches());

        assertTrue(ok, "plain peg-in succeeds");
        assertEq(user.balance - userBefore, net, "malformed OP_RETURN paid out as plain peg-in");
    }

    function test_Oversized_TreatedAsPlain() public {
        // Larger than the standard ~80-byte budget => treated as a plain peg-in.
        bytes memory opReturn = new bytes(120);
        uint256 net = AMOUNT - _fee(AMOUNT);
        uint256 userBefore = user.balance;

        vm.prank(lp);
        bool ok = pegIn.requestPegIn{value: net}(user, AMOUNT, keccak256("big"), opReturn, bytes32(0), 0, _noBranches());

        assertTrue(ok, "plain peg-in succeeds");
        assertEq(user.balance - userBefore, net, "oversized OP_RETURN paid out as plain peg-in");
    }

    function test_ZeroDestination_TreatedAsPlain() public {
        bytes memory opReturn = _opReturn(address(0), 200000, hex"01020304");
        uint256 net = AMOUNT - _fee(AMOUNT);
        uint256 userBefore = user.balance;

        vm.prank(lp);
        bool ok = pegIn.requestPegIn{value: net}(user, AMOUNT, keccak256("zero"), opReturn, bytes32(0), 0, _noBranches());

        assertTrue(ok, "zero-destination treated as plain");
        assertEq(user.balance - userBefore, net, "net sent to RSK address");
    }

    function test_PegInIdGetter_MatchesEncoding() public view {
        bytes32 txHash = keccak256("anything");
        assertEq(
            pegIn.pegInId(user, txHash),
            keccak256(abi.encodePacked(user, txHash)),
            "pegInId encoding"
        );
    }
}
