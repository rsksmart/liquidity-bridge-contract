# E3.2 Proportional global slash

**Epic:** E3 Global slash and grace window (Foundation track)
**Type:** Enabler

## Statement

As the protocol, I want a global slash that distributes a total penalty proportionally across registered LPs, skipping any LP inside its grace window, so an unserved valid operation penalizes the network without punishing fresh LPs.

## Frozen inputs

- Registered-LP set and `registrationBlock` from E3.1.
- S0.3 parameters: global slash equals one `penaltyFee` total; grace window 100 blocks.
- Existing `slashPegInCollateral` distribution: caller reward plus the `_penalties` pool, `Penalized` event.

## Acceptance criteria

- `globalSlash(total)` reduces each eligible LP's collateral proportionally to its share of eligible collateral.
- An LP within its grace window (`block.number <= registrationBlock[lp] + graceWindow`) is skipped.
- Each affected LP emits `Penalized`. The function is role-gated to `COLLATERAL_SLASHER`.

## Children

Tasks: see `tasks/`. Tests: see `tests/`.

## Depends on

E3.1.

**Estimate:** 5. **Labels:** enabler, P0, lbc.
