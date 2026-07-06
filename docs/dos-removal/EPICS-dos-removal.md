# EPICs: Flyover liquidity-DoS removal (PoC)

**Status:** Draft for review
**Owner:** Francis Rodriguez
**Date:** 2026-06-28
**Source:** [PRD-dos-removal.md](./PRD-dos-removal.md)
**Tracker:** JIRA FLY (epics not yet created)

Thirteen epics across three tracks. A shared foundation is built once, then the peg-in and peg-out tracks proceed independently, each on its own branches and worktrees. The epic folders live under `EPICS/FOUNDATION`, `EPICS/PEGIN`, and `EPICS/PEGOUT`. Each epic lists what it delivers, why, the acceptance criteria, dependencies, an estimate, and the PRD story it serves. Estimates use t-shirt sizes. Priority P0 marks the critical path that closes the peg-in DoS.

- **Foundation:** E0, E1, E3, EB.
- **Peg-in:** E2, E4, E5, E6, E10a, E11.
- **Peg-out:** E7, E8, E9, E10b.

> **EB is a P0 foundation blocker discovered by the PoC** (see `POC-FINDINGS.md`, finding B): the registry's deterministic address derivation is incompatible with the native fast-bridge settlement derivation, so `resolvePegIn` cannot release funds. EB gates `resolvePegIn` completion, the whole peg-out track (E7–E9 settle through the same bridge), and prod. Resolve EB before continuing E7+.

---

## E0. Design lock

**Delivers.** A short design note that freezes the peg-out escrow state machine, the three contract interfaces, the provisional parameter set, and the registration-auth decision. No code.

**Why.** Two open items gate every build epic, and the fee floor is a security parameter, not just an economic one.

**Acceptance criteria.**

- The escrow state machine lists every state, every permitted transition, and a resolution for each race named in the proposal.
- A provisional parameter table fixes fee floor, slash amounts, deadlines, and minimum collateral, each marked provisional.
- A decision record states whether registration requires an ECDSA signature or accepts any caller, which selects the institutional path in E10.

**Repos.** None (doc). **Serves.** All. **Depends on.** Nothing. **Blocks.** E1 to E10. **Estimate.** M. **Labels.** epic, P0, design.

---

## E1. FlyoverConfigurations contract

**Delivers.** A new `FlyoverConfigurations` contract in LBC holding both peg-in and peg-out configuration: fees (fixed floor plus percentage), confirmation tiers, deadlines, and limits, with time-locked setters. Both flows read it, and neither edits it after this epic.

**Why.** Removing the quote removes where these values lived, so they need an on-chain home both flows read. As a foundation contract, it holds both configurations once so the flow tracks only read it.

**Acceptance criteria.**

- `getPegInConfiguration` / `calculatePegInFee` and `getPegOutConfiguration` / `calculatePegOutFee` return the values their flows use.
- Setters apply only after a time lock, so a change cannot land mid-operation.
- Foundry tests cover fee calculation for both flows, confirmation tiers, and the time lock.

**Repos.** lbc. **Serves.** S1, S2. **Depends on.** E0. **Blocks.** E4, E5, E7. **Estimate.** M. **Labels.** epic, P0, lbc.

---

## E2. PegInAddressRegistry and deterministic address

**Delivers.** A `PegInAddressRegistry` contract deriving the BTC address from the registered RSK address, with the `registrationRoot` running hash, deposit-gated registration, and a federation-change policy.

**Why.** The per-quote address feeds the DoS and blocks institutions who cannot whitelist an address that changes every peg-in.

**Acceptance criteria.**

- `getPegInAddress` returns the same address across calls for one RSK address, and changes only on a federation change.
- An LP can rebuild its watch set from `AddressRegistered` events and match the on-chain `registrationRoot`.
- Registration succeeds only against a confirmed deposit.
- Foundry tests cover repeat derivation, a federation change, and the running-hash match.

**Repos.** lbc. **Serves.** S3, S4. **Depends on.** E0. **Blocks.** E4, E5, E6, E10. **Estimate.** L. **Labels.** epic, P0, lbc.

---

## E3. Global slash and grace window

**Delivers.** A proportional global slash across all registered LPs in `CollateralManagement`, plus a no-penalty window after registration. The existing individual slash stays for the post-claim case.

**Why.** The new model must penalize "no one served a valid operation," and the global slash creates bootstrap fragility that the grace window offsets.

**Acceptance criteria.**

- An unserved valid operation slashes all registered LPs proportionally.
- An LP registered within the window is not slashed.
- Foundry tests cover the few-LP bootstrap case and the window boundary.

**Repos.** lbc. **Serves.** S2, S5. **Depends on.** E0. **Blocks.** E4, E7. **Estimate.** M. **Labels.** epic, P0, lbc.

---

## E4. Peg-in claim flow

**Delivers.** `requestPegIn` and `resolvePegIn` in `PegInContract`, where the LP fronts RBTC from its own wallet, the claimer earns the full fee, an unclaimed valid peg-in triggers the global slash, `OP_RETURN(destContract, maxGas, callData)` carries contract-call data, and a second claim reverts on the first line.

**Why.** This is the peg-in half of user-commits-first on-chain.

**Acceptance criteria.**

- An LP claims a confirmed peg-in and the user receives RBTC minus fees, with no quote involved.
- A second claim on the same peg-in reverts cheaply.
- A smart-contract peg-in driven by `OP_RETURN` calls the destination with the carried data.
- An unclaimed valid peg-in triggers the global slash from E3.

**Known constraint.** The `OP_RETURN` standard ~80-byte limit caps SC-call calldata to roughly 28 bytes after the destination and max-gas fields. See `EPICS/PEGIN/E4-pegin-claim-flow/constraints.md`.

**Repos.** lbc. **Serves.** S1, S5. **Depends on.** E1, E2, E3. **Blocks.** E5, E6. **Estimate.** L. **Labels.** epic, P0, lbc.

---

## E5. LPS peg-in: event discovery and competitive claim

**Delivers.** Watchers in LPS for `AddressRegistered` with a `registrationRoot` check, Bitcoin monitoring of registered addresses, a competitive claim through `requestPegIn`, and removal of the off-chain reservation in `accept_pegin_quote.go`.

**Why.** The DoS dies here. Once LPS commits liquidity only against an on-chain commitment, the attack has nothing to spam.

**Acceptance criteria.**

- LPS claims a confirmed peg-in it discovered from events and the chain, with no user accept call.
- The accept-quote reservation path is gone, and liquidity is checked only at claim time against the LP wallet.
- The accept-spam attack leaves available liquidity unchanged (PoC success criterion 1).

**Repos.** lps. **Serves.** S5. **Depends on.** E4 (uses E1, E2). **Blocks.** Milestone A. **Estimate.** L. **Labels.** epic, P0, lps.

---

## E6. SDK peg-in: derive address and build the BTC transaction

**Delivers.** `flyover-sdk` fetches the deposit address from the registry and re-derives on a federation change, reads fees from `FlyoverConfigurations`, and builds the BTC transaction with an optional `OP_RETURN` output. `bridges-core-sdk` gains any missing BTC tx-build helpers.

**Why.** The client must commit on-chain first instead of negotiating.

**Acceptance criteria.**

- An integration test completes a peg-in commit-first against regtest with E4 and E5.
- The SDK re-derives a stale address after a simulated federation change.
- A contract-call peg-in produces a correct `OP_RETURN` output.

**Known constraint.** The `OP_RETURN` standard ~80-byte limit caps the calldata the SDK can build into a SC-call peg-in. Validate and fail early above the cap. See `EPICS/PEGIN/E6-sdk-pegin/constraints.md`.

**Repos.** flyover-sdk, bridges-core-sdk. **Serves.** S1. **Depends on.** E4 (uses E2). **Completes.** Milestone A: peg-in DoS closed on regtest. **Estimate.** M. **Labels.** epic, P0, sdk.

---

## E7. PegOutEscrow contract and claim flow

**Delivers.** A `PegOutEscrow` contract with the E0 state machine: `requestPegOut` (payable, user-first), `claimPegOut` with a signature that moves RBTC to `PegOutContract`, `cancelPegOut`, a global slash before claim, and an individual slash after. The existing SPV refund path is reused post-claim.

**Why.** This is the peg-out half of user-commits-first.

**Acceptance criteria.**

- A user deposits RBTC with `requestPegOut`, an LP claims and the responsibility is recorded on-chain.
- An unclaimed request past its deadline refunds the user and global-slashes registered LPs.
- The documented races resolve as specified in E0.

**Repos.** lbc. **Serves.** S2. **Depends on.** E1, E3 (uses E0). **Blocks.** E8, E9. **Estimate.** L. **Labels.** epic, P1, lbc.

---

## E8. LPS peg-out: escrow watcher and claim

**Delivers.** A `PegOutRequested` watcher in LPS, a claim through `claimPegOut`, BTC delivery, SPV refund, and removal of the off-chain reservation in `accept_pegout_quote.go`.

**Why.** Closes the peg-out DoS on the server side.

**Acceptance criteria.**

- LPS claims an escrow request it discovered from events, delivers BTC, and recovers RBTC by SPV proof.
- The peg-out accept-quote reservation path is gone.

**Repos.** lps. **Serves.** S5. **Depends on.** E7. **Blocks.** Milestone B. **Estimate.** M. **Labels.** epic, P1, lps.

---

## E9. SDK peg-out: deposit into the escrow

**Delivers.** `flyover-sdk` calls `requestPegOut` on the escrow instead of negotiating a quote, and reads peg-out fees from `FlyoverConfigurations`.

**Why.** The client must deposit to escrow first.

**Acceptance criteria.**

- An integration test completes a peg-out commit-first against regtest with E7 and E8.

**Repos.** flyover-sdk, bridges-core-sdk. **Serves.** S2. **Depends on.** E7. **Completes.** Milestone B: peg-out DoS closed on regtest. **Estimate.** S. **Labels.** epic, P1, sdk.

---

## E10a. Institutional registration path (peg-in track)

**Delivers.** One registration path chosen in E0, either a Watchtower service or the RIF Relay smart wallet, working end-to-end on regtest, with the contract and SDK support it needs.

**Why.** Some custody accounts cannot sign the way registration expects, so they need a self-serve or sponsored path.

**Acceptance criteria.**

- A user without RBTC registers an address end-to-end on regtest through the chosen path.
- Registration stays gated on a confirmed BTC deposit.

**Repos.** new service or lbc plus sdk. **Serves.** S6. **Depends on.** E0, E2. **Completes.** Milestone C: whitelist-once demonstrated. **Estimate.** L. **Labels.** epic, P2, institutional.

---

## E10b. Watchtower honest refund (peg-out track)

**Delivers.** The Watchtower executes `refundPegOut` on the LP's behalf when the LP stalls, earning a reward. Built only if the Watchtower path is chosen in E0.

**Why.** A user can attack an LP's availability after delivery to force a refund and duplicate funds. A third party incentivized to submit the proof closes that window.

**Acceptance criteria.**

- When an LP delivers BTC but does not submit the proof, the Watchtower submits `refundPegOut` and receives a reward.
- The contract pays the caller a reward in this scenario, not only in the penalizable one.

**Repos.** new service plus lbc. **Serves.** S2. **Depends on.** E0, E7. **Estimate.** M. **Labels.** epic, P2, institutional.

---

## EB. Settlement-compatible address derivation (Foundation, P0 blocker)

**Delivers.** A resolution to the conflict between the registry's deterministic deposit-address derivation and the native fast-bridge settlement derivation, so `resolvePegIn` can actually release funds and the LP is reimbursed.

**Why.** Discovered by the PoC (`POC-FINDINGS.md`, finding B). The bridge's `registerFastBridgeBtcTransaction` folds `(userRefundBtcAddress, lbcAddress, lpBtcAddress)` into the flyover derivation hash; `getPegInAddress` uses only `keccak256("FLYOVER_PEGIN_V1", rskAddr)`. The addresses differ, so the bridge finds no matching UTXO (returns -900). The user is served (LP fronts RBTC) but the LP cannot recover from the bridge. The LP-agnostic "address from RSK address" premise is in tension with the bridge requiring `lpBtcAddress` in its derivation.

**Acceptance criteria.**

- A design decision is recorded choosing the approach (see the spike), with rationale and tradeoff.
- After implementing it, a live regtest `resolvePegIn` settles successfully (bridge releases funds, LP reimbursed) for a peg-in to a registry-derived address.
- The deposit address stays deterministic from the RSK address and servable by any authorized LP (or the decision explicitly accepts a documented constraint).

**Work items.** EB.1 design spike (decide), then implementation stories TBD from the decision.

**Repos.** lbc (likely); possibly powpeg/bridge if option 3 is chosen. **Serves.** S1, S2 (settlement). **Depends on.** E0. **Blocks.** `resolvePegIn` completion, E7, E8, E9, prod. **Estimate.** spike S, implementation TBD. **Labels.** epic, P0, lbc, design, blocker.

---

## E11. Peg-in refund and non-happy-path settlement (RBTC rail)

**Delivers.** The peg-in behaviors beyond the proven happy path: settling to the user when no LP fronted, wiring the unclaimed global slash, SC-call-revert refunds, and a permissionless resolve/watchtower incentive so a peg-in is never stuck. Splits cleanly into the **RBTC rail** (address-safe, built now) and a **deferred BTC refund field decision** (address-rotating, done last).

**Why.** The PoC proved only "LP fronts → bridge reimburses LP". The proposal's negative scenarios (no LP advances, SC-call reverts, nobody resolves) are specified but not built, and leaving them out means a user whose deposit no LP serves has no on-chain path to their funds. The RBTC rail does not touch the derivation, so it can ship without rotating the static BTC address; the BTC refund field decision does rotate it and is parked as the final, non-blocking story.

**Acceptance criteria.**

- No-claimer `resolvePegIn` forwards `amount − fee` to the user's `rskAddr` (E11.1).
- An unclaimed serviceable peg-in past its deadline triggers `globalSlash`; non-penalizable cases skip it (E11.2, realizes E4.4).
- A reverting SC-call peg-in still settles, refunds the user, and pays the LP its fee (E11.3).
- A third party can resolve/register an abandoned peg-in and earn the reward (E11.4).
- The BTC refund field scheme is decided by spike and implemented with no static address in contracts or configs (E11.5, deferred; rotates the deposit address).

**Work items.** E11.1 no-claimer forward-to-user, E11.2 wire unclaimed→global-slash, E11.3 SC-call-revert refund, E11.4 permissionless resolve/watchtower, E11.5 BTC refund field decision (DEFERRED — address-rotating, do last).

**Repos.** lbc, lps. **Serves.** S1, S2, S5. **Depends on.** E4 (happy path), E3 (globalSlash), E2 (registration). Aligns with E10b. E11.5 also depends on EB. **Blocks.** prod peg-in completeness. **Estimate.** L. **Labels.** epic, P0 (E11.1–E11.2) / P1–P2 (E11.3–E11.5), lbc, lps.

---

## Dependency summary

- **Foundation (built once):** E0, then E1 and E3 in parallel. Both tracks depend on this.
- **Peg-in track (after foundation, runs independently):** E2, then E4, then E5 and E6, reaching Milestone A. E10a follows (needs E2), reaching Milestone C.
- **Peg-out track (after foundation, runs independently):** E7, then E8 and E9, reaching Milestone B. E10b follows (needs E7) if the Watchtower path is chosen.
- **EB (P0 blocker, foundation):** must be resolved before the peg-out track and before `resolvePegIn` is production-usable. The PoC peg-in succeeds without it (the LP fronts RBTC), but LP reimbursement via the bridge does not. Resolve EB next.

Every epic carries acceptance criteria that trace to a PRD success criterion or story, so the epic layer stays anchored to the PRD.
