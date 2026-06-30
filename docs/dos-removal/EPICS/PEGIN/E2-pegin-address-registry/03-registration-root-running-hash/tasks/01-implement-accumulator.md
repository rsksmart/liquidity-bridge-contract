# Task: Implement the accumulator

**Parent:** E2.3 registrationRoot running-hash accumulator
**Type:** Task

## Steps
1. Add an internal `_updateRoot(address rskAddr)` computing `registrationRoot = keccak256(abi.encodePacked(registrationRoot, rskAddr))`.
2. Call it from the registration path (wired in E2.4).
3. Expose `getRegistrationRoot()`.

## Done when
`forge test --match-path test/pegin-registry/Root.t.sol` passes.
