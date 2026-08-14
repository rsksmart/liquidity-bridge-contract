// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {CollateralTestBase} from "./CollateralTestBase.sol";
import {CollateralManagementContract} from "../../src/CollateralManagement.sol";
import {FlyoverDiscovery} from "../../src/FlyoverDiscovery.sol";
import {ICollateralManagement} from "../../src/interfaces/ICollateralManagement.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {Flyover} from "../../src/libraries/Flyover.sol";
import {Quotes} from "../../src/libraries/Quotes.sol";
import {WalletMock} from "../../src/test-contracts/WalletMock.sol";
import {P2PKH_ZERO_ADDRESS_TESTNET} from "../constants/btc.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {StdStorage, stdStorage} from "forge-std/StdStorage.sol";

contract SlashingTest is CollateralTestBase {
    using stdStorage for StdStorage;

    FlyoverDiscovery public discovery;

    address public punisher;
    address public liquidityProvider;
    address public user;
    address public notSlasher;
    address public lpA;
    address public lpB;
    address public pegInOnly;

    bytes32 public quoteHash;

    // Test constants
    uint256 constant CALL_FEE = 100000000000000; // 1e14
    uint256 constant PENALTY_FEE = 10000000000000; // 1e13
    uint256 constant GAS_FEE = 100;
    uint256 constant GAS_LIMIT = 21000;
    uint256 constant QUOTE_VALUE = 1 ether;
    uint256 constant COLLATERAL_A = 10 ether;
    uint256 constant COLLATERAL_B = 20 ether;
    uint256 constant SLASH_TOTAL = 3 ether;

    function setUp() public {
        deployCollateralManagement();
        setupRoles();
        _deployAndWireDiscovery();
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
        lpA = makeAddr("lpA");
        lpB = makeAddr("lpB");
        pegInOnly = makeAddr("pegInOnly");

        // Fund accounts
        vm.deal(punisher, 100 ether);
        vm.deal(liquidityProvider, 100 ether);
        vm.deal(user, 100 ether);
        vm.deal(notSlasher, 100 ether);
        vm.deal(lpA, 100 ether);
        vm.deal(lpB, 100 ether);
        vm.deal(pegInOnly, 100 ether);
    }

    function createPegInQuote()
        internal
        view
        returns (Quotes.PegInQuote memory quote)
    {
        bytes memory emptyBytes = new bytes(0);
        bytes memory testBtcAddress = P2PKH_ZERO_ADDRESS_TESTNET;

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
        bytes memory testBtcAddress = new bytes(21);
        testBtcAddress[0] = 0x6f;

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
        emit ICollateralManagement.RewardsWithdrawn(
            punisher,
            punisher,
            totalReward
        );
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
        emit ICollateralManagement.RewardsWithdrawn(
            punisher,
            recipient,
            totalReward
        );
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

        // (3) Event semantics: RewardsWithdrawn(caller, recipient, amount) documents who withdrew (caller), where the funds were sent (recipient), and how much
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

    // ============ globalSlash function tests ============

    function _deployAndWireDiscovery() internal {
        FlyoverDiscovery impl = new FlyoverDiscovery();
        ERC1967Proxy proxy = new ERC1967Proxy(
            address(impl),
            abi.encodeCall(
                FlyoverDiscovery.initialize,
                (
                    owner,
                    TEST_DEFAULT_ADMIN_DELAY,
                    address(collateralManagement),
                    pauseRegistry
                )
            )
        );
        discovery = FlyoverDiscovery(address(proxy));

        vm.startPrank(owner);
        collateralManagement.grantRole(
            collateralManagement.COLLATERAL_ADDER(),
            address(discovery)
        );
        collateralManagement.setFlyoverDiscovery(address(discovery));
        vm.stopPrank();
    }

    function _approvePegOut(address lp, uint256 amount) internal {
        vm.prank(lp, lp);
        discovery.register{value: amount}(
            "LP",
            "http://localhost/api",
            true,
            Flyover.ProviderType.PegOut
        );
        vm.prank(owner);
        discovery.approveRegistration(lp);
    }

    function _approvePegIn(address lp, uint256 amount) internal {
        vm.prank(lp, lp);
        discovery.register{value: amount}(
            "LP",
            "http://localhost/api",
            true,
            Flyover.ProviderType.PegIn
        );
        vm.prank(owner);
        discovery.approveRegistration(lp);
    }

    function _topUpPegOut(address lp, uint256 amount) internal {
        vm.prank(adder);
        collateralManagement.addPegOutCollateralTo{value: amount}(lp);
    }

    function test_T3_GlobalSlash_ProportionalToPegOutCollateral() public {
        _approvePegOut(lpA, COLLATERAL_A);
        _approvePegOut(lpB, COLLATERAL_B);
        vm.prank(adder);
        collateralManagement.addPegInCollateralTo{value: BASE_COLLATERAL}(lpA);

        uint256 pegInBefore = collateralManagement.getPegInCollateral(lpA);

        vm.prank(slasher);
        collateralManagement.globalSlash(SLASH_TOTAL);

        assertEq(
            collateralManagement.getPegOutCollateral(lpA),
            COLLATERAL_A - 1 ether,
            "lpA should lose 1/3 of slash"
        );
        assertEq(
            collateralManagement.getPegOutCollateral(lpB),
            COLLATERAL_B - 2 ether,
            "lpB should lose 2/3 of slash"
        );
        assertEq(
            collateralManagement.getPegInCollateral(lpA),
            pegInBefore,
            "peg-in collateral must be untouched"
        );
    }

    function test_T3_GlobalSlash_SkipsGraceWindow() public {
        uint256 grace = 100;
        vm.prank(owner);
        collateralManagement.setGlobalSlashGraceBlocks(grace);

        _approvePegOut(lpA, COLLATERAL_A);
        uint256 regA = collateralManagement.getPegOutRegistrationBlock(lpA);

        vm.roll(regA + grace);
        _approvePegOut(lpB, COLLATERAL_B);

        assertFalse(
            block.number <
                collateralManagement.getPegOutRegistrationBlock(lpA) + grace
        );
        assertTrue(
            block.number <
                collateralManagement.getPegOutRegistrationBlock(lpB) + grace
        );

        vm.prank(slasher);
        collateralManagement.globalSlash(SLASH_TOTAL);

        assertEq(
            collateralManagement.getPegOutCollateral(lpA),
            COLLATERAL_A - SLASH_TOTAL,
            "out-of-window LP pays the full slash"
        );
        assertEq(
            collateralManagement.getPegOutCollateral(lpB),
            COLLATERAL_B,
            "in-window LP must be skipped"
        );
    }

    function test_T3_GlobalSlash_SkipsResigned() public {
        _approvePegOut(lpA, COLLATERAL_A);
        _approvePegOut(lpB, COLLATERAL_B);

        vm.prank(lpB);
        collateralManagement.resign();

        vm.prank(slasher);
        collateralManagement.globalSlash(SLASH_TOTAL);

        assertEq(
            collateralManagement.getPegOutCollateral(lpA),
            COLLATERAL_A - SLASH_TOTAL
        );
        assertEq(
            collateralManagement.getPegOutCollateral(lpB),
            COLLATERAL_B,
            "resigned LP must be skipped"
        );
    }

    function test_T3_GlobalSlash_SkipsPegInOnly() public {
        _approvePegIn(pegInOnly, BASE_COLLATERAL);
        _approvePegOut(lpA, COLLATERAL_A);

        uint256 pegInBefore = collateralManagement.getPegInCollateral(
            pegInOnly
        );

        vm.prank(slasher);
        collateralManagement.globalSlash(SLASH_TOTAL);

        assertEq(
            collateralManagement.getPegInCollateral(pegInOnly),
            pegInBefore
        );
        assertEq(
            collateralManagement.getPegOutCollateral(lpA),
            COLLATERAL_A - SLASH_TOTAL
        );
    }

    function test_T3_GlobalSlash_UsesDiscoveryNotCollateralOnly() public {
        // Collateral without Discovery approval must not be slashed.
        vm.prank(adder);
        collateralManagement.addPegOutCollateralTo{value: COLLATERAL_A}(lpA);

        vm.prank(slasher);
        vm.expectRevert(
            ICollateralManagement.GlobalSlashNoEligibleProviders.selector
        );
        collateralManagement.globalSlash(SLASH_TOTAL);

        assertEq(collateralManagement.getPegOutCollateral(lpA), COLLATERAL_A);
    }

    function test_T3_GlobalSlash_GrandfatheredZeroRegBlockIsEligible() public {
        uint256 grace = 1_000;
        vm.prank(owner);
        collateralManagement.setGlobalSlashGraceBlocks(grace);

        _approvePegOut(lpA, COLLATERAL_A);
        stdstore
            .target(address(collateralManagement))
            .sig("getPegOutRegistrationBlock(address)")
            .with_key(lpA)
            .checked_write(uint256(0));
        assertEq(collateralManagement.getPegOutRegistrationBlock(lpA), 0);

        vm.prank(slasher);
        collateralManagement.globalSlash(SLASH_TOTAL);

        assertEq(
            collateralManagement.getPegOutCollateral(lpA),
            COLLATERAL_A - SLASH_TOTAL,
            "zero registration block must not grant infinite grace"
        );
    }

    function test_T3_GlobalSlash_DestinationIsPenalties() public {
        _approvePegOut(lpA, COLLATERAL_A);
        uint256 balanceBefore = address(collateralManagement).balance;
        uint256 penaltiesBefore = collateralManagement.getPenalties();
        uint256 rewardsSlashBefore = collateralManagement.getRewards(slasher);
        uint256 rewardsLpBefore = collateralManagement.getRewards(lpA);

        vm.expectEmit(true, true, false, true, address(collateralManagement));
        emit ICollateralManagement.GlobalSlashShare(lpA, SLASH_TOTAL);
        vm.expectEmit(true, true, false, true, address(collateralManagement));
        emit ICollateralManagement.GlobalSlashExecuted(
            SLASH_TOTAL,
            SLASH_TOTAL
        );

        vm.prank(slasher);
        collateralManagement.globalSlash(SLASH_TOTAL);

        assertEq(
            collateralManagement.getPenalties(),
            penaltiesBefore + SLASH_TOTAL,
            "100% of taken collateral goes to protocol penalties"
        );
        assertEq(collateralManagement.getRewards(slasher), rewardsSlashBefore);
        assertEq(collateralManagement.getRewards(lpA), rewardsLpBefore);
        assertEq(
            address(collateralManagement).balance,
            balanceBefore,
            "RBTC must stay in CollateralManagement"
        );
    }

    function test_T3_GlobalSlash_UnauthorizedReverts() public {
        _approvePegOut(lpA, COLLATERAL_A);
        bytes32 slasherRole = collateralManagement.COLLATERAL_SLASHER();

        vm.prank(notSlasher);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                notSlasher,
                slasherRole
            )
        );
        collateralManagement.globalSlash(SLASH_TOTAL);
    }

    function test_T3_GlobalSlash_NoEligibleReverts() public {
        vm.prank(slasher);
        vm.expectRevert(
            ICollateralManagement.GlobalSlashNoEligibleProviders.selector
        );
        collateralManagement.globalSlash(SLASH_TOTAL);

        uint256 grace = 100;
        vm.prank(owner);
        collateralManagement.setGlobalSlashGraceBlocks(grace);
        _approvePegOut(lpA, COLLATERAL_A);

        vm.prank(slasher);
        vm.expectRevert(
            ICollateralManagement.GlobalSlashNoEligibleProviders.selector
        );
        collateralManagement.globalSlash(SLASH_TOTAL);
    }

    function test_T3_GlobalSlash_DiscoveryNotSetReverts() public {
        // Fresh CM without Discovery wiring.
        CollateralManagementContract bareImpl = new CollateralManagementContract();
        ERC1967Proxy bareProxy = new ERC1967Proxy(
            address(bareImpl),
            abi.encodeCall(
                CollateralManagementContract.initialize,
                (
                    owner,
                    TEST_DEFAULT_ADMIN_DELAY,
                    TEST_MIN_COLLATERAL,
                    TEST_RESIGN_DELAY_BLOCKS,
                    TEST_REWARD_PERCENTAGE,
                    pauseRegistry
                )
            )
        );
        CollateralManagementContract bare = CollateralManagementContract(
            payable(address(bareProxy))
        );
        vm.startPrank(owner);
        bare.grantRole(bare.COLLATERAL_SLASHER(), slasher);
        vm.stopPrank();

        vm.prank(slasher);
        vm.expectRevert(
            CollateralManagementContract.FlyoverDiscoveryNotSet.selector
        );
        bare.globalSlash(SLASH_TOTAL);
    }

    function test_T3_GlobalSlash_ZeroAmountReverts() public {
        _approvePegOut(lpA, COLLATERAL_A);
        vm.prank(slasher);
        vm.expectRevert(ICollateralManagement.GlobalSlashZeroAmount.selector);
        collateralManagement.globalSlash(0);
    }

    function test_T3_GlobalSlash_CapsAtEligibleSum() public {
        _approvePegOut(lpA, 1 ether);
        _approvePegOut(lpB, 2 ether);

        vm.prank(slasher);
        collateralManagement.globalSlash(100 ether);

        assertEq(collateralManagement.getPegOutCollateral(lpA), 0);
        assertEq(collateralManagement.getPegOutCollateral(lpB), 0);
        assertEq(collateralManagement.getPenalties(), 3 ether);
    }

    function test_SetGlobalSlashGraceBlocks_OnlyAdmin() public {
        assertEq(collateralManagement.getGlobalSlashGraceBlocks(), 0);

        vm.prank(owner);
        vm.expectEmit(true, true, false, true, address(collateralManagement));
        emit CollateralManagementContract.GlobalSlashGraceBlocksSet(0, 50);
        collateralManagement.setGlobalSlashGraceBlocks(50);
        assertEq(collateralManagement.getGlobalSlashGraceBlocks(), 50);

        bytes32 adminRole = collateralManagement.DEFAULT_ADMIN_ROLE();
        vm.prank(notSlasher);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                notSlasher,
                adminRole
            )
        );
        collateralManagement.setGlobalSlashGraceBlocks(10);
    }

    function test_T3_GlobalSlash_TopUpDoesNotResetGraceWindow() public {
        uint256 grace = 100;
        vm.prank(owner);
        collateralManagement.setGlobalSlashGraceBlocks(grace);

        _approvePegOut(lpA, COLLATERAL_A);
        uint256 regBlock = collateralManagement.getPegOutRegistrationBlock(lpA);

        vm.roll(block.number + 10);
        _topUpPegOut(lpA, 1 ether);

        assertEq(
            collateralManagement.getPegOutRegistrationBlock(lpA),
            regBlock,
            "top-up must not refresh registration block"
        );
    }

    function test_T3_GlobalSlash_WithdrawThenReAddResetsGraceWindow() public {
        uint256 grace = 100;
        vm.prank(owner);
        collateralManagement.setGlobalSlashGraceBlocks(grace);

        _approvePegOut(lpA, COLLATERAL_A);
        uint256 firstReg = collateralManagement.getPegOutRegistrationBlock(lpA);

        vm.prank(lpA);
        collateralManagement.resign();
        vm.roll(block.number + TEST_RESIGN_DELAY_BLOCKS);
        vm.prank(lpA);
        collateralManagement.withdrawCollateral();

        assertEq(collateralManagement.getPegOutCollateral(lpA), 0);

        vm.roll(block.number + 5);
        _topUpPegOut(lpA, COLLATERAL_A);

        uint256 secondReg = collateralManagement.getPegOutRegistrationBlock(
            lpA
        );
        assertTrue(
            secondReg > firstReg,
            "re-add must start a new grace window"
        );
        assertEq(secondReg, block.number);
    }
}
