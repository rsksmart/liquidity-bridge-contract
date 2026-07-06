# E4.2 OP_RETURN smart-contract call

**Epic:** E4 Peg-in claim flow (Peg-in track)
**Type:** Enabler

## Statement

As a user, I want a peg-in that calls a contract, with the call described in the BTC transaction's OP_RETURN, so I can do an SC-call peg-in without a quote.

## Frozen inputs

- `../constraints.md` (OP_RETURN ~80-byte limit; layout `destContract(20) maxGasFee(32) callData`).
- Proposal peg-in negative scenario: a reverting destination does not revert the peg-in; it is registered as a failed call and funds go to the refund address (the RSK address).

## Acceptance criteria

- A present OP_RETURN calls `destContract` with `callData` and `amount - callFee - gasFee` under `maxGasFee`.
- A plain peg-in (no OP_RETURN) sends to the RSK address.
- A reverting destination sends funds to the refund address (RSK address) and marks a failed call without reverting the peg-in.
- Malformed or oversized OP_RETURN is handled per `../constraints.md`.

## Children

Tasks: see `tasks/`. Tests: see `tests/`.

## Depends on

E4.1.

**Estimate:** 5. **Labels:** enabler, P0, lbc.
