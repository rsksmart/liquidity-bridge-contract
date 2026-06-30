# Task: Implement requestPegIn validations

**Parent:** E4.1 requestPegIn claim path
**Type:** Task

## Inputs
- `registry.isRegistered`, `configurations.getRequiredPegInConfirmations`, `_bridge` confirmation check.

## Steps
1. Add `requestPegIn(depositAddress, btcTx, blockHash, merkleTree)`.
2. Revert on the first line if the peg-in is already processed.
3. Require `registry.isRegistered(rskAddr)`.
4. Require confirmations `>= configurations.getRequiredPegInConfirmations(amount)` via the Bridge.

## Done when
`forge test --match-path test/pegin/RequestPegIn.t.sol` passes.
