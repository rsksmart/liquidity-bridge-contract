# Flyover DoS-removal PoC: findings

**Date:** 2026-06-30 · **Status:** PoC success metric achieved, with two design findings.

## Success metric: achieved on a live regtest

Both criteria were proven on a live regtest (rskj **9.0.2**, real powpeg bridge precompile, contracts deployed and wired from the `dos-removal` worktrees):

1. **Static BTC address generation.** `PegInAddressRegistry.getPegInAddress(rskAddr)` derives a deterministic P2SH from the RSK address against the live powpeg redeem script. Example: `0x…DeaDBeef → 2Mt3h3W9hXiHtvCAjbroKm1cnPvfCWPy8Yj`. Deterministic across calls; changes only on a federation change.
2. **A successful commit-first peg-in.** End to end: derive address → fund 1.0 BTC to it → mine → on-chain registration gated by a real SPV proof the bridge validated (11 confirmations) → LP claim. The user RSK address balance went `0 → 998900000000000000` wei (**0.9989 RBTC = amount − fee**), verified on-chain. The LP fronted the RBTC from its own wallet; no off-chain quote or reservation was involved.

The DoS is structurally closed in the implemented flow: the LP commits liquidity only against an on-chain user commitment, and the off-chain accept-time reservation was removed from LPS.

## Finding A — `requestPegIn`'s confirmation check must take a full SPV proof (fixed)

`PegInContract._confirmationsFor` called the bridge hash-only: `getBtcTransactionConfirmations(txHash, bytes32(0), 0, [])`. The rskj bridge has **no by-hash transaction index** — that form returns `-1` on **both 9.0.1 and 9.0.2**. The unit tests passed only because `BridgeMock.getBtcTransactionConfirmations` ignores its arguments. Against the real bridge, the claim reverted `InsufficientConfirmations(0,1)`.

**Fix:** the canonical claim now takes the full SPV proof `(btcBlockHash, merkleBranchPath, merkleBranchHashes)` and reads confirmations via the bridge's full-proof path. Byte order matters: the bridge wants **big-endian (display) order** for `txHash`, `blockHash`, and the branch hashes (RSK-internal little-endian returns `-1`/`-5`).

## Finding B — `resolvePegIn` cannot settle: derived address ≠ fast-bridge address (FIXED, EB.1)

**RESOLVED on live regtest (2026-06-30).** The fix is the option-1 derivation from
`EPICS/FOUNDATION/EB-settlement-address-derivation/01-derivation-mismatch-spike/decision-settlement-derivation.md`,
now implemented in the REAL contracts via the shared `src/libraries/PegInDerivation.sol`:
`PegInAddressRegistry` derives, and `PegInContract._settleWithBridge` settles against, the SAME
bridge-compatible **PLAIN P2SH** whose 32-byte tag is
`keccak256(keccak256("FLYOVER_PEGIN_V1", rskAddr) ++ REFUND_PLACEHOLDER ++ bytes20(pegInContract) ++ LP_PLACEHOLDER)`,
with `shouldTransferToContract=true`. Proven end-to-end: deposit to `getPegInAddress` →
`resolvePegIn` bridge result **+1e18**, PegInContract balance **0 → 1e18**, LP reimbursed
`fronted + fee` (settle tx `0x174ab0df7cc86648a40d9b36da95fd4dacf2f18c135606141d532b7d1363c7de`),
re-resolve reverts `PegInAlreadyProcessed`. No powpeg/rskj/bridge edit. The original analysis is kept
below for context.

Original (pre-fix) symptom: `resolvePegIn` reverted `BridgeSettlementFailed(-900)`
(`FAST_BRIDGE_GENERIC_ERROR`). Root cause was an architectural mismatch between the redesign's
address scheme and the native fast bridge:

- **Registry (E2) derivation:** `keccak256(DERIVATION_DOMAIN, rskAddr)` as the derivation value, wrapped around the powpeg redeem script → the P2SH the user actually pays.
- **Native fast-bridge derivation** (`registerFastBridgeBtcTransaction`): derives its federation/flyover address from `(userRefundBtcAddress, lbcAddress, lpBtcAddress, derivationArgumentsHash)`.

These are different constructions, so the bridge re-derives a **different** address than the one that received the deposit, finds no matching UTXO, and refuses to release funds. The user still receives RBTC (the LP fronts it), but **the LP cannot recover it from the bridge** under the current scheme.

This is the central tension of the redesign: the "stable address derived from the RSK address" — the feature that fixes institutional whitelisting and removes per-quote addresses — is, as derived, **incompatible with the bridge's fast-bridge settlement**. Options to resolve (design decision, not yet made):

1. Derive the deposit address from the exact inputs the bridge expects, so `getPegInAddress` and `registerFastBridgeBtcTransaction` agree on the same address (constrains the "from RSK address only" property).
2. Change the settlement path so the LP recovers funds without relying on the native fast-bridge derivation (e.g. a native peg-in plus an LBC-internal accounting/refund), accepting different economics/latency.
3. Extend the RSK bridge to accept the new derivation (powpeg/node change; long lead time).

This belongs back in the threat-model / redesign-proposal discussion before peg-out (E7+) and production.

## Operational notes (regtest)

- **Use rskj 9.0.2, not 9.0.1**, and always the **real bridge precompile** (`0x…1000006`), never a `BridgeMock` — LBC `getLocalConfig`/`getFlyoverLocalConfig` patched so chainId 33 always uses the precompile.
- **Deploy reliability:** `forge script` batched broadcasting is unreliable on this rskj (address-prediction drift; phantom contracts). Deploy **one contract per script with `--slow`**, read the real address from the broadcast artifact, and verify code (retry on cold-start miss). `forge create` and single `cast send` txs are reliable.
- Registration deposit-gating is **read-only** (parse outputs + match derived P2SH + bridge `getBtcTransactionConfirmations`); it never calls the consuming `registerFastBridgeBtcTransaction`, which is owned solely by `resolvePegIn`.
