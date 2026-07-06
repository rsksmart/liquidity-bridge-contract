# Task: Implement resolvePegIn

**Parent:** E4.3 resolvePegIn settlement
**Type:** Task

## Steps
1. Add `resolvePegIn(depositAddress, btcTx, blockHash, merkleTree)` registering with the Bridge via `registerFastBridgeBtcTransaction`.
2. Release RBTC to the contract; pay the claiming LP its fronted RBTC plus the full `callFee`.
3. Mark the peg-in processed.

## Done when
`forge test --match-path test/pegin/ResolvePegIn.t.sol` passes.
