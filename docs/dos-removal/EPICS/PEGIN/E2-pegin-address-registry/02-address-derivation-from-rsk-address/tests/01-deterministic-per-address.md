# Test: Deterministic per RSK address

**Parent:** E2.2 Address derivation from RSK address
**Type:** Foundry test

## Asserts
- `getPegInAddress(rskAddr)` returns an identical address across repeated calls.
- Two different RSK addresses derive different addresses.

Path: `test/pegin-registry/Derivation.t.sol`.
