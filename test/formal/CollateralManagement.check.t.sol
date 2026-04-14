// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {FormalBase} from "./FormalBase.sol";
import {CollateralManagementContract} from "../../src/CollateralManagement.sol";
import {ICollateralManagement} from "../../src/interfaces/ICollateralManagement.sol";
import {Flyover} from "../../src/libraries/Flyover.sol";
import {Quotes} from "../../src/libraries/Quotes.sol";

/// @title Formal Verification PoC -- CollateralManagement
/// @notice Symbolic tests (prefix `check_`) that Halmos converts to SMT
///         constraints. Each test is verified for ALL possible inputs within
///         bounded execution, unlike fuzz tests which sample randomly.
contract CollateralManagementFormalTest is FormalBase {
    uint256 constant TOTAL_REWARD_PERCENTAGE = 10_000;

    // ------------------------------------------------------------------
    // Proof 1: Slash conservation -- reward + penalty remainder == slashed
    // ------------------------------------------------------------------

    /// @notice For any penalty amount and any reward percentage, slashing
    ///         never creates or destroys value: the punisher reward plus the
    ///         protocol penalty remainder always equals the effective penalty.
    function check_SlashPegInConservation(
        uint256 collateral,
        uint256 penaltyFee
    ) public {
        vm.assume(collateral > 0 && collateral <= 100 ether);
        vm.assume(penaltyFee > 0 && penaltyFee <= 100 ether);

        address lp = address(0xA1);
        address punisher = address(0xCAFE);

        vm.prank(adder);
        collateralManagement.addPegInCollateralTo{value: collateral}(lp);

        uint256 penaltiesBefore = collateralManagement.getPenalties();
        uint256 rewardsBefore = collateralManagement.getRewards(punisher);
        uint256 collateralBefore = collateralManagement.getPegInCollateral(lp);

        Quotes.PegInQuote memory quote = _basePegInQuote();
        quote.liquidityProviderRskAddress = lp;
        quote.penaltyFee = penaltyFee;

        vm.prank(slasher);
        collateralManagement.slashPegInCollateral(
            punisher,
            quote,
            keccak256("h")
        );

        uint256 effectivePenalty = penaltyFee < collateralBefore
            ? penaltyFee
            : collateralBefore;
        uint256 rewardDelta = collateralManagement.getRewards(punisher) -
            rewardsBefore;
        uint256 penaltyDelta = collateralManagement.getPenalties() -
            penaltiesBefore;

        assert(rewardDelta + penaltyDelta == effectivePenalty);

        uint256 collateralAfter = collateralManagement.getPegInCollateral(lp);
        assert(collateralBefore - collateralAfter == effectivePenalty);
    }

    /// @notice Mirror of the above for PegOut slashing.
    function check_SlashPegOutConservation(
        uint256 collateral,
        uint256 penaltyFee
    ) public {
        vm.assume(collateral > 0 && collateral <= 100 ether);
        vm.assume(penaltyFee > 0 && penaltyFee <= 100 ether);

        address lp = address(0xA1);
        address punisher = address(0xCAFE);

        vm.prank(adder);
        collateralManagement.addPegOutCollateralTo{value: collateral}(lp);

        uint256 penaltiesBefore = collateralManagement.getPenalties();
        uint256 rewardsBefore = collateralManagement.getRewards(punisher);
        uint256 collateralBefore = collateralManagement.getPegOutCollateral(lp);

        Quotes.PegOutQuote memory quote = _basePegOutQuote();
        quote.lpRskAddress = lp;
        quote.penaltyFee = penaltyFee;

        vm.prank(slasher);
        collateralManagement.slashPegOutCollateral(
            punisher,
            quote,
            keccak256("h")
        );

        uint256 effectivePenalty = penaltyFee < collateralBefore
            ? penaltyFee
            : collateralBefore;
        uint256 rewardDelta = collateralManagement.getRewards(punisher) -
            rewardsBefore;
        uint256 penaltyDelta = collateralManagement.getPenalties() -
            penaltiesBefore;

        assert(rewardDelta + penaltyDelta == effectivePenalty);

        uint256 collateralAfter = collateralManagement.getPegOutCollateral(lp);
        assert(collateralBefore - collateralAfter == effectivePenalty);
    }

    // ------------------------------------------------------------------
    // Proof 2: Collateral sufficiency threshold correctness
    // ------------------------------------------------------------------

    /// @notice For any collateral amount, isCollateralSufficient returns true
    ///         iff collateral >= minCollateral and the provider has not resigned.
    function check_CollateralSufficiencyPegIn(uint256 collateral) public {
        vm.assume(collateral > 0 && collateral <= 100 ether);

        address lp = address(0xA1);

        vm.prank(adder);
        collateralManagement.addPegInCollateralTo{value: collateral}(lp);

        bool sufficient = collateralManagement.isCollateralSufficient(
            Flyover.ProviderType.PegIn,
            lp
        );

        if (collateral >= MIN_COLLATERAL) {
            assert(sufficient);
        } else {
            assert(!sufficient);
        }
    }

    /// @notice A resigned provider must never be considered sufficient,
    ///         regardless of how much collateral they hold.
    ///         block.number must be > 0 because resign() stores block.number
    ///         as the resignation marker, and isCollateralSufficient checks
    ///         resignationBlockNum == 0 to mean "not resigned".
    function check_ResignedProviderNeverSufficient(uint256 collateral) public {
        vm.assume(collateral >= MIN_COLLATERAL && collateral <= 100 ether);

        address lp = address(0xABCD);
        vm.deal(lp, 1000 ether);

        vm.prank(adder);
        collateralManagement.addPegInCollateralTo{value: collateral}(lp);

        assert(
            collateralManagement.isCollateralSufficient(
                Flyover.ProviderType.PegIn,
                lp
            )
        );

        vm.prank(lp);
        collateralManagement.resign();

        assert(
            !collateralManagement.isCollateralSufficient(
                Flyover.ProviderType.PegIn,
                lp
            )
        );
    }

    // ------------------------------------------------------------------
    // Proof 3: Withdraw-after-resign timing enforcement
    // ------------------------------------------------------------------

    /// @notice withdrawCollateral must revert for any provider that has not
    ///         resigned, regardless of their collateral amount or block number.
    function check_WithdrawRevertsIfNotResigned(uint256 collateral) public {
        vm.assume(collateral > 0 && collateral <= 100 ether);

        address lp = address(0xABCD);
        vm.deal(lp, 1000 ether);

        vm.prank(adder);
        collateralManagement.addPegInCollateralTo{value: collateral}(lp);

        vm.prank(lp);
        try collateralManagement.withdrawCollateral() {
            assert(false); // must not succeed
        } catch {}
    }

    /// @notice withdrawCollateral must revert when the resign delay has not
    ///         elapsed, even if the provider has resigned.
    function check_WithdrawRevertsBeforeDelay(
        uint256 collateral,
        uint256 blocksAfterResign
    ) public {
        vm.assume(collateral > 0 && collateral <= 100 ether);
        vm.assume(blocksAfterResign < RESIGN_DELAY);

        address lp = address(0xABCD);
        vm.deal(lp, 1000 ether);

        vm.prank(adder);
        collateralManagement.addPegInCollateralTo{value: collateral}(lp);

        vm.prank(lp);
        collateralManagement.resign();

        vm.roll(block.number + blocksAfterResign);

        vm.prank(lp);
        try collateralManagement.withdrawCollateral() {
            assert(false); // must not succeed before delay
        } catch {}
    }

    // ------------------------------------------------------------------
    // Helpers
    // ------------------------------------------------------------------

    function _basePegInQuote()
        internal
        view
        returns (Quotes.PegInQuote memory quote)
    {
        bytes memory emptyBytes = new bytes(0);
        bytes memory testAddr = new bytes(20);
        quote.chainId = block.chainid;
        quote.fedBtcAddress = bytes20(testAddr);
        quote.btcRefundAddress = testAddr;
        quote.liquidityProviderBtcAddress = testAddr;
        quote.data = emptyBytes;
    }

    function _basePegOutQuote()
        internal
        view
        returns (Quotes.PegOutQuote memory quote)
    {
        bytes memory testAddr = new bytes(20);
        quote.chainId = block.chainid;
        quote.depositAddress = testAddr;
        quote.btcRefundAddress = testAddr;
        quote.lpBtcAddress = testAddr;
    }
}
