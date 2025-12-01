// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {CollateralFuzzTestBase} from "./CollateralFuzzTestBase.sol";
import {ICollateralManagement} from "../../../src/interfaces/ICollateralManagement.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {Flyover} from "../../../src/libraries/Flyover.sol";
import {Quotes} from "../../../src/libraries/Quotes.sol";

/// @title CollateralManagement Slashing Fuzz Tests
/// @notice Fuzz tests for slashing collateral functionality
contract CollateralSlashingFuzzTest is CollateralFuzzTestBase {
    address public punisher;

    function setUp() public {
        deployCollateralManagement();
        setupRoles();
        setupProviders();

        punisher = makeAddr("punisher");
        vm.deal(punisher, 100 ether);

        fuzzUser = makeAddr("fuzzUser");
        vm.deal(fuzzUser, 100 ether);
    }

    // ============ slashPegInCollateral Tests ============

    /// @notice Fuzz test: Slashing PegIn collateral reduces balance correctly
    function testFuzz_SlashPegInCollateral_ReducesCollateralCorrectly(
        uint128 penaltyFee
    ) public {
        penaltyFee = uint128(bound(penaltyFee, 0.001 ether, BASE_COLLATERAL / 2));

        Quotes.PegInQuote memory quote = createPegInQuote(pegInLp, penaltyFee);
        bytes32 quoteHash = generateQuoteHash(1);

        uint256 collateralBefore = collateralManagement.getPegInCollateral(pegInLp);
        uint256 expectedReward = calculateReward(penaltyFee);

        vm.prank(slasher);
        vm.expectEmit(true, true, true, true);
        emit ICollateralManagement.Penalized(
            pegInLp,
            punisher,
            quoteHash,
            Flyover.ProviderType.PegIn,
            penaltyFee,
            expectedReward
        );
        collateralManagement.slashPegInCollateral(punisher, quote, quoteHash);

        assertEq(
            collateralManagement.getPegInCollateral(pegInLp),
            collateralBefore - penaltyFee,
            "Collateral should decrease by penalty"
        );
    }

    /// @notice Fuzz test: Reward is calculated correctly
    function testFuzz_SlashPegInCollateral_RewardCalculatedCorrectly(
        uint128 penaltyFee
    ) public {
        penaltyFee = uint128(bound(penaltyFee, 0.001 ether, BASE_COLLATERAL / 2));

        Quotes.PegInQuote memory quote = createPegInQuote(pegInLp, penaltyFee);
        bytes32 quoteHash = generateQuoteHash(2);

        uint256 expectedReward = calculateReward(penaltyFee);

        vm.prank(slasher);
        collateralManagement.slashPegInCollateral(punisher, quote, quoteHash);

        assertEq(
            collateralManagement.getRewards(punisher),
            expectedReward,
            "Punisher reward should be calculated correctly"
        );
    }

    /// @notice Fuzz test: Penalties accumulate correctly (minus rewards)
    function testFuzz_SlashPegInCollateral_PenaltiesAccumulate(
        uint128 penaltyFee
    ) public {
        penaltyFee = uint128(bound(penaltyFee, 0.001 ether, BASE_COLLATERAL / 2));

        Quotes.PegInQuote memory quote = createPegInQuote(pegInLp, penaltyFee);
        bytes32 quoteHash = generateQuoteHash(3);

        uint256 expectedReward = calculateReward(penaltyFee);
        uint256 expectedPenalty = penaltyFee - expectedReward;

        vm.prank(slasher);
        collateralManagement.slashPegInCollateral(punisher, quote, quoteHash);

        assertEq(
            collateralManagement.getPenalties(),
            expectedPenalty,
            "Penalties should be penalty minus reward"
        );
    }

    /// @notice Fuzz test: Slashing more than available caps to available
    function testFuzz_SlashPegInCollateral_CapsToAvailableCollateral(
        uint256 excessAmount
    ) public {
        excessAmount = bound(excessAmount, 1, 100 ether);
        uint256 totalPenalty = BASE_COLLATERAL + excessAmount;

        Quotes.PegInQuote memory quote = createPegInQuote(pegInLp, totalPenalty);
        bytes32 quoteHash = generateQuoteHash(4);

        // Actual penalty will be capped to available collateral
        uint256 actualPenalty = BASE_COLLATERAL;
        uint256 expectedReward = calculateReward(actualPenalty);

        vm.prank(slasher);
        vm.expectEmit(true, true, true, true);
        emit ICollateralManagement.Penalized(
            pegInLp,
            punisher,
            quoteHash,
            Flyover.ProviderType.PegIn,
            actualPenalty,
            expectedReward
        );
        collateralManagement.slashPegInCollateral(punisher, quote, quoteHash);

        assertEq(
            collateralManagement.getPegInCollateral(pegInLp),
            0,
            "Collateral should be zero when fully slashed"
        );
    }

    /// @notice Fuzz test: Non-slasher cannot slash
    function testFuzz_SlashPegInCollateral_RevertsForNonSlasher(
        address nonSlasher,
        uint128 penaltyFee
    ) public {
        vm.assume(nonSlasher != slasher);
        vm.assume(nonSlasher != address(0));
        penaltyFee = uint128(bound(penaltyFee, 0.001 ether, BASE_COLLATERAL));

        Quotes.PegInQuote memory quote = createPegInQuote(pegInLp, penaltyFee);
        bytes32 quoteHash = generateQuoteHash(5);
        bytes32 slasherRole = collateralManagement.COLLATERAL_SLASHER();

        vm.prank(nonSlasher);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                nonSlasher,
                slasherRole
            )
        );
        collateralManagement.slashPegInCollateral(punisher, quote, quoteHash);
    }

    // ============ slashPegOutCollateral Tests ============

    /// @notice Fuzz test: Slashing PegOut collateral reduces balance correctly
    function testFuzz_SlashPegOutCollateral_ReducesCollateralCorrectly(
        uint128 penaltyFee
    ) public {
        penaltyFee = uint128(bound(penaltyFee, 0.001 ether, BASE_COLLATERAL / 2));

        Quotes.PegOutQuote memory quote = createPegOutQuote(pegOutLp, penaltyFee);
        bytes32 quoteHash = generateQuoteHash(6);

        uint256 collateralBefore = collateralManagement.getPegOutCollateral(pegOutLp);
        uint256 expectedReward = calculateReward(penaltyFee);

        vm.prank(slasher);
        vm.expectEmit(true, true, true, true);
        emit ICollateralManagement.Penalized(
            pegOutLp,
            punisher,
            quoteHash,
            Flyover.ProviderType.PegOut,
            penaltyFee,
            expectedReward
        );
        collateralManagement.slashPegOutCollateral(punisher, quote, quoteHash);

        assertEq(
            collateralManagement.getPegOutCollateral(pegOutLp),
            collateralBefore - penaltyFee,
            "Collateral should decrease by penalty"
        );
    }

    /// @notice Fuzz test: Non-slasher cannot slash PegOut
    function testFuzz_SlashPegOutCollateral_RevertsForNonSlasher(
        address nonSlasher,
        uint128 penaltyFee
    ) public {
        vm.assume(nonSlasher != slasher);
        vm.assume(nonSlasher != address(0));
        penaltyFee = uint128(bound(penaltyFee, 0.001 ether, BASE_COLLATERAL));

        Quotes.PegOutQuote memory quote = createPegOutQuote(pegOutLp, penaltyFee);
        bytes32 quoteHash = generateQuoteHash(7);
        bytes32 slasherRole = collateralManagement.COLLATERAL_SLASHER();

        vm.prank(nonSlasher);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                nonSlasher,
                slasherRole
            )
        );
        collateralManagement.slashPegOutCollateral(punisher, quote, quoteHash);
    }

    // ============ Multiple Slashing Tests ============

    /// @notice Fuzz test: Multiple slashings accumulate rewards
    function testFuzz_Slash_MultipleSlashingsAccumulateRewards(
        uint64 penalty1,
        uint64 penalty2
    ) public {
        penalty1 = uint64(bound(penalty1, 0.001 ether, BASE_COLLATERAL / 4));
        penalty2 = uint64(bound(penalty2, 0.001 ether, BASE_COLLATERAL / 4));

        Quotes.PegInQuote memory pegInQuote = createPegInQuote(fullLp, penalty1);
        Quotes.PegOutQuote memory pegOutQuote = createPegOutQuote(fullLp, penalty2);

        bytes32 quoteHash1 = generateQuoteHash(8);
        bytes32 quoteHash2 = generateQuoteHash(9);

        uint256 expectedReward1 = calculateReward(penalty1);
        uint256 expectedReward2 = calculateReward(penalty2);

        vm.startPrank(slasher);
        collateralManagement.slashPegInCollateral(punisher, pegInQuote, quoteHash1);
        collateralManagement.slashPegOutCollateral(punisher, pegOutQuote, quoteHash2);
        vm.stopPrank();

        assertEq(
            collateralManagement.getRewards(punisher),
            expectedReward1 + expectedReward2,
            "Rewards should accumulate"
        );
    }

    /// @notice Fuzz test: Multiple slashings accumulate penalties
    function testFuzz_Slash_MultipleSlashingsAccumulatePenalties(
        uint64 penalty1,
        uint64 penalty2
    ) public {
        penalty1 = uint64(bound(penalty1, 0.001 ether, BASE_COLLATERAL / 4));
        penalty2 = uint64(bound(penalty2, 0.001 ether, BASE_COLLATERAL / 4));

        Quotes.PegInQuote memory pegInQuote = createPegInQuote(fullLp, penalty1);
        Quotes.PegOutQuote memory pegOutQuote = createPegOutQuote(fullLp, penalty2);

        bytes32 quoteHash1 = generateQuoteHash(10);
        bytes32 quoteHash2 = generateQuoteHash(11);

        uint256 expectedReward1 = calculateReward(penalty1);
        uint256 expectedReward2 = calculateReward(penalty2);
        uint256 expectedPenalties = (penalty1 - expectedReward1) + (penalty2 - expectedReward2);

        vm.startPrank(slasher);
        collateralManagement.slashPegInCollateral(punisher, pegInQuote, quoteHash1);
        collateralManagement.slashPegOutCollateral(punisher, pegOutQuote, quoteHash2);
        vm.stopPrank();

        assertEq(
            collateralManagement.getPenalties(),
            expectedPenalties,
            "Penalties should accumulate"
        );
    }

    // ============ withdrawRewards Tests ============

    /// @notice Fuzz test: Punisher can withdraw rewards
    function testFuzz_WithdrawRewards_PunisherCanWithdraw(uint128 penaltyFee) public {
        penaltyFee = uint128(bound(penaltyFee, 0.01 ether, BASE_COLLATERAL / 2));

        Quotes.PegInQuote memory quote = createPegInQuote(pegInLp, penaltyFee);
        bytes32 quoteHash = generateQuoteHash(12);

        vm.prank(slasher);
        collateralManagement.slashPegInCollateral(punisher, quote, quoteHash);

        uint256 expectedReward = calculateReward(penaltyFee);
        uint256 balanceBefore = punisher.balance;

        vm.prank(punisher);
        vm.expectEmit(true, true, false, true);
        emit ICollateralManagement.RewardsWithdrawn(punisher, expectedReward);
        collateralManagement.withdrawRewards();

        assertEq(
            punisher.balance,
            balanceBefore + expectedReward,
            "Punisher balance should increase by reward"
        );

        assertEq(
            collateralManagement.getRewards(punisher),
            0,
            "Rewards should be zero after withdrawal"
        );
    }

    /// @notice Fuzz test: Cannot withdraw if no rewards
    function testFuzz_WithdrawRewards_RevertsIfNoRewards(address noRewardUser) public {
        vm.assume(noRewardUser != address(0));
        vm.assume(collateralManagement.getRewards(noRewardUser) == 0);

        vm.prank(noRewardUser);
        vm.expectRevert(
            abi.encodeWithSelector(
                ICollateralManagement.NothingToWithdraw.selector,
                noRewardUser
            )
        );
        collateralManagement.withdrawRewards();
    }

    // ============ Slashing With Zero Collateral Tests ============

    /// @notice Fuzz test: Slashing provider with zero collateral does nothing
    function testFuzz_Slash_ZeroCollateralSlashesNothing(uint128 penaltyFee) public {
        penaltyFee = uint128(bound(penaltyFee, 0.001 ether, 10 ether));

        // fuzzUser has no collateral
        Quotes.PegInQuote memory quote = createPegInQuote(fuzzUser, penaltyFee);
        bytes32 quoteHash = generateQuoteHash(13);

        vm.prank(slasher);
        vm.expectEmit(true, true, true, true);
        emit ICollateralManagement.Penalized(
            fuzzUser,
            punisher,
            quoteHash,
            Flyover.ProviderType.PegIn,
            0, // actual penalty is 0 (min of penaltyFee and collateral)
            0  // reward is 0
        );
        collateralManagement.slashPegInCollateral(punisher, quote, quoteHash);

        assertEq(
            collateralManagement.getRewards(punisher),
            0,
            "Punisher should have no rewards"
        );
    }
}
