// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {RequestPegInTestBase} from "./RequestPegInTestBase.sol";
import {IPegInCommitFirst} from "../../src/interfaces/IPegInCommitFirst.sol";
import {IPauseRegistry} from "../../src/interfaces/IPauseRegistry.sol";
import {Flyover} from "../../src/libraries/Flyover.sol";

/// @title requestPegIn atomicity and pause-regression tests
/// @notice Any failed check leaves no claim written and no funds delivered, and a hard pause
/// blocks the claim entirely.
contract RequestPegInAtomicityTest is RequestPegInTestBase {
    function test_failedCheck_isAtomic_unregistered() public {
        address unregistered = makeAddr("unregisteredAtomic");
        bytes memory btcTx = _depositTx(unregistered, DEFAULT_AMOUNT);
        bytes32 pegInId = _pegInIdForTx(unregistered, btcTx);
        uint256 userBefore = unregistered.balance;

        vm.prank(claimer);
        vm.expectRevert(
            abi.encodeWithSelector(
                IPegInCommitFirst.AddressNotRegistered.selector,
                unregistered
            )
        );
        pegInContract.requestPegIn{value: 1 ether}(
            unregistered,
            btcTx,
            "",
            bytes32(0),
            0,
            _emptyBranch()
        );

        _assertNoClaim(pegInId);
        assertEq(
            unregistered.balance,
            userBefore,
            "no delivery on unregistered"
        );
    }

    function test_failedCheck_isAtomic_depositOutputNotFound() public {
        bytes memory unrelated = _unrelatedTx();
        // Hashed before the prank: hashTx is an external self-call and would consume it.
        bytes32 txHash = this.hashTx(unrelated);
        bytes32 pegInId = _pegInId(rskUser, txHash);
        uint256 userBefore = rskUser.balance;

        vm.prank(claimer);
        vm.expectRevert(
            abi.encodeWithSelector(
                IPegInCommitFirst.DepositOutputNotFound.selector,
                rskUser,
                txHash
            )
        );
        pegInContract.requestPegIn{value: 1 wei}(
            rskUser,
            unrelated,
            "",
            bytes32(0),
            0,
            _emptyBranch()
        );

        _assertNoClaim(pegInId);
        assertEq(
            rskUser.balance,
            userBefore,
            "no delivery when no output pays the derived address"
        );
    }

    function test_failedCheck_isAtomic_belowMinimum() public {
        uint256 amount = TEST_MIN_PEGIN - Flyover.SAT_TO_WEI_CONVERSION;
        bytes memory btcTx = _depositTx(rskUser, amount);
        bytes32 pegInId = _pegInIdForTx(rskUser, btcTx);
        uint256 userBefore = rskUser.balance;
        uint256 claimerBefore = claimer.balance;
        uint256 sentValue = 1 ether;

        vm.prank(claimer);
        vm.expectRevert(
            abi.encodeWithSelector(
                IPegInCommitFirst.PegInBelowMinimum.selector,
                amount,
                TEST_MIN_PEGIN
            )
        );
        pegInContract.requestPegIn{value: sentValue}(
            rskUser,
            btcTx,
            "",
            bytes32(0),
            0,
            _emptyBranch()
        );

        _assertNoClaim(pegInId);
        assertEq(rskUser.balance, userBefore, "no delivery below minimum");
        assertEq(
            claimer.balance,
            claimerBefore,
            "msg.value held on below-minimum revert"
        );
    }

    function test_failedCheck_isAtomic_insufficientConfirmations() public {
        bridgeMock.setConfirmations(int256(DEFAULT_TIER_CONFIRMATIONS) - 1);
        bytes memory btcTx = _defaultTx();
        bytes32 pegInId = _pegInIdForTx(rskUser, btcTx);
        uint256 userBefore = rskUser.balance;

        vm.prank(claimer);
        vm.expectRevert(
            abi.encodeWithSelector(
                IPegInCommitFirst.InsufficientConfirmations.selector,
                DEFAULT_TIER_CONFIRMATIONS - 1,
                DEFAULT_TIER_CONFIRMATIONS
            )
        );
        pegInContract.requestPegIn{value: 1 ether}(
            rskUser,
            btcTx,
            "",
            bytes32(0),
            0,
            _emptyBranch()
        );

        _assertNoClaim(pegInId);
        assertEq(
            rskUser.balance,
            userBefore,
            "no delivery on insufficient confirmations"
        );
    }

    function test_failedCheck_isAtomic_incorrectFronting() public {
        uint256 amount = DEFAULT_AMOUNT;
        uint256 wrongValue = amount; // not amount - fee
        bytes memory btcTx = _defaultTx();
        bytes32 pegInId = _pegInIdForTx(rskUser, btcTx);
        uint256 userBefore = rskUser.balance;

        vm.prank(claimer);
        vm.expectRevert(
            abi.encodeWithSelector(
                IPegInCommitFirst.IncorrectFronting.selector,
                amount - _expectedFee(amount),
                wrongValue
            )
        );
        pegInContract.requestPegIn{value: wrongValue}(
            rskUser,
            btcTx,
            "",
            bytes32(0),
            0,
            _emptyBranch()
        );

        _assertNoClaim(pegInId);
        assertEq(
            rskUser.balance,
            userBefore,
            "no delivery on incorrect fronting"
        );
    }

    function test_revert_whenHardPaused() public {
        vm.prank(owner);
        pauseRegistry.setPauseLevel(
            IPauseRegistry.PauseLevel.Hard,
            "Hard pause regression"
        );

        uint256 amount = DEFAULT_AMOUNT;
        uint256 net = amount - _expectedFee(amount);
        bytes memory btcTx = _defaultTx();
        bytes32 pegInId = _pegInIdForTx(rskUser, btcTx);
        uint256 userBefore = rskUser.balance;

        vm.prank(claimer);
        vm.expectRevert(Flyover.EnforcedPause.selector);
        pegInContract.requestPegIn{value: net}(
            rskUser,
            btcTx,
            "",
            bytes32(0),
            0,
            _emptyBranch()
        );

        _assertNoClaim(pegInId);
        assertEq(rskUser.balance, userBefore, "no delivery when hard paused");
    }

    function _assertNoClaim(bytes32 pegInId) internal view {
        (
            address claimerAddr,
            uint256 frontedAmount,
            uint256 feeAtClaim,
            uint256 requestBlock
        ) = _readClaim(pegInId);
        assertEq(claimerAddr, address(0), "no claimer written");
        assertEq(frontedAmount, 0, "no fronted amount written");
        assertEq(feeAtClaim, 0, "no fee written");
        assertEq(requestBlock, 0, "no request block written");
    }
}
