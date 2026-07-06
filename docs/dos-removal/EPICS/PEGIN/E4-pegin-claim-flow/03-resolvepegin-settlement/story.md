# E4.3 resolvePegIn settlement

**Epic:** E4 Peg-in claim flow (Peg-in track)
**Type:** Enabler

## Statement

As the claiming LP, I want to settle the peg-in with the Bridge and recover RBTC plus the full fee, so claiming is rewarded.

## Frozen inputs

- Current `registerPegIn` and `_bridge.registerFastBridgeBtcTransaction`. The proposal names `requestPegIn` / `resolvePegIn` as the equivalents of `callForUser` / `registerPegIn`.
- Registrant (Watchtower) fee, subtracted from `callFee` on the first peg-in only.

## Acceptance criteria

- `resolvePegIn` registers with the Bridge after the required confirmations and releases RBTC to the contract.
- The claiming LP recovers its fronted RBTC plus the full `callFee`.
- The registrant fee is paid once, from `callFee`, on the first peg-in for the address.
- The peg-in is marked processed.

## Children

Tasks: see `tasks/`. Tests: see `tests/`.

## Depends on

E4.1.

**Estimate:** 5. **Labels:** enabler, P0, lbc.
