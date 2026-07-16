// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {ConfigurationsTestBase} from "./ConfigurationsTestBase.sol";
import {Quotes} from "../../src/libraries/Quotes.sol";

/// @title FeeTest
/// @notice calculatePegInFee: floor behavior, satoshi rounding, and hand-computed values.
/// @dev Walkthrough anchors: step 2, decision block 2·D (the fixed fee is a security floor).
contract FeeTest is ConfigurationsTestBase {
    function setUp() public {
        _deploy();
    }

    /// @dev Independent mirror of the contract formula + rounding, to assert against.
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

    /// @notice The SAT constant used by the suite equals the on-chain conversion constant.
    function test_satConstant_matchesQuotesLibrary() public view {
        assertEq(SAT, Quotes.SAT_TO_WEI_CONVERSION);
        assertEq(SAT, config.SAT_TO_WEI_CONVERSION());
    }

    /// @notice At zero amount the fee is exactly the fixed floor (2·D).
    function test_zeroAmount_returnsFixedFloor() public view {
        assertEq(config.calculatePegInFee(0), SEED_FIXED_FEE);
    }

    /// @notice At the minimum peg-in amount the fee is floor + percentage of that amount.
    /// Hand-computed: 1000*SAT + 0.001e18 * 10 / 10000 = 1e13 + 1e12 = 11 * 1e12.
    function test_floorAtMinAmount_handComputed() public view {
        uint256 amount = SEED_MIN_AMOUNT; // 0.001 ether = 1e15 wei
        uint256 expected = 1e13 + (1e15 * 10) / 10_000; // 1e13 + 1e12
        assertEq(expected, 11 * 1e12); // sanity on the hand math
        assertEq(config.calculatePegInFee(amount), expected);
    }

    /// @notice A mid-range amount: floor + percentage, asserted against the hand formula.
    /// 5 ether * 10 / 10000 = 5e15; plus 1e13 floor = 5_010_000_000_000_000 wei.
    function test_midAmount_handComputed() public view {
        uint256 amount = 5 ether;
        uint256 expected = SEED_FIXED_FEE +
            (amount * SEED_PCT) /
            PCT_DENOMINATOR;
        assertEq(expected, 5_010_000_000_000_000);
        assertEq(config.calculatePegInFee(amount), expected);
    }

    /// @notice The fee is rounded DOWN to a satoshi boundary, exactly like
    /// Quotes.checkAgreedAmount, for an amount whose percentage term is not satoshi-aligned.
    function test_roundingMatchesCheckAgreedAmount() public view {
        // percentage term = amount * 10 / 10000 = amount / 1000; choose a non-SAT-aligned result.
        uint256 amount = 123_456_789_012_345;
        uint256 rawFee = SEED_FIXED_FEE + (amount * SEED_PCT) / PCT_DENOMINATOR;
        assertTrue(
            rawFee % SAT != 0,
            "test setup: pick an amount with a sub-satoshi remainder"
        );

        uint256 got = config.calculatePegInFee(amount);
        assertEq(got, rawFee - (rawFee % SAT));
        assertEq(got % SAT, 0, "result must be satoshi-aligned");
        assertEq(got, _expectedFee(SEED_FIXED_FEE, SEED_PCT, amount));
    }

    /// @notice A large amount does not overflow and matches the hand formula.
    function test_largeAmount_noOverflow() public view {
        uint256 amount = type(uint128).max;
        uint256 fee = config.calculatePegInFee(amount);
        assertEq(fee, _expectedFee(SEED_FIXED_FEE, SEED_PCT, amount));
        assertGt(fee, 0);
    }
}
