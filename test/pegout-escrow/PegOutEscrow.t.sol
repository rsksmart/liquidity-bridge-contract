// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {PegOutEscrow} from "../../src/PegOutEscrow.sol";
import {PauseRegistry} from "../../src/PauseRegistry.sol";
import {IPegOutEscrow} from "../../src/interfaces/IPegOutEscrow.sol";
import {IFlyoverConfigurations} from "../../src/interfaces/IFlyoverConfigurations.sol";
import {Flyover} from "../../src/libraries/Flyover.sol";
import {Quotes} from "../../src/libraries/Quotes.sol";
import {FlyoverConfigurationsMock} from "../pegin/FlyoverConfigurationsMock.sol";

/// @dev Minimal PegOut stand-in: only `dustThreshold` (public getter) is read by escrow.
contract PegOutDustMock {
    uint256 public dustThreshold;

    constructor(uint256 dustThreshold_) {
        dustThreshold = dustThreshold_;
    }

    function setDustThreshold(uint256 dustThreshold_) external {
        dustThreshold = dustThreshold_;
    }
}

/// @dev Satisfies initialize code.length checks; unused by request/cancel.
contract CodeStub {

}

/// @title PegOutEscrow request + cancel AC coverage (S12-A)
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

    /// @dev msg.value that yields a serviceable principal near 1 ether under the seed config.
    uint256 internal constant DEFAULT_VALUE = 1.012 ether;

    PegOutEscrow internal escrow;
    FlyoverConfigurationsMock internal configurations;
    PegOutDustMock internal pegOut;
    PauseRegistry internal pauseRegistry;

    address internal owner;
    address internal user;
    address internal other;

    bytes internal constant DEST =
        hex"0014deadbeefdeadbeefdeadbeefdeadbeefdeadbeef";

    function setUp() public {
        owner = makeAddr("owner");
        user = makeAddr("user");
        other = makeAddr("other");
        vm.deal(user, 100 ether);
        vm.deal(other, 100 ether);

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
        pegOut = new PegOutDustMock(DUST);
        CodeStub collateral = new CodeStub();

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
    // stubs
    // -------------------------------------------------------------------------

    function test_stubs_revertNotImplemented() public {
        vm.expectRevert(PegOutEscrow.PegOutPathNotImplemented.selector);
        escrow.claimPegOut(bytes32(0), "");

        vm.expectRevert(PegOutEscrow.PegOutPathNotImplemented.selector);
        escrow.refundOnNoClaim(bytes32(0));

        vm.expectRevert(PegOutEscrow.PegOutPathNotImplemented.selector);
        escrow.onSettlement(
            bytes32(0),
            IPegOutEscrow.EscrowedPegOutState.FULFILLED
        );
    }

    // -------------------------------------------------------------------------
    // helpers
    // -------------------------------------------------------------------------

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
