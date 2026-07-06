# E2.5 Federation-change derivation and batch getters

**Epic:** E2 PegInAddressRegistry (Peg-in track)
**Type:** Enabler

## Statement

As an LP, I want `getPegInAddress` to reflect the current powpeg and a batch getter for many addresses, so I can re-derive my watch set after a federation change.

## Frozen inputs

- `getPegInAddresses(address[]) returns (bytes[], Encoding)` from the interface.
- Federation-change policy (S0.1 / proposal): derivation reads the current powpeg each call, so the address changes when the composition changes, the same as the native peg-in address.

## Acceptance criteria

- `getPegInAddresses(addrs)` returns the per-address derivations for the current powpeg.
- A simulated federation change yields a different derived address for the same RSK address.

## Children

Tasks: see `tasks/`. Tests: see `tests/`.

## Depends on

E2.2.

**Estimate:** 3. **Labels:** enabler, P0, lbc.
