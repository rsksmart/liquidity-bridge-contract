// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {ConfigurationsTestBase} from "./ConfigurationsTestBase.sol";
import {FlyoverConfigurations} from "../../src/FlyoverConfigurations.sol";
import {IFlyoverConfigurations} from "../../src/interfaces/IFlyoverConfigurations.sol";

contract TimelockTest is ConfigurationsTestBase {
    /// @dev pending.fixedFee slot: namespace base + 6 (five scalars and tiers length in active config).
    bytes32 private constant _PENDING_FIXED_FEE_SLOT =
        bytes32(uint256(STORAGE_SLOT) + 6);

    function setUp() public {
        _deploy();
    }

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

    /// @notice applyChange re-validates against the immutable bounds. Since queueChange blocks
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
}
