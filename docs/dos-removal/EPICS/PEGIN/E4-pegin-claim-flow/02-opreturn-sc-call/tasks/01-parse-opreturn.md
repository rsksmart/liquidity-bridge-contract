# Task: Parse the OP_RETURN payload

**Parent:** E4.2 OP_RETURN smart-contract call
**Type:** Task

## Inputs
- Layout from `../constraints.md`: 20-byte destContract, 32-byte maxGasFee, then bounded callData.

## Steps
1. Detect the OP_RETURN output and parse destContract, maxGasFee, callData.
2. Reject malformed payloads; enforce the bounded calldata size.

## Done when
`forge test --match-path test/pegin/OpReturnParse.t.sol` passes.
