# E11.1 No-claimer settlement: forward to the user

**Epic:** E11 Peg-in refund & non-happy-path settlement (Peg-in track)
**Type:** Enabler · **Address impact:** none (RBTC rail — does not touch derivation)

## Statement

As a user whose deposit no LP fronted, I want `resolvePegIn` to release my funds to the LBC
and forward the RBTC to my `rskAddr`, so I am always made whole from my own deposit — just
later than if an LP had served me fast.

## Frozen inputs

- `resolvePegIn` / `_settleWithBridge` (E4.3): settles via the bridge with
  `shouldTransferToContract = true`; contract balance goes `0 → amount`.
- `_reimburseClaim` currently assumes a claimer exists (`claim.claimer`) and credits it
  `fronted + fee`. There is no path today for "no LP fronted".
- Proposal negative scenario "No LP advances the payment": the peg-in still settles; the user
  receives their funds; LPs are global-slashed (the slash itself is E11.2).
- Fee is subtracted from the amount (no separate `gasFee` informed in advance).

## Output (concrete deliverable)

A `resolvePegIn` path that, when no claim was recorded for the peg-in id, forwards
`amount − fee` from the bridge-released RBTC to the user's `rskAddr` (or the OP_RETURN
destination contract if present), marks the peg-in processed, and does **not** attempt an
LP reimbursement. The registrant/watchtower fee is still paid once (E4.3 rule).

## Acceptance criteria

- A registered, confirmed peg-in that no LP fronted settles when `resolvePegIn` is called,
  releasing RBTC to the LBC and forwarding `amount − fee` to the user's `rskAddr`.
- The claimer path (E4.3) is unchanged when a claim exists.
- Re-resolving reverts `PegInAlreadyProcessed`.
- A plain peg-in forwards to `rskAddr`; an OP_RETURN SC-call peg-in targets the destination
  contract (revert handling is E11.3).
- Foundry tests cover: no-claimer forward-to-user, claimer path still reimburses, and
  double-resolve revert.

## Children

Tasks: see `tasks/`. Tests: see `tests/`.

## Depends on

E4.3 (settlement), E2 (registration/`rskAddr` binding). Independent of E11.5.

**Estimate:** 5. **Labels:** enabler, P0, lbc.
