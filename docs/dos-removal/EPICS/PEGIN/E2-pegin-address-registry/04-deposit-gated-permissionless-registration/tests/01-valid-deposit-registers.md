# Test: Valid deposit registers

**Parent:** E2.4 Deposit-gated permissionless registration
**Type:** Foundry test

## Asserts
- With a valid deposit proof, `registerAddress` sets `isRegistered` true, records the block, increments the count, updates the root, and emits `AddressRegistered`.

Path: `test/pegin-registry/Register.t.sol`.
