# E6 known constraints

## OP_RETURN size limit (building the smart-contract peg-in transaction)

A standard Bitcoin `OP_RETURN` output carries about 80 bytes. The smart-contract peg-in payload the SDK builds is:

```
OP_RETURN <destinationContract: 20 bytes> <maxGasFee: 32 bytes> <callData>
```

The destination contract (20) plus max gas (32) consume 52 bytes, leaving roughly 28 bytes for `callData` within the standard limit.

### Impact on E6 (SDK building the transaction)

- The SDK must validate that `destinationContract + maxGasFee + callData` fits the standard `OP_RETURN` budget before building the transaction.
- If the calldata exceeds the budget, fail early with a clear error rather than producing a transaction that nodes may not relay.
- A plain peg-in omits the `OP_RETURN` output entirely; only add it for a smart-contract peg-in.
- Keep the parser (E4) and the builder (E6) in lockstep on the exact byte layout.

### Options to weigh at breakdown

- PoC stance: support only calldata that fits the standard 80-byte `OP_RETURN`, and surface a clear SDK error above the cap.
- Tighter encoding: 4-byte selector plus minimal packed args.
- Do not rely on relaxed Bitcoin Core `OP_RETURN` limits for the PoC; relay is not guaranteed.

Source: proposal peg-in change "What about the capability to execute a smart contract function while pegging in?" and the `OP_RETURN` discussion.
