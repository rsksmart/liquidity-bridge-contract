// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {E4TestBase} from "./E4TestBase.sol";
import {PegInContract} from "../../src/PegInContract.sol";

/// @title UnclaimedSlash (E11.1 + E11.2 refund rail)
/// @notice A registered peg-in that NO LP fronted is settled by resolvePegIn: the funds are forwarded
/// to the user (amount - fee) and, if the peg-in is serviceable (>= minimum) and past its claim deadline
/// (anchored to the registration block), the network is global-slashed. Below-minimum amounts are still
/// refunded but not penalizable; before the deadline the funds are forwarded with no slash. This replaces
/// the standalone E4.4 slash, which slashed without settling and thus stranded the user's deposit.
contract UnclaimedSlashTest is E4TestBase {
    uint256 internal constant AMOUNT = 2 ether;

    function setUp() public {
        _deployAll();
    }

    function _minAmount() internal view returns (uint256) {
        return config.getPegInConfiguration().minAmount;
    }

    /// @notice Resolve an unclaimed peg-in (no requestPegIn) — the E11.1/E11.2 refund rail.
    function _resolveUnclaimed(address addr, bytes32 txHash) internal returns (int256) {
        vm.prank(otherLp);
        return pegIn.resolvePegIn(addr, txHash, hex"00", hex"00", 1, payable(registrant));
    }

    /// @notice Roll to just past the claim deadline, anchored to the registration block.
    function _pastDeadline(address addr) internal {
        vm.roll(registry.getRegistrationBlock(addr) + CLAIM_DEADLINE_BLOCKS + 1);
    }

    function _totalCollateral() internal view returns (uint256) {
        return collateral.getPegInCollateral(lp) + collateral.getPegInCollateral(otherLp);
    }

    /// E11.1 AC (forward) + E11.2 AC (slash on same resolve) + processed.
    function test_UnclaimedValid_ForwardsToUserAndSlashes() public {
        // Move past the LP collateral grace window, then register the user's address.
        vm.roll(block.number + collateral.getGraceWindow() + 1);
        _register(user, AMOUNT);
        _pastDeadline(user);

        uint256 net = AMOUNT - _fee(AMOUNT);
        uint256 userBefore = user.balance;
        uint256 collBefore = _totalCollateral();

        int256 result = _resolveUnclaimed(user, keccak256("unclaimed"));

        assertEq(uint256(result), AMOUNT, "bridge released the peg-in amount");
        assertEq(user.balance - userBefore, net, "user forwarded amount - fee");
        assertLt(_totalCollateral(), collBefore, "global slash reduced LP collateral");

        PegInContract.PegInClaim memory claim = pegIn.getPegInClaim(user, keccak256("unclaimed"));
        assertTrue(claim.resolved, "peg-in marked processed");
    }

    /// E11.2 non-penalizable AC: an unregistered address cannot be resolved/slashed.
    function test_Unregistered_Reverts() public {
        address stranger = makeAddr("stranger");
        vm.roll(block.number + 200);
        vm.prank(otherLp);
        vm.expectRevert(abi.encodeWithSelector(PegInContract.AddressNotRegistered.selector, stranger));
        pegIn.resolvePegIn(stranger, keccak256("x"), hex"00", hex"00", 1, payable(registrant));
    }

    /// E11.2 non-penalizable AC: a below-minimum amount is refunded to the user but not slashed.
    function test_BelowMinimum_ForwardsButNoSlash() public {
        vm.roll(block.number + collateral.getGraceWindow() + 1);
        uint256 belowMin = _minAmount() - 1;
        _register(user, belowMin);
        _pastDeadline(user);

        uint256 net = belowMin - _fee(belowMin);
        uint256 userBefore = user.balance;
        uint256 collBefore = _totalCollateral();

        _resolveUnclaimed(user, keccak256("small"));

        assertEq(user.balance - userBefore, net, "below-min still refunded to the user");
        assertEq(_totalCollateral(), collBefore, "below-min is not penalizable");
    }

    /// E11.1 AC (forward) with E11.2 AC (no slash before the deadline).
    function test_BeforeDeadline_ForwardsNoSlash() public {
        vm.roll(block.number + collateral.getGraceWindow() + 1);
        _register(user, AMOUNT);
        // Do NOT advance past the claim deadline.

        uint256 net = AMOUNT - _fee(AMOUNT);
        uint256 userBefore = user.balance;
        uint256 collBefore = _totalCollateral();

        _resolveUnclaimed(user, keccak256("early"));

        assertEq(user.balance - userBefore, net, "user forwarded before the deadline");
        assertEq(_totalCollateral(), collBefore, "no slash before the deadline");
    }

    /// E11.1 AC: the refund rail is idempotent — a resolved peg-in cannot be resolved again.
    function test_ResolveTwice_Reverts() public {
        vm.roll(block.number + collateral.getGraceWindow() + 1);
        _register(user, AMOUNT);
        _pastDeadline(user);

        bytes32 txHash = keccak256("dup");
        _resolveUnclaimed(user, txHash);

        vm.prank(otherLp);
        vm.expectRevert(
            abi.encodeWithSelector(PegInContract.PegInAlreadyProcessed.selector, pegIn.pegInId(user, txHash))
        );
        pegIn.resolvePegIn(user, txHash, hex"00", hex"00", 1, payable(registrant));
    }
}
