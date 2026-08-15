// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {PegOutEscrow} from "../../src/PegOutEscrow.sol";
import {PegOutContract} from "../../src/PegOutContract.sol";
import {CollateralManagementContract} from "../../src/CollateralManagement.sol";
import {FlyoverDiscovery} from "../../src/FlyoverDiscovery.sol";
import {PauseRegistry} from "../../src/PauseRegistry.sol";
import {ICollateralManagement} from "../../src/interfaces/ICollateralManagement.sol";
import {IPegOut} from "../../src/interfaces/IPegOut.sol";
import {IPegOutEscrow} from "../../src/interfaces/IPegOutEscrow.sol";
import {IFlyoverConfigurations} from "../../src/interfaces/IFlyoverConfigurations.sol";
import {IPauseRegistry} from "../../src/interfaces/IPauseRegistry.sol";
import {Flyover} from "../../src/libraries/Flyover.sol";
import {Quotes} from "../../src/libraries/Quotes.sol";
import {SignatureValidator} from "../../src/libraries/SignatureValidator.sol";
import {BridgeMock} from "../../src/test-contracts/BridgeMock.sol";
import {CollateralManagementMock} from "../../src/test-contracts/CollateralManagementMock.sol";
import {FlyoverConfigurationsMock} from "../pegin/FlyoverConfigurationsMock.sol";

/// @title PegOutEscrow S11.1 state machine + claim gates
/// @dev Test names map to S11.1 transition / race / B-scenario ids where applicable.
/// TODO: rename tests that embed user-story ids (e.g. S13.1) once those ids are no longer needed for review.
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
    BridgeMock internal bridge;

    address internal owner;
    address internal user;
    address internal other;
    address internal lp;
    uint256 internal lpKey;
    address internal otherLp;
    uint256 internal otherLpKey;

    bytes32 internal constant BLOCK_HEADER_HASH = bytes32(uint256(1));
    uint256 internal constant PARTIAL_MERKLE_TREE = 0;
    bytes32[] internal merkleHashes;

    /// @dev Seed config maxMinerFee (snapshotted per request).
    uint256 internal constant MAX_MINER_FEE = 0.001 ether;

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

        merkleHashes = new bytes32[](1);
        merkleHashes[0] = bytes32(uint256(1));

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

        bridge = new BridgeMock();
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
    // T0 — requestPegOut
    // -------------------------------------------------------------------------

    function test_T0_Request_NoneToRequested() public {
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
        assertEq(escrow.getMaxMinerFee(requestHash), MAX_MINER_FEE);
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

    function test_B7_Unserviceable_EmptyDestination_StaysNone() public {
        vm.prank(user);
        vm.expectRevert(IPegOutEscrow.InvalidDestination.selector);
        escrow.requestPegOut{value: DEFAULT_VALUE}("", user);
    }

    function test_B7_Unserviceable_AmountBelowMin_StaysNone() public {
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
    // T1 / B6 — cancelPegOut
    // -------------------------------------------------------------------------

    function test_T1_Cancel_RequestedToCancelled() public {
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

    function test_Forbidden_CancelTwice_Reverts() public {
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
    // T2 — claimPegOut
    // -------------------------------------------------------------------------

    function test_T2_Claim_RequestedToClaimed() public {
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

    /// @notice Claim-fed quote mirrored into PegOutContract passes today's validatePegout.
    /// TODO: rename off the S13.1 story id once review no longer needs the ticket tag.
    function test_S13_1_ClaimFedRecord_PassesValidatePegout() public {
        bytes memory dest = _btcAddressP2pkh();
        vm.prank(user);
        bytes32 requestHash = escrow.requestPegOut{value: DEFAULT_VALUE}(
            dest,
            user
        );

        Quotes.PegOutQuote memory quote = escrow.getPegOutQuote(requestHash);
        bytes memory signature = _signForLp(lpKey, quote, lp);
        vm.prank(lp);
        escrow.claimPegOut(requestHash, signature);

        quote = escrow.getPegOutQuote(requestHash);
        bytes memory btcTx = _generateBtcTx(quote, requestHash);

        vm.prank(lp);
        Quotes.PegOutQuote memory returned = pegOut.validatePegout(
            requestHash,
            btcTx
        );

        assertEq(returned.lpRskAddress, lp);
        assertEq(returned.value, quote.value);
        assertEq(returned.callFee, quote.callFee);
        assertEq(
            keccak256(returned.depositAddress),
            keccak256(quote.depositAddress)
        );
    }

    function test_R4_B1_SecondClaim_RevertsInvalidState() public {
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

    function test_R1_CancelVsClaim_CancelFirst_ClaimReverts() public {
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

    function test_Forbidden_ClaimAfterRefunded_Reverts() public {
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
    // T3 / T5 / R2 — deadline refunds
    // -------------------------------------------------------------------------

    function test_R2_RefundOnNoClaimWhileWindowOpen_Reverts() public {
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

    function test_T3_B2_RefundOnNoClaim_RequestedToRefunded() public {
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

    function test_B6_Cancel_DoesNotCallGlobalSlash() public {
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

    function test_T5_B3_RefundUser_ClaimedToRefunded() public {
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
    // S11.1 gaps — races, T4, forbidden CLAIMED exits, fee snapshot, B8
    // -------------------------------------------------------------------------

    function test_R1_CancelVsClaim_ClaimFirst_CancelReverts() public {
        bytes32 requestHash = _claimDefault();

        vm.expectRevert(
            abi.encodeWithSelector(
                IPegOutEscrow.InvalidState.selector,
                requestHash,
                IPegOutEscrow.EscrowedPegOutState.REQUESTED,
                IPegOutEscrow.EscrowedPegOutState.CLAIMED
            )
        );
        vm.prank(user);
        escrow.cancelPegOut(requestHash);
    }

    function test_R2_ClaimAtExactDepositDateLimit_Succeeds() public {
        bytes32 requestHash = _requestDefault();
        Quotes.PegOutQuote memory quote = escrow.getPegOutQuote(requestHash);
        bytes memory signature = _signForLp(lpKey, quote, lp);

        vm.warp(uint256(quote.depositDateLimit));

        vm.prank(lp);
        escrow.claimPegOut(requestHash, signature);

        assertEq(
            uint256(escrow.getPegOutState(requestHash)),
            uint256(IPegOutEscrow.EscrowedPegOutState.CLAIMED)
        );
    }

    function test_R2_RefundOnNoClaimAtExactLimit_RevertsClaimWindowOpen()
        public
    {
        bytes32 requestHash = _requestDefault();
        uint256 depositDateLimit = escrow
            .getPegOutQuote(requestHash)
            .depositDateLimit;

        vm.warp(depositDateLimit);

        vm.expectRevert(
            abi.encodeWithSelector(
                IPegOutEscrow.ClaimWindowOpen.selector,
                depositDateLimit
            )
        );
        vm.prank(other);
        escrow.refundOnNoClaim(requestHash);
    }

    function test_R2_ClaimAfterDeadline_RevertsClaimWindowClosed() public {
        bytes32 requestHash = _requestDefault();
        Quotes.PegOutQuote memory quote = escrow.getPegOutQuote(requestHash);
        bytes memory signature = _signForLp(lpKey, quote, lp);

        vm.warp(uint256(quote.depositDateLimit) + 1);

        vm.expectRevert(
            abi.encodeWithSelector(
                IPegOutEscrow.ClaimWindowClosed.selector,
                quote.depositDateLimit
            )
        );
        vm.prank(lp);
        escrow.claimPegOut(requestHash, signature);
    }

    /// @dev T4 product path (refundPegOut → onSettlement(FULFILLED)) is an S13 gap;
    /// this asserts the escrow transition via the PegOut-only notify surface.
    function test_T4_OnSettlement_ClaimedToFulfilled() public {
        bytes32 requestHash = _claimDefault();

        vm.prank(address(pegOut));
        escrow.onSettlement(
            requestHash,
            IPegOutEscrow.EscrowedPegOutState.FULFILLED
        );

        assertEq(
            uint256(escrow.getPegOutState(requestHash)),
            uint256(IPegOutEscrow.EscrowedPegOutState.FULFILLED)
        );
        Quotes.PegOutQuote memory cleared = escrow.getPegOutQuote(requestHash);
        assertEq(cleared.value, 0);
        assertEq(cleared.lpRskAddress, address(0));
    }

    function test_Forbidden_CancelFromClaimed_Reverts() public {
        bytes32 requestHash = _claimDefault();

        vm.expectRevert(
            abi.encodeWithSelector(
                IPegOutEscrow.InvalidState.selector,
                requestHash,
                IPegOutEscrow.EscrowedPegOutState.REQUESTED,
                IPegOutEscrow.EscrowedPegOutState.CLAIMED
            )
        );
        vm.prank(user);
        escrow.cancelPegOut(requestHash);
    }

    function test_Forbidden_RefundOnNoClaimFromClaimed_Reverts() public {
        bytes32 requestHash = _claimDefault();
        Quotes.PegOutQuote memory q = escrow.getPegOutQuote(requestHash);
        vm.warp(uint256(q.depositDateLimit) + 1);

        vm.expectRevert(
            abi.encodeWithSelector(
                IPegOutEscrow.InvalidState.selector,
                requestHash,
                IPegOutEscrow.EscrowedPegOutState.REQUESTED,
                IPegOutEscrow.EscrowedPegOutState.CLAIMED
            )
        );
        vm.prank(other);
        escrow.refundOnNoClaim(requestHash);
    }

    function test_Forbidden_OnSettlement_NotClaimed_Reverts() public {
        bytes32 requestHash = _requestDefault();

        vm.expectRevert(
            abi.encodeWithSelector(
                IPegOutEscrow.InvalidState.selector,
                requestHash,
                IPegOutEscrow.EscrowedPegOutState.CLAIMED,
                IPegOutEscrow.EscrowedPegOutState.REQUESTED
            )
        );
        vm.prank(address(pegOut));
        escrow.onSettlement(
            requestHash,
            IPegOutEscrow.EscrowedPegOutState.FULFILLED
        );
    }

    /// @dev R3 / B5 — late but valid fulfillment stays FULFILLED (not REFUNDED).
    function test_R3_B5_LateProof_FulfilledViaOnSettlement() public {
        bytes32 requestHash = _claimDefault();
        Quotes.PegOutQuote memory q = escrow.getPegOutQuote(requestHash);
        // Past call window but before user-refund expiry is the late-delivery window;
        // escrow notify does not re-check time — settlement race is owned by PegOut.
        vm.warp(uint256(q.depositDateLimit) + uint256(q.transferTime) + 1);

        vm.prank(address(pegOut));
        escrow.onSettlement(
            requestHash,
            IPegOutEscrow.EscrowedPegOutState.FULFILLED
        );

        assertEq(
            uint256(escrow.getPegOutState(requestHash)),
            uint256(IPegOutEscrow.EscrowedPegOutState.FULFILLED)
        );
    }

    function test_R3_UserRefundWins_ThenOnSettlementReverts() public {
        bytes32 requestHash = _claimDefault();
        Quotes.PegOutQuote memory q = escrow.getPegOutQuote(requestHash);
        _warpPastFulfillment(q);

        vm.prank(other);
        pegOut.refundUserPegOut(requestHash);

        assertEq(
            uint256(escrow.getPegOutState(requestHash)),
            uint256(IPegOutEscrow.EscrowedPegOutState.REFUNDED)
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                IPegOutEscrow.InvalidState.selector,
                requestHash,
                IPegOutEscrow.EscrowedPegOutState.CLAIMED,
                IPegOutEscrow.EscrowedPegOutState.REFUNDED
            )
        );
        vm.prank(address(pegOut));
        escrow.onSettlement(
            requestHash,
            IPegOutEscrow.EscrowedPegOutState.FULFILLED
        );
    }

    function test_FeeSnapshot_ConfigChangeMidFlight_UnchangedEconomics()
        public
    {
        bytes32 requestHash = _requestDefault();
        Quotes.PegOutQuote memory before = escrow.getPegOutQuote(requestHash);
        uint256 snapshottedMaxMinerFee = escrow.getMaxMinerFee(requestHash);
        assertEq(snapshottedMaxMinerFee, MAX_MINER_FEE);

        IFlyoverConfigurations.ConfirmationTier[]
            memory tiers = new IFlyoverConfigurations.ConfirmationTier[](1);
        tiers[0] = IFlyoverConfigurations.ConfirmationTier({
            maxAmount: type(uint256).max,
            confirmations: TIER_CONFIRMATIONS
        });
        configurations.setPegOutConfiguration(
            IFlyoverConfigurations.PegOutConfiguration({
                fixedFee: FIXED_FEE * 5,
                percentageFee: PERCENTAGE_FEE * 2,
                minAmount: MIN_AMOUNT,
                maxAmount: MAX_AMOUNT,
                confirmationTiers: tiers,
                penaltyFee: PENALTY_FEE * 3,
                claimWindow: CLAIM_WINDOW / 2,
                claimWindowBlocks: CLAIM_WINDOW_BLOCKS,
                callTime: CALL_TIME,
                expireTime: EXPIRE_TIME,
                expireBlocks: EXPIRE_BLOCKS,
                maxMinerFee: 0.05 ether
            })
        );

        Quotes.PegOutQuote memory afterCfg = escrow.getPegOutQuote(requestHash);
        assertEq(afterCfg.callFee, before.callFee);
        assertEq(afterCfg.penaltyFee, before.penaltyFee);
        assertEq(afterCfg.value, before.value);
        assertEq(afterCfg.depositDateLimit, before.depositDateLimit);
        assertEq(afterCfg.expireDate, before.expireDate);
        assertEq(escrow.getMaxMinerFee(requestHash), snapshottedMaxMinerFee);
        assertEq(
            configurations.getPegOutConfiguration().maxMinerFee,
            0.05 ether
        );

        bytes memory signature = _signForLp(lpKey, afterCfg, lp);
        vm.prank(lp);
        escrow.claimPegOut(requestHash, signature);

        assertEq(escrow.getPegOutQuote(requestHash).callFee, before.callFee);
        assertEq(
            escrow.getPegOutQuote(requestHash).penaltyFee,
            before.penaltyFee
        );
        assertEq(escrow.getMaxMinerFee(requestHash), snapshottedMaxMinerFee);
        assertEq(
            uint256(escrow.getPegOutState(requestHash)),
            uint256(IPegOutEscrow.EscrowedPegOutState.CLAIMED)
        );
    }

    /// @dev B8: delivery at the floor settles with no RBTC top-up.
    function test_B8_AtFloor_NoTopUp() public {
        (
            bytes32 requestHash,
            Quotes.PegOutQuote memory quote,
            uint256 floor
        ) = _claimWithP2pkhDest();
        uint256 escrowed = quote.value + quote.callFee + quote.gasFee;

        bytes memory btcTx = _generateBtcTxWithAmount(
            quote,
            requestHash,
            floor
        );
        _setupBridgeConfirmations(quote);

        uint256 userBefore = user.balance;
        uint256 lpBefore = lp.balance;

        vm.prank(lp);
        pegOut.refundPegOut(
            requestHash,
            btcTx,
            BLOCK_HEADER_HASH,
            PARTIAL_MERKLE_TREE,
            merkleHashes
        );

        assertEq(user.balance, userBefore, "no top-up at floor");
        assertEq(lp.balance, lpBefore + escrowed);
        assertTrue(pegOut.isQuoteCompleted(requestHash));
        assertEq(
            uint256(escrow.getPegOutState(requestHash)),
            uint256(IPegOutEscrow.EscrowedPegOutState.FULFILLED)
        );
    }

    /// @dev B8: delivery above the floor settles with no RBTC top-up.
    function test_B8_AboveFloor_NoTopUp() public {
        (
            bytes32 requestHash,
            Quotes.PegOutQuote memory quote,
            uint256 floor
        ) = _claimWithP2pkhDest();
        uint256 escrowed = quote.value + quote.callFee + quote.gasFee;
        uint256 paid = floor + Quotes.SAT_TO_WEI_CONVERSION;

        bytes memory btcTx = _generateBtcTxWithAmount(quote, requestHash, paid);
        _setupBridgeConfirmations(quote);

        uint256 userBefore = user.balance;
        uint256 lpBefore = lp.balance;

        vm.prank(lp);
        pegOut.refundPegOut(
            requestHash,
            btcTx,
            BLOCK_HEADER_HASH,
            PARTIAL_MERKLE_TREE,
            merkleHashes
        );

        assertEq(user.balance, userBefore, "no top-up above floor");
        assertEq(lp.balance, lpBefore + escrowed);
        assertTrue(pegOut.isQuoteCompleted(requestHash));
    }

    /// @dev B8: under-floor delivery tops up user and debits LP by the same shortfall.
    function test_B8_UnderFloor_TopUpAndDebitLp() public {
        (
            bytes32 requestHash,
            Quotes.PegOutQuote memory quote,
            uint256 floor
        ) = _claimWithP2pkhDest();
        uint256 escrowed = quote.value + quote.callFee + quote.gasFee;
        uint256 paid = floor - Quotes.SAT_TO_WEI_CONVERSION;
        uint256 topUp = floor - paid;

        bytes memory btcTx = _generateBtcTxWithAmount(quote, requestHash, paid);
        _setupBridgeConfirmations(quote);

        uint256 userBefore = user.balance;
        uint256 lpBefore = lp.balance;
        uint256 pegOutBefore = address(pegOut).balance;

        vm.prank(lp);
        pegOut.refundPegOut(
            requestHash,
            btcTx,
            BLOCK_HEADER_HASH,
            PARTIAL_MERKLE_TREE,
            merkleHashes
        );

        assertEq(user.balance, userBefore + topUp);
        assertEq(lp.balance, lpBefore + escrowed - topUp);
        assertEq(user.balance - userBefore + lp.balance - lpBefore, escrowed);
        assertEq(address(pegOut).balance, pegOutBefore - escrowed);
        assertTrue(pegOut.isQuoteCompleted(requestHash));
        assertEq(
            uint256(escrow.getPegOutState(requestHash)),
            uint256(IPegOutEscrow.EscrowedPegOutState.FULFILLED)
        );
    }

    /// @dev B8: live maxMinerFee change after request does not move this peg-out's floor.
    function test_B8_ConfigChangeAfterRequest_FloorUnchanged() public {
        bytes memory dest = _btcAddressP2pkh();
        vm.prank(user);
        bytes32 requestHash = escrow.requestPegOut{value: DEFAULT_VALUE}(
            dest,
            user
        );
        Quotes.PegOutQuote memory quote = escrow.getPegOutQuote(requestHash);
        uint256 snapshotted = escrow.getMaxMinerFee(requestHash);
        uint256 floorBefore = _floor(quote, snapshotted);

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
                maxMinerFee: MAX_MINER_FEE * 20
            })
        );

        assertEq(escrow.getMaxMinerFee(requestHash), snapshotted);
        assertEq(
            _floor(quote, escrow.getMaxMinerFee(requestHash)),
            floorBefore
        );

        bytes memory signature = _signForLp(lpKey, quote, lp);
        vm.prank(lp);
        escrow.claimPegOut(requestHash, signature);
        quote = escrow.getPegOutQuote(requestHash);

        // Pay just under the snapshotted floor (would be above a higher live-config floor).
        uint256 paid = floorBefore - Quotes.SAT_TO_WEI_CONVERSION;
        bytes memory btcTx = _generateBtcTxWithAmount(quote, requestHash, paid);
        _setupBridgeConfirmations(quote);

        uint256 topUp = floorBefore - paid;
        uint256 userBefore = user.balance;
        uint256 lpBefore = lp.balance;
        uint256 escrowed = quote.value + quote.callFee + quote.gasFee;

        vm.prank(lp);
        pegOut.refundPegOut(
            requestHash,
            btcTx,
            BLOCK_HEADER_HASH,
            PARTIAL_MERKLE_TREE,
            merkleHashes
        );

        assertEq(user.balance, userBefore + topUp);
        assertEq(lp.balance, lpBefore + escrowed - topUp);
    }

    // -------------------------------------------------------------------------
    // helpers
    // -------------------------------------------------------------------------

    string constant HELPER_SCRIPT_GENERATE_BTC_TX =
        "script/helpers/generate-btc-tx.ts";
    string constant HELPER_SCRIPT_GET_BTC_ADDRESS_BYTES =
        "script/helpers/get-btc-address-bytes.ts";

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

    function _claimWithP2pkhDest()
        internal
        returns (
            bytes32 requestHash,
            Quotes.PegOutQuote memory quote,
            uint256 floor
        )
    {
        bytes memory dest = _btcAddressP2pkh();
        vm.prank(user);
        requestHash = escrow.requestPegOut{value: DEFAULT_VALUE}(dest, user);
        quote = escrow.getPegOutQuote(requestHash);
        bytes memory signature = _signForLp(lpKey, quote, lp);
        vm.prank(lp);
        escrow.claimPegOut(requestHash, signature);
        quote = escrow.getPegOutQuote(requestHash);
        floor = _floor(quote, escrow.getMaxMinerFee(requestHash));
    }

    function _floor(
        Quotes.PegOutQuote memory quote,
        uint256 maxMinerFee
    ) internal pure returns (uint256 floorAmount) {
        uint256 deductions = quote.callFee + maxMinerFee;
        floorAmount = quote.value > deductions ? quote.value - deductions : 0;
        if (
            floorAmount > Quotes.SAT_TO_WEI_CONVERSION &&
            (floorAmount % Quotes.SAT_TO_WEI_CONVERSION) != 0
        ) {
            floorAmount -= floorAmount % Quotes.SAT_TO_WEI_CONVERSION;
        }
    }

    function _setupBridgeConfirmations(
        Quotes.PegOutQuote memory quote
    ) internal {
        bytes memory header = new bytes(80);
        uint32 ts = uint32(block.timestamp + 100);
        header[68] = bytes1(uint8(ts));
        header[69] = bytes1(uint8(ts >> 8));
        header[70] = bytes1(uint8(ts >> 16));
        header[71] = bytes1(uint8(ts >> 24));
        bridge.setHeaderByHash(BLOCK_HEADER_HASH, header);
        bridge.setConfirmations(int256(uint256(quote.transferConfirmations)));
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

    /// @dev P2PKH address bytes matching generate-btc-tx.ts / LpRefund helpers.
    function _btcAddressP2pkh() internal returns (bytes memory) {
        string[] memory inputs = new string[](4);
        inputs[0] = "npx";
        inputs[1] = "ts-node";
        inputs[2] = HELPER_SCRIPT_GET_BTC_ADDRESS_BYTES;
        inputs[3] = "p2pkh";
        return vm.ffi(inputs);
    }

    function _generateBtcTx(
        Quotes.PegOutQuote memory quote,
        bytes32 quoteHash
    ) internal returns (bytes memory) {
        return _generateBtcTxWithAmount(quote, quoteHash, quote.value);
    }

    function _generateBtcTxWithAmount(
        Quotes.PegOutQuote memory quote,
        bytes32 quoteHash,
        uint256 amountWei
    ) internal returns (bytes memory) {
        string[] memory inputs = new string[](7);
        inputs[0] = "npx";
        inputs[1] = "ts-node";
        inputs[2] = HELPER_SCRIPT_GENERATE_BTC_TX;
        inputs[3] = vm.toString(quoteHash);
        inputs[4] = vm.toString(quote.depositAddress);
        inputs[5] = vm.toString(amountWei);
        inputs[6] = "p2pkh";
        return vm.ffi(inputs);
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
                maxMinerFee: MAX_MINER_FEE
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

/// @title CLAIMED timeout individual slash against live CollateralManagement
/// @dev Complements {PegOutEscrowTest} mock-CM state machine coverage.
contract PegOutEscrowIndividualSlashTest is Test {
    uint256 internal constant FIXED_FEE = 0.001 ether;
    uint256 internal constant PERCENTAGE_FEE = 100;
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
    uint256 internal constant BTC_BLOCK_TIME = 3600;
    uint256 internal constant MAX_MINER_FEE = 0.001 ether;
    uint256 internal constant DEFAULT_VALUE = 1.012 ether;
    uint256 internal constant MIN_COLLATERAL = 0.6 ether;
    uint256 internal constant REWARD_PERCENTAGE = 1000;
    uint256 internal constant RESIGN_DELAY_BLOCKS = 500;
    uint48 internal constant ADMIN_DELAY = 30;

    PegOutEscrow internal escrow;
    PegOutContract internal pegOut;
    CollateralManagementContract internal collateral;
    FlyoverDiscovery internal discovery;
    FlyoverConfigurationsMock internal configurations;
    PauseRegistry internal pauseRegistry;
    BridgeMock internal bridge;

    address internal owner;
    address internal user;
    address internal other;
    address internal lp;
    uint256 internal lpKey;
    address internal otherLp;
    uint256 internal otherLpKey;

    bytes32 internal constant BLOCK_HEADER_HASH = bytes32(uint256(1));
    uint256 internal constant PARTIAL_MERKLE_TREE = 0;
    bytes32[] internal merkleHashes;

    bytes internal constant DEST =
        hex"0014deadbeefdeadbeefdeadbeefdeadbeefdeadbeef";

    string constant HELPER_SCRIPT_GENERATE_BTC_TX =
        "script/helpers/generate-btc-tx.ts";
    string constant HELPER_SCRIPT_GET_BTC_ADDRESS_BYTES =
        "script/helpers/get-btc-address-bytes.ts";

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
        vm.deal(owner, 100 ether);

        merkleHashes = new bytes32[](1);
        merkleHashes[0] = bytes32(uint256(1));

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

        CollateralManagementContract cmImpl = new CollateralManagementContract();
        collateral = CollateralManagementContract(
            payable(
                address(
                    new ERC1967Proxy(
                        address(cmImpl),
                        abi.encodeCall(
                            cmImpl.initialize,
                            (
                                owner,
                                ADMIN_DELAY,
                                MIN_COLLATERAL,
                                RESIGN_DELAY_BLOCKS,
                                REWARD_PERCENTAGE,
                                pauseRegistry
                            )
                        )
                    )
                )
            )
        );

        FlyoverDiscovery discoveryImpl = new FlyoverDiscovery();
        discovery = FlyoverDiscovery(
            payable(
                address(
                    new ERC1967Proxy(
                        address(discoveryImpl),
                        abi.encodeCall(
                            discoveryImpl.initialize,
                            (
                                owner,
                                uint48(5000),
                                address(collateral),
                                pauseRegistry
                            )
                        )
                    )
                )
            )
        );

        bytes32 adderRole = collateral.COLLATERAL_ADDER();
        bytes32 slasherRole = collateral.COLLATERAL_SLASHER();

        configurations = new FlyoverConfigurationsMock();

        bridge = new BridgeMock();
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

        PegOutEscrow escrowImpl = new PegOutEscrow();
        escrow = PegOutEscrow(
            payable(
                address(
                    new ERC1967Proxy(
                        address(escrowImpl),
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

        vm.startPrank(owner);
        collateral.grantRole(adderRole, address(discovery));
        pegOut.setPegOutEscrow(address(escrow));
        collateral.grantRole(slasherRole, address(pegOut));
        collateral.grantRole(slasherRole, address(escrow));
        collateral.grantRole(adderRole, owner);
        vm.stopPrank();

        _seedPegOutConfig();
        _registerPegOutLp(lp, "Claimer LP", "claimer.lp");
        _registerPegOutLp(otherLp, "Other LP", "other.lp");
    }

    function test_T5_RefundUser_SlashesOnlyClaimer() public {
        bytes32 requestHash = _claimDefault();
        Quotes.PegOutQuote memory q = escrow.getPegOutQuote(requestHash);
        uint256 payout = q.value + q.callFee + q.gasFee;
        uint256 userBefore = user.balance;
        uint256 claimerBefore = collateral.getPegOutCollateral(lp);
        uint256 otherBefore = collateral.getPegOutCollateral(otherLp);
        uint256 expectedPenalty = q.penaltyFee < claimerBefore
            ? q.penaltyFee
            : claimerBefore;
        uint256 expectedReward = (expectedPenalty * REWARD_PERCENTAGE) / 10_000;

        _warpPastFulfillment(q);

        vm.expectEmit(true, true, false, true, address(pegOut));
        emit IPegOut.PegOutUserRefunded(requestHash, user, payout);
        vm.expectEmit(true, true, true, true, address(collateral));
        emit ICollateralManagement.Penalized(
            lp,
            other,
            requestHash,
            Flyover.ProviderType.PegOut,
            expectedPenalty,
            expectedReward
        );

        vm.prank(other);
        pegOut.refundUserPegOut(requestHash);

        assertEq(user.balance, userBefore + payout);
        assertEq(
            collateral.getPegOutCollateral(lp),
            claimerBefore - expectedPenalty
        );
        assertEq(collateral.getPegOutCollateral(otherLp), otherBefore);
        assertTrue(pegOut.isQuoteCompleted(requestHash));
        assertEq(
            uint256(escrow.getPegOutState(requestHash)),
            uint256(IPegOutEscrow.EscrowedPegOutState.REFUNDED)
        );
    }

    function test_R3_LateProof_SlashViaShouldPenalize_TimeoutReverts() public {
        (
            bytes32 requestHash,
            Quotes.PegOutQuote memory quote,
            uint256 claimTs
        ) = _claimWithP2pkhDest();
        uint256 claimerBefore = collateral.getPegOutCollateral(lp);
        uint256 expectedPenalty = quote.penaltyFee < claimerBefore
            ? quote.penaltyFee
            : claimerBefore;
        uint256 expectedReward = (expectedPenalty * REWARD_PERCENTAGE) / 10_000;

        uint32 lateTime = uint32(
            claimTs + quote.transferTime + BTC_BLOCK_TIME + 500
        );
        // Still inside the user-refund window (before expireDate / expireBlock).
        vm.warp(claimTs + quote.transferTime + 1);
        vm.roll(block.number + 1);

        bytes memory btcTx = _generateBtcTx(quote, requestHash);
        _setupBridgeConfirmations(quote, lateTime);

        vm.expectEmit(true, true, true, true, address(collateral));
        emit ICollateralManagement.Penalized(
            lp,
            lp,
            requestHash,
            Flyover.ProviderType.PegOut,
            expectedPenalty,
            expectedReward
        );

        vm.prank(lp);
        pegOut.refundPegOut(
            requestHash,
            btcTx,
            BLOCK_HEADER_HASH,
            PARTIAL_MERKLE_TREE,
            merkleHashes
        );

        assertEq(
            uint256(escrow.getPegOutState(requestHash)),
            uint256(IPegOutEscrow.EscrowedPegOutState.FULFILLED)
        );
        assertEq(
            collateral.getPegOutCollateral(lp),
            claimerBefore - expectedPenalty
        );

        _warpPastFulfillment(quote);
        vm.expectRevert(
            abi.encodeWithSelector(
                IPegOut.QuoteAlreadyCompleted.selector,
                requestHash
            )
        );
        vm.prank(other);
        pegOut.refundUserPegOut(requestHash);

        assertEq(
            collateral.getPegOutCollateral(lp),
            claimerBefore - expectedPenalty,
            "timeout must not slash again"
        );
    }

    function test_R3_TimeoutWins_ThenRefundPegOutReverts() public {
        (
            bytes32 requestHash,
            Quotes.PegOutQuote memory quote,

        ) = _claimWithP2pkhDest();
        uint256 claimerBefore = collateral.getPegOutCollateral(lp);
        uint256 expectedPenalty = quote.penaltyFee < claimerBefore
            ? quote.penaltyFee
            : claimerBefore;

        bytes memory btcTx = _generateBtcTx(quote, requestHash);
        _setupBridgeConfirmations(quote, uint32(block.timestamp + 100));

        _warpPastFulfillment(quote);

        vm.prank(other);
        pegOut.refundUserPegOut(requestHash);

        assertEq(
            collateral.getPegOutCollateral(lp),
            claimerBefore - expectedPenalty
        );
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
        vm.prank(lp);
        pegOut.refundPegOut(
            requestHash,
            btcTx,
            BLOCK_HEADER_HASH,
            PARTIAL_MERKLE_TREE,
            merkleHashes
        );

        assertEq(
            collateral.getPegOutCollateral(lp),
            claimerBefore - expectedPenalty,
            "late proof must not slash again"
        );
    }

    function test_T5_PauseOverlap_UsesClaimAnchor() public {
        // Hard pause entirely before claim must not extend the T5 gate.
        vm.prank(owner);
        pauseRegistry.setPauseLevel(
            IPauseRegistry.PauseLevel.Hard,
            "pre-claim pause"
        );
        vm.roll(block.number + 20);
        vm.warp(block.timestamp + 30 minutes);
        vm.prank(owner);
        pauseRegistry.setPauseLevel(IPauseRegistry.PauseLevel.None, "");

        bytes32 requestHash = _claimDefault();
        Quotes.PegOutQuote memory q = escrow.getPegOutQuote(requestHash);

        _warpPastFulfillment(q);
        vm.prank(other);
        pegOut.refundUserPegOut(requestHash);
        assertTrue(pegOut.isQuoteCompleted(requestHash));

        // Restore claimer above min so a second claim is allowed.
        vm.prank(owner);
        collateral.addPegOutCollateralTo{value: PENALTY_FEE}(lp);

        // Fresh peg-out: pause after claim must extend expiry.
        bytes32 requestHash2 = _claimDefault();
        Quotes.PegOutQuote memory q2 = escrow.getPegOutQuote(requestHash2);

        uint256 pauseSeconds = 1 hours;
        uint256 pauseBlocks = 25;
        vm.prank(owner);
        pauseRegistry.setPauseLevel(
            IPauseRegistry.PauseLevel.Hard,
            "post-claim pause"
        );
        vm.warp(block.timestamp + pauseSeconds);
        vm.roll(block.number + pauseBlocks);
        vm.prank(owner);
        pauseRegistry.setPauseLevel(IPauseRegistry.PauseLevel.None, "");

        // At signed expiry without pause extension: still locked.
        vm.warp(uint256(q2.expireDate) + 1);
        vm.roll(uint256(q2.expireBlock) + 1);
        vm.expectRevert(
            abi.encodeWithSelector(
                IPegOut.QuoteNotExpired.selector,
                requestHash2
            )
        );
        vm.prank(other);
        pegOut.refundUserPegOut(requestHash2);

        // Past expiry + post-claim pause overlap: refund + slash succeed.
        vm.warp(uint256(q2.expireDate) + pauseSeconds + 1);
        vm.roll(uint256(q2.expireBlock) + pauseBlocks + 1);
        vm.prank(other);
        pegOut.refundUserPegOut(requestHash2);
        assertTrue(pegOut.isQuoteCompleted(requestHash2));
        assertEq(
            uint256(escrow.getPegOutState(requestHash2)),
            uint256(IPegOutEscrow.EscrowedPegOutState.REFUNDED)
        );
    }

    function _registerPegOutLp(
        address provider,
        string memory name,
        string memory apiUrl
    ) internal {
        vm.prank(provider, provider);
        discovery.register{value: MIN_COLLATERAL}(
            name,
            apiUrl,
            true,
            Flyover.ProviderType.PegOut
        );
        vm.prank(owner);
        discovery.approveRegistration(provider);
    }

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

    function _claimWithP2pkhDest()
        internal
        returns (
            bytes32 requestHash,
            Quotes.PegOutQuote memory quote,
            uint256 claimTs
        )
    {
        bytes memory dest = _btcAddressP2pkh();
        vm.prank(user);
        requestHash = escrow.requestPegOut{value: DEFAULT_VALUE}(dest, user);
        quote = escrow.getPegOutQuote(requestHash);
        bytes memory signature = _signForLp(lpKey, quote, lp);
        vm.prank(lp);
        escrow.claimPegOut(requestHash, signature);
        claimTs = block.timestamp;
        quote = escrow.getPegOutQuote(requestHash);
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

    function _btcAddressP2pkh() internal returns (bytes memory) {
        string[] memory inputs = new string[](4);
        inputs[0] = "npx";
        inputs[1] = "ts-node";
        inputs[2] = HELPER_SCRIPT_GET_BTC_ADDRESS_BYTES;
        inputs[3] = "p2pkh";
        return vm.ffi(inputs);
    }

    function _generateBtcTx(
        Quotes.PegOutQuote memory quote,
        bytes32 quoteHash
    ) internal returns (bytes memory) {
        string[] memory inputs = new string[](7);
        inputs[0] = "npx";
        inputs[1] = "ts-node";
        inputs[2] = HELPER_SCRIPT_GENERATE_BTC_TX;
        inputs[3] = vm.toString(quoteHash);
        inputs[4] = vm.toString(quote.depositAddress);
        inputs[5] = vm.toString(quote.value);
        inputs[6] = "p2pkh";
        return vm.ffi(inputs);
    }

    function _setupBridgeConfirmations(
        Quotes.PegOutQuote memory quote,
        uint32 headerTimestamp
    ) internal {
        bytes memory header = new bytes(80);
        header[68] = bytes1(uint8(headerTimestamp));
        header[69] = bytes1(uint8(headerTimestamp >> 8));
        header[70] = bytes1(uint8(headerTimestamp >> 16));
        header[71] = bytes1(uint8(headerTimestamp >> 24));
        bridge.setHeaderByHash(BLOCK_HEADER_HASH, header);
        bridge.setConfirmations(int256(uint256(quote.transferConfirmations)));
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
                maxMinerFee: MAX_MINER_FEE
            })
        );
    }
}
