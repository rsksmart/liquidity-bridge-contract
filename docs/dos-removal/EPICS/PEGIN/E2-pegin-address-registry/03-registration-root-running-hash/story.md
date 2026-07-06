# E2.3 registrationRoot running-hash accumulator

**Epic:** E2 PegInAddressRegistry (Peg-in track)
**Type:** Enabler

## Statement

As a restarting or newly joined LP, I want an on-chain running hash over the registered set, so I can verify my replicated watch list is complete.

## Frozen inputs

- `getRegistrationRoot() returns (bytes32)` from the interface.
- Accumulator definition from the proposal: `registrationRoot = H(registrationRoot || rskAddress)`, order-dependent, replayed from `AddressRegistered` events in (block, log index) order.

## Acceptance criteria

- Each registration updates `registrationRoot = keccak256(abi.encodePacked(registrationRoot, rskAddress))`.
- `getRegistrationRoot()` returns the current value.
- Replaying registrations in order reproduces the on-chain root.

## Children

Tasks: see `tasks/`. Tests: see `tests/`.

## Depends on

E2.1.

**Estimate:** 3. **Labels:** enabler, P0, lbc.
