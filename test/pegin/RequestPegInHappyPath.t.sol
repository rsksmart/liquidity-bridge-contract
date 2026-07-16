// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {RequestPegInTestBase} from "./RequestPegInTestBase.sol";
import {IPegInCommitFirst} from "../../src/interfaces/IPegInCommitFirst.sol";

/// @title requestPegIn happy-path, claim record, fee snapshot, and event tests
contract RequestPegInHappyPathTest is RequestPegInTestBase {
    function test_setUp_deploysWiresAndSeeds() public view {
        assertEq(
            pegInContract.getPegInAddressRegistry(),
            address(registry),
            "registry wired"
        );
        assertEq(
            pegInContract.getFlyoverConfigurations(),
            address(configurations),
            "configurations wired"
        );
        assertTrue(
            registry.isRegistered(rskUser),
            "rskUser seeded as registered"
        );
        assertEq(
            configurations.calculatePegInFee(DEFAULT_AMOUNT),
            _expectedFee(DEFAULT_AMOUNT),
            "fee formula"
        );
    }

    function test_happyPath_claimRecordAndDelivery() public {
        uint256 amount = DEFAULT_AMOUNT;
        uint256 fee = _expectedFee(amount);
        uint256 expectedNet = amount - fee;
        bytes32 pegInId = _pegInId(rskUser, DEFAULT_BTC_TX_HASH);

        uint256 claimerBefore = claimer.balance;
        uint256 userBefore = rskUser.balance;

        vm.expectEmit(true, true, true, true);
        emit IPegInCommitFirst.PegInRequested(
            pegInId,
            claimer,
            rskUser,
            amount,
            expectedNet,
            true
        );

        bytes32 returnedId = _requestPegIn(
            claimer,
            rskUser,
            amount,
            DEFAULT_BTC_TX_HASH,
            expectedNet
        );

        assertEq(returnedId, pegInId, "returned pegInId");
        assertEq(
            rskUser.balance,
            userBefore + expectedNet,
            "user received net"
        );
        assertEq(
            claimer.balance,
            claimerBefore - expectedNet,
            "claimer spent msg.value"
        );

        (
            address claimerAddr,
            uint256 frontedAmount,
            uint256 feeAtClaim,
            uint256 requestBlock
        ) = _readClaim(pegInId);
        assertEq(claimerAddr, claimer, "claim.claimer");
        assertEq(
            frontedAmount,
            expectedNet,
            "claim.frontedAmount == msg.value"
        );
        assertEq(feeAtClaim, fee, "claim.feeAtClaim == fee at call time");
        assertEq(requestBlock, block.number, "claim.requestBlock");
    }

    function test_feeAtClaim_immutableAfterConfigChange() public {
        uint256 amount = DEFAULT_AMOUNT;
        uint256 fee = _expectedFee(amount);
        uint256 expectedNet = amount - fee;
        bytes32 pegInId = _pegInId(rskUser, DEFAULT_BTC_TX_HASH);

        _requestPegIn(
            claimer,
            rskUser,
            amount,
            DEFAULT_BTC_TX_HASH,
            expectedNet
        );

        (, , uint256 feeAtClaimBefore, ) = _readClaim(pegInId);
        assertEq(feeAtClaimBefore, fee, "fee snapshot at claim");

        // Mutate the live configuration well away from the snapshot value.
        configurations.setFee(
            DEFAULT_FIXED_FEE * 10,
            DEFAULT_PERCENTAGE_FEE * 5
        );
        assertTrue(
            configurations.calculatePegInFee(amount) != fee,
            "sanity: live fee changed"
        );

        (, , uint256 feeAtClaimAfter, ) = _readClaim(pegInId);
        assertEq(
            feeAtClaimAfter,
            feeAtClaimBefore,
            "recorded feeAtClaim unchanged after config change"
        );
    }
}
