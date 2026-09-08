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
        bytes memory btcTx = _defaultTx();
        bytes32 pegInId = _pegInIdForTx(rskUser, btcTx);

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

        bytes32 returnedId = _requestPegInTx(
            claimer,
            rskUser,
            btcTx,
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
        bytes memory btcTx = _defaultTx();
        bytes32 pegInId = _pegInIdForTx(rskUser, btcTx);

        _requestPegInTx(claimer, rskUser, btcTx, expectedNet);

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

    function test_minAmount_immutableAfterConfigRaise() public {
        uint256 amount = DEFAULT_AMOUNT;
        uint256 expectedNet = amount - _expectedFee(amount);
        bytes memory btcTx = _defaultTx();
        bytes32 pegInId = _pegInIdForTx(rskUser, btcTx);

        _requestPegInTx(claimer, rskUser, btcTx, expectedNet);

        (
            address claimerAddrBefore,
            uint256 frontedBefore,
            uint256 feeBefore,
            uint256 requestBlockBefore
        ) = _readClaim(pegInId);

        configurations.setAmountBounds(DEFAULT_AMOUNT + 1, DEFAULT_MAX_AMOUNT);

        (
            address claimerAddrAfter,
            uint256 frontedAfter,
            uint256 feeAfter,
            uint256 requestBlockAfter
        ) = _readClaim(pegInId);
        assertEq(claimerAddrAfter, claimerAddrBefore, "claimer unchanged");
        assertEq(frontedAfter, frontedBefore, "frontedAmount unchanged");
        assertEq(feeAfter, feeBefore, "feeAtClaim unchanged");
        assertEq(
            requestBlockAfter,
            requestBlockBefore,
            "requestBlock unchanged"
        );
    }

    /// @notice The amount is read off the deposit output, so a caller who wants a different
    /// amount has to present a different deposit. Two deposits of different sizes, claimed with
    /// nothing but the transaction changing, produce two different peg-in amounts.
    function test_amount_followsTheDepositOutput() public {
        address second = makeAddr("rskUserSecond");
        registry.harness_seedRegistration(second, makeAddr("registrant3"), 1);

        uint256 small = 0.5 ether;
        uint256 large = 20 ether;
        vm.deal(claimer, 100 ether);

        bytes memory smallTx = _depositTx(rskUser, small);
        bytes memory largeTx = _depositTx(second, large);

        vm.expectEmit(true, true, true, true);
        emit IPegInCommitFirst.PegInRequested(
            _pegInIdForTx(rskUser, smallTx),
            claimer,
            rskUser,
            small,
            small - _expectedFee(small),
            true
        );
        _requestPegInTx(claimer, rskUser, smallTx, small - _expectedFee(small));

        vm.expectEmit(true, true, true, true);
        emit IPegInCommitFirst.PegInRequested(
            _pegInIdForTx(second, largeTx),
            claimer,
            second,
            large,
            large - _expectedFee(large),
            true
        );
        _requestPegInTx(claimer, second, largeTx, large - _expectedFee(large));
    }

    /// @notice Satoshi-to-wei conversion pinned to a literal fixture, so an off-by-a-power-of-ten
    /// in the scaling cannot pass CI. 123_456_789 sats is 1.23456789 RBTC; every neighbouring
    /// power of ten is a different number and would fail this assertion.
    function test_satToWei_pinnedFixture() public {
        uint64 depositSats = 123_456_789;
        uint256 expectedAmount = 1.23456789 ether;
        assertEq(
            uint256(depositSats) * 10 ** 10,
            expectedAmount,
            "fixture self-check: 123456789 sats == 1.23456789 ether"
        );

        bytes memory btcTx = _buildTx(
            _depositPkScript(rskUser),
            depositSats,
            42
        );
        uint256 net = expectedAmount - _expectedFee(expectedAmount);
        vm.deal(claimer, 100 ether);

        vm.expectEmit(true, true, true, true);
        emit IPegInCommitFirst.PegInRequested(
            _pegInIdForTx(rskUser, btcTx),
            claimer,
            rskUser,
            expectedAmount,
            net,
            true
        );
        _requestPegInTx(claimer, rskUser, btcTx, net);
    }
}
