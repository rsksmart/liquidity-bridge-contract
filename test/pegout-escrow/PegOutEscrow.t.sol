// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {PegOutEscrow} from "../../src/PegOutEscrow.sol";
import {PegOutContract} from "../../src/PegOutContract.sol";
import {PauseRegistry} from "../../src/PauseRegistry.sol";
import {ICollateralManagement} from "../../src/interfaces/ICollateralManagement.sol";
import {IPegOut} from "../../src/interfaces/IPegOut.sol";
import {IPegOutEscrow} from "../../src/interfaces/IPegOutEscrow.sol";
import {IFlyoverConfigurations} from "../../src/interfaces/IFlyoverConfigurations.sol";
import {Flyover} from "../../src/libraries/Flyover.sol";
import {Quotes} from "../../src/libraries/Quotes.sol";
import {SignatureValidator} from "../../src/libraries/SignatureValidator.sol";
import {BridgeMock} from "../../src/test-contracts/BridgeMock.sol";
import {CollateralManagementMock} from "../../src/test-contracts/CollateralManagementMock.sol";
import {FlyoverConfigurationsMock} from "../pegin/FlyoverConfigurationsMock.sol";

/// @title PegOutEscrow request, cancel, and claimPegOut
contract PegOutEscrowTest is Test {
    /// @dev Mirrors impl-only {PegOutEscrow.EscrowPegOutChangePaid} for expectEmit.
    event EscrowPegOutChangePaid(
        bytes32 indexed requestHash,
        address indexed refundAddress,
        uint256 indexed change
    );

    uint256 internal constant FIXED_FEE = 0.001 ether;
    uint256 internal constant PERCENTAGE_FEE = 100; // 1%
    uint256 internal constant MIN_AMOUNT = 0.01 ether;
    uint256 internal constant MAX_AMOUNT = 50 ether;
    uint256 internal constant DUST = 0.001 ether;
    uint256 internal constant CLAIM_WINDOW = 1 hours;
    uint256 internal constant CLAIM_WINDOW_BLOCKS = 100;
    uint256 internal constant CALL_TIME = 2 hours;
    uint256 internal constant EXPIRE_TIME = 1 hours;
    uint256 internal constant EXPIRE_BLOCKS = 50;
    uint256 internal constant PENALTY_FEE = 0.01 ether;
    uint256 internal constant TIER_CONFIRMATIONS = 6;
    uint256 internal constant BASIS = 10_000;
    uint256 internal constant BTC_BLOCK_TIME = 3600;

    /// @dev msg.value that yields a serviceable principal near 1 ether under the seed config.
    uint256 internal constant DEFAULT_VALUE = 1.012 ether;

    /// @dev ERC-7201 PegOutEscrow storage root (matches PegOutEscrow._PEGOUT_ESCROW_STORAGE).
    bytes32 internal constant PEGOUT_ESCROW_STORAGE =
        0xb99c8d82bac3ff4ec6a3e7ff5aa17dda321aa2a152ae7dc22fe007bc5dcb3000;

    PegOutEscrow internal escrow;
    PegOutContract internal pegOut;
    FlyoverConfigurationsMock internal configurations;
    CollateralManagementMock internal collateral;
    PauseRegistry internal pauseRegistry;

    address internal owner;
    address internal user;
    address internal other;
    address internal lp;
    uint256 internal lpKey;
    address internal otherLp;
    uint256 internal otherLpKey;

    bytes internal constant DEST =
        hex"0014deadbeefdeadbeefdeadbeefdeadbeefdeadbeef";

    function setUp() public {
        owner = makeAddr("owner");
        user = makeAddr("user");
        other = makeAddr("other");
        (lp, lpKey) = makeAddrAndKey("lp");
        (otherLp, otherLpKey) = makeAddrAndKey("otherLp");
        vm.deal(user, 100 ether);
        vm.deal(other, 100 ether);
        vm.deal(lp, 100 ether);
        vm.deal(otherLp, 100 ether);

        PauseRegistry prImpl = new PauseRegistry();
        pauseRegistry = PauseRegistry(
            payable(
                address(
                    new ERC1967Proxy(
                        address(prImpl),
                        abi.encodeCall(prImpl.initialize, (0, owner))
                    )
                )
            )
        );

        configurations = new FlyoverConfigurationsMock();
        collateral = new CollateralManagementMock();

        BridgeMock bridge = new BridgeMock();
        PegOutContract pegOutImpl = new PegOutContract();
        pegOut = PegOutContract(
            payable(
                address(
                    new ERC1967Proxy(
                        address(pegOutImpl),
                        abi.encodeCall(
                            pegOutImpl.initialize,
                            (
                                owner,
                                payable(address(bridge)),
                                DUST,
                                address(collateral),
                                false,
                                BTC_BLOCK_TIME,
                                pauseRegistry
                            )
                        )
                    )
                )
            )
        );

        PegOutEscrow impl = new PegOutEscrow();
        escrow = PegOutEscrow(
            payable(
                address(
                    new ERC1967Proxy(
                        address(impl),
                        abi.encodeCall(
                            PegOutEscrow.initialize,
                            (
                                owner,
                                uint48(0),
                                pauseRegistry,
                                address(pegOut),
                                address(collateral),
                                address(configurations)
                            )
                        )
                    )
                )
            )
        );

        vm.prank(owner);
        pegOut.setPegOutEscrow(address(escrow));

        _seedPegOutConfig();
    }

    // -------------------------------------------------------------------------
    // requestPegOut
    // -------------------------------------------------------------------------

    function test_requestPegOut_happyPath_stateQuoteGettersAndEvent() public {
        (uint256 amount, uint256 callFee, uint256 change) = _expectedSplit(
            DEFAULT_VALUE
        );
        assertGt(amount, 0);
        assertEq(
            amount % Quotes.SAT_TO_WEI_CONVERSION,
            0,
            "amount sat-floored"
        );
        assertTrue(amount >= MIN_AMOUNT && amount <= MAX_AMOUNT);

        uint256 userBefore = user.balance;
        uint256 nonce = 1;
        bytes32 expectedHash = _expectedRequestHash(
            nonce,
            user,
            DEST,
            amount,
            callFee
        );

        vm.expectEmit(true, true, true, true, address(escrow));
        emit IPegOutEscrow.PegOutRequested(expectedHash, user, amount, DEST);

        vm.prank(user);
        bytes32 requestHash = escrow.requestPegOut{value: DEFAULT_VALUE}(
            DEST,
            user
        );

        assertEq(requestHash, expectedHash);
        assertEq(
            uint256(escrow.getPegOutState(requestHash)),
            uint256(IPegOutEscrow.EscrowedPegOutState.REQUESTED)
        );
        assertEq(escrow.totalRequests(), 1);
        assertEq(escrow.requestIdAt(1), requestHash);

        Quotes.PegOutQuote memory q = escrow.getPegOutQuote(requestHash);
        assertEq(q.value, amount);
        assertEq(q.callFee, callFee);
        assertEq(q.gasFee, 0);
        assertEq(q.depositConfirmations, 0);
        assertEq(q.penaltyFee, PENALTY_FEE);
        assertEq(q.rskRefundAddress, user);
        assertEq(q.lbcAddress, address(pegOut));
        assertEq(q.lpRskAddress, address(0));
        assertEq(q.nonce, int64(uint64(nonce)));
        assertEq(q.depositDateLimit, uint32(block.timestamp + CLAIM_WINDOW));
        assertEq(q.transferTime, uint32(CALL_TIME));
        assertEq(
            q.expireDate,
            uint32(block.timestamp + CLAIM_WINDOW + EXPIRE_TIME)
        );
        assertEq(
            q.expireBlock,
            uint32(block.number + CLAIM_WINDOW_BLOCKS + EXPIRE_BLOCKS)
        );
        assertEq(q.transferConfirmations, uint16(TIER_CONFIRMATIONS));
        assertEq(q.depositAddress, DEST);

        // Change below dust is folded into callFee (DEFAULT_VALUE residual is small).
        if (change == 0) {
            assertEq(user.balance, userBefore - DEFAULT_VALUE);
            assertEq(address(escrow).balance, amount + callFee);
        } else {
            assertEq(user.balance, userBefore - DEFAULT_VALUE + change);
            assertEq(address(escrow).balance, DEFAULT_VALUE - change);
        }
    }

    function test_requestPegOut_zeroRefundAddress_mapsToMsgSender() public {
        (uint256 amount, uint256 callFee, ) = _expectedSplit(DEFAULT_VALUE);
        bytes32 expectedHash = _expectedRequestHash(
            1,
            user,
            DEST,
            amount,
            callFee
        );

        vm.prank(user);
        bytes32 requestHash = escrow.requestPegOut{value: DEFAULT_VALUE}(
            DEST,
            address(0)
        );

        assertEq(requestHash, expectedHash);
        assertEq(escrow.getPegOutQuote(requestHash).rskRefundAddress, user);
    }

    function test_requestPegOut_emptyDestination_reverts() public {
        vm.prank(user);
        vm.expectRevert(IPegOutEscrow.InvalidDestination.selector);
        escrow.requestPegOut{value: DEFAULT_VALUE}("", user);
    }

    function test_requestPegOut_amountBelowMin_revertsNotServiceable() public {
        // Tiny payment → principal below MIN_AMOUNT after fee split.
        uint256 tiny = FIXED_FEE + 0.001 ether;
        (uint256 amount, , ) = _expectedSplit(tiny);
        assertLt(amount, MIN_AMOUNT);

        vm.prank(user);
        vm.expectRevert(
            abi.encodeWithSelector(
                IPegOutEscrow.NotServiceable.selector,
                amount,
                MIN_AMOUNT,
                MAX_AMOUNT
            )
        );
        escrow.requestPegOut{value: tiny}(DEST, user);
    }

    function test_requestPegOut_changeAtOrAboveDust_isRefunded() public {
        vm.prank(owner);
        pegOut.setDustThreshold(1 wei);

        // Pick a value whose residual after split is clearly >= 1 wei.
        uint256 value = 2 ether;
        (uint256 amount, uint256 callFee, uint256 change) = _expectedSplit(
            value
        );
        // With dust=1, residual above required is returned (not folded).
        assertGt(change, 0);

        uint256 userBefore = user.balance;
        bytes32 expectedHash = _expectedRequestHash(
            1,
            user,
            DEST,
            amount,
            callFee
        );

        vm.expectEmit(true, true, true, true, address(escrow));
        emit IPegOutEscrow.PegOutRequested(expectedHash, user, amount, DEST);
        vm.expectEmit(true, true, true, true, address(escrow));
        emit EscrowPegOutChangePaid(expectedHash, user, change);

        vm.prank(user);
        bytes32 requestHash = escrow.requestPegOut{value: value}(DEST, user);

        assertEq(user.balance, userBefore - value + change);
        assertEq(address(escrow).balance, amount + callFee);
        assertEq(escrow.getPegOutQuote(requestHash).callFee, callFee);
    }

    function test_requestPegOut_changeBelowDust_foldedIntoCallFee() public {
        vm.prank(owner);
        pegOut.setDustThreshold(type(uint256).max);

        uint256 value = 2 ether;
        (
            uint256 amount,
            uint256 baseCallFee,
            uint256 residual
        ) = _expectedSplitBeforeDust(value);
        assertGt(residual, 0);

        uint256 userBefore = user.balance;

        vm.prank(user);
        bytes32 requestHash = escrow.requestPegOut{value: value}(DEST, user);

        // No change refunded; residual absorbed into callFee.
        assertEq(user.balance, userBefore - value);
        assertEq(address(escrow).balance, value);

        Quotes.PegOutQuote memory q = escrow.getPegOutQuote(requestHash);
        assertEq(q.value, amount);
        assertEq(q.callFee, baseCallFee + residual);
    }

    // -------------------------------------------------------------------------
    // cancelPegOut
    // -------------------------------------------------------------------------

    function test_cancelPegOut_refundsAndTerminates() public {
        vm.prank(user);
        bytes32 requestHash = escrow.requestPegOut{value: DEFAULT_VALUE}(
            DEST,
            user
        );

        Quotes.PegOutQuote memory q = escrow.getPegOutQuote(requestHash);
        uint256 payout = q.value + q.callFee + q.gasFee;
        uint256 userBefore = user.balance;
        uint256 escrowBefore = address(escrow).balance;

        vm.expectEmit(true, false, false, true, address(escrow));
        emit IPegOutEscrow.PegOutCancelled(requestHash);

        vm.prank(user);
        escrow.cancelPegOut(requestHash);

        assertEq(
            uint256(escrow.getPegOutState(requestHash)),
            uint256(IPegOutEscrow.EscrowedPegOutState.CANCELLED)
        );
        assertEq(user.balance, userBefore + payout);
        assertEq(address(escrow).balance, escrowBefore - payout);

        // Quote storage is cleared; state is CANCELLED (not NONE), so getter still returns.
        Quotes.PegOutQuote memory cleared = escrow.getPegOutQuote(requestHash);
        assertEq(cleared.value, 0);
        assertEq(cleared.callFee, 0);
        assertEq(cleared.rskRefundAddress, address(0));
    }

    function test_cancelPegOut_wrongCaller_reverts() public {
        vm.prank(user);
        bytes32 requestHash = escrow.requestPegOut{value: DEFAULT_VALUE}(
            DEST,
            user
        );

        vm.prank(other);
        vm.expectRevert(
            abi.encodeWithSelector(Flyover.InvalidSender.selector, user, other)
        );
        escrow.cancelPegOut(requestHash);
    }

    function test_cancelPegOut_notRequested_reverts() public {
        bytes32 missing = keccak256("missing");
        vm.prank(user);
        vm.expectRevert(
            abi.encodeWithSelector(
                IPegOutEscrow.InvalidState.selector,
                missing,
                IPegOutEscrow.EscrowedPegOutState.REQUESTED,
                IPegOutEscrow.EscrowedPegOutState.NONE
            )
        );
        escrow.cancelPegOut(missing);
    }

    function test_cancelPegOut_twice_reverts() public {
        vm.prank(user);
        bytes32 requestHash = escrow.requestPegOut{value: DEFAULT_VALUE}(
            DEST,
            user
        );

        vm.prank(user);
        escrow.cancelPegOut(requestHash);

        vm.prank(user);
        vm.expectRevert(
            abi.encodeWithSelector(
                IPegOutEscrow.InvalidState.selector,
                requestHash,
                IPegOutEscrow.EscrowedPegOutState.REQUESTED,
                IPegOutEscrow.EscrowedPegOutState.CANCELLED
            )
        );
        escrow.cancelPegOut(requestHash);
    }

    // -------------------------------------------------------------------------
    // claimPegOut
    // -------------------------------------------------------------------------

    function test_claimPegOut_happyPath_lpAnchorFundsAndClaimed() public {
        bytes32 requestHash = _requestDefault();
        Quotes.PegOutQuote memory quote = escrow.getPegOutQuote(requestHash);
        uint256 payout = quote.value + quote.callFee + quote.gasFee;
        uint256 pegOutBefore = address(pegOut).balance;
        uint256 escrowBefore = address(escrow).balance;

        bytes memory signature = _signForLp(lpKey, quote, lp);
        uint256 claimTs = block.timestamp;

        vm.expectEmit(true, true, false, true, address(escrow));
        emit IPegOutEscrow.PegOutClaimed(lp, requestHash);
        // Claim timestamp is readable via PegOutDeposit (no public registry getter).
        vm.expectEmit(true, true, true, true, address(pegOut));
        emit IPegOut.PegOutDeposit(requestHash, lp, claimTs, payout);

        vm.prank(lp);
        escrow.claimPegOut(requestHash, signature);

        assertEq(
            uint256(escrow.getPegOutState(requestHash)),
            uint256(IPegOutEscrow.EscrowedPegOutState.CLAIMED)
        );
        assertEq(escrow.getPegOutQuote(requestHash).lpRskAddress, lp);
        assertEq(address(pegOut).balance, pegOutBefore + payout);
        assertEq(address(escrow).balance, escrowBefore - payout);
    }

    function test_claimPegOut_secondClaim_revertsInvalidState() public {
        bytes32 requestHash = _requestDefault();
        Quotes.PegOutQuote memory quote = escrow.getPegOutQuote(requestHash);
        bytes memory signature = _signForLp(lpKey, quote, lp);

        vm.prank(lp);
        escrow.claimPegOut(requestHash, signature);

        bytes memory otherSig = _signForLp(otherLpKey, quote, otherLp);
        vm.expectRevert(
            abi.encodeWithSelector(
                IPegOutEscrow.InvalidState.selector,
                requestHash,
                IPegOutEscrow.EscrowedPegOutState.REQUESTED,
                IPegOutEscrow.EscrowedPegOutState.CLAIMED
            )
        );
        vm.prank(otherLp);
        escrow.claimPegOut(requestHash, otherSig);
    }

    function test_claimPegOut_afterCancel_revertsInvalidState() public {
        bytes32 requestHash = _requestDefault();
        Quotes.PegOutQuote memory quote = escrow.getPegOutQuote(requestHash);
        bytes memory signature = _signForLp(lpKey, quote, lp);

        vm.prank(user);
        escrow.cancelPegOut(requestHash);

        vm.expectRevert(
            abi.encodeWithSelector(
                IPegOutEscrow.InvalidState.selector,
                requestHash,
                IPegOutEscrow.EscrowedPegOutState.REQUESTED,
                IPegOutEscrow.EscrowedPegOutState.CANCELLED
            )
        );
        vm.prank(lp);
        escrow.claimPegOut(requestHash, signature);
    }

    function test_claimPegOut_afterRefund_revertsInvalidState() public {
        bytes32 requestHash = _requestDefault();
        Quotes.PegOutQuote memory quote = escrow.getPegOutQuote(requestHash);
        bytes memory signature = _signForLp(lpKey, quote, lp);

        _forceEscrowState(
            requestHash,
            IPegOutEscrow.EscrowedPegOutState.REFUNDED
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                IPegOutEscrow.InvalidState.selector,
                requestHash,
                IPegOutEscrow.EscrowedPegOutState.REQUESTED,
                IPegOutEscrow.EscrowedPegOutState.REFUNDED
            )
        );
        vm.prank(lp);
        escrow.claimPegOut(requestHash, signature);
    }

    function test_claimPegOut_notRegistered_reverts() public {
        bytes32 requestHash = _requestDefault();
        Quotes.PegOutQuote memory quote = escrow.getPegOutQuote(requestHash);
        bytes memory signature = _signForLp(lpKey, quote, lp);

        vm.mockCall(
            address(collateral),
            abi.encodeCall(
                ICollateralManagement.isRegistered,
                (Flyover.ProviderType.PegOut, lp)
            ),
            abi.encode(false)
        );

        vm.expectRevert(
            abi.encodeWithSelector(Flyover.ProviderNotRegistered.selector, lp)
        );
        vm.prank(lp);
        escrow.claimPegOut(requestHash, signature);
    }

    function test_claimPegOut_underCollateralized_reverts() public {
        bytes32 requestHash = _requestDefault();
        Quotes.PegOutQuote memory quote = escrow.getPegOutQuote(requestHash);
        bytes memory signature = _signForLp(lpKey, quote, lp);

        uint256 lowCollateral = 0.1 ether;
        vm.mockCall(
            address(collateral),
            abi.encodeCall(
                ICollateralManagement.isCollateralSufficient,
                (Flyover.ProviderType.PegOut, lp)
            ),
            abi.encode(false)
        );
        vm.mockCall(
            address(collateral),
            abi.encodeCall(ICollateralManagement.getPegOutCollateral, (lp)),
            abi.encode(lowCollateral)
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                IPegOut.InsufficientCollateral.selector,
                lowCollateral
            )
        );
        vm.prank(lp);
        escrow.claimPegOut(requestHash, signature);
    }

    function test_claimPegOut_badSignature_reverts() public {
        bytes32 requestHash = _requestDefault();
        Quotes.PegOutQuote memory quote = escrow.getPegOutQuote(requestHash);
        bytes memory badSignature = _signForLp(otherLpKey, quote, lp);

        quote.lpRskAddress = lp;
        bytes32 eip712Hash = pegOut.hashPegOutQuoteEIP712(quote);

        vm.expectRevert(
            abi.encodeWithSelector(
                SignatureValidator.IncorrectSignature.selector,
                lp,
                eip712Hash,
                badSignature
            )
        );
        vm.prank(lp);
        escrow.claimPegOut(requestHash, badSignature);
    }

    // -------------------------------------------------------------------------
    // deadline refunds (acceptance)
    // -------------------------------------------------------------------------

    function test_refundOnNoClaim_beforeDeadline_reverts() public {
        bytes32 requestHash = _requestDefault();
        uint256 depositDateLimit = escrow
            .getPegOutQuote(requestHash)
            .depositDateLimit;

        vm.expectRevert(
            abi.encodeWithSelector(
                IPegOutEscrow.ClaimWindowOpen.selector,
                depositDateLimit
            )
        );
        vm.prank(other);
        escrow.refundOnNoClaim(requestHash);
    }

    function test_refundUserPegOut_beforeExpire_reverts() public {
        bytes32 requestHash = _claimDefault();

        vm.expectRevert(
            abi.encodeWithSelector(
                IPegOut.QuoteNotExpired.selector,
                requestHash
            )
        );
        vm.prank(other);
        pegOut.refundUserPegOut(requestHash);
    }

    function test_refundOnNoClaim_afterDeadline_anyoneRefundsAndAttemptsGlobalSlash()
        public
    {
        bytes32 requestHash = _requestDefault();
        Quotes.PegOutQuote memory q = escrow.getPegOutQuote(requestHash);
        uint256 payout = q.value + q.callFee + q.gasFee;
        uint256 userBefore = user.balance;

        vm.warp(uint256(q.depositDateLimit) + 1);

        vm.expectEmit(true, true, false, true, address(escrow));
        emit IPegOutEscrow.PegOutRefundedOnNoClaim(requestHash, user, payout);
        vm.expectEmit(true, false, false, true, address(escrow));
        emit IPegOutEscrow.GlobalSlashSkipped(requestHash);

        vm.prank(other);
        escrow.refundOnNoClaim(requestHash);

        assertEq(
            uint256(escrow.getPegOutState(requestHash)),
            uint256(IPegOutEscrow.EscrowedPegOutState.REFUNDED)
        );
        assertEq(user.balance, userBefore + payout);
    }

    function test_cancelPegOut_doesNotCallGlobalSlash() public {
        collateral.setGlobalSlashReverts(false);

        bytes32 requestHash = _requestDefault();
        vm.prank(user);
        escrow.cancelPegOut(requestHash);

        assertEq(collateral.globalSlashCalls(), 0);
        assertEq(
            uint256(escrow.getPegOutState(requestHash)),
            uint256(IPegOutEscrow.EscrowedPegOutState.CANCELLED)
        );
    }

    function test_refundUserPegOut_afterExpire_anyoneRefundsIndividualSlashAndLateReverts()
        public
    {
        bytes32 requestHash = _claimDefault();
        Quotes.PegOutQuote memory q = escrow.getPegOutQuote(requestHash);
        uint256 payout = q.value + q.callFee + q.gasFee;
        uint256 userBefore = user.balance;

        _warpPastFulfillment(q);

        vm.expectEmit(true, true, false, true, address(pegOut));
        emit IPegOut.PegOutUserRefunded(requestHash, user, payout);
        vm.expectEmit(true, true, true, true, address(collateral));
        emit ICollateralManagement.Penalized(
            address(0),
            address(0),
            bytes32(0),
            Flyover.ProviderType.PegOut,
            0,
            0
        );

        vm.prank(other);
        pegOut.refundUserPegOut(requestHash);

        assertEq(user.balance, userBefore + payout);
        assertTrue(pegOut.isQuoteCompleted(requestHash));
        assertEq(
            uint256(escrow.getPegOutState(requestHash)),
            uint256(IPegOutEscrow.EscrowedPegOutState.REFUNDED)
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                IPegOut.QuoteAlreadyCompleted.selector,
                requestHash
            )
        );
        vm.prank(other);
        pegOut.refundUserPegOut(requestHash);
    }

    // -------------------------------------------------------------------------
    // helpers
    // -------------------------------------------------------------------------

    function _requestDefault() internal returns (bytes32 requestHash) {
        vm.prank(user);
        requestHash = escrow.requestPegOut{value: DEFAULT_VALUE}(DEST, user);
    }

    function _claimDefault() internal returns (bytes32 requestHash) {
        requestHash = _requestDefault();
        Quotes.PegOutQuote memory quote = escrow.getPegOutQuote(requestHash);
        bytes memory signature = _signForLp(lpKey, quote, lp);
        vm.prank(lp);
        escrow.claimPegOut(requestHash, signature);
    }

    function _warpPastFulfillment(Quotes.PegOutQuote memory q) internal {
        vm.warp(uint256(q.expireDate) + 1);
        vm.roll(uint256(q.expireBlock) + 1);
    }

    function _signForLp(
        uint256 privateKey,
        Quotes.PegOutQuote memory quote,
        address lpAddress
    ) internal view returns (bytes memory) {
        quote.lpRskAddress = lpAddress;
        bytes32 eip712Hash = pegOut.hashPegOutQuoteEIP712(quote);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, eip712Hash);
        return abi.encodePacked(r, s, v);
    }

    /// @dev `state` mapping is at struct offset 4 under the ERC-7201 root.
    function _forceEscrowState(
        bytes32 requestHash,
        IPegOutEscrow.EscrowedPegOutState newState
    ) internal {
        bytes32 mappingSlot = bytes32(uint256(PEGOUT_ESCROW_STORAGE) + 4);
        bytes32 loc = keccak256(abi.encode(requestHash, mappingSlot));
        vm.store(address(escrow), loc, bytes32(uint256(uint8(newState))));
    }

    function _seedPegOutConfig() internal {
        IFlyoverConfigurations.ConfirmationTier[]
            memory tiers = new IFlyoverConfigurations.ConfirmationTier[](1);
        tiers[0] = IFlyoverConfigurations.ConfirmationTier({
            maxAmount: type(uint256).max,
            confirmations: TIER_CONFIRMATIONS
        });

        configurations.setPegOutConfiguration(
            IFlyoverConfigurations.PegOutConfiguration({
                fixedFee: FIXED_FEE,
                percentageFee: PERCENTAGE_FEE,
                minAmount: MIN_AMOUNT,
                maxAmount: MAX_AMOUNT,
                confirmationTiers: tiers,
                penaltyFee: PENALTY_FEE,
                claimWindow: CLAIM_WINDOW,
                claimWindowBlocks: CLAIM_WINDOW_BLOCKS,
                callTime: CALL_TIME,
                expireTime: EXPIRE_TIME,
                expireBlocks: EXPIRE_BLOCKS,
                maxMinerFee: 0.001 ether
            })
        );
    }

    function _expectedSplitBeforeDust(
        uint256 value
    )
        internal
        view
        returns (uint256 amount, uint256 callFee, uint256 residual)
    {
        amount = ((value - FIXED_FEE) * BASIS) / (BASIS + PERCENTAGE_FEE);
        amount -= amount % Quotes.SAT_TO_WEI_CONVERSION;
        callFee = configurations.calculatePegOutFee(amount);
        residual = value - (amount + callFee);
    }

    function _expectedSplit(
        uint256 value
    ) internal view returns (uint256 amount, uint256 callFee, uint256 change) {
        uint256 residual;
        (amount, callFee, residual) = _expectedSplitBeforeDust(value);
        uint256 dust = pegOut.dustThreshold();
        if (dust > residual) {
            callFee += residual;
            change = 0;
        } else {
            change = residual;
        }
    }

    function _expectedRequestHash(
        uint256 nonce,
        address refundTo,
        bytes memory destination,
        uint256 amount,
        uint256 callFee
    ) internal view returns (bytes32) {
        return
            keccak256(
                abi.encode(
                    block.chainid,
                    address(escrow),
                    nonce,
                    user,
                    refundTo,
                    keccak256(destination),
                    amount,
                    callFee,
                    block.timestamp
                )
            );
    }
}
