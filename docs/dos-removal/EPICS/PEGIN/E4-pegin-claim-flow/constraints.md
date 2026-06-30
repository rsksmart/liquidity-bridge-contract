# E4 known constraints

## OP_RETURN size limit (smart-contract peg-in calldata)

A standard Bitcoin `OP_RETURN` output carries about 80 bytes. The smart-contract peg-in payload uses:

```
OP_RETURN <destinationContract: 20 bytes> <maxGasFee: 32 bytes> <callData>
```

The destination contract (20) plus max gas (32) already consume 52 bytes, leaving roughly 28 bytes for `callData` within the standard limit. Large calldata does not fit in a single standard `OP_RETURN`.

### Impact on E4 (contract parsing)

- The parser must treat the calldata as bounded and must not assume arbitrary length.
- Define behavior for the three cases: no `OP_RETURN` (plain peg-in), a well-formed `OP_RETURN` (SC-call peg-in), and a malformed or oversized one (reject or treat as plain, decided at breakdown).
- The destination contract address in the `OP_RETURN` is the call target; the RSK address that derived the deposit address is the refund address.

### Options to weigh at breakdown

- PoC stance: support only calldata that fits the standard 80-byte `OP_RETURN` (small calls), and document the cap.
- Tighter encoding: 4-byte selector plus minimal packed args to stretch the budget.
- Relying on relaxed Bitcoin Core `OP_RETURN` limits is risky for relay and standardness; not for the PoC.
- Larger calldata is a future concern: either a hash-of-calldata in `OP_RETURN` with the data fetched off-chain (adds a data-availability dependency), or the rejected register-address-plus-data option. Out of scope for the PoC.

Source: proposal peg-in change "What about the capability to execute a smart contract function while pegging in?" and the `OP_RETURN` discussion.
