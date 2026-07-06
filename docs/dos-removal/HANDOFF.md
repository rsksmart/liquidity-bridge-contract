# Flyover liquidity-DoS removal — handoff

**Date:** 2026-06-30 · **State:** peg-in redesign complete and proven end-to-end on regtest; peg-out + institutional planned, not built.

## What was delivered

The off-chain quote-acceptance DoS is closed by a **commit-first peg-in**: the user commits BTC on-chain first (to a deterministic address derived from their RSK address), LPs detect it and compete to serve it, and no LP liquidity is reserved before the user commits. Proven end-to-end on a live regtest (rskj **9.0.2**, real powpeg bridge) with **no changes to the bridge or powpeg**.

Read `ARCHITECTURE.html` for the full picture; this file is the operational handoff.

## Where everything is

Working dir: `~/Documents/wk/flyover/flyover-dos-removal/` (worktrees + docs).

| Doc | Purpose |
|-----|---------|
| `ARCHITECTURE.html` | Architecture, step-by-step flow, and the old-vs-new "what changed" comparison. |
| `PRD-dos-removal.md` | Product requirements (PoC scope, success criteria, 10 phases). |
| `EPICS-dos-removal.md` | Epic breakdown (Foundation / Peg-in / Peg-out tracks + EB blocker). |
| `EPICS/` | Per-epic story/task/test folders (E0 decisions, E1, E3, E2, E4, EB spike + decision record). |
| `POC-FINDINGS.md` | The two findings (A: full SPV proof; B: bridge-compatible derivation) and regtest ops notes. |
| `lbc/script/regtest-pegin/` | Runnable, ordered `00`–`07` peg-in runbook (README + step scripts). |

## Commits (all on `dos-removal`, NOT pushed — per instruction)

- **lbc** (11): `8ed48ce` E1 → `271cb6d` E2 → `6b0e7d9` E3 → `ee3d4ef` E4 → bridge/deploy fixes → `55c4732` read-only SPV gating → `3ed2b5b` runbook → `dba49bd` requestPegIn full-proof → `59f1f28` EB bridge-compatible derivation. 698 Foundry tests green.
- **lps** (1): `04c87ef4` E5 — event discovery + claim; off-chain reservation removed. `go build ./...` + unit tests green.
- **flyover-sdk** (1): `39407de` E6. **bridges-core-sdk** (1): `be287fc` E6. Builds + tests green.

To publish when you're ready: `git -C <repo> push -u origin dos-removal` (nothing has been pushed).

## Proven on regtest (final EB.2 deployment)

Full cycle: derive → fund BTC → register (bridge confirmed 11 confs) → `requestPegIn` (user credited `amount − fee`) → **`resolvePegIn` settles** (bridge releases 1 RBTC to the LBC; LP `getBalance` = fronted + claimer fee + registrant fee); re-resolve reverts `PegInAlreadyProcessed`. Settle tx `0x174ab0df…63c7de`. Deployed addresses are in `lbc/script/regtest-pegin/config.env`. The stack is currently up; `flyover_down --wipe` tears it down.

## Open items / follow-ups

1. **Peg-out track (E7–E9)** and **institutional path (E10a/E10b)** — planned in `EPICS/`, not built. **Now unblocked** (EB solved the settlement-derivation problem peg-out shares). Start at E7 (`PegOutEscrow` + state machine).
2. **Production placeholders.** `REFUND_PLACEHOLDER_BTC` / `LP_PLACEHOLDER_BTC` in `src/libraries/PegInDerivation.sol` are regtest values; set them to a single protocol-owned, monitored BTC address before mainnet (the bridge's failure-refund path targets `REFUND_PLACEHOLDER_BTC`).
3. **Parameter calibration.** Fees, slash amounts, deadlines, grace window, confirmation tiers are provisional PoC values (time-locked, adjustable on-chain). Real calibration is deferred to a later PRD.
4. **E1 task specs are thin** (pre-droppable-standard); enrich before that contract is hardened.
5. **SDK/LPS register bindings** for `registerAddress` are stale vs the final signature — neither calls it on the peg-in critical path, but refresh before institutional work.
6. **Incidental:** `lbc/foundry.lock` + `package-lock.json` have uncommitted churn from agent `npm install` runs; review/discard as you prefer.

## How to resume

- Bring the env up: `flyover_core_up`, start `flyover_autotick`, then deploy per `POC-FINDINGS.md` ("Deploy reliability" — one contract per `forge script --slow`, read the real address from the broadcast artifact) and run `lbc/script/regtest-pegin/`.
- The initiative's context is in memory (`project_flyover_dos_removal`, `project_flyover_integration_branches`) for the next session.
