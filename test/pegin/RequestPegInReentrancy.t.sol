// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {RequestPegInTestBase} from "./RequestPegInTestBase.sol";
import {RequestPegInReenterReceiver} from "../../src/test-contracts/RequestPegInReenterReceiver.sol";
import {IPegInCommitFirst} from "../../src/interfaces/IPegInCommitFirst.sol";

/// @title requestPegIn reentrancy-guard test
/// @notice A malicious destination re-enters requestPegIn on delivery with a second, genuine
/// deposit transaction of its own (a different txid, so a fresh pegInId), so the block comes from
/// the nonReentrant guard rather than the already-processed check or the deposit match. The
/// re-entry's revert makes the delivery fail, so the outer claim is stored as a failed payment
/// and no claim is written for the re-entrant pegInId.
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

        vm.expectCall(
            address(pegInContract),
            abi.encodeCall(
                IPegInCommitFirst.requestPegIn,
                (address(receiver), reenterTx, bytes32(0), 0, _emptyBranch())
            )
        );
        uint256 claimerBalanceBefore = pegInContract.getBalance(claimer);
        _requestPegInTx(claimer, address(receiver), outerTx, net);

        (address outerClaimer, uint256 outerFronted, , ) = _readClaim(outerId);
        (address reenterClaimer, , , ) = _readClaim(reenterId);
        assertEq(outerClaimer, claimer, "outer claim recorded for the LP");
        assertEq(outerFronted, 0, "nothing delivered to the receiver");
        assertEq(
            pegInContract.getBalance(claimer),
            claimerBalanceBefore + net,
            "fronted RBTC credited to the LP"
        );
        assertEq(
            reenterClaimer,
            address(0),
            "no claim written for re-entrant pegInId"
        );
    }
}
