// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {CollateralFuzzTestBase} from "./CollateralFuzzTestBase.sol";
import {ICollateralManagement} from "../../../src/interfaces/ICollateralManagement.sol";
import {Flyover} from "../../../src/libraries/Flyover.sol";
import {Quotes} from "../../../src/libraries/Quotes.sol";

/// @title CollateralManagement Resign/Withdraw Fuzz Tests
/// @notice Fuzz tests for resign and withdraw collateral functionality
contract CollateralResignWithdrawFuzzTest is CollateralFuzzTestBase {
    function setUp() public {
        deployCollateralManagement();
        setupRoles();
        setupProviders();

        fuzzUser = makeAddr("fuzzUser");
        vm.deal(fuzzUser, 100 ether);
    }

    // ============ resign Tests ============

    /// @notice Fuzz test: Unregistered address cannot resign
    function testFuzz_Resign_RevertsForUnregistered(
        address unregistered
    ) public {
        vm.assume(
            unregistered != pegInLp &&
                unregistered != pegOutLp &&
                unregistered != fullLp
        );
        vm.assume(unregistered != address(0));

        vm.prank(unregistered);
        vm.expectRevert(
            abi.encodeWithSelector(
                Flyover.ProviderNotRegistered.selector,
                unregistered
            )
        );
        collateralManagement.resign();
    }

    /// @notice Fuzz test: Resignation block is recorded correctly at various blocks
    function testFuzz_Resign_RecordsCorrectBlock(uint256 blockNumber) public {
        blockNumber = bound(blockNumber, 1, type(uint64).max);
        vm.roll(blockNumber);

        vm.prank(pegInLp);
        collateralManagement.resign();

        assertEq(
            collateralManagement.getResignationBlock(pegInLp),
            blockNumber,
            "Resignation block should match"
        );
    }

    // ============ withdrawCollateral Tests ============

    /// @notice Fuzz test: Cannot withdraw before resigning
    function testFuzz_WithdrawCollateral_RevertsIfNotResigned() public {
        vm.prank(pegInLp);
        vm.expectRevert(
            abi.encodeWithSelector(
                ICollateralManagement.NotResigned.selector,
                pegInLp
            )
        );
        collateralManagement.withdrawCollateral();
    }

    /// @notice Fuzz test: Cannot withdraw before delay passes
    function testFuzz_WithdrawCollateral_RevertsBeforeDelay(
        uint256 blocksPassed
    ) public {
        blocksPassed = bound(blocksPassed, 0, TEST_RESIGN_DELAY_BLOCKS - 1);

        vm.prank(pegInLp);
        collateralManagement.resign();

        uint256 resignBlock = collateralManagement.getResignationBlock(pegInLp);

        vm.roll(block.number + blocksPassed);

        vm.prank(pegInLp);
        vm.expectRevert(
            abi.encodeWithSelector(
                ICollateralManagement.ResignationDelayNotMet.selector,
                pegInLp,
                resignBlock,
                TEST_RESIGN_DELAY_BLOCKS
            )
        );
        collateralManagement.withdrawCollateral();
    }

    /// @notice Fuzz test: Can withdraw exactly at delay
    function testFuzz_WithdrawCollateral_SucceedsAtExactDelay() public {
        vm.prank(pegInLp);
        collateralManagement.resign();

        vm.roll(block.number + TEST_RESIGN_DELAY_BLOCKS);

        uint256 expectedAmount = collateralManagement.getPegInCollateral(
            pegInLp
        );
        uint256 balanceBefore = pegInLp.balance;

        vm.prank(pegInLp);
        vm.expectEmit(true, true, false, true);
        emit ICollateralManagement.WithdrawCollateral(pegInLp, expectedAmount);
        collateralManagement.withdrawCollateral();

        assertEq(
            pegInLp.balance,
            balanceBefore + expectedAmount,
            "Balance should increase by collateral"
        );
    }

    /// @notice Fuzz test: Can withdraw after delay with various extra blocks
    function testFuzz_WithdrawCollateral_SucceedsAfterDelay(
        uint256 extraBlocks
    ) public {
        extraBlocks = bound(extraBlocks, 1, 10000);

        vm.prank(pegInLp);
        collateralManagement.resign();

        vm.roll(block.number + TEST_RESIGN_DELAY_BLOCKS + extraBlocks);

        uint256 expectedAmount = collateralManagement.getPegInCollateral(
            pegInLp
        );
        uint256 balanceBefore = pegInLp.balance;

        vm.prank(pegInLp);
        collateralManagement.withdrawCollateral();

        assertEq(
            pegInLp.balance,
            balanceBefore + expectedAmount,
            "Balance should increase by collateral"
        );
    }

    /// @notice Fuzz test: Partial slashing before withdrawal
    function testFuzz_WithdrawCollateral_PartialSlashBeforeWithdrawal(
        uint128 slashAmount
    ) public {
        slashAmount = uint128(
            bound(slashAmount, 0.001 ether, BASE_COLLATERAL - 0.001 ether)
        );

        uint256 initialCollateral = collateralManagement.getPegInCollateral(
            pegInLp
        );

        // Slash some collateral
        Quotes.PegInQuote memory quote = createPegInQuote(pegInLp, slashAmount);
        vm.prank(slasher);
        collateralManagement.slashPegInCollateral(
            ZERO_ADDRESS,
            quote,
            bytes32(0)
        );

        vm.prank(pegInLp);
        collateralManagement.resign();

        vm.roll(block.number + TEST_RESIGN_DELAY_BLOCKS);

        uint256 expectedWithdrawal = initialCollateral - slashAmount;
        uint256 balanceBefore = pegInLp.balance;

        vm.prank(pegInLp);
        vm.expectEmit(true, true, false, true);
        emit ICollateralManagement.WithdrawCollateral(
            pegInLp,
            expectedWithdrawal
        );
        collateralManagement.withdrawCollateral();

        assertEq(
            pegInLp.balance,
            balanceBefore + expectedWithdrawal,
            "Should receive remaining collateral after slash"
        );
    }

    // ============ Registration Status After Resign Tests ============

    /// @notice Fuzz test: Resigned provider is not registered
    function testFuzz_Resign_NotRegisteredAfterResign(
        uint8 providerTypeRaw
    ) public {
        Flyover.ProviderType providerType = getValidProviderType(
            providerTypeRaw
        );

        // Use fullLp which has both PegIn and PegOut collateral
        assertTrue(
            collateralManagement.isRegistered(providerType, fullLp),
            "Should be registered initially"
        );

        vm.prank(fullLp);
        collateralManagement.resign();

        assertFalse(
            collateralManagement.isRegistered(providerType, fullLp),
            "Should not be registered after resign"
        );
    }

    /// @notice Fuzz test: Resigned provider has insufficient collateral
    function testFuzz_Resign_InsufficientCollateralAfterResign(
        uint8 providerTypeRaw
    ) public {
        Flyover.ProviderType providerType = getValidProviderType(
            providerTypeRaw
        );

        // Use fullLp which has both PegIn and PegOut collateral
        assertTrue(
            collateralManagement.isCollateralSufficient(providerType, fullLp),
            "Should have sufficient collateral initially"
        );

        vm.prank(fullLp);
        collateralManagement.resign();

        assertFalse(
            collateralManagement.isCollateralSufficient(providerType, fullLp),
            "Should not have sufficient collateral after resign"
        );
    }
}
