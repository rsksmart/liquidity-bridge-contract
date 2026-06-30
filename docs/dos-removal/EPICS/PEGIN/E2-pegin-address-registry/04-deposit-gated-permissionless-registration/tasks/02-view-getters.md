# Task: Registration view getters

**Parent:** E2.4 Deposit-gated permissionless registration
**Type:** Task

## Steps
1. Implement `isRegistered(address)`, `getRegistrationBlock(address)`, and `getRegistrationCount()` over the storage from E2.1.

## Done when
`forge test --match-path test/pegin-registry/Register.t.sol` covers the getters and passes.
