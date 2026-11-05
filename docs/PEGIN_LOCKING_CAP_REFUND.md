# Peg-in locking cap refund

This document records what happens when the RSK bridge refunds a commit-first peg-in because of its locking cap, and why the protocol accepts that the refunded BTC is burned.

## Rules

1. **The bridge refunds a deposit that would exceed the locking cap.** At `resolvePegIn`, the bridge returns -100 (refund to the user refund address) or -200 (refund to the liquidity provider address). The bridge marks the transaction as processed, so every later call returns -302.
2. **The contract settles the peg-in and pays nobody.** `resolvePegIn` marks the peg-in settled, emits `BridgeCapExceeded(pegInId, errorCode)`, and returns the code. The provider does not get back the RBTC it fronted at `requestPegIn`.
3. **The refunded BTC is burned.** Both refund addresses are the zero placeholders in `PegInDerivation` (`version ++ 20 zero bytes`). No private key can spend from them.

## When the bridge refunds

`BridgeSupport.verifyLockDoesNotSurpassLockingCap` (rskj) refunds when:

```
locked BTC + deposit > locking cap
```

The bridge computes the locked BTC as `21,000,000 BTC - bridge RBTC balance` (`getBtcLockedInFederation`, with `BridgeConstants.getMaxRbtc()` = 21,000,000 BTC).

The locking cap is 21,000,000 BTC on mainnet and testnet (`getLockingCap()` returns 2,100,000,000,000,000 satoshis). With that cap, the condition becomes:

```
deposit > bridge RBTC balance
```

| Value (mainnet, read on 2026-11-05) | Amount                      |
| ----------------------------------- | --------------------------- |
| Locking cap                         | 21,000,000 BTC              |
| Bridge RBTC balance                 | 20,998,865.17 RBTC          |
| Smallest deposit that is refunded   | more than 20,998,865.17 BTC |

No deposit can be that large, because that much BTC does not exist. So with the current cap, -100 and -200 cannot happen.

## Why the cap cannot go down

`LockingCapSupportImpl.increaseLockingCap` (rskj) rejects a new value that is lower than the current cap. Only a change to RSKj consensus (a network upgrade) can lower the cap or change the check.

These values were read from RSKj 9.0.3 (`VETIVER-c19cf12`), which mainnet and testnet run, and `master` has the same code.

## Accepted risk

The protocol accepts that a refund burns the BTC. The reasons:

- With the current cap, a refund cannot happen (see above).
- The refund addresses are mixed into the deposit address, and the deposit address must be the same whichever provider serves the peg-in. So the refund addresses cannot be the serving provider's address.

Revisit this decision if a network upgrade lowers the locking cap or changes the check. Before such an upgrade activates, replace the zero placeholders with recoverable addresses. A placeholder change rotates every derived deposit address (see `PegInDerivation`).
