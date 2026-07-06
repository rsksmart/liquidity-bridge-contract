# Task: Implement getPegInAddresses

**Parent:** E2.5 Federation-change derivation and batch getters
**Type:** Task

## Steps
1. Implement `getPegInAddresses(address[])` looping the single derivation from E2.2 and returning the array plus the shared `Encoding`.

## Done when
`forge test --match-path test/pegin-registry/Federation.t.sol` passes.
