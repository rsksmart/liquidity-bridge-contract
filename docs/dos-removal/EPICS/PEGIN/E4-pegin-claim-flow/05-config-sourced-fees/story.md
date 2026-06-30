# E4.5 Config-sourced fees and confirmations

**Epic:** E4 Peg-in claim flow (Peg-in track)
**Type:** Enabler

## Statement

As an LBC engineer, I want the peg-in path to read fees and confirmations from `FlyoverConfigurations`, so nothing depends on a negotiated quote.

## Frozen inputs

- E1 `calculatePegInFee(amount)` and `getRequiredPegInConfirmations(amount)`.

## Acceptance criteria

- `requestPegIn` and `resolvePegIn` source the fee from `calculatePegInFee` and the confirmations from `getRequiredPegInConfirmations`.
- No fee or confirmation value is read from a quote.

## Children

Tasks: see `tasks/`. Tests: see `tests/`.

## Depends on

E1, E4.1.

**Estimate:** 2. **Labels:** enabler, P0, lbc.
