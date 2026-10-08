// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {RequestPegInTestBase} from "./RequestPegInTestBase.sol";
import {Flyover} from "../../src/libraries/Flyover.sol";

/// @title requestPegIn registered peg-in provider gate
/// @notice An unregistered caller reverts before the witness check, before an existing claim,
/// and before any bridge call. A peg-out-only provider is not registered for peg-in.
contract RequestPegInProviderGateTest is RequestPegInTestBase {
    struct PegInGateSnapshot {
        bytes btcTx;
        uint256 net;
        bytes32 pegInId;
        uint256 contractBalance;
        uint256 userBalance;
        address storedClaimer;
        uint256 frontedAmount;
        uint256 feeAtClaim;
        uint256 requestBlock;
    }

    function test_revert_unregisteredCaller() public {
        address stranger = makeAddr("stranger");
        vm.deal(stranger, 100 ether);

        PegInGateSnapshot memory before = _snapshotDefaultPegIn();
        _requestPegInExpectingUnregistered(stranger, before);

        (address storedClaimer, , , ) = _readClaim(before.pegInId);
        assertEq(storedClaimer, address(0), "no claim written");
    }

    function test_revert_pegOutOnlyCaller() public {
        setupProviders();

        PegInGateSnapshot memory before = _snapshotDefaultPegIn();
        _requestPegInExpectingUnregistered(pegOutLp, before);
    }

    function test_revert_unregisteredCaller_existingClaim() public {
        PegInGateSnapshot memory pending = _snapshotDefaultPegIn();
        _requestPegInTx(claimer, rskUser, pending.btcTx, pending.net);

        address stranger = makeAddr("stranger");
        vm.deal(stranger, 100 ether);

        PegInGateSnapshot memory before = _snapshotDefaultPegIn();
        _requestPegInExpectingUnregistered(stranger, before);

        (address storedClaimer, , , ) = _readClaim(before.pegInId);
        assertEq(storedClaimer, claimer, "stored claimer stays claimer");
    }

    /// @notice The default deposit, the net value a registered caller would send, and the
    /// contract, user, and claim state at the moment the rejected call is about to happen.
    function _snapshotDefaultPegIn()
        internal
        view
        returns (PegInGateSnapshot memory snap)
    {
        snap.btcTx = _defaultTx();
        snap.net = DEFAULT_AMOUNT - _expectedFee(DEFAULT_AMOUNT);
        snap.pegInId = _pegInIdForTx(rskUser, snap.btcTx);
        snap.contractBalance = address(pegInContract).balance;
        snap.userBalance = rskUser.balance;
        (
            snap.storedClaimer,
            snap.frontedAmount,
            snap.feeAtClaim,
            snap.requestBlock
        ) = _readClaim(snap.pegInId);
    }

    function _requestPegInExpectingUnregistered(
        address caller,
        PegInGateSnapshot memory before
    ) internal {
        vm.prank(caller);
        vm.expectRevert(
            abi.encodeWithSelector(
                Flyover.ProviderNotRegistered.selector,
                caller
            )
        );
        pegInContract.requestPegIn{value: before.net}(
            rskUser,
            before.btcTx,
            bytes32(0),
            0,
            _emptyBranch()
        );

        assertEq(address(pegInContract).balance, before.contractBalance);
        assertEq(rskUser.balance, before.userBalance);
        (
            address storedClaimer,
            uint256 frontedAmount,
            uint256 feeAtClaim,
            uint256 requestBlock
        ) = _readClaim(before.pegInId);
        assertEq(storedClaimer, before.storedClaimer);
        assertEq(frontedAmount, before.frontedAmount);
        assertEq(feeAtClaim, before.feeAtClaim);
        assertEq(requestBlock, before.requestBlock);
    }
}
