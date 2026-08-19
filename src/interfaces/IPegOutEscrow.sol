// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Quotes} from "../libraries/Quotes.sol";

/// @title Peg-out escrow interface (commit-first)
/// @notice Holds the user's RBTC commitment before an LP claims. Settlement after claim
/// stays on PegOutContract. LPs discover work via {PegOutRequested}; there is no off-chain
/// quote acceptance and no liquidity reservation before this deposit.
/// @dev This interface is frozen: any change to it is a cross-lane ABI event, not a side
/// effect of another task.
interface IPegOutEscrow {
    /// @notice Lifecycle of one escrowed peg-out. `NONE` is the storage default so unset
    /// ids are never confused with `REQUESTED`.
    enum EscrowedPegOutState {
        NONE,
        REQUESTED,
        CLAIMED,
        CANCELLED,
        FULFILLED,
        REFUNDED
    }

    /// @notice Emitted when a user escrows RBTC for a peg-out (the sole commitment)
    /// @dev Fee / deadline / confirmation snapshots live on the stored quote
    /// ({getPegOutQuote}); this event is the LPS discovery signal only.
    /// @param requestHash Stable request id = `hashPegOutQuote` of the incomplete quote
    /// (`lpRskAddress = 0`). Same encoding as PegOutContract / OP_RETURN. Distinct requests
    /// stay distinct via `nonce` on the quote.
    /// @param refundAddress Who may cancel and who receives refunds
    /// @param amount BTC-equivalent principal in wei after the fee split
    /// @param destinationAddress User BTC payout script / address bytes
    event PegOutRequested(
        bytes32 indexed requestHash,
        address indexed refundAddress,
        uint256 indexed amount,
        bytes destinationAddress
    );

    /// @notice Emitted when an LP claims a REQUESTED peg-out and funds move to PegOutContract
    /// @dev A claim is a hard commitment: there is no release / unclaim path.
    event PegOutClaimed(address indexed lpAddress, bytes32 indexed requestHash);

    /// @notice Emitted when the refund address cancels while still REQUESTED (no slash)
    event PegOutCancelled(bytes32 indexed requestHash);

    /// @notice Emitted when nobody claimed by the claim deadline and the user is refunded
    event PegOutRefundedOnNoClaim(bytes32 indexed requestHash, address indexed refundAddress, uint256 amount);

    /// @notice Emitted when {refundOnNoClaim}'s global slash attempt reverts (user still refunded)
    event GlobalSlashSkipped(bytes32 indexed requestHash);

    error InvalidDestination();
    error NotServiceable(uint256 amount, uint256 minAmount, uint256 maxAmount);
    error InvalidState(bytes32 requestHash, EscrowedPegOutState expected, EscrowedPegOutState actual);
    error ClaimWindowClosed(uint256 depositDateLimit);
    error ClaimWindowOpen(uint256 depositDateLimit);
    error PegOutContractNotSet();
    error CollateralManagementNotSet();
    error OnlyPegOutContract(address caller);
    error LpRestricted(address lp, uint256 restrictedUntil);

    /// @notice User commits RBTC. Splits `msg.value` into `amount` + `callFee` + `gasFee` from
    /// FlyoverConfigurations, stores a quote-shaped record, emits {PegOutRequested}.
    /// @dev **Amount / fee split:** `requestPegOut` takes no explicit `amount`. For active
    /// config `fixedFee`, `percentageFee` (basis points over `FEE_PERCENTAGE_DENOMINATOR` =
    /// 10_000), and `maxMinerFee` snapshotted into `quote.gasFee`:
    /// `amount = ((msg.value - fixedFee - gasFee) * DEN) / (DEN + percentageFee)`;
    /// then `amount -= amount % SAT_TO_WEI` (satoshi floor);
    /// `callFee = calculatePegOutFee(amount)` (same satoshi-floor fee as configs);
    /// `gasFee = maxMinerFee`.
    /// **Overpayment rule:** `required = amount + callFee + gasFee`. If
    /// `msg.value - required` is at least the wired PegOutContract `dustThreshold`,
    /// the excess is refunded to the refund address (legacy `depositPegOut` dust-change
    /// semantics). Otherwise the residual is absorbed into `callFee` so escrow balance
    /// stays attributed. `msg.value` must exceed `fixedFee + gasFee` and the derived
    /// `amount` must lie in `[minAmount, maxAmount]` or the call reverts.
    /// @param destinationAddress User BTC payout script / address bytes
    /// @param refundAddress Who may cancel and who receives refunds; must be non-zero
    /// @return requestHash `hashPegOutQuote` of the incomplete quote (`lpRskAddress = 0`)
    function requestPegOut(
        bytes calldata destinationAddress,
        address refundAddress
    ) external payable returns (bytes32 requestHash);

    /// @notice User cancels while still REQUESTED. Only `rskRefundAddress` on the quote.
    /// @dev Full refund, no slash.
    function cancelPegOut(bytes32 requestHash) external;

    /// @notice Registered LP claims the peg-out and moves funds into PegOutContract.
    /// @dev Hard commitment: no release/unclaim path. Caller must pass EIP-712 over the
    /// reconstructed quote with `lpRskAddress = msg.sender`.
    function claimPegOut(bytes32 requestHash, bytes calldata signature) external;

    /// @notice Permissionless refund after `depositDateLimit` if nobody claimed.
    /// @dev Attempts global slash; user refund must not depend on slash success.
    function refundOnNoClaim(bytes32 requestHash) external;

    /// @notice Called by PegOutContract when settlement finishes (`FULFILLED` or `REFUNDED`)
    /// @dev Escrow does not move funds here; custody already left at claim.
    function onSettlement(bytes32 requestHash, EscrowedPegOutState finalState) external;

    /// @notice Called by PegOutContract on claimed-expired user refund (`refundUserPegOut`).
    /// @dev Increments `claimFailCount` and sets `restrictedUntil` to
    /// `now + (RESTRICTION_BASE ** n) * RESTRICTION_UNIT`. Always overwrites `restrictedUntil`
    /// (including after admin revoke). Only PegOutContract may call.
    function onClaimFail(address lp) external;

    /// @notice Admin indefinite ban: `restrictedUntil = type(uint256).max`. Does not change fail count.
    function revoke(address lp) external;

    /// @notice Admin clear ban / timed freeze: `restrictedUntil = 0`. Does not change fail count.
    function unrevoke(address lp) external;

    /// @notice Current lifecycle state for `requestHash` (`NONE` if never requested)
    function getPegOutState(bytes32 requestHash) external view returns (EscrowedPegOutState);

    /// @notice Quote-shaped terms snapshotted at request (and `lpRskAddress` after claim)
    /// @dev Reverts if state is `NONE`. Fee/deadline/confirmation fields are the LPS and
    /// settlement source of truth alongside the lean {PegOutRequested} event.
    function getPegOutQuote(bytes32 requestHash) external view returns (Quotes.PegOutQuote memory);

    /// @notice Number of requests ever minted (monotone nonce high-water mark)
    /// @dev With {requestIdAt}, an LPS can rebuild the pending set after missed events.
    function totalRequests() external view returns (uint256);

    /// @notice `requestHash` minted for sequence `nonce` (1-based); zero if unused
    function requestIdAt(uint256 nonce) external view returns (bytes32);

    /// @notice Number of claim-fail bumps for `lp` (used as exponent `n` in freeze length)
    function claimFailCount(address lp) external view returns (uint256);

    /// @notice Timestamp until which `lp` cannot call {claimPegOut} (`0` ⇒ not frozen)
    function restrictedUntil(address lp) external view returns (uint256);
}
