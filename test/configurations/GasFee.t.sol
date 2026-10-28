// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {ConfigurationsTestBase} from "./ConfigurationsTestBase.sol";
import {FlyoverConfigurations} from "../../src/FlyoverConfigurations.sol";
import {IFlyoverConfigurations} from "../../src/interfaces/IFlyoverConfigurations.sol";

/// @title GasFeeTest
contract GasFeeTest is ConfigurationsTestBase {
    function setUp() public {
        _deploy();
    }

    function test_queueChange_rejects_claimGasFee_above_max() public {
        IFlyoverConfigurations.PegConfiguration memory c = _altConfig();
        c.claimGasFee = BOUND_MAX_CLAIM_GAS_FEE + 1;
        vm.prank(owner);
        vm.expectRevert(
            abi.encodeWithSelector(
                FlyoverConfigurations.ConfigValueOutOfBounds.selector,
                FlyoverConfigurations.Field.ClaimGasFee,
                BOUND_MAX_CLAIM_GAS_FEE + 1,
                BOUND_MIN_CLAIM_GAS_FEE,
                BOUND_MAX_CLAIM_GAS_FEE
            )
        );
        config.queueChange(c);
    }

    function test_queueChange_rejects_minAmount_equal_to_deduction() public {
        IFlyoverConfigurations.PegConfiguration memory c = _altConfig();
        c.percentageFee = 0;
        c.minAmount = c.fixedFee + c.claimGasFee;
        vm.prank(owner);
        vm.expectRevert(
            abi.encodeWithSelector(
                FlyoverConfigurations.MinAmountDoesNotCoverDeduction.selector,
                c.minAmount,
                c.minAmount
            )
        );
        config.queueChange(c);
    }

    function test_calculatePegInDeduction_adds_claimGasFee() public view {
        uint256 amount = 1 ether;
        assertEq(
            config.calculatePegInDeduction(amount),
            config.calculatePegInFee(amount) + SEED_CLAIM_GAS_FEE
        );
    }

    function test_applyChange_activates_claimGasFee() public {
        IFlyoverConfigurations.PegConfiguration memory c = _altConfig();
        c.claimGasFee = BOUND_MAX_CLAIM_GAS_FEE;
        _applyConfig(c);
        assertEq(
            config.getPegInConfiguration().claimGasFee,
            BOUND_MAX_CLAIM_GAS_FEE
        );
    }

    function test_queueBoundsChange_rejects_inverted_claimGasFee_pair() public {
        IFlyoverConfigurations.PegConfiguration memory min = _boundsMin();
        min.claimGasFee = BOUND_MAX_CLAIM_GAS_FEE + 1;
        vm.prank(owner);
        vm.expectRevert(
            abi.encodeWithSelector(
                FlyoverConfigurations.InvalidBounds.selector,
                FlyoverConfigurations.Field.ClaimGasFee,
                BOUND_MAX_CLAIM_GAS_FEE + 1,
                BOUND_MAX_CLAIM_GAS_FEE
            )
        );
        config.queueBoundsChange(min, _boundsMax());
    }

    function test_applyBoundsChange_rejects_bounds_excluding_active_claimGasFee()
        public
    {
        IFlyoverConfigurations.PegConfiguration memory max = _boundsMax();
        max.claimGasFee = SEED_CLAIM_GAS_FEE - 1;
        vm.prank(owner);
        config.queueBoundsChange(_boundsMin(), max);
        vm.warp(block.timestamp + TIMELOCK_DELAY);
        vm.prank(owner);
        vm.expectRevert(
            abi.encodeWithSelector(
                FlyoverConfigurations.ActiveConfigOutsideNewBounds.selector,
                FlyoverConfigurations.Field.ClaimGasFee,
                SEED_CLAIM_GAS_FEE,
                BOUND_MIN_CLAIM_GAS_FEE,
                SEED_CLAIM_GAS_FEE - 1
            )
        );
        config.applyBoundsChange();
    }
}
