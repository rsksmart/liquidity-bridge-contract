// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {RequestPegInTestBase} from "./RequestPegInTestBase.sol";
import {RequestPegInReenterReceiver} from "../../src/test-contracts/RequestPegInReenterReceiver.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Flyover} from "../../src/libraries/Flyover.sol";

/// @title requestPegIn reentrancy-guard test
/// @notice A malicious destination re-enters requestPegIn on delivery with a second, genuine
/// deposit transaction of its own (a different txid, so a fresh pegInId), so the block comes from
/// the nonReentrant guard rather than the already-processed check or the deposit match. The
/// re-entry's revert bubbles through the delivery call, so the whole transaction reverts
/// atomically and no claim is written for either pegInId.
contract RequestPegInReentrancyTest is RequestPegInTestBase {
    uint256 internal constant REENTER_TX_NONCE = 99;

    function test_reentrancy_maliciousRskAddr_differentPegInId() public {
        RequestPegInReenterReceiver receiver = new RequestPegInReenterReceiver(
            address(pegInContract)
        );
        registry.harness_seedRegistration(
            address(receiver),
            makeAddr("registrant2"),
            1
        );

        uint256 amount = DEFAULT_AMOUNT;
        uint256 net = amount - _expectedFee(amount);

        // Both transactions really pay the receiver's derived deposit address, so the re-entry
        // is stopped by the guard and not by a failed derivation.
        bytes memory outerTx = _depositTx(address(receiver), amount);
        bytes memory reenterTx = _depositTx(
            address(receiver),
            amount,
            REENTER_TX_NONCE
        );
        receiver.setAttack(true, reenterTx);

        bytes32 outerId = _pegInIdForTx(address(receiver), outerTx);
        bytes32 reenterId = _pegInIdForTx(address(receiver), reenterTx);
        assertTrue(outerId != reenterId, "re-entry targets a fresh pegInId");

        // The re-entry reverts with the reentrancy guard error, which the delivery call surfaces
        // (and the implementation wraps) as PaymentFailed, reverting the whole transaction.
        bytes memory reentrancyReason = abi.encodeWithSelector(
            ReentrancyGuard.ReentrancyGuardReentrantCall.selector
        );
        vm.prank(claimer);
        vm.expectRevert(
            abi.encodeWithSelector(
                Flyover.PaymentFailed.selector,
                address(receiver),
                net,
                reentrancyReason
            )
        );
        pegInContract.requestPegIn{value: net}(
            address(receiver),
            outerTx,
            "",
            bytes32(0),
            0,
            _emptyBranch()
        );

        // Atomic revert-all: neither the outer nor the re-entrant pegInId holds a claim.
        (address outerClaimer, , , ) = _readClaim(outerId);
        (address reenterClaimer, , , ) = _readClaim(reenterId);
        assertEq(
            outerClaimer,
            address(0),
            "no claim written for outer pegInId"
        );
        assertEq(
            reenterClaimer,
            address(0),
            "no claim written for re-entrant pegInId"
        );
    }
}
