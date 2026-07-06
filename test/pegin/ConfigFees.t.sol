// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {E4TestBase} from "./E4TestBase.sol";
import {PegInContract} from "../../src/PegInContract.sol";

/// @title ConfigFees
/// @notice E4.5: the claim flow sources fees and confirmations from FlyoverConfigurations, not a quote.
contract ConfigFeesTest is E4TestBase {
    function setUp() public {
        _deployAll();
    }

    function test_FeeChargedEqualsCalculatePegInFee() public {
        uint256 amount = 3 ether; // tier 1 => 6 confirmations
        _register(user, amount);
        bridge.setConfirmations(6);

        uint256 expectedFee = config.calculatePegInFee(amount);
        uint256 net = amount - expectedFee;
        uint256 userBefore = user.balance;

        vm.prank(lp);
        pegIn.requestPegIn{value: net}(user, amount, keccak256("fee"), new bytes(0), bytes32(0), 0, _noBranches());

        // The fee withheld from the user equals calculatePegInFee.
        assertEq(amount - (user.balance - userBefore), expectedFee, "fee == calculatePegInFee");

        PegInContract.PegInClaim memory claim = pegIn.getPegInClaim(user, keccak256("fee"));
        assertEq(claim.fee, expectedFee, "stored fee == calculatePegInFee");
    }

    function test_ConfirmationsMatchTier_LowTier() public {
        // tier 0: <=1 ether => 2 confirmations.
        uint256 amount = 0.5 ether;
        _register(user, amount);
        assertEq(config.getRequiredPegInConfirmations(amount), 2, "tier 0 confirmations");

        uint256 net = amount - _fee(amount);

        // 1 confirmation must revert, 2 must pass.
        bridge.setConfirmations(1);
        vm.prank(lp);
        vm.expectRevert(abi.encodeWithSelector(PegInContract.InsufficientConfirmations.selector, 1, 2));
        pegIn.requestPegIn{value: net}(user, amount, keccak256("c0"), new bytes(0), bytes32(0), 0, _noBranches());

        bridge.setConfirmations(2);
        vm.prank(lp);
        pegIn.requestPegIn{value: net}(user, amount, keccak256("c0"), new bytes(0), bytes32(0), 0, _noBranches());
    }

    function test_ConfirmationsMatchTier_HighTier() public {
        // tier 2: <=100 ether => 20 confirmations.
        uint256 amount = 50 ether;
        _register(otherLp, amount);
        assertEq(config.getRequiredPegInConfirmations(amount), 20, "tier 2 confirmations");

        uint256 net = amount - _fee(amount);
        bridge.setConfirmations(19);
        vm.deal(lp, 200 ether);
        vm.prank(lp);
        vm.expectRevert(abi.encodeWithSelector(PegInContract.InsufficientConfirmations.selector, 19, 20));
        pegIn.requestPegIn{value: net}(otherLp, amount, keccak256("big"), new bytes(0), bytes32(0), 0, _noBranches());
    }
}
