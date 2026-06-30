# Task: Implement registerAddress

**Parent:** E2.4 Deposit-gated permissionless registration
**Type:** Task

## Inputs
- Derivation from E2.2, accumulator from E2.3.
- Bridge SPV validation as used in `registerPegIn`.

## Steps
1. Derive the expected BTC address for `addr` (E2.2).
2. Validate via the Bridge that `btcTx` at `blockHeight` with `merkleProof` pays that address.
3. Require `addr` is not already registered.
4. Set `registrationBlock[addr]`, increment `count`, call `_updateRoot(addr)`, emit `AddressRegistered(addr, registrationRoot)`.
5. Keep the function permissionless: do not check `msg.sender` against `addr`.

## Done when
`forge test --match-path test/pegin-registry/Register.t.sol` passes.
