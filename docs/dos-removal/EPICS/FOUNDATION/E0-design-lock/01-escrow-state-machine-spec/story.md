# S0.1 Peg-out escrow state machine spec

**Epic:** E0 Design lock (Foundation track)
**Type:** Story

## Statement

As an LBC engineer, I want a frozen escrow state machine, so that I can build E7 without re-deciding transitions mid-implementation.

## Output (the deliverable)

A markdown document `escrow-state-machine.md` containing a Mermaid state diagram, a transition table, a race-resolution table, and the no-release-path rule.

## Acceptance criteria

- The transition table covers every permitted transition and rejects all others by default.
- Each race named in the proposal has a resolution: user cancel against LP claim in the same block, LP claim against the pre-claim deadline, and slash trigger against a late delivery.
- The "no release path" rule is explicit: once an LP claims, it must fulfill or be slashed.
- Reviewed and approved by one other engineer.

## Decisions (locked)

### Cancel vs claim race (2026-06-28)

**Decision:** first transaction mined wins, and the loser reverts. No gas-price cap for the PoC.

**Rationale:** pre-claim, both outcomes are safe because no BTC is committed yet, so this is the simplest correct rule. A user cannot cancel once a claim has landed, which is consistent with a claim being a hard commitment.

**Tradeoff:** a user cannot guarantee a cancel beats an LP's claim. If the claim lands first the user is served rather than refunded, which is safe because no BTC was committed. The alternative, a gas-price cap favoring cancel, guarantees the user's exit but adds mechanism and lets a user reliably beat LPs for no real pre-claim benefit.

### Claim vs pre-claim-deadline race (2026-06-28)

**Decision:** gate the claim on `block.timestamp <= preClaimDeadline`, first transaction mined wins. A claim at or before the deadline succeeds; after it, the claim reverts and the request becomes refund-and-global-slash eligible.

**Rationale:** consistent with the cancel-vs-claim rule, reuses the existing timestamp-based deadline checks in the peg-out contract, and is deterministic with no extra mechanism.

**Tradeoff:** an LP that claims a block or two late is global-slashed with everyone else, even on a near-miss. The alternative, a grace buffer past the deadline, is kinder to LPs but adds a tunable window and softens the deadline, which the PoC does not need.

### Slash-trigger vs late-delivery race (2026-06-28)

**Decision:** adjudicate late delivery by the BTC transaction timestamp via SPV, not by on-chain submission order. The contract compares the BTC tx timestamp plus the transfer window against the deadline. To treat honest LPs gently, the individual slash fires only when the BTC tx timestamp exceeds the deadline plus a delivery-grace tolerance, which absorbs BTC timestamp jitter and minor delays. The tolerance is a provisional parameter set in S0.3, reusing or extending the existing `btcBlockTime` buffer.

**Rationale:** the BTC tx timestamp is immutable and provable, so the outcome cannot be gamed by transaction ordering and it matches the current peg-out timestamp check. The grace tolerance keeps an honest LP from being slashed for a marginal, network-induced delay, which protects LP participation, especially at bootstrap with few LPs.

**Tradeoff:** a generous grace window lets a genuinely late LP escape the slash within the buffer and extends the user's wait before the request resolves. We accept that to avoid unfairly slashing honest LPs over BTC timestamp imprecision. Judging by proof-submission time instead would be simpler to compute but reintroduces a race and can slash an LP that delivered on time but submitted the proof slowly.

Note: the case where an LP delivers BTC but never submits the proof, letting the user collect a refund and keep the BTC, is the Watchtower honest-refund case, handled in E10b.

## Grounded in

Proposal `IPegOutEscrow` enum (`REQUESTED, CLAIMED, CANCELLED, FULFILLED, REFUNDED`), the proposal "Negative scenarios" peg-out list, and the "no release path for a claim" callout. Current peg-out behavior mapped in `PegOutContract` (`depositPegOut`, `refundPegOut`, `refundUserPegOut`).

## Children

Tasks: see `tasks/`. Tests: see `tests/`.

## Feeds

E7 (PegOutEscrow contract and claim flow).

## Depends on

None (within E0).

**Estimate:** 3. **Labels:** story, design, lbc.
