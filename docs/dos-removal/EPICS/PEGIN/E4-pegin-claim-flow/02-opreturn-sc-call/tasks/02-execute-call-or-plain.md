# Task: Execute the call or plain transfer

**Parent:** E4.2 OP_RETURN smart-contract call
**Type:** Task

## Steps
1. If OP_RETURN present, call destContract with callData and `amount - callFee - gasFee` capped at maxGasFee.
2. Else send to the RSK address.
3. On a reverting call, send funds to the refund address (RSK address), mark a failed call, and do not revert the peg-in.

## Done when
`forge test --match-path test/pegin/OpReturnCall.t.sol` passes.
