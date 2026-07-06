# Test: Reverting destination refunds

**Parent:** E4.2 OP_RETURN smart-contract call
**Type:** Foundry test

## Asserts
- A reverting destination sends funds to the refund address and marks a failed call, and the peg-in is not reverted.

Path: `test/pegin/OpReturnCall.t.sol`.
