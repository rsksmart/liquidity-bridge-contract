// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {ConfigurationsTestBase} from "./ConfigurationsTestBase.sol";
import {FlyoverConfigurations} from "../../src/FlyoverConfigurations.sol";
import {IFlyoverConfigurations} from "../../src/interfaces/IFlyoverConfigurations.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";

/// @title AdminGatingTest
/// @notice Access control on the admin path and every configuration-validation revert reachable
/// through queueChange. Bounds guard even a compromised role (2·D).
contract AdminGatingTest is ConfigurationsTestBase {
    function setUp() public {
        _deploy();
    }

    function _unauthorized(
        address account
    ) private view returns (bytes memory) {
        return
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                account,
                config.DEFAULT_ADMIN_ROLE()
            );
    }

    // ------------------------------------------------------------------ role gating

    function test_queueChange_nonAdminReverts() public {
        IFlyoverConfigurations.PegConfiguration memory c = _altConfig();
        // Precompute the expected error before pranking: reading DEFAULT_ADMIN_ROLE() is itself
        // a call that would otherwise consume the prank.
        bytes memory err = _unauthorized(stranger);
        vm.prank(stranger);
        vm.expectRevert(err);
        config.queueChange(c);
    }

    function test_applyChange_nonAdminReverts() public {
        _queueAlt();
        vm.warp(block.timestamp + TIMELOCK_DELAY);
        bytes memory err = _unauthorized(stranger);
        vm.prank(stranger);
        vm.expectRevert(err);
        config.applyChange();
    }

    function test_admin_canQueueAndApply() public {
        _queueAlt();
        vm.warp(block.timestamp + TIMELOCK_DELAY);
        vm.prank(owner);
        config.applyChange();
        assertEq(
            config.getPegInConfiguration().fixedFee,
            _altConfig().fixedFee
        );
    }

    // ------------------------------------------------------------------ tier validation

    function test_queueChange_emptyTiersReverts() public {
        IFlyoverConfigurations.PegConfiguration memory c = _altConfig();
        c.confirmationTiers = new IFlyoverConfigurations.ConfirmationTier[](0);
        vm.prank(owner);
        vm.expectRevert(FlyoverConfigurations.EmptyTiers.selector);
        config.queueChange(c);
    }

    function test_queueChange_nonAscendingTiersReverts() public {
        IFlyoverConfigurations.PegConfiguration memory c = _altConfig();
        c.confirmationTiers = new IFlyoverConfigurations.ConfirmationTier[](2);
        c.confirmationTiers[0] = IFlyoverConfigurations.ConfirmationTier({
            maxAmount: 10 ether,
            confirmations: 3
        });
        c.confirmationTiers[1] = IFlyoverConfigurations.ConfirmationTier({
            maxAmount: 1 ether,
            confirmations: 1
        });
        vm.prank(owner);
        vm.expectRevert(FlyoverConfigurations.TiersNotAscending.selector);
        config.queueChange(c);
    }

    function test_queueChange_equalAdjacentTiersReverts() public {
        // Strictly ascending: equal adjacent maxAmounts are rejected too.
        IFlyoverConfigurations.PegConfiguration memory c = _altConfig();
        c.confirmationTiers = new IFlyoverConfigurations.ConfirmationTier[](2);
        c.confirmationTiers[0] = IFlyoverConfigurations.ConfirmationTier({
            maxAmount: 1 ether,
            confirmations: 1
        });
        c.confirmationTiers[1] = IFlyoverConfigurations.ConfirmationTier({
            maxAmount: 1 ether,
            confirmations: 2
        });
        vm.prank(owner);
        vm.expectRevert(FlyoverConfigurations.TiersNotAscending.selector);
        config.queueChange(c);
    }

    // ------------------------------------------------------------------ bounds validation

    /// @notice The fixed-fee floor (2·D) cannot be undercut even by the admin role.
    function test_queueChange_fixedFeeBelowFloorReverts() public {
        IFlyoverConfigurations.PegConfiguration memory c = _altConfig();
        c.fixedFee = BOUND_MIN_FIXED_FEE - 1;
        vm.prank(owner);
        vm.expectRevert(
            abi.encodeWithSelector(
                FlyoverConfigurations.ConfigValueOutOfBounds.selector,
                FlyoverConfigurations.Field.FixedFee,
                BOUND_MIN_FIXED_FEE - 1,
                BOUND_MIN_FIXED_FEE,
                BOUND_MAX_FIXED_FEE
            )
        );
        config.queueChange(c);
    }

    function test_queueChange_fixedFeeAboveMaxReverts() public {
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

    function test_queueChange_percentageFeeOutOfBoundsReverts() public {
        IFlyoverConfigurations.PegConfiguration memory c = _altConfig();
        c.percentageFee = BOUND_MAX_PCT + 1;
        vm.prank(owner);
        vm.expectRevert(
            abi.encodeWithSelector(
                FlyoverConfigurations.ConfigValueOutOfBounds.selector,
                FlyoverConfigurations.Field.PercentageFee,
                BOUND_MAX_PCT + 1,
                BOUND_MIN_PCT,
                BOUND_MAX_PCT
            )
        );
        config.queueChange(c);
    }

    function test_queueChange_minAmountOutOfBoundsReverts() public {
        IFlyoverConfigurations.PegConfiguration memory c = _altConfig();
        c.minAmount = BOUND_MAX_MIN_AMOUNT + 1;
        vm.prank(owner);
        vm.expectRevert(
            abi.encodeWithSelector(
                FlyoverConfigurations.ConfigValueOutOfBounds.selector,
                FlyoverConfigurations.Field.MinAmount,
                BOUND_MAX_MIN_AMOUNT + 1,
                BOUND_MIN_MIN_AMOUNT,
                BOUND_MAX_MIN_AMOUNT
            )
        );
        config.queueChange(c);
    }

    function test_queueChange_maxAmountOutOfBoundsReverts() public {
        IFlyoverConfigurations.PegConfiguration memory c = _altConfig();
        c.maxAmount = BOUND_MAX_MAX_AMOUNT + 1;
        vm.prank(owner);
        vm.expectRevert(
            abi.encodeWithSelector(
                FlyoverConfigurations.ConfigValueOutOfBounds.selector,
                FlyoverConfigurations.Field.MaxAmount,
                BOUND_MAX_MAX_AMOUNT + 1,
                BOUND_MIN_MAX_AMOUNT,
                BOUND_MAX_MAX_AMOUNT
            )
        );
        config.queueChange(c);
    }

    // ------------------------------------------------------------------ structural invariants

    /// @notice percentageFee within bounds but above the 100% denominator is rejected.
    function test_queueChange_invalidPercentageFeeReverts() public {
        uint256 badPct = PCT_DENOMINATOR + 5000; // 15000: within [0, 20000] bound, but > 100%
        IFlyoverConfigurations.PegConfiguration memory c = _altConfig();
        c.percentageFee = badPct;
        vm.prank(owner);
        vm.expectRevert(
            abi.encodeWithSelector(
                FlyoverConfigurations.InvalidPercentageFee.selector,
                badPct
            )
        );
        config.queueChange(c);
    }

    /// @notice minAmount greater than maxAmount is rejected, even when both are within bounds.
    function test_queueChange_invalidAmountLimitsReverts() public {
        IFlyoverConfigurations.PegConfiguration memory c = _altConfig();
        c.minAmount = 1 ether; // within [0, 1 ether]
        c.maxAmount = 0.5 ether; // within [0, 10000 ether] but < minAmount
        vm.prank(owner);
        vm.expectRevert(
            abi.encodeWithSelector(
                FlyoverConfigurations.InvalidAmountLimits.selector,
                1 ether,
                0.5 ether
            )
        );
        config.queueChange(c);
    }

    // ============================================================ bounds changes (FLY-2523)

    // ------------------------------------------------------------------ role gating

    function test_queueBoundsChange_nonAdminReverts() public {
        IFlyoverConfigurations.PegConfiguration memory min = _wideMin();
        IFlyoverConfigurations.PegConfiguration memory max = _wideMax();
        bytes memory err = _unauthorized(stranger);
        vm.prank(stranger);
        vm.expectRevert(err);
        config.queueBoundsChange(min, max);
    }

    function test_applyBoundsChange_nonAdminReverts() public {
        _queueWideBounds();
        vm.warp(block.timestamp + TIMELOCK_DELAY);
        bytes memory err = _unauthorized(stranger);
        vm.prank(stranger);
        vm.expectRevert(err);
        config.applyBoundsChange();
    }

    function test_admin_canQueueAndApplyBounds() public {
        _queueWideBounds();
        vm.warp(block.timestamp + TIMELOCK_DELAY);
        vm.prank(owner);
        config.applyBoundsChange();
        (IFlyoverConfigurations.PegConfiguration memory min, ) = config
            .getPegInConfigurationBounds();
        assertEq(min.fixedFee, WIDE_MIN_FIXED_FEE);
    }

    /// @notice There is no way to move a bound outside the time lock: no setter exists, so the
    /// only two selectors that write the bounds namespace are the queue/apply pair.
    function test_noPlainBoundsSetterExists() public {
        // A single-step setter would be the obvious name; it must not be routable.
        (bool ok, ) = address(config).call(
            abi.encodeWithSignature(
                "setPegInConfigurationBounds((uint256,uint256,uint256,uint256,(uint256,uint256)[]),"
                "(uint256,uint256,uint256,uint256,(uint256,uint256)[]))",
                _wideMin(),
                _wideMax()
            )
        );
        assertFalse(ok, "no single-step bounds setter may exist");
    }

    // ------------------------------------------------------ inverted pair, one case per field

    function test_queueBoundsChange_invertedFixedFeeReverts() public {
        IFlyoverConfigurations.PegConfiguration memory max = _boundsMax();
        max.fixedFee = BOUND_MIN_FIXED_FEE - 1; // max below min
        vm.prank(owner);
        vm.expectRevert(
            abi.encodeWithSelector(
                FlyoverConfigurations.InvalidBounds.selector,
                FlyoverConfigurations.Field.FixedFee,
                BOUND_MIN_FIXED_FEE,
                BOUND_MIN_FIXED_FEE - 1
            )
        );
        config.queueBoundsChange(_boundsMin(), max);
    }

    function test_queueBoundsChange_invertedPercentageFeeReverts() public {
        IFlyoverConfigurations.PegConfiguration memory min = _boundsMin();
        min.percentageFee = BOUND_MAX_PCT + 1;
        vm.prank(owner);
        vm.expectRevert(
            abi.encodeWithSelector(
                FlyoverConfigurations.InvalidBounds.selector,
                FlyoverConfigurations.Field.PercentageFee,
                BOUND_MAX_PCT + 1,
                BOUND_MAX_PCT
            )
        );
        config.queueBoundsChange(min, _boundsMax());
    }

    function test_queueBoundsChange_invertedMinAmountReverts() public {
        IFlyoverConfigurations.PegConfiguration memory min = _boundsMin();
        min.minAmount = BOUND_MAX_MIN_AMOUNT + 1;
        vm.prank(owner);
        vm.expectRevert(
            abi.encodeWithSelector(
                FlyoverConfigurations.InvalidBounds.selector,
                FlyoverConfigurations.Field.MinAmount,
                BOUND_MAX_MIN_AMOUNT + 1,
                BOUND_MAX_MIN_AMOUNT
            )
        );
        config.queueBoundsChange(min, _boundsMax());
    }

    function test_queueBoundsChange_invertedMaxAmountReverts() public {
        IFlyoverConfigurations.PegConfiguration memory min = _boundsMin();
        min.maxAmount = BOUND_MAX_MAX_AMOUNT + 1;
        vm.prank(owner);
        vm.expectRevert(
            abi.encodeWithSelector(
                FlyoverConfigurations.InvalidBounds.selector,
                FlyoverConfigurations.Field.MaxAmount,
                BOUND_MAX_MAX_AMOUNT + 1,
                BOUND_MAX_MAX_AMOUNT
            )
        );
        config.queueBoundsChange(min, _boundsMax());
    }

    /// @notice min == max is a degenerate but well-formed pair: it pins the field to one value.
    function test_queueBoundsChange_equalMinAndMaxAccepted() public {
        IFlyoverConfigurations.PegConfiguration memory min = _boundsMin();
        IFlyoverConfigurations.PegConfiguration memory max = _boundsMax();
        min.fixedFee = SEED_FIXED_FEE;
        max.fixedFee = SEED_FIXED_FEE;

        vm.prank(owner);
        config.queueBoundsChange(min, max);
        vm.warp(block.timestamp + TIMELOCK_DELAY);
        vm.prank(owner);
        config.applyBoundsChange();

        (
            IFlyoverConfigurations.PegConfiguration memory activeMin,
            IFlyoverConfigurations.PegConfiguration memory activeMax
        ) = config.getPegInConfigurationBounds();
        assertEq(activeMin.fixedFee, SEED_FIXED_FEE);
        assertEq(activeMax.fixedFee, SEED_FIXED_FEE);
    }
}
