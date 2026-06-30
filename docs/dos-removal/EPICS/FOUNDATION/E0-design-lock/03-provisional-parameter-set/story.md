# S0.3 Provisional parameter set

**Epic:** E0 Design lock
**Story:** As the protocol owner, I want a provisional parameter table, so that the build epics have concrete values and the bait-peg-in vector is sanity-checked.

## Decision (locked 2026-06-28)

**Decision:** adopt the following provisional set for the PoC. All values are regtest placeholders and are adjustable for prod through the E1.5 time-locked setters, with full calibration deferred to a later PRD.

| Parameter | Provisional value | Note |
|---|---|---|
| `fixedFee` (fee floor) | at least 3x measured worst-case regtest gas for `requestPegIn` + `resolvePegIn` | measured in this story's task; security gate |
| `percentageFee` | 0.1% (`10` on the `10000 = 100%` scale) | |
| individual slash (`penaltyFee`) | 0.01 RBTC | post-claim LP failure |
| global slash | one `penaltyFee` total, split proportionally across registered LPs | keeps the network-wide hit modest |
| `minCollateral` | reuse the current LBC value | |
| pre-claim deadline | 30 min | time for an LP to claim before global slash |
| `callTime` (LP action after claim) | 2 h | LP delivers BTC and submits proof |
| `expireTime` (refund-enable) | `callTime` + 30 min overlap buffer | strictly later than `callTime` per S0.2 |
| registration grace window (E3) | 100 blocks | no global slash for a freshly registered LP |
| delivery-grace tolerance (S0.1) | 2x `btcBlockTime` | absorbs BTC timestamp jitter, treats LP gently |
| confirmation tiers | small to 1, medium to 3, large to 6 | regtest-friendly low counts |

**Rationale:** the values are internally consistent (expire later than call, LP-side grace tolerances per the S0.1 and S0.2 decisions) and cheap to change, so they unblock E1, E3, and E4 without pretending to be calibrated.

**Tradeoff:** loose provisional values could mask a vector the PoC then fails to surface. We mitigate that two ways: the fee floor is gated on the measured worst-case gas, and the bait-peg-in case is run explicitly even with these uncalibrated values. The prod adjustment path is the E1.5 time-locked setters plus the calibration PRD.

## Output (the deliverable)

A markdown document `parameters.md` containing:

1. A parameter table with columns: parameter, provisional value, unit, rationale, source.
2. A bait-peg-in check comparing the fee floor against a worst-case regtest gas figure.
3. A header marking every value provisional and pointing to the later calibration PRD.

## Acceptance criteria

- The table fixes the fee floor, the global slash amount, the individual slash amount, the claim deadline, the fulfillment deadline, the minimum collateral, the grace-window length, and the confirmation tiers.
- Each value carries a one-line rationale.
- The fee floor is shown to exceed worst-case regtest gas for a peg-in, so a minimum-amount peg-in is not trivially unprofitable to serve.

## Children

Tasks: see `tasks/`. Tests: see `tests/`.

## Grounded in

Proposal "Next steps" (parameter calibration as critical pre-build work) and "Disadvantages" (fee-floor calibration, bootstrap fragility mitigated by a no-penalty window). Threat model section 8 (bait peg-ins make fee-floor calibration a security parameter). Current values for reference: `CollateralManagement` minimum collateral and reward percentage, per-quote `penaltyFee`, `depositConfirmations`.

## Feeds

E1 (FlyoverConfigurations), E3 (global slash and grace window), E4 (peg-in claim flow), E7 (PegOutEscrow).

## Depends on (within E0)

None. Best done alongside S0.2 so the values match the interface fields.

**Estimate:** 3. **Labels:** story, design.
