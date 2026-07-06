# Test: Root folds registrations in order

**Parent:** E2.3 registrationRoot running-hash accumulator
**Type:** Foundry test

## Asserts
- After registering A then B, `registrationRoot == keccak256(keccak256(0 || A) || B)`.

Path: `test/pegin-registry/Root.t.sol`.
