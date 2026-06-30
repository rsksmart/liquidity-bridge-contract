# E3.1 Registered-LP enumeration and registration block

**Epic:** E3 Global slash and grace window (Foundation track)
**Type:** Enabler

## Statement

As `CollateralManagement`, I want an enumerable set of registered LPs and each LP's registration block, so the global slash can iterate the set and the grace window can be checked.

## Frozen inputs

- Current `CollateralManagement`: `_pegInCollateral` / `_pegOutCollateral` mappings, `isRegistered`, and the `FlyoverDiscovery.approveRegistration` to `addPegInCollateralTo` path.
- OpenZeppelin `EnumerableSet`.

## Acceptance criteria

- An `EnumerableSet.AddressSet` of currently registered LPs is maintained: added on registration, removed on resign or full withdrawal.
- `registrationBlock[lp]` is recorded at registration.
- Getters expose the set size and membership.

## Children

Tasks: see `tasks/`. Tests: see `tests/`.

## Depends on

E0 (provisional grace window value). No dependency on the flow tracks.

**Estimate:** 3. **Labels:** enabler, P0, lbc.
