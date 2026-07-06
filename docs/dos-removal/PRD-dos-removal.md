# PRD: Flyover liquidity-DoS removal (Proof of Concept)

**Status:** Draft for review
**Owner:** Francis Rodriguez
**Date:** 2026-06-28
**Sources:** approved threat model, redesign proposal, Q2 OKRs, Q2 tech plan
**Target:** Proof of Concept on regtest. Mainnet hardening and full economic calibration are out of scope (see Non-goals).

---

## 1. Executive summary

**Problem.** Flyover reserves an LP's liquidity when a user accepts a quote off-chain, before the user commits any capital. An attacker accepts genuine quotes and never funds them. That locks an LP's liquidity for the full expiry window at zero cost, and the attacker repeats it. A single attacker can keep an LP dark indefinitely, and with few LPs the service goes down.

**Solution.** Remove off-chain negotiation. The user commits on-chain first: BTC to a deterministic deposit address for peg-in, RBTC to an escrow for peg-out. LPs then detect that commitment and compete to serve it. No liquidity is reserved before the user commits, so the attack has nothing to spam.

**Success criteria (PoC).**

1. Running the accept-spam attack against the regtest stack leaves the LP's available liquidity unchanged, because no off-chain reservation path remains.
2. A peg-in completes commit-first on regtest: the user sends BTC to an address derived from their RSK address, an LP claims and settles, and the user receives RBTC.
3. A peg-out completes commit-first on regtest: the user deposits RBTC to the escrow, an LP claims and delivers BTC, and the LP recovers RBTC by SPV proof.
4. For one RSK address, the deposit address stays identical across repeated peg-ins and changes only on a federation change (whitelist once).
5. No user-facing time window exists that can expire during an hours-long signing cycle.

---

## 2. User experience and functionality

### Personas

- **Retail user.** Converts BTC and RBTC through Flyover, and signs in seconds.
- **Institutional user.** Moves funds from multisig custody. Signing and treasury sign-off take hours.
- **Liquidity Provider (LP).** Holds BTC and RBTC, earns fees by serving operations, and posts collateral.
- **Watchtower operator.** A third party, possibly an LP, who registers addresses and executes refunds for a reward. This is a new role.
- **Attacker.** The adversary from the threat model. Listed so the security stories below have an explicit subject.

### User stories and acceptance criteria

**S1. Commit-first peg-in.** As a user, I want to send BTC first and have an LP serve me, so that I never negotiate or wait on a reservation.

- The user obtains a BTC deposit address derived from their RSK address, with no quote and no LP round-trip.
- After the BTC confirms, an authorized LP claims the peg-in and the user receives RBTC minus fees.
- The service fee and required confirmations come from on-chain configuration, not from a negotiated quote.

**S2. Commit-first peg-out.** As a user, I want to deposit RBTC into an escrow and have an LP deliver BTC, so that I commit before any LP does.

- The user calls `requestPegOut` and deposits RBTC. The request is visible on-chain.
- An LP claims the request, delivers BTC to the destination, and recovers the RBTC by SPV proof.
- If no LP claims by the deadline, the user is refunded and all registered LPs are slashed.

**S3. Stable institutional address.** As an institutional user, I want one deposit address I can whitelist once, so that custody approval is not repeated per transfer.

- The address derived for a given RSK address is identical across peg-ins.
- The address changes only when the powpeg federation composition changes, the same as the native peg-in address today.

**S4. No expiring window (institutional).** As an institutional user signing over hours, I want no time window that can expire mid-signing, so that I am never silently dropped to the slow native peg.

- The user commitment carries no `timeForDeposit`. The signing phase sits entirely outside the service model.

**S5. Attack yields nothing (security).** As the protocol, I want quote acceptance to reserve nothing, so that the accept-spam attack cannot lock liquidity.

- No code path reserves liquidity before an on-chain user commitment.
- An attack script that requests and "accepts" repeatedly leaves available liquidity unchanged and costs the LP nothing.
- Requirements R1 to R6 from the threat model each hold, verified case by case.

**S6. Institutional self-registration (one path).** As an institutional user without RBTC, I want to register my address without trusting a single LP, so that I can onboard independently.

- One registration path works end-to-end on regtest: either a Watchtower or the RIF Relay smart wallet, chosen in Phase 0.
- Registration is gated on a confirmed BTC deposit, so it cannot be spammed cheaply.

### Non-goals (this PoC)

- Full economic calibration of fees, slash amounts, deadlines, and collateral through modeling. The PoC uses minimal viable values and flags calibration as later work.
- Mainnet deployment and production hardening.
- Removing the quote structure everywhere in the codebase. The PoC keeps internal quote types where removing them adds risk without proving the concept.
- Building both institutional paths. The PoC ships one.
- Passive-LP yield, commit-reveal for claim races, and UI work beyond the SDK.

---

## 3. Technical specifications

### Architecture overview

The redesign replaces off-chain negotiation with on-chain commitment and event-driven service across three layers.

- **Contracts (LBC, Foundry).** Add `FlyoverConfigurations` for fees, confirmations, deadlines, limits, and time-locked setters. Add `PegInAddressRegistry` for the deterministic address, the `registrationRoot` running hash, and deposit-gated registration. Add `PegOutEscrow` for the `REQUESTED → CLAIMED → FULFILLED / CANCELLED / REFUNDED` state machine. Modify `PegInContract` to claim with `requestPegIn` and `resolvePegIn`, where the LP fronts RBTC from its own wallet. Modify `CollateralManagement` to slash all registered LPs proportionally when no one serves a valid operation, with a no-penalty window after registration.
- **Server (LPS, Go).** Add watchers for the `AddressRegistered` and `PegOutRequested` events, plus Bitcoin monitoring of registered addresses. Claim work competitively through the contracts. Delete the off-chain liquidity reservation in `accept_pegin_quote.go` and `accept_pegout_quote.go`, and check liquidity only at claim time against the LP's own wallet.
- **Client (flyover-sdk, bridges-core-sdk).** Derive the deposit address from the registry, read fees from `FlyoverConfigurations`, build the BTC transaction with an optional `OP_RETURN` output for contract calls, and deposit peg-outs into the escrow.

### Integration points

- **Rootstock Bridge (PowPeg).** Confirmation checks and `registerFastBridgeBtcTransaction` settlement, unchanged in role.
- **Bitcoin network.** LPs monitor it for deposits to registered addresses.
- **MongoDB.** LPS state, repurposed from quote reservation to watched-set and claim tracking.
- **ethers and contract bindings.** Regenerated from the new ABIs.

### Security and privacy

The redesign closes the original attack and opens three vectors the PoC must track, all flagged in the threat model. First, bait peg-ins, where the fee floor is a security parameter. Second, bootstrap fragility with few LPs, mitigated by the grace window. Third, claim-and-fail griefing on peg-out, mitigated by revocable LP authorization and a sufficient individual slash. Parameter calibration that would set these safely is deferred, so the PoC states the values it uses and marks them provisional. The registration-authorization decision, an ECDSA signature versus any caller, is made in Phase 0 because it selects the institutional path.

---

## 4. Risks and roadmap

### Phased rollout

Each phase is small and ends in a demonstrable result. The phases organize into three tracks. A shared foundation is built once, then the peg-in and peg-out tracks proceed independently, each on its own branches and worktrees, each shipping its own milestone.

**Foundation track (built once, both tracks depend on it).**

- **Phase 0. Design lock.** Freeze the escrow state machine, the three contract interfaces, the provisional parameter set, and the registration-auth decision. Output: a short design note, no code.
- **Phase 1. `FlyoverConfigurations`.** Add the contract holding both peg-in and peg-out configuration. Both flows read it; neither edits it after this phase.
- **Phase 3. Global slash and grace window** in `CollateralManagement`. One mechanism both flows call.

**Peg-in track.**

- **Phase 2. `PegInAddressRegistry`.** Deterministic address from the RSK address, plus the running hash.
- **Phase 4. Peg-in claim flow.** `requestPegIn` and `resolvePegIn`, OP_RETURN, and race-revert.
- **Phase 5. LPS peg-in.** Event discovery and competitive claim. Remove the peg-in reservation.
- **Phase 6. SDK peg-in.** Derive the address and build the BTC transaction. Milestone A: peg-in DoS closed on regtest.
- **Phase 10a. Institutional registration.** One path, Watchtower or RIF Relay, end-to-end. Milestone C: whitelist-once demonstrated.

**Peg-out track.**

- **Phase 7. `PegOutEscrow`** contract and claim flow.
- **Phase 8. LPS peg-out.** Escrow-event watcher and claim.
- **Phase 9. SDK peg-out.** Deposit into the escrow. Milestone B: peg-out DoS closed on regtest.
- **Phase 10b. Watchtower honest refund.** The Watchtower executes `refundPegOut` on the LP's behalf when the LP stalls. Built only if the Watchtower path is chosen in Phase 0.

### Technical risks

- Provisional parameters could mask a vector the PoC then fails to surface. Mitigation: run the bait-peg-in case explicitly, even with uncalibrated values.
- Escrow race conditions could slip through. Mitigation: Phase 0 specifies every transition before Phase 7 starts.
- Quote-structure entanglement in LPS could widen Phases 5 and 8 beyond "small". Mitigation: keep internal quote types, and change only the reservation path.
