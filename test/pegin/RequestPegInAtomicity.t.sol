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
        bytes32 pegInId = _pegInId(unregistered, DEFAULT_BTC_TX_HASH);
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
            DEFAULT_AMOUNT,
            DEFAULT_BTC_TX_HASH,
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

    function test_failedCheck_isAtomic_insufficientConfirmations() public {
        bridgeMock.setConfirmations(int256(DEFAULT_TIER_CONFIRMATIONS) - 1);
        bytes32 pegInId = _pegInId(rskUser, DEFAULT_BTC_TX_HASH);
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
            DEFAULT_AMOUNT,
            DEFAULT_BTC_TX_HASH,
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
        bytes32 pegInId = _pegInId(rskUser, DEFAULT_BTC_TX_HASH);
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
            amount,
            DEFAULT_BTC_TX_HASH,
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
        bytes32 pegInId = _pegInId(rskUser, DEFAULT_BTC_TX_HASH);
        uint256 userBefore = rskUser.balance;

        vm.prank(claimer);
        vm.expectRevert(Flyover.EnforcedPause.selector);
        pegInContract.requestPegIn{value: net}(
            rskUser,
            amount,
            DEFAULT_BTC_TX_HASH,
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
