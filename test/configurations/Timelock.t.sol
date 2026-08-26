// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {ConfigurationsTestBase} from "./ConfigurationsTestBase.sol";
import {FlyoverConfigurations} from "../../src/FlyoverConfigurations.sol";
import {IFlyoverConfigurations} from "../../src/interfaces/IFlyoverConfigurations.sol";

/// @title TimelockTest
/// @notice The two-step time-locked admin path, all four spec cases:
/// (1) queue-then-apply after the delay succeeds;
/// (2) apply before the delay reverts;
/// (3) out-of-bounds values revert at both queue and apply time;
/// (4) a second queue replaces the pending change.
/// Plus exact-eta success, applying with nothing queued, and event emission.
contract TimelockTest is ConfigurationsTestBase {
    /// @dev pending.fixedFee lives at the mutable namespace base + 6 (activePegIn occupies the
    /// first 6 slots: five scalars plus confirmationTiers-length).
    bytes32 private constant _PENDING_FIXED_FEE_SLOT =
        bytes32(uint256(STORAGE_SLOT) + 6);

    function setUp() public {
        _deploy();
    }

    // ------------------------------------------------------ case 1: queue then apply succeeds

    function test_case1_queueThenApplyAfterDelay_succeeds() public {
        IFlyoverConfigurations.PegConfiguration memory c = _queueAlt();

        // Not applied yet: active config is still the seed.
        assertEq(config.getPegInConfiguration().fixedFee, SEED_FIXED_FEE);

        vm.warp(block.timestamp + TIMELOCK_DELAY);
        vm.prank(owner);
        config.applyChange();

        IFlyoverConfigurations.PegConfiguration memory active = config
            .getPegInConfiguration();
        assertEq(active.fixedFee, c.fixedFee);
        assertEq(active.percentageFee, c.percentageFee);
        assertEq(active.minAmount, c.minAmount);
        assertEq(active.maxAmount, c.maxAmount);
        assertEq(active.confirmationTiers.length, c.confirmationTiers.length);
        // Every nested tier field must survive queue+apply (incl. the second tier).
        for (uint256 i = 0; i < c.confirmationTiers.length; ++i) {
            assertEq(
                active.confirmationTiers[i].maxAmount,
                c.confirmationTiers[i].maxAmount
            );
            assertEq(
                active.confirmationTiers[i].confirmations,
                c.confirmationTiers[i].confirmations
            );
        }
        // fee/confirmation reads now reflect the applied config.
        assertEq(config.calculatePegInFee(0), c.fixedFee);
        assertEq(config.getRequiredPegInBtcConfirmations(1 ether), 2);
        assertEq(config.getRequiredPegInBtcConfirmations(10 ether), 5);
    }

    function test_applyAtExactEta_succeeds() public {
        _queueAlt();
        (, uint256 eta) = config.getPendingChange();
        vm.warp(eta); // block.timestamp == eta is allowed (>=)
        vm.prank(owner);
        config.applyChange();
        assertEq(
            config.getPegInConfiguration().fixedFee,
            _altConfig().fixedFee
        );
    }

    // ------------------------------------------------------ case 2: apply before delay reverts

    function test_case2_applyBeforeDelay_reverts() public {
        _queueAlt();
        (, uint256 eta) = config.getPendingChange();

        vm.warp(eta - 1);
        vm.prank(owner);
        vm.expectRevert(
            abi.encodeWithSelector(
                FlyoverConfigurations.TimelockNotElapsed.selector,
                eta,
                eta - 1
            )
        );
        config.applyChange();

        // The active config is untouched.
        assertEq(config.getPegInConfiguration().fixedFee, SEED_FIXED_FEE);
    }

    function test_applyWithoutQueue_reverts() public {
        vm.prank(owner);
        vm.expectRevert(FlyoverConfigurations.NoQueuedChange.selector);
        config.applyChange();
    }

    // ------------------------------------------------------ case 3: out-of-bounds at both steps

    function test_case3_outOfBounds_revertsAtQueueTime() public {
        IFlyoverConfigurations.PegConfiguration memory c = _altConfig();
        c.fixedFee = BOUND_MAX_FIXED_FEE + 1;
        vm.prank(owner);
        vm.expectRevert(
            abi.encodeWithSelector(
                FlyoverConfigurations.ConfigValueOutOfBounds.selector,
                FlyoverConfigurations.Field.FixedFee,
                BOUND_MAX_FIXED_FEE + 1,
                BOUND_MIN_FIXED_FEE,
                BOUND_MAX_FIXED_FEE
            )
        );
        config.queueChange(c);
    }

    /// @notice applyChange re-validates against the active bounds. Since queueChange blocks
    /// out-of-bounds values, we prove the apply-time guard by queuing a valid change and then
    /// corrupting the stored pending value directly before applying.
    function test_case3_outOfBounds_revertsAtApplyTime() public {
        _queueAlt();
        (, uint256 eta) = config.getPendingChange();

        // Corrupt pending.fixedFee to just above the max bound, bypassing queueChange.
        vm.store(
            address(config),
            _PENDING_FIXED_FEE_SLOT,
            bytes32(BOUND_MAX_FIXED_FEE + 1)
        );
        // Sanity: the poke landed on the pending value.
        (IFlyoverConfigurations.PegConfiguration memory pending, ) = config
            .getPendingChange();
        assertEq(pending.fixedFee, BOUND_MAX_FIXED_FEE + 1);

        vm.warp(eta);
        vm.prank(owner);
        vm.expectRevert(
            abi.encodeWithSelector(
                FlyoverConfigurations.ConfigValueOutOfBounds.selector,
                FlyoverConfigurations.Field.FixedFee,
                BOUND_MAX_FIXED_FEE + 1,
                BOUND_MIN_FIXED_FEE,
                BOUND_MAX_FIXED_FEE
            )
        );
        config.applyChange();

        // The active config remains the seed; the corrupted change never took effect.
        assertEq(config.getPegInConfiguration().fixedFee, SEED_FIXED_FEE);
    }

    // ------------------------------------------------------ case 4: second queue replaces pending

    function test_case4_secondQueueReplacesPending() public {
        // First queued change.
        IFlyoverConfigurations.PegConfiguration memory first = _altConfig();
        first.fixedFee = 2000 * SAT;
        vm.prank(owner);
        config.queueChange(first);

        // Advance time so the second queue gets a distinct eta.
        vm.warp(block.timestamp + 1 hours);
        uint256 expectedEta = block.timestamp + TIMELOCK_DELAY;

        // Second queued change replaces the first.
        IFlyoverConfigurations.PegConfiguration memory second = _altConfig();
        second.fixedFee = 3000 * SAT;
        vm.prank(owner);
        config.queueChange(second);

        (
            IFlyoverConfigurations.PegConfiguration memory pending,
            uint256 eta
        ) = config.getPendingChange();
        assertEq(
            pending.fixedFee,
            3000 * SAT,
            "pending must be the second change"
        );
        assertEq(eta, expectedEta, "eta must be refreshed by the second queue");

        // Applying activates the second change, never the replaced first.
        vm.warp(eta);
        vm.prank(owner);
        config.applyChange();
        assertEq(config.getPegInConfiguration().fixedFee, 3000 * SAT);
    }

    // ------------------------------------------------------ events

    function test_queueChange_emitsChangeQueued() public {
        IFlyoverConfigurations.PegConfiguration memory c = _altConfig();
        uint256 expectedEta = block.timestamp + TIMELOCK_DELAY;

        vm.expectEmit(true, true, true, true, address(config));
        emit FlyoverConfigurations.ChangeQueued(c, expectedEta);
        vm.prank(owner);
        config.queueChange(c);
    }

    function test_applyChange_emitsChangeApplied() public {
        IFlyoverConfigurations.PegConfiguration memory c = _queueAlt();
        vm.warp(block.timestamp + TIMELOCK_DELAY);

        vm.expectEmit(true, true, true, true, address(config));
        emit FlyoverConfigurations.ChangeApplied(c);
        vm.prank(owner);
        config.applyChange();
    }

    // ================================================================== bounds changes (FLY-2523)
    //
    // The bounds run through the same two-step time lock as a configuration change. These mirror
    // the four cases above for the bounds path, then pin the two rules unique to it: a pair may
    // not invert, and a pair the active configuration falls outside is rejected at apply time.

    /// @dev pendingMin.fixedFee lives at the bounds namespace base + 13 (timelockDelay occupies
    /// slot 0, then min and max take 6 slots each: five scalars plus confirmationTiers-length).
    bytes32 private constant _PENDING_MIN_FIXED_FEE_SLOT =
        bytes32(uint256(BOUNDS_SLOT) + 13);

    // ------------------------------------------------ case 1: queue then apply after the delay

    function test_bounds_queueThenApplyAfterDelay_succeeds() public {
        _queueWideBounds();

        // Not applied yet: the active bounds are still the deployment ones.
        (IFlyoverConfigurations.PegConfiguration memory minBefore, ) = config
            .getPegInConfigurationBounds();
        assertEq(minBefore.fixedFee, BOUND_MIN_FIXED_FEE);

        vm.warp(block.timestamp + TIMELOCK_DELAY);
        vm.prank(owner);
        config.applyBoundsChange();

        (
            IFlyoverConfigurations.PegConfiguration memory min,
            IFlyoverConfigurations.PegConfiguration memory max
        ) = config.getPegInConfigurationBounds();
        assertEq(min.fixedFee, WIDE_MIN_FIXED_FEE);
        assertEq(min.percentageFee, WIDE_MIN_PCT);
        assertEq(min.minAmount, WIDE_MIN_MIN_AMOUNT);
        assertEq(min.maxAmount, WIDE_MIN_MAX_AMOUNT);
        assertEq(max.fixedFee, WIDE_MAX_FIXED_FEE);
        assertEq(max.percentageFee, WIDE_MAX_PCT);
        assertEq(max.minAmount, WIDE_MAX_MIN_AMOUNT);
        assertEq(max.maxAmount, WIDE_MAX_MAX_AMOUNT);

        // The pending slot is cleared.
        (, , uint256 eta) = config.getPendingBoundsChange();
        assertEq(eta, 0);
    }

    function test_bounds_applyAtExactEta_succeeds() public {
        _queueWideBounds();
        (, , uint256 eta) = config.getPendingBoundsChange();
        vm.warp(eta); // block.timestamp == eta is allowed (>=)
        vm.prank(owner);
        config.applyBoundsChange();
        (IFlyoverConfigurations.PegConfiguration memory min, ) = config
            .getPegInConfigurationBounds();
        assertEq(min.fixedFee, WIDE_MIN_FIXED_FEE);
    }

    /// @notice The point of the feature: after widening, a fee the old bounds rejected is
    /// accepted, and the widening required no upgrade.
    function test_bounds_widening_admitsPreviouslyRejectedValue() public {
        uint256 highFee = BOUND_MAX_FIXED_FEE + 1 ether; // above the old max, below the new one

        // Rejected under the deployment bounds.
        IFlyoverConfigurations.PegConfiguration memory c = _altConfig();
        c.fixedFee = highFee;
        vm.prank(owner);
        vm.expectRevert(
            abi.encodeWithSelector(
                FlyoverConfigurations.ConfigValueOutOfBounds.selector,
                FlyoverConfigurations.Field.FixedFee,
                highFee,
                BOUND_MIN_FIXED_FEE,
                BOUND_MAX_FIXED_FEE
            )
        );
        config.queueChange(c);

        _applyBounds(_wideMin(), _wideMax());

        // Accepted under the widened bounds.
        vm.prank(owner);
        config.queueChange(c);
        (IFlyoverConfigurations.PegConfiguration memory pending, ) = config
            .getPendingChange();
        assertEq(pending.fixedFee, highFee);
    }

    /// @notice The mirror direction: after tightening, a value the old bounds accepted is
    /// rejected, so a queued change is measured against the bounds in force when it is queued.
    function test_bounds_tightening_rejectsPreviouslyAcceptedValue() public {
        uint256 fee = _altConfig().fixedFee; // accepted under the deployment bounds

        // Tighten the fixed-fee ceiling to just below that value. The seed config's fixedFee is
        // lower still, so the active configuration stays inside the new pair.
        IFlyoverConfigurations.PegConfiguration memory tightMax = _boundsMax();
        tightMax.fixedFee = fee - 1;
        _applyBounds(_boundsMin(), tightMax);

        IFlyoverConfigurations.PegConfiguration memory c = _altConfig();
        vm.prank(owner);
        vm.expectRevert(
            abi.encodeWithSelector(
                FlyoverConfigurations.ConfigValueOutOfBounds.selector,
                FlyoverConfigurations.Field.FixedFee,
                fee,
                BOUND_MIN_FIXED_FEE,
                fee - 1
            )
        );
        config.queueChange(c);
    }

    // ------------------------------------------------------- case 2: apply before delay reverts

    function test_bounds_applyBeforeDelay_reverts() public {
        _queueWideBounds();
        (, , uint256 eta) = config.getPendingBoundsChange();

        vm.warp(eta - 1);
        vm.prank(owner);
        vm.expectRevert(
            abi.encodeWithSelector(
                FlyoverConfigurations.TimelockNotElapsed.selector,
                eta,
                eta - 1
            )
        );
        config.applyBoundsChange();

        // The active bounds are untouched.
        (IFlyoverConfigurations.PegConfiguration memory min, ) = config
            .getPegInConfigurationBounds();
        assertEq(min.fixedFee, BOUND_MIN_FIXED_FEE);
    }

    function test_bounds_applyWithoutQueue_reverts() public {
        vm.prank(owner);
        vm.expectRevert(FlyoverConfigurations.NoQueuedBoundsChange.selector);
        config.applyBoundsChange();
    }

    // ----------------------------------------------------- case 3: re-validated at both steps

    function test_bounds_invertedPair_revertsAtQueueTime() public {
        IFlyoverConfigurations.PegConfiguration memory min = _boundsMin();
        min.fixedFee = BOUND_MAX_FIXED_FEE + 1; // min above max
        vm.prank(owner);
        vm.expectRevert(
            abi.encodeWithSelector(
                FlyoverConfigurations.InvalidBounds.selector,
                FlyoverConfigurations.Field.FixedFee,
                BOUND_MAX_FIXED_FEE + 1,
                BOUND_MAX_FIXED_FEE
            )
        );
        config.queueBoundsChange(min, _boundsMax());
    }

    /// @notice applyBoundsChange re-validates well-formedness. Since queueBoundsChange blocks an
    /// inverted pair, we prove the apply-time guard by queuing a valid pair and then corrupting
    /// the stored pending min directly before applying.
    function test_bounds_invertedPair_revertsAtApplyTime() public {
        _queueWideBounds();
        (, , uint256 eta) = config.getPendingBoundsChange();

        // Corrupt pendingMin.fixedFee to just above pendingMax.fixedFee, bypassing the queue.
        uint256 corrupted = WIDE_MAX_FIXED_FEE + 1;
        vm.store(
            address(config),
            _PENDING_MIN_FIXED_FEE_SLOT,
            bytes32(corrupted)
        );
        // Sanity: the poke landed on the pending min.
        (IFlyoverConfigurations.PegConfiguration memory pendingMin, , ) = config
            .getPendingBoundsChange();
        assertEq(pendingMin.fixedFee, corrupted);

        vm.warp(eta);
        vm.prank(owner);
        vm.expectRevert(
            abi.encodeWithSelector(
                FlyoverConfigurations.InvalidBounds.selector,
                FlyoverConfigurations.Field.FixedFee,
                corrupted,
                WIDE_MAX_FIXED_FEE
            )
        );
        config.applyBoundsChange();

        // The active bounds remain the deployment ones.
        (IFlyoverConfigurations.PegConfiguration memory min, ) = config
            .getPegInConfigurationBounds();
        assertEq(min.fixedFee, BOUND_MIN_FIXED_FEE);
    }

    // --------------------------------------------------- case 4: second queue replaces pending

    function test_bounds_secondQueueReplacesPending() public {
        // First queued pair.
        IFlyoverConfigurations.PegConfiguration memory firstMax = _wideMax();
        firstMax.fixedFee = 2 ether;
        vm.prank(owner);
        config.queueBoundsChange(_wideMin(), firstMax);

        // Advance time so the second queue gets a distinct eta.
        vm.warp(block.timestamp + 1 hours);
        uint256 expectedEta = block.timestamp + TIMELOCK_DELAY;

        // Second queued pair replaces the first.
        IFlyoverConfigurations.PegConfiguration memory secondMax = _wideMax();
        secondMax.fixedFee = 3 ether;
        vm.prank(owner);
        config.queueBoundsChange(_wideMin(), secondMax);

        (
            ,
            IFlyoverConfigurations.PegConfiguration memory pendingMax,
            uint256 eta
        ) = config.getPendingBoundsChange();
        assertEq(
            pendingMax.fixedFee,
            3 ether,
            "pending must be the second pair"
        );
        assertEq(eta, expectedEta, "eta must be refreshed by the second queue");

        // Applying activates the second pair, never the replaced first.
        vm.warp(eta);
        vm.prank(owner);
        config.applyBoundsChange();
        (, IFlyoverConfigurations.PegConfiguration memory max) = config
            .getPegInConfigurationBounds();
        assertEq(max.fixedFee, 3 ether);
    }

    // ------------------------------------- the documented decision: active config must still fit

    /// @notice Bounds that would strand the active configuration outside them are rejected at
    /// apply time. This is the choice documented on applyBoundsChange: the active configuration
    /// is always within the active bounds, with no qualification a reader has to know about.
    function test_bounds_applyRejectedWhenActiveConfigFallsOutside() public {
        // Tighten the fixed-fee floor above the seed config's fixedFee.
        IFlyoverConfigurations.PegConfiguration memory min = _boundsMin();
        min.fixedFee = SEED_FIXED_FEE + 1;

        vm.prank(owner);
        config.queueBoundsChange(min, _boundsMax());
        vm.warp(block.timestamp + TIMELOCK_DELAY);

        vm.prank(owner);
        vm.expectRevert(
            abi.encodeWithSelector(
                FlyoverConfigurations.ActiveConfigOutsideNewBounds.selector,
                FlyoverConfigurations.Field.FixedFee,
                SEED_FIXED_FEE,
                SEED_FIXED_FEE + 1,
                BOUND_MAX_FIXED_FEE
            )
        );
        config.applyBoundsChange();

        // Nothing moved: the bounds and the active configuration are both unchanged.
        (IFlyoverConfigurations.PegConfiguration memory activeMin, ) = config
            .getPegInConfigurationBounds();
        assertEq(activeMin.fixedFee, BOUND_MIN_FIXED_FEE);
        assertEq(config.getPegInConfiguration().fixedFee, SEED_FIXED_FEE);
    }

    /// @notice The documented remedy for the case above: move the active configuration into the
    /// new range first, then the same tightening applies. Both steps are time-locked, and the
    /// configuration change can run during the bounds change's own delay.
    function test_bounds_tighteningSucceedsAfterMovingActiveConfigFirst()
        public
    {
        uint256 newFloor = SEED_FIXED_FEE + 1000 * SAT;

        IFlyoverConfigurations.PegConfiguration memory min = _boundsMin();
        min.fixedFee = newFloor;

        // Queue the tightening now; the configuration move happens during its delay.
        vm.prank(owner);
        config.queueBoundsChange(min, _boundsMax());

        IFlyoverConfigurations.PegConfiguration memory c = _altConfig();
        c.fixedFee = newFloor; // inside both the old and the new bounds
        _applyConfig(c);

        (, , uint256 eta) = config.getPendingBoundsChange();
        vm.warp(eta);
        vm.prank(owner);
        config.applyBoundsChange();

        (IFlyoverConfigurations.PegConfiguration memory activeMin, ) = config
            .getPegInConfigurationBounds();
        assertEq(activeMin.fixedFee, newFloor);
        assertEq(config.getPegInConfiguration().fixedFee, newFloor);
    }

    // ------------------------------------------------------------ the two pending slots are separate

    /// @notice A queued bounds change and a queued configuration change occupy independent slots,
    /// so queueing one never clobbers the other.
    function test_bounds_pendingSlotIsIndependentOfConfigPending() public {
        IFlyoverConfigurations.PegConfiguration memory c = _queueAlt();
        _queueWideBounds();

        (
            IFlyoverConfigurations.PegConfiguration memory pending,
            uint256 cEta
        ) = config.getPendingChange();
        (
            IFlyoverConfigurations.PegConfiguration memory pendingMin,
            ,
            uint256 bEta
        ) = config.getPendingBoundsChange();

        assertEq(pending.fixedFee, c.fixedFee, "config pending survived");
        assertEq(pendingMin.fixedFee, WIDE_MIN_FIXED_FEE, "bounds pending set");
        assertTrue(cEta != 0 && bEta != 0);

        // Applying the bounds leaves the queued configuration in place.
        vm.warp(bEta);
        vm.prank(owner);
        config.applyBoundsChange();

        (pending, cEta) = config.getPendingChange();
        assertEq(pending.fixedFee, c.fixedFee);
        assertTrue(cEta != 0);

        vm.prank(owner);
        config.applyChange();
        assertEq(config.getPegInConfiguration().fixedFee, c.fixedFee);
    }

    // ------------------------------------------------------------------------------ events

    function test_queueBoundsChange_emitsBoundsChangeQueued() public {
        IFlyoverConfigurations.PegConfiguration memory min = _wideMin();
        IFlyoverConfigurations.PegConfiguration memory max = _wideMax();
        uint256 expectedEta = block.timestamp + TIMELOCK_DELAY;

        vm.expectEmit(true, true, true, true, address(config));
        emit FlyoverConfigurations.BoundsChangeQueued(min, max, expectedEta);
        vm.prank(owner);
        config.queueBoundsChange(min, max);
    }

    function test_applyBoundsChange_emitsBoundsChangeApplied() public {
        _queueWideBounds();
        vm.warp(block.timestamp + TIMELOCK_DELAY);

        vm.expectEmit(true, true, true, true, address(config));
        emit FlyoverConfigurations.BoundsChangeApplied(_wideMin(), _wideMax());
        vm.prank(owner);
        config.applyBoundsChange();
    }
}
