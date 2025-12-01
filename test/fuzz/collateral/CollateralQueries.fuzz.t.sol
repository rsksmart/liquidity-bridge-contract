// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {CollateralFuzzTestBase} from "./CollateralFuzzTestBase.sol";
import {ICollateralManagement} from "../../../src/interfaces/ICollateralManagement.sol";
import {Flyover} from "../../../src/libraries/Flyover.sol";
import {Quotes} from "../../../src/libraries/Quotes.sol";

/// @title CollateralManagement Query Fuzz Tests
/// @notice Fuzz tests for query functions (isRegistered, isCollateralSufficient, getters)
contract CollateralQueriesFuzzTest is CollateralFuzzTestBase {
    function setUp() public {
        deployCollateralManagement();
        setupRoles();
        setupProviders();

        fuzzUser = makeAddr("fuzzUser");
        vm.deal(fuzzUser, 1000 ether);
    }

    // ============ isRegistered Tests ============

    /// @notice Fuzz test: isRegistered returns true for PegIn provider with PegIn collateral
    function testFuzz_IsRegistered_TrueForPegInProvider() public view {
        assertTrue(
            collateralManagement.isRegistered(Flyover.ProviderType.PegIn, pegInLp),
            "PegIn provider should be registered for PegIn"
        );
        assertFalse(
            collateralManagement.isRegistered(Flyover.ProviderType.PegOut, pegInLp),
            "PegIn provider should not be registered for PegOut"
        );
        assertFalse(
            collateralManagement.isRegistered(Flyover.ProviderType.Both, pegInLp),
            "PegIn provider should not be registered for Both"
        );
    }

    /// @notice Fuzz test: isRegistered returns true for PegOut provider with PegOut collateral
    function testFuzz_IsRegistered_TrueForPegOutProvider() public view {
        assertTrue(
            collateralManagement.isRegistered(Flyover.ProviderType.PegOut, pegOutLp),
            "PegOut provider should be registered for PegOut"
        );
        assertFalse(
            collateralManagement.isRegistered(Flyover.ProviderType.PegIn, pegOutLp),
            "PegOut provider should not be registered for PegIn"
        );
        assertFalse(
            collateralManagement.isRegistered(Flyover.ProviderType.Both, pegOutLp),
            "PegOut provider should not be registered for Both"
        );
    }

    /// @notice Fuzz test: isRegistered returns true for Full provider for all types
    function testFuzz_IsRegistered_TrueForFullProvider() public view {
        assertTrue(
            collateralManagement.isRegistered(Flyover.ProviderType.PegIn, fullLp),
            "Full provider should be registered for PegIn"
        );
        assertTrue(
            collateralManagement.isRegistered(Flyover.ProviderType.PegOut, fullLp),
            "Full provider should be registered for PegOut"
        );
        assertTrue(
            collateralManagement.isRegistered(Flyover.ProviderType.Both, fullLp),
            "Full provider should be registered for Both"
        );
    }

    /// @notice Fuzz test: isRegistered returns false for unregistered address
    function testFuzz_IsRegistered_FalseForUnregistered(
        address unregistered,
        uint8 providerTypeRaw
    ) public view {
        vm.assume(unregistered != pegInLp && unregistered != pegOutLp && unregistered != fullLp);
        Flyover.ProviderType providerType = getValidProviderType(providerTypeRaw);

        assertFalse(
            collateralManagement.isRegistered(providerType, unregistered),
            "Unregistered address should not be registered"
        );
    }

    /// @notice Fuzz test: Adding collateral changes registration status
    function testFuzz_IsRegistered_TrueAfterAddingCollateral(uint256 amount) public {
        amount = bound(amount, 1 wei, 50 ether);

        assertFalse(
            collateralManagement.isRegistered(Flyover.ProviderType.PegIn, fuzzUser),
            "Should not be registered initially"
        );

        vm.prank(adder);
        collateralManagement.addPegInCollateralTo{value: amount}(fuzzUser);

        assertTrue(
            collateralManagement.isRegistered(Flyover.ProviderType.PegIn, fuzzUser),
            "Should be registered after adding collateral"
        );
    }

    // ============ isCollateralSufficient Tests ============

    /// @notice Fuzz test: isCollateralSufficient returns true when >= minCollateral
    function testFuzz_IsCollateralSufficient_TrueWhenAboveMin(uint256 amount) public {
        amount = bound(amount, TEST_MIN_COLLATERAL, 100 ether);

        vm.prank(adder);
        collateralManagement.addPegInCollateralTo{value: amount}(fuzzUser);

        assertTrue(
            collateralManagement.isCollateralSufficient(Flyover.ProviderType.PegIn, fuzzUser),
            "Should be sufficient when >= min collateral"
        );
    }

    /// @notice Fuzz test: isCollateralSufficient returns false when < minCollateral
    function testFuzz_IsCollateralSufficient_FalseWhenBelowMin(uint256 amount) public {
        amount = bound(amount, 1 wei, TEST_MIN_COLLATERAL - 1);

        vm.prank(adder);
        collateralManagement.addPegInCollateralTo{value: amount}(fuzzUser);

        assertFalse(
            collateralManagement.isCollateralSufficient(Flyover.ProviderType.PegIn, fuzzUser),
            "Should not be sufficient when < min collateral"
        );
    }

    /// @notice Fuzz test: isCollateralSufficient at exact minimum
    function testFuzz_IsCollateralSufficient_TrueAtExactMin() public {
        vm.prank(adder);
        collateralManagement.addPegInCollateralTo{value: TEST_MIN_COLLATERAL}(fuzzUser);

        assertTrue(
            collateralManagement.isCollateralSufficient(Flyover.ProviderType.PegIn, fuzzUser),
            "Should be sufficient at exact min collateral"
        );
    }

    /// @notice Fuzz test: isCollateralSufficient returns false after resign
    function testFuzz_IsCollateralSufficient_FalseAfterResign() public {
        assertTrue(
            collateralManagement.isCollateralSufficient(Flyover.ProviderType.PegIn, pegInLp),
            "Should be sufficient initially"
        );

        vm.prank(pegInLp);
        collateralManagement.resign();

        assertFalse(
            collateralManagement.isCollateralSufficient(Flyover.ProviderType.PegIn, pegInLp),
            "Should not be sufficient after resign"
        );
    }

    /// @notice Fuzz test: isCollateralSufficient becomes false after slashing below min
    function testFuzz_IsCollateralSufficient_FalseAfterSlashBelowMin(uint256 slashAmount) public {
        // Slash enough to go below minimum
        slashAmount = bound(slashAmount, BASE_COLLATERAL - TEST_MIN_COLLATERAL + 1, BASE_COLLATERAL);

        Quotes.PegInQuote memory quote = createPegInQuote(pegInLp, slashAmount);

        vm.prank(slasher);
        collateralManagement.slashPegInCollateral(ZERO_ADDRESS, quote, bytes32(0));

        assertFalse(
            collateralManagement.isCollateralSufficient(Flyover.ProviderType.PegIn, pegInLp),
            "Should not be sufficient after slashing below min"
        );
    }

    // ============ getPegInCollateral / getPegOutCollateral Tests ============

    /// @notice Fuzz test: getPegInCollateral returns correct value after addition
    function testFuzz_GetPegInCollateral_ReturnsCorrectValueAfterAddition(uint256 amount) public {
        amount = bound(amount, 0.001 ether, 50 ether);

        vm.prank(adder);
        collateralManagement.addPegInCollateralTo{value: amount}(fuzzUser);

        assertEq(
            collateralManagement.getPegInCollateral(fuzzUser),
            amount,
            "Should return correct collateral amount"
        );
    }

    /// @notice Fuzz test: getPegOutCollateral returns correct value after addition
    function testFuzz_GetPegOutCollateral_ReturnsCorrectValueAfterAddition(uint256 amount) public {
        amount = bound(amount, 0.001 ether, 50 ether);

        vm.prank(adder);
        collateralManagement.addPegOutCollateralTo{value: amount}(fuzzUser);

        assertEq(
            collateralManagement.getPegOutCollateral(fuzzUser),
            amount,
            "Should return correct collateral amount"
        );
    }

    /// @notice Fuzz test: Collateral is tracked separately for PegIn and PegOut
    function testFuzz_GetCollateral_TrackedSeparately(
        uint128 pegInAmount,
        uint128 pegOutAmount
    ) public {
        pegInAmount = uint128(bound(pegInAmount, 0.001 ether, 50 ether));
        pegOutAmount = uint128(bound(pegOutAmount, 0.001 ether, 50 ether));

        vm.startPrank(adder);
        collateralManagement.addPegInCollateralTo{value: pegInAmount}(fuzzUser);
        collateralManagement.addPegOutCollateralTo{value: pegOutAmount}(fuzzUser);
        vm.stopPrank();

        assertEq(
            collateralManagement.getPegInCollateral(fuzzUser),
            pegInAmount,
            "PegIn collateral should match"
        );
        assertEq(
            collateralManagement.getPegOutCollateral(fuzzUser),
            pegOutAmount,
            "PegOut collateral should match"
        );
    }

    // ============ getResignationBlock Tests ============

    /// @notice Fuzz test: getResignationBlock returns 0 for non-resigned
    function testFuzz_GetResignationBlock_ZeroForNonResigned(address addr) public view {
        vm.assume(addr != pegInLp && addr != pegOutLp && addr != fullLp);

        assertEq(
            collateralManagement.getResignationBlock(addr),
            0,
            "Should return 0 for non-resigned"
        );
    }

    /// @notice Fuzz test: getResignationBlock returns correct block after resign
    function testFuzz_GetResignationBlock_CorrectBlockAfterResign(uint256 blockNum) public {
        blockNum = bound(blockNum, 1, type(uint64).max);
        vm.roll(blockNum);

        vm.prank(pegInLp);
        collateralManagement.resign();

        assertEq(
            collateralManagement.getResignationBlock(pegInLp),
            blockNum,
            "Should return correct resignation block"
        );
    }

    // ============ Configuration Getters Tests ============

    /// @notice Fuzz test: getMinCollateral returns configured value
    function testFuzz_GetMinCollateral_ReturnsConfiguredValue() public view {
        assertEq(
            collateralManagement.getMinCollateral(),
            TEST_MIN_COLLATERAL,
            "Should return configured min collateral"
        );
    }

    /// @notice Fuzz test: getResignDelayInBlocks returns configured value
    function testFuzz_GetResignDelayInBlocks_ReturnsConfiguredValue() public view {
        assertEq(
            collateralManagement.getResignDelayInBlocks(),
            TEST_RESIGN_DELAY_BLOCKS,
            "Should return configured resign delay"
        );
    }

    /// @notice Fuzz test: getRewardPercentage returns configured value
    function testFuzz_GetRewardPercentage_ReturnsConfiguredValue() public view {
        assertEq(
            collateralManagement.getRewardPercentage(),
            TEST_REWARD_PERCENTAGE,
            "Should return configured reward percentage"
        );
    }

    // ============ getRewards / getPenalties Tests ============

    /// @notice Fuzz test: getRewards returns 0 initially
    function testFuzz_GetRewards_ZeroInitially(address addr) public view {
        assertEq(
            collateralManagement.getRewards(addr),
            0,
            "Should return 0 rewards initially"
        );
    }

    /// @notice Fuzz test: getPenalties returns 0 initially
    function testFuzz_GetPenalties_ZeroInitially() public view {
        assertEq(
            collateralManagement.getPenalties(),
            0,
            "Should return 0 penalties initially"
        );
    }

    /// @notice Fuzz test: getRewards accumulates from slashing
    function testFuzz_GetRewards_AccumulatesFromSlashing(
        uint64 penalty1,
        uint64 penalty2
    ) public {
        penalty1 = uint64(bound(penalty1, 0.001 ether, BASE_COLLATERAL / 4));
        penalty2 = uint64(bound(penalty2, 0.001 ether, BASE_COLLATERAL / 4));

        address punisher = makeAddr("punisher");

        Quotes.PegInQuote memory quote1 = createPegInQuote(fullLp, penalty1);
        Quotes.PegOutQuote memory quote2 = createPegOutQuote(fullLp, penalty2);

        vm.startPrank(slasher);
        collateralManagement.slashPegInCollateral(punisher, quote1, bytes32(uint256(1)));
        collateralManagement.slashPegOutCollateral(punisher, quote2, bytes32(uint256(2)));
        vm.stopPrank();

        uint256 expectedReward = calculateReward(penalty1) + calculateReward(penalty2);

        assertEq(
            collateralManagement.getRewards(punisher),
            expectedReward,
            "Should return accumulated rewards"
        );
    }

    /// @notice Fuzz test: getPenalties accumulates from slashing
    function testFuzz_GetPenalties_AccumulatesFromSlashing(
        uint64 penalty1,
        uint64 penalty2
    ) public {
        penalty1 = uint64(bound(penalty1, 0.001 ether, BASE_COLLATERAL / 4));
        penalty2 = uint64(bound(penalty2, 0.001 ether, BASE_COLLATERAL / 4));

        address punisher = makeAddr("punisher");

        Quotes.PegInQuote memory quote1 = createPegInQuote(fullLp, penalty1);
        Quotes.PegOutQuote memory quote2 = createPegOutQuote(fullLp, penalty2);

        vm.startPrank(slasher);
        collateralManagement.slashPegInCollateral(punisher, quote1, bytes32(uint256(1)));
        collateralManagement.slashPegOutCollateral(punisher, quote2, bytes32(uint256(2)));
        vm.stopPrank();

        uint256 expectedReward1 = calculateReward(penalty1);
        uint256 expectedReward2 = calculateReward(penalty2);
        uint256 expectedPenalties = (penalty1 - expectedReward1) + (penalty2 - expectedReward2);

        assertEq(
            collateralManagement.getPenalties(),
            expectedPenalties,
            "Should return accumulated penalties"
        );
    }
}
