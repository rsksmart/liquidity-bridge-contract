// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {E4TestBase} from "./E4TestBase.sol";
import {PegInContract} from "../../src/PegInContract.sol";
import {IPegIn} from "../../src/interfaces/IPegIn.sol";

/// @title UnclaimedSlash
/// @notice E4.4: a valid, registered peg-in left unclaimed past its deadline triggers a global slash;
/// unregistered or below-minimum peg-ins are not penalizable.
contract UnclaimedSlashTest is E4TestBase {
    uint256 internal constant AMOUNT = 2 ether;

    function setUp() public {
        _deployAll();
    }

    function _minAmount() internal view returns (uint256) {
        return config.getPegInConfiguration().minAmount;
    }

    function _pastDeadline(address addr) internal {
        vm.roll(registry.getRegistrationBlock(addr) + CLAIM_DEADLINE_BLOCKS + 1);
    }

    function test_UnclaimedValid_TriggersGlobalSlash() public {
        // Move past the LP collateral grace window, then register the user's address.
        vm.roll(block.number + collateral.getGraceWindow() + 1);
        _register(user, AMOUNT);
        _pastDeadline(user);

        uint256 collBefore = collateral.getPegInCollateral(lp) + collateral.getPegInCollateral(otherLp);

        vm.prank(otherLp);
        pegIn.slashUnclaimedPegIn(user, AMOUNT, keccak256("unclaimed"));

        uint256 collAfter = collateral.getPegInCollateral(lp) + collateral.getPegInCollateral(otherLp);
        assertLt(collAfter, collBefore, "global slash reduced LP collateral");

        // Peg-in is marked processed so it cannot be slashed again.
        PegInContract.PegInClaim memory claim = pegIn.getPegInClaim(user, keccak256("unclaimed"));
        assertTrue(claim.resolved, "peg-in marked processed");
    }

    function test_Unregistered_DoesNotSlash() public {
        address stranger = makeAddr("stranger");
        vm.roll(block.number + 200);
        vm.prank(otherLp);
        vm.expectRevert(abi.encodeWithSelector(PegInContract.AddressNotRegistered.selector, stranger));
        pegIn.slashUnclaimedPegIn(stranger, AMOUNT, keccak256("x"));
    }

    function test_BelowMinimum_DoesNotSlash() public {
        vm.roll(block.number + collateral.getGraceWindow() + 1);
        _register(user, AMOUNT);
        _pastDeadline(user);

        uint256 belowMin = _minAmount() - 1;
        vm.prank(otherLp);
        vm.expectRevert(abi.encodeWithSelector(IPegIn.AmountUnderMinimum.selector, _minAmount()));
        pegIn.slashUnclaimedPegIn(user, belowMin, keccak256("small"));
    }

    function test_BeforeDeadline_Reverts() public {
        _register(user, AMOUNT);
        uint256 deadlineBlock = registry.getRegistrationBlock(user) + CLAIM_DEADLINE_BLOCKS;
        vm.prank(otherLp);
        vm.expectRevert(abi.encodeWithSelector(PegInContract.ClaimDeadlineNotReached.selector, deadlineBlock));
        pegIn.slashUnclaimedPegIn(user, AMOUNT, keccak256("early"));
    }

    function test_AlreadyClaimed_NotSlashable() public {
        vm.roll(block.number + collateral.getGraceWindow() + 1);
        _register(user, AMOUNT);
        bridge.setConfirmations(6);

        uint256 net = AMOUNT - _fee(AMOUNT);
        bytes32 txHash = keccak256("claimed");
        vm.prank(lp);
        pegIn.requestPegIn{value: net}(user, AMOUNT, txHash, new bytes(0));

        _pastDeadline(user);
        vm.prank(otherLp);
        vm.expectRevert(
            abi.encodeWithSelector(PegInContract.PegInAlreadyProcessed.selector, pegIn.pegInId(user, txHash))
        );
        pegIn.slashUnclaimedPegIn(user, AMOUNT, txHash);
    }
}
