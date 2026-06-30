# Task: Federation-change behavior

**Parent:** E2.5 Federation-change derivation and batch getters
**Type:** Task

## Inputs
- A `BridgeMock` that can return two different powpeg redeem scripts.

## Steps
1. Confirm `getPegInAddress` reads the current powpeg each call. If it caches, change it to read live.
2. Add `test/pegin-registry/Federation.t.sol` using the mock with two redeem scripts.

## Done when
`forge test --match-path test/pegin-registry/Federation.t.sol` passes.
