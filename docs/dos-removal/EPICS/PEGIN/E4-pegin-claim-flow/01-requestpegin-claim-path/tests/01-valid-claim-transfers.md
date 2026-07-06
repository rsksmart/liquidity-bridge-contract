# Test: Valid claim transfers RBTC

**Parent:** E4.1 requestPegIn claim path
**Type:** Foundry test

## Asserts
- A valid claim transfers `amount - gasFee - callFee` from the LP wallet to the user.

Path: `test/pegin/RequestPegIn.t.sol`.
