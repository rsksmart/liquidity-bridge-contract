# E2.4 Deposit-gated permissionless registration

**Epic:** E2 PegInAddressRegistry (Peg-in track)
**Type:** Enabler

## Statement

As any caller, I want to register an RSK address against an SPV proof of a BTC deposit, with no signature, so that a Watchtower or the user can register on the user's behalf.

## Frozen inputs

- D1 decision (S0.4): registration is permissionless and deposit-gated; no ECDSA signature.
- `registerAddress(address addr, bytes btcTx, uint256 blockHeight, bytes merkleProof)` from the frozen interface.
- SPV validation reference: `PegInContract.registerPegIn` / `_bridge` confirmation checks and `BtcUtils`.

## Acceptance criteria

- `registerAddress` validates the BTC tx pays the address derived for `addr`, via the Bridge SPV path, then registers: sets the registration block, increments the count, updates the root, and emits `AddressRegistered`.
- An invalid or missing deposit proof reverts and nothing is registered.
- Any `msg.sender` can register a valid deposit; no signature from `addr` is required.

## Children

Tasks: see `tasks/`. Tests: see `tests/`.

## Depends on

E2.2 (derivation), E2.3 (root).

**Estimate:** 5. **Labels:** enabler, P0, lbc.
