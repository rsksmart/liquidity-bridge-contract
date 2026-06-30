# Regtest commit-first peg-in — ordered runbook

These scripts drive a **commit-first peg-in** end to end against a live regtest, exactly
the flow that succeeded on 2026-06-30 (rskj **9.0.2**, real powpeg bridge precompile).
They are ordered `00`..`07`; run them in sequence. Values from the proven run are recorded
in `config.env` as a worked example.

## What this proves
- **Static address generation:** the deposit address is derived deterministically from the
  user's RSK address (`getPegInAddress`), stable across calls and re-deploys. The derivation is the
  bridge-compatible **PLAIN P2SH** built by the shared `PegInDerivation` library (EB.1).
- **A successful peg-in:** the user RSK address receives `amount - fee` RBTC, fronted by the LP
  after a real BTC deposit, a real SPV-gated registration, and the LP's claim.
- **A successful resolve (NEW):** `resolvePegIn` settles on the unmodified native fast bridge — the
  bridge releases the deposit to the LBC and the LP is reimbursed `fronted + fee`. Finding B is fixed.

## Prerequisites
- Core regtest up (rskj 9.0.1 will NOT work — use **9.0.2**; the bridge needs a real
  `getBtcTransactionConfirmations`). bitcoind `main` wallet funded; auto-tick running so the
  bridge ingests BTC headers.
- Contracts deployed + wired and an LP registered with collateral (see the deploy notes in
  `POC-FINDINGS.md`). Put the addresses in `config.env`.
- `foundry` (cast), `docker`, and Node with `@rsksmart/pmt-builder` (use the flyover-sdk
  node_modules: `export NODE_PATH=<repo>/flyover-sdk/node_modules`).

## Steps
| # | Script | Does |
|---|--------|------|
| 00 | `config.env` | addresses, keys, RPC, and the worked-example values |
| 00 | `bcli.sh` | bitcoin-cli wrapper for the core's bitcoind |
| 01 | `01-derive-address.sh` | `getPegInAddress(user)` -> base58 BTC deposit address |
| 02 | `02-fund-and-mine.sh` | send BTC to the deposit address; mine a single-tx block; capture txid/blockhash/rawtx/coinbase |
| 03 | `03-advance-bridge.sh` | mine BTC + RSK blocks until the bridge confirms the deposit; verify confirmations |
| 04 | `04-build-proof.js` | build the SPV proof (branch + path, **big-endian**) and the PMT for resolve |
| 05 | `05-register.sh` | `registerAddress(user, rawTx, blockHash, path, branch)` — read-only SPV deposit-gating |
| 06 | `06-request-pegin.sh` | LP fronts RBTC via the proof-based claim — **user receives `amount-fee`** |
| 07 | `07-resolve-pegin.sh` | `resolvePegIn` — **settles on the bridge; LP reimbursed** (finding B fixed) |

## Byte order (the hard-won detail)
The RSK bridge wants **big-endian (display) order** for txHash, blockHash, and branch hashes —
the order bitcoin-cli prints. RSK-internal little-endian returns `-1`/`-5`. Mine a block with
only coinbase + the deposit tx so the merkle branch is a single sibling (the coinbase txid),
path bit `1`.

## Findings (see ../../../POC-FINDINGS.md)
- **A (fixed):** the claim's confirmation check must pass a FULL SPV proof; the rskj bridge has
  no by-hash lookup. The original hash-only `requestPegIn` reverted `InsufficientConfirmations`.
- **B (FIXED, EB.1):** `resolvePegIn` now settles. The registry and `_settleWithBridge` share the
  `PegInDerivation` library: a PLAIN P2SH of the flyover redeem script whose 32-byte tag mixes
  `keccak256("FLYOVER_PEGIN_V1", rskAddr)` with the fixed REFUND/LP placeholder BTC addresses and
  the wired PegInContract (lbcAddress). The deposit address the user pays is byte-for-byte the
  address the bridge re-derives at settlement, so the bridge releases the funds (proven on regtest:
  bridge result `+1e18`, LBC balance `0 → 1e18`, LP reimbursed `fronted + fee`). No bridge/rskj edit.
