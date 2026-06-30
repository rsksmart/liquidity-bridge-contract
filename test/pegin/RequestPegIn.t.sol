// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {E4TestBase} from "./E4TestBase.sol";
import {PegInContract} from "../../src/PegInContract.sol";

/// @title RequestPegIn
/// @notice E4.1: an LP claims a confirmed, registered peg-in by fronting RBTC from its own wallet.
contract RequestPegInTest is E4TestBase {
    bytes32 internal constant TX_HASH = keccak256("btc-tx-1");
    uint256 internal constant AMOUNT = 2 ether; // tier 1 (<=10 ether) => 6 confirmations

    function setUp() public {
        _deployAll();
        _register(user, AMOUNT);
        bridge.setConfirmations(6);
    }

    function test_ValidClaim_TransfersNetFromLpWalletToUser() public {
        uint256 net = AMOUNT - _fee(AMOUNT);
        uint256 lpBefore = lp.balance;
        uint256 userBefore = user.balance;

        vm.prank(lp);
        pegIn.requestPegIn{value: net}(user, AMOUNT, TX_HASH, new bytes(0));

        assertEq(user.balance - userBefore, net, "user receives amount - fee");
        assertEq(lpBefore - lp.balance, net, "LP wallet debited by the fronted amount");

        PegInContract.PegInClaim memory claim = pegIn.getPegInClaim(user, TX_HASH);
        assertEq(claim.claimer, lp, "claimer recorded");
        assertEq(claim.amount, AMOUNT, "amount recorded");
        assertEq(claim.fee, _fee(AMOUNT), "fee recorded");
        assertFalse(claim.resolved, "not yet resolved");
    }

    function test_DoubleClaim_Reverts() public {
        uint256 net = AMOUNT - _fee(AMOUNT);
        vm.prank(lp);
        pegIn.requestPegIn{value: net}(user, AMOUNT, TX_HASH, new bytes(0));

        vm.prank(otherLp);
        vm.expectRevert(
            abi.encodeWithSelector(PegInContract.PegInAlreadyProcessed.selector, pegIn.pegInId(user, TX_HASH))
        );
        pegIn.requestPegIn{value: net}(user, AMOUNT, TX_HASH, new bytes(0));
    }

    function test_UnregisteredAddress_Reverts() public {
        address stranger = makeAddr("stranger");
        uint256 net = AMOUNT - _fee(AMOUNT);
        vm.prank(lp);
        vm.expectRevert(abi.encodeWithSelector(PegInContract.AddressNotRegistered.selector, stranger));
        pegIn.requestPegIn{value: net}(stranger, AMOUNT, TX_HASH, new bytes(0));
    }

    function test_InsufficientConfirmations_Reverts() public {
        bridge.setConfirmations(5); // below the 6 required for tier 1
        uint256 net = AMOUNT - _fee(AMOUNT);
        vm.prank(lp);
        vm.expectRevert(abi.encodeWithSelector(PegInContract.InsufficientConfirmations.selector, 5, 6));
        pegIn.requestPegIn{value: net}(user, AMOUNT, TX_HASH, new bytes(0));
    }

    function test_WrongFrontedValue_Reverts() public {
        uint256 net = AMOUNT - _fee(AMOUNT);
        vm.prank(lp);
        vm.expectRevert(
            abi.encodeWithSelector(PegInContract.IncorrectFronting.selector, net, net - 1)
        );
        pegIn.requestPegIn{value: net - 1}(user, AMOUNT, TX_HASH, new bytes(0));
    }
}
