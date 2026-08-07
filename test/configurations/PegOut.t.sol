// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {ConfigurationsTestBase} from "./ConfigurationsTestBase.sol";
import {FlyoverConfigurations} from "../../src/FlyoverConfigurations.sol";
import {IFlyoverConfigurations} from "../../src/interfaces/IFlyoverConfigurations.sol";

/// @title PegOutConfigurationsTest
/// @notice AC coverage for peg-out FlyoverConfigurations: fee, tiers, queue/apply, snapshot.
contract PegOutConfigurationsTest is ConfigurationsTestBase {
    function setUp() public {
        _deployWithPegOut();
    }

    function _expectedFee(
        uint256 fixedFee,
        uint256 pct,
        uint256 amount
    ) private pure returns (uint256) {
        uint256 fee = fixedFee + (amount * pct) / PCT_DENOMINATOR;
        if (fee > SAT && (fee % SAT) != 0) {
            fee -= (fee % SAT);
        }
        return fee;
    }

    function test_calculatePegOutFee_fixedFloorAndSatoshiRounding()
        public
        view
    {
        assertEq(config.calculatePegOutFee(0), SEED_FIXED_FEE);

        uint256 amount = 123_456_789_012_345;
        uint256 rawFee = SEED_FIXED_FEE + (amount * SEED_PCT) / PCT_DENOMINATOR;
        assertTrue(rawFee % SAT != 0, "test setup: sub-satoshi remainder");

        uint256 got = config.calculatePegOutFee(amount);
        assertEq(got, rawFee - (rawFee % SAT));
        assertEq(got % SAT, 0);
        assertEq(got, _expectedFee(SEED_FIXED_FEE, SEED_PCT, amount));
    }

    function test_getRequiredPegOutBtcConfirmations_tiers() public view {
        assertEq(config.getRequiredPegOutBtcConfirmations(0.5 ether), 1);
        assertEq(config.getRequiredPegOutBtcConfirmations(1 ether), 1);
        assertEq(config.getRequiredPegOutBtcConfirmations(5 ether), 3);
        assertEq(config.getRequiredPegOutBtcConfirmations(10 ether), 3);
        assertEq(config.getRequiredPegOutBtcConfirmations(50 ether), 6);
        assertEq(config.getRequiredPegOutBtcConfirmations(1000 ether), 6);
    }

    function test_queueThenApplyPegOut_updatesActiveAndEmits() public {
        IFlyoverConfigurations.PegOutConfiguration
            memory c = _altPegOutConfig();
        uint256 expectedEta = block.timestamp + TIMELOCK_DELAY;

        vm.expectEmit(true, true, true, true, address(config));
        emit FlyoverConfigurations.PegOutChangeQueued(c, expectedEta);
        vm.prank(owner);
        config.queuePegOutChange(c);

        assertEq(config.getPegOutConfiguration().fixedFee, SEED_FIXED_FEE);

        vm.warp(expectedEta);
        vm.expectEmit(true, true, true, true, address(config));
        emit FlyoverConfigurations.PegOutChangeApplied(c);
        vm.prank(owner);
        config.applyPegOutChange();

        IFlyoverConfigurations.PegOutConfiguration memory active = config
            .getPegOutConfiguration();
        assertEq(active.fixedFee, c.fixedFee);
        assertEq(active.claimWindow, c.claimWindow);
        assertEq(active.callTime, c.callTime);
        assertEq(active.expireTime, c.expireTime);
        assertEq(active.maxMinerFee, c.maxMinerFee);
        assertEq(config.calculatePegOutFee(0), c.fixedFee);
        assertEq(config.getRequiredPegOutBtcConfirmations(1 ether), 2);
    }

    function test_applyPegOut_beforeDelay_reverts() public {
        _queueAltPegOut();
        (, uint256 eta) = config.getPendingPegOutChange();

        vm.warp(eta - 1);
        vm.prank(owner);
        vm.expectRevert(
            abi.encodeWithSelector(
                FlyoverConfigurations.TimelockNotElapsed.selector,
                eta,
                eta - 1
            )
        );
        config.applyPegOutChange();
        assertEq(config.getPegOutConfiguration().fixedFee, SEED_FIXED_FEE);
    }

    /// @notice A later queue/apply must not change a prior in-memory snapshot of fee, deadlines,
    /// and maxMinerFee (escrow should persist that snapshot at request time).
    function test_configChange_leavesPriorSnapshotUntouched() public {
        uint256 amount = 1 ether;
        IFlyoverConfigurations.PegOutConfiguration memory snapshot = config
            .getPegOutConfiguration();
        uint256 snapshottedFee = config.calculatePegOutFee(amount);

        IFlyoverConfigurations.PegOutConfiguration
            memory next = _queueAltPegOut();
        vm.warp(block.timestamp + TIMELOCK_DELAY);
        vm.prank(owner);
        config.applyPegOutChange();

        IFlyoverConfigurations.PegOutConfiguration memory live = config
            .getPegOutConfiguration();
        assertEq(live.fixedFee, next.fixedFee);
        assertEq(live.claimWindow, next.claimWindow);
        assertEq(live.callTime, next.callTime);
        assertEq(live.maxMinerFee, next.maxMinerFee);
        assertEq(
            config.calculatePegOutFee(amount),
            _expectedFee(next.fixedFee, next.percentageFee, amount)
        );

        assertEq(snapshot.fixedFee, SEED_FIXED_FEE);
        assertEq(snapshot.percentageFee, SEED_PCT);
        assertEq(snapshot.claimWindow, SEED_CLAIM_WINDOW);
        assertEq(snapshot.callTime, SEED_CALL_TIME);
        assertEq(snapshot.expireTime, SEED_EXPIRE_TIME);
        assertEq(snapshot.maxMinerFee, SEED_MAX_MINER_FEE);
        assertEq(
            snapshottedFee,
            _expectedFee(SEED_FIXED_FEE, SEED_PCT, amount)
        );
        assertTrue(snapshot.fixedFee != live.fixedFee);
        assertTrue(snapshottedFee != config.calculatePegOutFee(amount));
    }
}
