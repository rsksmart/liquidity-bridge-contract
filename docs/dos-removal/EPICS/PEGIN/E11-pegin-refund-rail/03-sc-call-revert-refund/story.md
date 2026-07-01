# E11.3 SC-call-revert refund

**Epic:** E11 Peg-in refund & non-happy-path settlement (Peg-in track)
**Type:** Enabler · **Address impact:** none (RBTC rail)

## Statement

As a user doing an OP_RETURN smart-contract peg-in whose destination reverts, I want the
peg-in to still settle, my funds refunded to my `rskAddr`, and the LP to still earn its fee,
so a failing call does not strand funds or punish the LP.

## Frozen inputs

- E4.2 OP_RETURN parsing (`OP_RETURN <destContract 20> <maxGasFee 32> <callData>`) and the
  `constraints.md` size limit.
- Proposal negative scenario "SC-call peg-in where the destination reverts": the peg-in is
  **not** reverted; it is registered as a failed call; the LP gets its fee at `resolvePegIn`;
  the money is sent to the refund address (the RSK address that derived the deposit).

## Output

On an SC-call peg-in whose destination call reverts, the flow records a failed call, refunds
`amount − fee` to the user's `rskAddr` in RBTC, and still pays the LP its fee at resolve —
covering both the fronted (claimer) path and the no-claimer path (E11.1).

## Acceptance criteria

- A reverting destination call does not revert the peg-in; it is recorded as failed.
- The user is refunded `amount − fee` to `rskAddr`.
- The LP/claimer still receives its fee at `resolvePegIn`.
- Foundry tests cover a reverting destination for both the claimer and no-claimer paths.

## Children

Tasks: see `tasks/`. Tests: see `tests/`.

## Depends on

E4.2, E11.1. Independent of E11.5.

**Estimate:** 3. **Labels:** enabler, P1, lbc.
