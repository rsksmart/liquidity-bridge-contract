// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {CollateralTestBase} from "./CollateralTestBase.sol";
import {CollateralManagementContract} from "../../src/CollateralManagement.sol";
import {ICollateralManagement} from "../../src/interfaces/ICollateralManagement.sol";
import {Flyover} from "../../src/libraries/Flyover.sol";
import {Quotes} from "../../src/libraries/Quotes.sol";
import {WalletMock} from "../../src/test-contracts/WalletMock.sol";

contract ResignTest is CollateralTestBase {
    address public notProvider;

    function setUp() public {
        deployCollateralManagement();
        setupRoles();
        setupProviders();

        // Create additional test account
        notProvider = makeAddr("notProvider");
        vm.deal(notProvider, 100 ether);
    }

    // ============ resign function tests ============

    function test_Resign_RevertsIfProviderResignsTwice() public {
        address[3] memory providers = [pegInLp, pegOutLp, fullLp];

        for (uint i = 0; i < providers.length; i++) {
            address provider = providers[i];

            // First resign should succeed
            vm.prank(provider);
            collateralManagement.resign();

            // Second resign should revert
            vm.prank(provider);
            vm.expectRevert(
                abi.encodeWithSelector(
                    ICollateralManagement.AlreadyResigned.selector,
                    provider
                )
            );
            collateralManagement.resign();
        }
    }

    function test_Resign_RevertsIfAccountNotRegistered() public {
        vm.prank(notProvider);
        vm.expectRevert(
            abi.encodeWithSelector(
                Flyover.ProviderNotRegistered.selector,
                notProvider
            )
        );
        collateralManagement.resign();
    }

    function test_Resign_AllowsProvidersToResign() public {
        // Test pegInLp
        assertTrue(
            collateralManagement.isRegistered(
                Flyover.ProviderType.PegIn,
                pegInLp
            )
        );
        assertTrue(
            collateralManagement.isCollateralSufficient(
                Flyover.ProviderType.PegIn,
                pegInLp
            )
        );

        vm.prank(pegInLp);
        vm.expectEmit(true, false, false, true);
        emit ICollateralManagement.Resigned(pegInLp);
        collateralManagement.resign();

        uint256 resignBlock = collateralManagement.getResignationBlock(pegInLp);
        assertEq(
            resignBlock,
            block.number,
            "Resignation block should match current block"
        );

        assertFalse(
            collateralManagement.isRegistered(
                Flyover.ProviderType.PegIn,
                pegInLp
            )
        );
        assertFalse(
            collateralManagement.isCollateralSufficient(
                Flyover.ProviderType.PegIn,
                pegInLp
            )
        );

        // Test pegOutLp
        assertTrue(
            collateralManagement.isRegistered(
                Flyover.ProviderType.PegOut,
                pegOutLp
            )
        );
        assertTrue(
            collateralManagement.isCollateralSufficient(
                Flyover.ProviderType.PegOut,
                pegOutLp
            )
        );

        vm.prank(pegOutLp);
        vm.expectEmit(true, false, false, true);
        emit ICollateralManagement.Resigned(pegOutLp);
        collateralManagement.resign();

        resignBlock = collateralManagement.getResignationBlock(pegOutLp);
        assertEq(
            resignBlock,
            block.number,
            "Resignation block should match current block"
        );

        assertFalse(
            collateralManagement.isRegistered(
                Flyover.ProviderType.PegOut,
                pegOutLp
            )
        );
        assertFalse(
            collateralManagement.isCollateralSufficient(
                Flyover.ProviderType.PegOut,
                pegOutLp
            )
        );

        // Test fullLp
        assertTrue(
            collateralManagement.isRegistered(
                Flyover.ProviderType.PegIn,
                fullLp
            )
        );
        assertTrue(
            collateralManagement.isCollateralSufficient(
                Flyover.ProviderType.PegIn,
                fullLp
            )
        );
        assertTrue(
            collateralManagement.isRegistered(
                Flyover.ProviderType.PegOut,
                fullLp
            )
        );
        assertTrue(
            collateralManagement.isCollateralSufficient(
                Flyover.ProviderType.PegOut,
                fullLp
            )
        );

        vm.prank(fullLp);
        vm.expectEmit(true, false, false, true);
        emit ICollateralManagement.Resigned(fullLp);
        collateralManagement.resign();

        resignBlock = collateralManagement.getResignationBlock(fullLp);
        assertEq(
            resignBlock,
            block.number,
            "Resignation block should match current block"
        );

        assertFalse(
            collateralManagement.isRegistered(
                Flyover.ProviderType.PegIn,
                fullLp
            )
        );
        assertFalse(
            collateralManagement.isCollateralSufficient(
                Flyover.ProviderType.PegIn,
                fullLp
            )
        );
        assertFalse(
            collateralManagement.isRegistered(
                Flyover.ProviderType.PegOut,
                fullLp
            )
        );
        assertFalse(
            collateralManagement.isCollateralSufficient(
                Flyover.ProviderType.PegOut,
                fullLp
            )
        );
    }

    // ============ withdrawCollateral function tests ============

    function test_WithdrawCollateral_RevertsIfProviderNotResigned() public {
        vm.prank(notProvider);
        vm.expectRevert(
            abi.encodeWithSelector(
                ICollateralManagement.NotResigned.selector,
                notProvider
            )
        );
        collateralManagement.withdrawCollateral();
    }

    function test_WithdrawCollateral_RevertsIfResignDelayNotPassed() public {
        address[3] memory providers = [pegInLp, pegOutLp, fullLp];

        for (uint i = 0; i < providers.length; i++) {
            address provider = providers[i];

            vm.prank(provider);
            collateralManagement.resign();

            uint256 resignBlockNum = collateralManagement.getResignationBlock(
                provider
            );

            // Mine blocks but not enough to meet the delay
            vm.roll(block.number + TEST_RESIGN_DELAY_BLOCKS - 2);

            vm.prank(provider);
            vm.expectRevert(
                abi.encodeWithSelector(
                    ICollateralManagement.ResignationDelayNotMet.selector,
                    provider,
                    resignBlockNum,
                    TEST_RESIGN_DELAY_BLOCKS
                )
            );
            collateralManagement.withdrawCollateral();
        }
    }

    function test_WithdrawCollateral_RevertsIfNoCollateralToWithdraw() public {
        // Slash all collateral from pegInLp
        vm.prank(pegInLp);
        collateralManagement.resign();

        Quotes.PegInQuote memory quote = getEmptyPegInQuote();
        quote.penaltyFee = 300 ether;
        quote.liquidityProviderRskAddress = pegInLp;

        vm.prank(slasher);
        collateralManagement.slashPegInCollateral(
            ZERO_ADDRESS,
            quote,
            bytes32(0)
        );

        // Wait for resign delay
        vm.roll(block.number + TEST_RESIGN_DELAY_BLOCKS);

        vm.prank(pegInLp);
        vm.expectRevert(
            abi.encodeWithSelector(
                ICollateralManagement.NothingToWithdraw.selector,
                pegInLp
            )
        );
        collateralManagement.withdrawCollateral();

        // Slash all collateral from pegOutLp
        vm.prank(pegOutLp);
        collateralManagement.resign();

        Quotes.PegOutQuote memory pegOutQuote = getEmptyPegOutQuote();
        pegOutQuote.penaltyFee = 300 ether;
        pegOutQuote.lpRskAddress = pegOutLp;

        vm.prank(slasher);
        collateralManagement.slashPegOutCollateral(
            ZERO_ADDRESS,
            pegOutQuote,
            bytes32(0)
        );

        // Wait for resign delay
        vm.roll(block.number + TEST_RESIGN_DELAY_BLOCKS);

        vm.prank(pegOutLp);
        vm.expectRevert(
            abi.encodeWithSelector(
                ICollateralManagement.NothingToWithdraw.selector,
                pegOutLp
            )
        );
        collateralManagement.withdrawCollateral();

        // Slash all collateral from fullLp (both pegIn and pegOut)
        vm.prank(fullLp);
        collateralManagement.resign();

        quote.liquidityProviderRskAddress = fullLp;
        vm.prank(slasher);
        collateralManagement.slashPegInCollateral(
            ZERO_ADDRESS,
            quote,
            bytes32(0)
        );

        pegOutQuote.lpRskAddress = fullLp;
        vm.prank(slasher);
        collateralManagement.slashPegOutCollateral(
            ZERO_ADDRESS,
            pegOutQuote,
            bytes32(0)
        );

        // Wait for resign delay
        vm.roll(block.number + TEST_RESIGN_DELAY_BLOCKS);

        vm.prank(fullLp);
        vm.expectRevert(
            abi.encodeWithSelector(
                ICollateralManagement.NothingToWithdraw.selector,
                fullLp
            )
        );
        collateralManagement.withdrawCollateral();
    }

    function test_WithdrawCollateral_RevertsWithInvalidAddressWhenRecipientIsZeroAddress()
        public
    {
        uint256 pegInCollateral = collateralManagement.getPegInCollateral(
            pegInLp
        );
        vm.prank(pegInLp);
        collateralManagement.resign();

        vm.roll(block.number + TEST_RESIGN_DELAY_BLOCKS);

        vm.prank(pegInLp);
        vm.expectRevert(
            abi.encodeWithSelector(Flyover.InvalidAddress.selector, address(0))
        );
        collateralManagement.withdrawCollateral(payable(address(0)));

        // State should be unchanged
        assertEq(
            collateralManagement.getResignationBlock(pegInLp),
            block.number - TEST_RESIGN_DELAY_BLOCKS,
            "Resignation block should be unchanged"
        );
        assertEq(
            collateralManagement.getPegInCollateral(pegInLp),
            pegInCollateral,
            "Collateral should be unchanged"
        );
    }

    function test_WithdrawCollateral_AllowsWithdrawToDifferentRecipient()
        public
    {
        uint256 pegInCollateral = collateralManagement.getPegInCollateral(
            pegInLp
        );

        vm.prank(pegInLp);
        collateralManagement.resign();

        vm.roll(block.number + TEST_RESIGN_DELAY_BLOCKS);

        address recipient = makeAddr("collateralRecipient");
        vm.deal(recipient, 0);
        uint256 recipientBalanceBefore = recipient.balance;
        uint256 pegInLpBalanceBefore = pegInLp.balance;

        vm.prank(pegInLp);
        vm.expectEmit(true, true, false, true);
        emit ICollateralManagement.WithdrawCollateral(pegInLp, pegInCollateral);
        collateralManagement.withdrawCollateral(payable(recipient));

        // (1) Funds arrive at to
        assertEq(
            recipient.balance,
            recipientBalanceBefore + pegInCollateral,
            "Recipient should receive the withdrawn collateral"
        );
        assertEq(
            pegInLp.balance,
            pegInLpBalanceBefore,
            "Caller (provider) should not receive the funds; they went to recipient"
        );

        // (2) Caller's state is cleared
        assertEq(
            collateralManagement.getPegInCollateral(pegInLp),
            0,
            "PegIn collateral should be 0"
        );
        assertEq(
            collateralManagement.getResignationBlock(pegInLp),
            0,
            "Resignation block should be reset"
        );

        // (3) Event semantics: WithdrawCollateral(addr, amount) documents who withdrew and how much
        // (already asserted via vm.expectEmit above)
    }

    function test_WithdrawCollateral_AllowsProvidersToWithdrawCollateral()
        public
    {
        // Test pegInLp
        uint256 pegInCollateral = collateralManagement.getPegInCollateral(
            pegInLp
        );

        // Slash half of the collateral
        Quotes.PegInQuote memory quote = getEmptyPegInQuote();
        quote.penaltyFee = pegInCollateral / 2;
        quote.liquidityProviderRskAddress = pegInLp;

        vm.prank(slasher);
        collateralManagement.slashPegInCollateral(
            ZERO_ADDRESS,
            quote,
            bytes32(0)
        );

        vm.prank(pegInLp);
        collateralManagement.resign();

        // Wait for resign delay
        vm.roll(block.number + TEST_RESIGN_DELAY_BLOCKS);

        uint256 expectedWithdrawal = pegInCollateral / 2;
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
            "Balance should increase"
        );
        assertEq(
            collateralManagement.getPegInCollateral(pegInLp),
            0,
            "PegIn collateral should be 0"
        );
        assertEq(
            collateralManagement.getResignationBlock(pegInLp),
            0,
            "Resignation block should be reset"
        );

        // Test pegOutLp
        uint256 pegOutCollateral = collateralManagement.getPegOutCollateral(
            pegOutLp
        );

        Quotes.PegOutQuote memory pegOutQuote = getEmptyPegOutQuote();
        pegOutQuote.penaltyFee = pegOutCollateral / 2;
        pegOutQuote.lpRskAddress = pegOutLp;

        vm.prank(slasher);
        collateralManagement.slashPegOutCollateral(
            ZERO_ADDRESS,
            pegOutQuote,
            bytes32(0)
        );

        vm.prank(pegOutLp);
        collateralManagement.resign();

        vm.roll(block.number + TEST_RESIGN_DELAY_BLOCKS);

        expectedWithdrawal = pegOutCollateral / 2;
        balanceBefore = pegOutLp.balance;

        vm.prank(pegOutLp);
        vm.expectEmit(true, true, false, true);
        emit ICollateralManagement.WithdrawCollateral(
            pegOutLp,
            expectedWithdrawal
        );
        collateralManagement.withdrawCollateral();

        assertEq(
            pegOutLp.balance,
            balanceBefore + expectedWithdrawal,
            "Balance should increase"
        );
        assertEq(
            collateralManagement.getPegOutCollateral(pegOutLp),
            0,
            "PegOut collateral should be 0"
        );
        assertEq(
            collateralManagement.getResignationBlock(pegOutLp),
            0,
            "Resignation block should be reset"
        );

        // Test fullLp
        uint256 fullLpPegInCollateral = collateralManagement.getPegInCollateral(
            fullLp
        );
        uint256 fullLpPegOutCollateral = collateralManagement
            .getPegOutCollateral(fullLp);

        quote.penaltyFee = fullLpPegInCollateral / 2;
        quote.liquidityProviderRskAddress = fullLp;
        vm.prank(slasher);
        collateralManagement.slashPegInCollateral(
            ZERO_ADDRESS,
            quote,
            bytes32(0)
        );

        pegOutQuote.penaltyFee = fullLpPegOutCollateral / 2;
        pegOutQuote.lpRskAddress = fullLp;
        vm.prank(slasher);
        collateralManagement.slashPegOutCollateral(
            ZERO_ADDRESS,
            pegOutQuote,
            bytes32(0)
        );

        vm.prank(fullLp);
        collateralManagement.resign();

        vm.roll(block.number + TEST_RESIGN_DELAY_BLOCKS);

        expectedWithdrawal =
            fullLpPegInCollateral /
            2 +
            fullLpPegOutCollateral /
            2;
        balanceBefore = fullLp.balance;

        vm.prank(fullLp);
        vm.expectEmit(true, true, false, true);
        emit ICollateralManagement.WithdrawCollateral(
            fullLp,
            expectedWithdrawal
        );
        collateralManagement.withdrawCollateral();

        assertEq(
            fullLp.balance,
            balanceBefore + expectedWithdrawal,
            "Balance should increase"
        );
        assertEq(
            collateralManagement.getPegInCollateral(fullLp),
            0,
            "PegIn collateral should be 0"
        );
        assertEq(
            collateralManagement.getPegOutCollateral(fullLp),
            0,
            "PegOut collateral should be 0"
        );
        assertEq(
            collateralManagement.getResignationBlock(fullLp),
            0,
            "Resignation block should be reset"
        );
    }

    function test_WithdrawCollateral_RevertsIfWithdrawalFails() public {
        // Deploy WalletMock
        WalletMock walletMock = new WalletMock();
        address walletAddress = address(walletMock);

        // Fund the wallet mock
        vm.deal(walletAddress, 100 ether);

        // Add collateral to the wallet mock
        vm.startPrank(adder);
        collateralManagement.addPegInCollateralTo{value: 100 ether}(
            walletAddress
        );
        collateralManagement.addPegOutCollateralTo{value: 100 ether}(
            walletAddress
        );
        vm.stopPrank();

        // Wallet resigns via execute function
        bytes memory resignData = abi.encodeWithSelector(
            collateralManagement.resign.selector
        );
        walletMock.execute(address(collateralManagement), 0, resignData);

        // Wait for resign delay
        vm.roll(block.number + TEST_RESIGN_DELAY_BLOCKS);

        // Set wallet to reject funds
        walletMock.setRejectFunds(true);

        // Try to withdraw - should emit TransactionRejected event (no-arg overload)
        bytes memory withdrawData = abi.encodeWithSelector(
            bytes4(keccak256("withdrawCollateral()"))
        );

        // The withdrawal should fail and emit TransactionRejected
        vm.expectEmit(true, true, false, false);
        emit WalletMock.TransactionRejected(
            address(collateralManagement),
            0,
            bytes("")
        );
        walletMock.execute(address(collateralManagement), 0, withdrawData);
    }

    // ============ isRegistered function tests ============

    function test_IsRegistered_ReturnsTrueIfProviderHasCollateralAndHasNotResigned()
        public
        view
    {
        // Check pegInLp
        assertTrue(
            collateralManagement.isRegistered(
                Flyover.ProviderType.PegIn,
                pegInLp
            )
        );
        assertFalse(
            collateralManagement.isRegistered(
                Flyover.ProviderType.PegOut,
                pegInLp
            )
        );
        assertFalse(
            collateralManagement.isRegistered(
                Flyover.ProviderType.Both,
                pegInLp
            )
        );

        // Check pegOutLp
        assertTrue(
            collateralManagement.isRegistered(
                Flyover.ProviderType.PegOut,
                pegOutLp
            )
        );
        assertFalse(
            collateralManagement.isRegistered(
                Flyover.ProviderType.PegIn,
                pegOutLp
            )
        );
        assertFalse(
            collateralManagement.isRegistered(
                Flyover.ProviderType.Both,
                pegOutLp
            )
        );

        // Check fullLp
        assertTrue(
            collateralManagement.isRegistered(
                Flyover.ProviderType.PegIn,
                fullLp
            )
        );
        assertTrue(
            collateralManagement.isRegistered(
                Flyover.ProviderType.PegOut,
                fullLp
            )
        );
        assertTrue(
            collateralManagement.isRegistered(Flyover.ProviderType.Both, fullLp)
        );
    }

    function test_IsRegistered_ReturnsFalseIfProviderHasResigned() public {
        // Resign all providers
        vm.prank(pegInLp);
        collateralManagement.resign();

        vm.prank(pegOutLp);
        collateralManagement.resign();

        vm.prank(fullLp);
        collateralManagement.resign();

        // Check pegInLp
        assertFalse(
            collateralManagement.isRegistered(
                Flyover.ProviderType.PegIn,
                pegInLp
            )
        );
        assertFalse(
            collateralManagement.isRegistered(
                Flyover.ProviderType.PegOut,
                pegInLp
            )
        );
        assertFalse(
            collateralManagement.isRegistered(
                Flyover.ProviderType.Both,
                pegInLp
            )
        );

        // Check pegOutLp
        assertFalse(
            collateralManagement.isRegistered(
                Flyover.ProviderType.PegOut,
                pegOutLp
            )
        );
        assertFalse(
            collateralManagement.isRegistered(
                Flyover.ProviderType.PegIn,
                pegOutLp
            )
        );
        assertFalse(
            collateralManagement.isRegistered(
                Flyover.ProviderType.Both,
                pegOutLp
            )
        );

        // Check fullLp
        assertFalse(
            collateralManagement.isRegistered(
                Flyover.ProviderType.PegIn,
                fullLp
            )
        );
        assertFalse(
            collateralManagement.isRegistered(
                Flyover.ProviderType.PegOut,
                fullLp
            )
        );
        assertFalse(
            collateralManagement.isRegistered(Flyover.ProviderType.Both, fullLp)
        );
    }

    // ============ isCollateralSufficient function tests ============

    function test_IsCollateralSufficient_ReturnsTrueIfProviderHasMinimumCollateralAndHasNotResigned()
        public
        view
    {
        // Check pegInLp
        assertTrue(
            collateralManagement.isCollateralSufficient(
                Flyover.ProviderType.PegIn,
                pegInLp
            )
        );
        assertFalse(
            collateralManagement.isCollateralSufficient(
                Flyover.ProviderType.PegOut,
                pegInLp
            )
        );
        assertFalse(
            collateralManagement.isCollateralSufficient(
                Flyover.ProviderType.Both,
                pegInLp
            )
        );

        // Check pegOutLp
        assertTrue(
            collateralManagement.isCollateralSufficient(
                Flyover.ProviderType.PegOut,
                pegOutLp
            )
        );
        assertFalse(
            collateralManagement.isCollateralSufficient(
                Flyover.ProviderType.PegIn,
                pegOutLp
            )
        );
        assertFalse(
            collateralManagement.isCollateralSufficient(
                Flyover.ProviderType.Both,
                pegOutLp
            )
        );

        // Check fullLp
        assertTrue(
            collateralManagement.isCollateralSufficient(
                Flyover.ProviderType.PegIn,
                fullLp
            )
        );
        assertTrue(
            collateralManagement.isCollateralSufficient(
                Flyover.ProviderType.PegOut,
                fullLp
            )
        );
        assertTrue(
            collateralManagement.isCollateralSufficient(
                Flyover.ProviderType.Both,
                fullLp
            )
        );
    }

    function test_IsCollateralSufficient_ReturnsFalseIfProviderHasResigned()
        public
    {
        address[3] memory providers = [pegInLp, pegOutLp, fullLp];

        for (uint i = 0; i < providers.length; i++) {
            address provider = providers[i];

            vm.prank(provider);
            collateralManagement.resign();

            assertFalse(
                collateralManagement.isCollateralSufficient(
                    Flyover.ProviderType.PegIn,
                    provider
                )
            );
            assertFalse(
                collateralManagement.isCollateralSufficient(
                    Flyover.ProviderType.PegOut,
                    provider
                )
            );
            assertFalse(
                collateralManagement.isCollateralSufficient(
                    Flyover.ProviderType.Both,
                    provider
                )
            );
        }
    }

    function test_IsCollateralSufficient_ReturnsFalseIfProviderHasLessThanMinimumCollateral()
        public
    {
        address[3] memory providers = [pegInLp, pegOutLp, fullLp];

        for (uint i = 0; i < providers.length; i++) {
            address provider = providers[i];

            // Slash a lot of collateral
            Quotes.PegInQuote memory pegInQuote = getEmptyPegInQuote();
            pegInQuote.penaltyFee = 1000000 ether;
            pegInQuote.liquidityProviderRskAddress = provider;

            Quotes.PegOutQuote memory pegOutQuote = getEmptyPegOutQuote();
            pegOutQuote.penaltyFee = 1000000 ether;
            pegOutQuote.lpRskAddress = provider;

            vm.prank(slasher);
            collateralManagement.slashPegInCollateral(
                ZERO_ADDRESS,
                pegInQuote,
                bytes32(0)
            );

            vm.prank(slasher);
            collateralManagement.slashPegOutCollateral(
                ZERO_ADDRESS,
                pegOutQuote,
                bytes32(0)
            );

            assertFalse(
                collateralManagement.isCollateralSufficient(
                    Flyover.ProviderType.PegIn,
                    provider
                )
            );
            assertFalse(
                collateralManagement.isCollateralSufficient(
                    Flyover.ProviderType.PegOut,
                    provider
                )
            );
            assertFalse(
                collateralManagement.isCollateralSufficient(
                    Flyover.ProviderType.Both,
                    provider
                )
            );
        }
    }
}
