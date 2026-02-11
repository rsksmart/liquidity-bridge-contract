// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {CollateralTestBase} from "./CollateralTestBase.sol";
import {CollateralManagementContract} from "../../src/CollateralManagement.sol";
import {ICollateralManagement} from "../../src/interfaces/ICollateralManagement.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {Flyover} from "../../src/libraries/Flyover.sol";
import {Quotes} from "../../src/libraries/Quotes.sol";
import {WalletMock} from "../../src/test-contracts/WalletMock.sol";

contract SlashingTest is CollateralTestBase {
    address public punisher;
    address public liquidityProvider;
    address public user;
    address public notSlasher;

    bytes32 public quoteHash;

    // Test constants
    uint256 constant CALL_FEE = 100000000000000; // 1e14
    uint256 constant PENALTY_FEE = 10000000000000; // 1e13
    uint256 constant GAS_FEE = 100;
    uint256 constant GAS_LIMIT = 21000;
    uint256 constant QUOTE_VALUE = 1 ether;

    function setUp() public {
        deployCollateralManagement();
        setupRoles();
        setupTestAccounts();
        setupCollateral();

        // Generate quote hash
        quoteHash = keccak256(abi.encodePacked(block.timestamp, block.number));
    }

    function setupTestAccounts() internal {
        // Create test accounts
        punisher = makeAddr("punisher");
        liquidityProvider = makeAddr("liquidityProvider");
        user = makeAddr("user");
        notSlasher = makeAddr("notSlasher");

        // Fund accounts
        vm.deal(punisher, 100 ether);
        vm.deal(liquidityProvider, 100 ether);
        vm.deal(user, 100 ether);
        vm.deal(notSlasher, 100 ether);
    }

    function createPegInQuote()
        internal
        view
        returns (Quotes.PegInQuote memory quote)
    {
        bytes memory emptyBytes = new bytes(0);
        bytes memory testBtcAddress = new bytes(20);

        quote.callFee = CALL_FEE;
        quote.penaltyFee = PENALTY_FEE;
        quote.value = QUOTE_VALUE;
        quote.lbcAddress = address(collateralManagement);
        quote.liquidityProviderRskAddress = liquidityProvider;
        quote.contractAddress = user;
        quote.rskRefundAddress = payable(user);
        quote.gasLimit = uint32(GAS_LIMIT);
        quote.btcRefundAddress = testBtcAddress;
        quote.liquidityProviderBtcAddress = testBtcAddress;
        quote.data = emptyBytes;
    }

    function createPegOutQuote()
        internal
        view
        returns (Quotes.PegOutQuote memory quote)
    {
        bytes memory testBtcAddress = new bytes(20);

        quote.callFee = CALL_FEE;
        quote.penaltyFee = PENALTY_FEE;
        quote.value = QUOTE_VALUE;
        quote.lbcAddress = address(collateralManagement);
        quote.lpRskAddress = liquidityProvider;
        quote.rskRefundAddress = user;
        quote.depositAddress = testBtcAddress;
        quote.btcRefundAddress = testBtcAddress;
        quote.lpBtcAddress = testBtcAddress;
    }

    function setupCollateral() internal {
        // Add collateral to liquidity provider
        vm.startPrank(adder);
        collateralManagement.addPegInCollateralTo{value: BASE_COLLATERAL}(
            liquidityProvider
        );
        collateralManagement.addPegOutCollateralTo{value: BASE_COLLATERAL}(
            liquidityProvider
        );
        vm.stopPrank();
    }

    // ============ Helper Functions ============

    function getRewardForQuote(
        uint256 penaltyFee,
        uint256 rewardPercentage
    ) internal pure returns (uint256) {
        return (penaltyFee * rewardPercentage) / 10000;
    }

    // ============ slashPegInCollateral and slashPegOutCollateral function tests ============

    function test_Slash_OnlyAllowsSlasherRoleToSlashCollateral() public {
        bytes32 slasherRole = collateralManagement.COLLATERAL_SLASHER();
        Quotes.PegOutQuote memory pegOutQuote = createPegOutQuote();
        Quotes.PegInQuote memory pegInQuote = createPegInQuote();

        // Try to slash PegOut collateral without role
        vm.prank(notSlasher);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                notSlasher,
                slasherRole
            )
        );
        collateralManagement.slashPegOutCollateral(
            punisher,
            pegOutQuote,
            quoteHash
        );

        // Try to slash PegIn collateral without role
        vm.prank(notSlasher);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                notSlasher,
                slasherRole
            )
        );
        collateralManagement.slashPegInCollateral(
            punisher,
            pegInQuote,
            quoteHash
        );
    }

    function test_SlashPegInCollateral_SlashesProperly() public {
        Quotes.PegInQuote memory pegInQuote = createPegInQuote();
        uint256 penalty = pegInQuote.penaltyFee;
        uint256 reward = getRewardForQuote(penalty, TEST_REWARD_PERCENTAGE);

        // Check initial collateral
        assertEq(
            collateralManagement.getPegInCollateral(liquidityProvider),
            BASE_COLLATERAL,
            "Initial collateral should match"
        );

        // Slash collateral
        vm.prank(slasher);
        vm.expectEmit(true, true, true, true);
        emit ICollateralManagement.Penalized(
            liquidityProvider,
            punisher,
            quoteHash,
            Flyover.ProviderType.PegIn,
            penalty,
            reward
        );
        collateralManagement.slashPegInCollateral(
            punisher,
            pegInQuote,
            quoteHash
        );

        // Verify collateral was slashed
        assertEq(
            collateralManagement.getPegInCollateral(liquidityProvider),
            BASE_COLLATERAL - penalty,
            "Collateral should be reduced by penalty"
        );

        // Verify reward was added
        assertEq(
            collateralManagement.getRewards(punisher),
            reward,
            "Punisher should receive reward"
        );

        // Verify penalties
        assertEq(
            collateralManagement.getPenalties(),
            penalty - reward,
            "Penalties should be penalty minus reward"
        );
    }

    function test_SlashPegOutCollateral_SlashesProperly() public {
        Quotes.PegOutQuote memory pegOutQuote = createPegOutQuote();
        uint256 penalty = pegOutQuote.penaltyFee;
        uint256 reward = getRewardForQuote(penalty, TEST_REWARD_PERCENTAGE);

        // Check initial collateral
        assertEq(
            collateralManagement.getPegOutCollateral(liquidityProvider),
            BASE_COLLATERAL,
            "Initial collateral should match"
        );

        // Slash collateral
        vm.prank(slasher);
        vm.expectEmit(true, true, true, true);
        emit ICollateralManagement.Penalized(
            liquidityProvider,
            punisher,
            quoteHash,
            Flyover.ProviderType.PegOut,
            penalty,
            reward
        );
        collateralManagement.slashPegOutCollateral(
            punisher,
            pegOutQuote,
            quoteHash
        );

        // Verify collateral was slashed
        assertEq(
            collateralManagement.getPegOutCollateral(liquidityProvider),
            BASE_COLLATERAL - penalty,
            "Collateral should be reduced by penalty"
        );

        // Verify reward was added
        assertEq(
            collateralManagement.getRewards(punisher),
            reward,
            "Punisher should receive reward"
        );

        // Verify penalties
        assertEq(
            collateralManagement.getPenalties(),
            penalty - reward,
            "Penalties should be penalty minus reward"
        );
    }

    function test_WithdrawRewards_PaysSlashRewardsProperly() public {
        Quotes.PegInQuote memory pegInQuote = createPegInQuote();
        Quotes.PegOutQuote memory pegOutQuote = createPegOutQuote();
        uint256 pegInPenalty = pegInQuote.penaltyFee;
        uint256 pegOutPenalty = pegOutQuote.penaltyFee;
        uint256 pegInReward = getRewardForQuote(
            pegInPenalty,
            TEST_REWARD_PERCENTAGE
        );
        uint256 pegOutReward = getRewardForQuote(
            pegOutPenalty,
            TEST_REWARD_PERCENTAGE
        );
        uint256 totalReward = pegInReward + pegOutReward;

        // Slash both types of collateral
        vm.startPrank(slasher);
        collateralManagement.slashPegInCollateral(
            punisher,
            pegInQuote,
            quoteHash
        );
        collateralManagement.slashPegOutCollateral(
            punisher,
            pegOutQuote,
            quoteHash
        );
        vm.stopPrank();

        // Verify rewards accumulated
        assertEq(
            collateralManagement.getRewards(punisher),
            totalReward,
            "Total rewards should match"
        );

        // Verify penalties
        assertEq(
            collateralManagement.getPenalties(),
            pegInPenalty + pegOutPenalty - totalReward,
            "Penalties should be total penalties minus rewards"
        );

        // Withdraw rewards
        uint256 balanceBefore = punisher.balance;

        vm.prank(punisher);
        vm.expectEmit(true, true, false, true);
        emit ICollateralManagement.RewardsWithdrawn(punisher, totalReward);
        collateralManagement.withdrawRewards();

        // Verify balance increased
        assertEq(
            punisher.balance,
            balanceBefore + totalReward,
            "Balance should increase by reward amount"
        );

        // Verify rewards reset
        assertEq(
            collateralManagement.getRewards(punisher),
            0,
            "Rewards should be reset to 0"
        );

        // Verify penalties unchanged
        assertEq(
            collateralManagement.getPenalties(),
            pegInPenalty + pegOutPenalty - totalReward,
            "Penalties should remain the same"
        );
    }

    function test_WithdrawRewards_AllowsWithdrawToDifferentRecipient() public {
        Quotes.PegInQuote memory pegInQuote = createPegInQuote();
        Quotes.PegOutQuote memory pegOutQuote = createPegOutQuote();
        uint256 totalReward = getRewardForQuote(
            pegInQuote.penaltyFee,
            TEST_REWARD_PERCENTAGE
        ) + getRewardForQuote(pegOutQuote.penaltyFee, TEST_REWARD_PERCENTAGE);

        vm.startPrank(slasher);
        collateralManagement.slashPegInCollateral(
            punisher,
            pegInQuote,
            quoteHash
        );
        collateralManagement.slashPegOutCollateral(
            punisher,
            pegOutQuote,
            quoteHash
        );
        vm.stopPrank();

        address recipient = makeAddr("rewardsRecipient");
        vm.deal(recipient, 0);
        uint256 recipientBalanceBefore = recipient.balance;
        uint256 punisherBalanceBefore = punisher.balance;

        vm.prank(punisher);
        vm.expectEmit(true, true, false, true);
        emit ICollateralManagement.RewardsWithdrawn(recipient, totalReward);
        collateralManagement.withdrawRewards(payable(recipient));

        // (1) Funds arrive at to
        assertEq(
            recipient.balance,
            recipientBalanceBefore + totalReward,
            "Recipient should receive the withdrawn rewards"
        );
        assertEq(
            punisher.balance,
            punisherBalanceBefore,
            "Caller (punisher) should not receive the funds; they went to recipient"
        );

        // (2) Caller's state is cleared
        assertEq(
            collateralManagement.getRewards(punisher),
            0,
            "Punisher rewards should be reset to 0"
        );

        // (3) Event semantics: RewardsWithdrawn(addr, amount) documents who withdrew and how much
        // (already asserted via vm.expectEmit above)
    }

    function test_WithdrawRewards_RevertsIfNoRewardToWithdraw() public {
        Quotes.PegInQuote memory pegInQuote = createPegInQuote();
        Quotes.PegOutQuote memory pegOutQuote = createPegOutQuote();

        // Slash collateral (rewards go to punisher, not slasher)
        vm.startPrank(slasher);
        collateralManagement.slashPegInCollateral(
            punisher,
            pegInQuote,
            quoteHash
        );
        collateralManagement.slashPegOutCollateral(
            punisher,
            pegOutQuote,
            quoteHash
        );
        vm.stopPrank();

        // Slasher tries to withdraw (should fail as they have no rewards)
        vm.prank(slasher);
        vm.expectRevert(
            abi.encodeWithSelector(
                ICollateralManagement.NothingToWithdraw.selector,
                slasher
            )
        );
        collateralManagement.withdrawRewards();
    }

    function test_WithdrawRewards_RevertsWithInvalidAddressWhenRecipientIsZeroAddress()
        public
    {
        Quotes.PegInQuote memory pegInQuote = createPegInQuote();
        Quotes.PegOutQuote memory pegOutQuote = createPegOutQuote();

        vm.startPrank(slasher);
        collateralManagement.slashPegInCollateral(
            punisher,
            pegInQuote,
            quoteHash
        );
        collateralManagement.slashPegOutCollateral(
            punisher,
            pegOutQuote,
            quoteHash
        );
        vm.stopPrank();

        uint256 rewardsBefore = collateralManagement.getRewards(punisher);

        vm.prank(punisher);
        vm.expectRevert(
            abi.encodeWithSelector(Flyover.InvalidAddress.selector, address(0))
        );
        collateralManagement.withdrawRewards(payable(address(0)));

        // Rewards should be unchanged
        assertEq(
            collateralManagement.getRewards(punisher),
            rewardsBefore,
            "Rewards should be unchanged"
        );
    }

    function test_WithdrawRewards_RevertsIfWithdrawExternalCallFails() public {
        Quotes.PegInQuote memory pegInQuote = createPegInQuote();
        Quotes.PegOutQuote memory pegOutQuote = createPegOutQuote();

        // Deploy WalletMock
        WalletMock walletMock = new WalletMock();
        address walletAddress = address(walletMock);

        // Slash collateral with walletMock as punisher
        vm.startPrank(slasher);
        collateralManagement.slashPegInCollateral(
            walletAddress,
            pegInQuote,
            quoteHash
        );
        collateralManagement.slashPegOutCollateral(
            walletAddress,
            pegOutQuote,
            quoteHash
        );
        vm.stopPrank();

        // Set wallet to reject funds
        walletMock.setRejectFunds(true);

        // Try to withdraw via wallet mock - should emit TransactionRejected
        bytes memory withdrawData = abi.encodeWithSelector(
            bytes4(keccak256("withdrawRewards()"))
        );

        vm.expectEmit(true, true, false, false);
        emit WalletMock.TransactionRejected(
            address(collateralManagement),
            0,
            bytes("")
        );
        walletMock.execute(address(collateralManagement), 0, withdrawData);
    }
}
