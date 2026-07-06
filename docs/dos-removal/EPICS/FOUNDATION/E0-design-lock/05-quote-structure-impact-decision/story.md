# S0.5 Quote-structure impact decision

**Epic:** E0 Design lock
**Story:** As an LPS and SDK engineer, I want a decision on what of the quote structure to keep, so that E5 and E8 stay small.

## Decision (locked 2026-06-28)

**Decision:** minimal removal for the PoC. Cut the off-chain reservation, keep the quote types.
- Remove the `RetainedQuote` liquidity-locking in `accept_pegin_quote.go` and `accept_pegout_quote.go`, and the `LockedLiquidity` computation tied to it. This closes the DoS.
- Keep `PeginQuote` and `PegoutQuote` as internal data carriers where the claim and settlement code finds them convenient.
- SDK: drop `getQuotes` and `acceptQuote` from the user flow; internal types may stay.
- Prefer adding new files for the reservation-free discovery and claim path over heavily rewriting the quote-entangled code, where that keeps the change small.
- Boundary: E5 and E8 touch only the reservation path plus the new event and claim watchers, not a full rewrite of the quote model.

**Rationale:** concentrates the change on what removes the DoS, keeps E5 and E8 small and low-risk, and proves the concept without a sweeping refactor. New files isolate the new path from the legacy quote code.

**Tradeoff:** keeping the quote types and adding parallel files leaves residual structure and some duplication behind, a bit of tech debt that is not as clean as a full removal. We accept that to keep the PoC scoped; the full quote-removal refactor is deferred to prod, where it can be done deliberately.

## Output (the deliverable)

A decision record `decision-quote-structure.md` containing:

1. A table of quote types and fields, each marked keep-internal or remove, for both LPS and the SDK.
2. The blast-radius boundary: the exact packages and files E5 and E8 may touch, and those they must not.
3. The reasoning that keeps the PoC change scoped to the reservation path.

## Acceptance criteria

- The table lists the LPS quote entities (`PeginQuote`, `RetainedPeginQuote`, `PegoutQuote`, `RetainedPegoutQuote`) and the SDK quote types, each marked keep or remove for the PoC.
- The record states that E5 and E8 change only the reservation path, not the whole quote model.
- The boundary names the files involved: `accept_pegin_quote.go`, `accept_pegout_quote.go`, `liquidity_provider.go`.

## Grounded in

Proposal "Next steps" open question: off-chain negotiation is removed, but whether to remove quotes from the protocol logic is a separate, large change to minimize. PRD non-goal: keep internal quote types where removing them adds risk without proving the concept. LPS map: the reservation lives in `accept_pegin_quote.go` and `accept_pegout_quote.go`, with locking computed in `liquidity_provider.go`.

## Children

Tasks: see `tasks/`. Tests: see `tests/`.

## Feeds

E5 (LPS peg-in), E8 (LPS peg-out).

## Depends on (within E0)

None.

**Estimate:** 2. **Labels:** story, design.
