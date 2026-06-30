// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {E4TestBase} from "./E4TestBase.sol";
import {PegInContract} from "../../src/PegInContract.sol";

/// @title ResolvePegIn
/// @notice E4.3: the claiming LP settles with the bridge and recovers fronted RBTC plus the full fee
/// (credited to its internal balance). The registrant fee is taken from the fee on the first peg-in only.
contract ResolvePegInTest is E4TestBase {
    uint256 internal constant AMOUNT = 2 ether;

    function setUp() public {
        _deployAll();
        // Fund the registry derivation with enough for several settlements (registration leaves it in place).
        _register(user, AMOUNT * 4);
        // Each settlement releases exactly one AMOUNT-sized deposit (one BTC tx) from the funded pool.
        bridge.setSettlementAmount(AMOUNT);
        bridge.setConfirmations(6);
    }

    function _claim(bytes32 txHash) internal {
        uint256 net = AMOUNT - _fee(AMOUNT);
        vm.prank(lp);
        pegIn.requestPegIn{value: net}(user, AMOUNT, txHash, new bytes(0), bytes32(0), 0, _noBranches());
    }

    function test_ClaimerRecoversFrontedPlusFee() public {
        bytes32 txHash = keccak256("tx-a");
        _claim(txHash);

        uint256 net = AMOUNT - _fee(AMOUNT);
        uint256 fee = _fee(AMOUNT);
        uint256 lpBalBefore = pegIn.getBalance(lp);

        vm.prank(lp);
        pegIn.resolvePegIn(user, txHash, hex"00", hex"00", 1, payable(registrant));

        // First peg-in: the registrant fee is subtracted from the fee returned to the claimer.
        uint256 expected = net + fee - REGISTRANT_FEE;
        assertEq(pegIn.getBalance(lp) - lpBalBefore, expected, "claimer recovers fronted + fee - registrantFee");
        assertEq(pegIn.getBalance(registrant), REGISTRANT_FEE, "registrant credited once");

        PegInContract.PegInClaim memory claim = pegIn.getPegInClaim(user, txHash);
        assertTrue(claim.resolved, "claim marked resolved");
    }

    function test_ClaimerRecoversFullFee_NoRegistrant() public {
        bytes32 txHash = keccak256("tx-no-registrant");
        _claim(txHash);

        uint256 net = AMOUNT - _fee(AMOUNT);
        uint256 fee = _fee(AMOUNT);
        uint256 lpBalBefore = pegIn.getBalance(lp);

        vm.prank(lp);
        pegIn.resolvePegIn(user, txHash, hex"00", hex"00", 1, payable(address(0)));

        assertEq(pegIn.getBalance(lp) - lpBalBefore, net + fee, "claimer recovers fronted + FULL fee");
    }

    function test_RegistrantFeePaidOnce() public {
        bytes32 txA = keccak256("tx-a");
        bytes32 txB = keccak256("tx-b");

        _claim(txA);
        vm.prank(lp);
        pegIn.resolvePegIn(user, txA, hex"00", hex"00", 1, payable(registrant));
        assertEq(pegIn.getBalance(registrant), REGISTRANT_FEE, "registrant fee on first peg-in");

        // Second peg-in for the same address: no registrant fee.
        _claim(txB);
        uint256 net = AMOUNT - _fee(AMOUNT);
        uint256 fee = _fee(AMOUNT);
        uint256 lpBalBefore = pegIn.getBalance(lp);
        uint256 registrantBefore = pegIn.getBalance(registrant);

        vm.prank(lp);
        pegIn.resolvePegIn(user, txB, hex"00", hex"00", 1, payable(registrant));

        assertEq(pegIn.getBalance(lp) - lpBalBefore, net + fee, "second peg-in: full fee, no registrant cut");
        assertEq(pegIn.getBalance(registrant), registrantBefore, "registrant not paid again");
    }

    function test_ResolveUnclaimed_Reverts() public {
        bytes32 txHash = keccak256("never-claimed");
        vm.prank(lp);
        vm.expectRevert(
            abi.encodeWithSelector(PegInContract.PegInNotClaimed.selector, pegIn.pegInId(user, txHash))
        );
        pegIn.resolvePegIn(user, txHash, hex"00", hex"00", 1, payable(registrant));
    }

    function test_DoubleResolve_Reverts() public {
        bytes32 txHash = keccak256("tx-a");
        _claim(txHash);
        vm.prank(lp);
        pegIn.resolvePegIn(user, txHash, hex"00", hex"00", 1, payable(registrant));

        vm.prank(lp);
        vm.expectRevert(
            abi.encodeWithSelector(PegInContract.PegInAlreadyProcessed.selector, pegIn.pegInId(user, txHash))
        );
        pegIn.resolvePegIn(user, txHash, hex"00", hex"00", 1, payable(registrant));
    }
}
