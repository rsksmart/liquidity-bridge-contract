// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {RequestPegInTestBase} from "./RequestPegInTestBase.sol";
import {RequestPegInReenterReceiver} from "../../src/test-contracts/RequestPegInReenterReceiver.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Flyover} from "../../src/libraries/Flyover.sol";

/// @title requestPegIn reentrancy-guard test
/// @notice A malicious destination re-enters requestPegIn on delivery with a different btcTxHash
/// (a fresh pegInId), so the block comes from the nonReentrant guard rather than the
/// already-processed check. The re-entry's revert bubbles through the delivery call, so the whole
/// transaction reverts atomically and no claim is written for either pegInId.
contract RequestPegInReentrancyTest is RequestPegInTestBase {
    bytes32 internal constant REENTER_BTC_TX_HASH = keccak256("reenter-btc-tx");

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
        receiver.setAttack(true, REENTER_BTC_TX_HASH);

        bytes32 outerId = _pegInId(address(receiver), DEFAULT_BTC_TX_HASH);
        bytes32 reenterId = _pegInId(address(receiver), REENTER_BTC_TX_HASH);

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
            amount,
            DEFAULT_BTC_TX_HASH,
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
