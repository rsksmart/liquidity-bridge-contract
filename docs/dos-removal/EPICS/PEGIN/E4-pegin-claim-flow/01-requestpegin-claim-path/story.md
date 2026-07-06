# E4.1 requestPegIn claim path

**Epic:** E4 Peg-in claim flow (Peg-in track)
**Type:** Enabler

## Statement

As an LP, I want to claim a confirmed peg-in by fronting RBTC from my own wallet, so I serve the user without parking liquidity in the contract.

## Frozen inputs

- E2 `PegInAddressRegistry.isRegistered` and the derived address.
- E1 `getRequiredPegInConfirmations(amount)`.
- Bridge confirmation check and the current `callForUser` logic (which today spends contract `_balances`).

## Acceptance criteria

- `requestPegIn(depositAddress, btcTx, blockHash, merkleTree)` validates the address is registered, the BTC tx has the required confirmations, and the peg-in is not already processed.
- The LP transfers RBTC from its own wallet to the user (`amount - gasFee - callFee`), not from contract balances.
- A second claim on the same peg-in reverts on the first line.

## Children

Tasks: see `tasks/`. Tests: see `tests/`.

## Depends on

E1, E2, E3. See also `../constraints.md` (OP_RETURN, used by E4.2).

**Estimate:** 5. **Labels:** enabler, P0, lbc.
