# Task: Implement getPegInAddress

**Parent:** E2.2 Address derivation from RSK address
**Type:** Task

## Inputs
- The pinned scheme from task 01.
- `_bridge.getActivePowpegRedeemScript()` and `BtcUtils` from the current contracts.

## Steps
1. Implement `getPegInAddress(address)` per the pinned scheme, reading the active powpeg redeem script from the Bridge.
2. Return the encoded address plus its `Encoding`.

## Done when
`forge test --match-path test/pegin-registry/Derivation.t.sol` passes.
