# Provisional parameters (PoC)

Output of S0.3. All values are regtest placeholders, adjustable for prod through the E1.5 time-locked setters, with full calibration deferred to a later PRD. Source: the locked S0.3 decision and the S0.1 and S0.2 decisions.

## Parameter table

| Parameter | Provisional value | Note |
|---|---|---|
| `fixedFee` (fee floor) | at least 3x measured worst-case regtest gas for `requestPegIn` + `resolvePegIn` | see the gas measurement below; security gate |
| `percentageFee` | 0.1% (`10` on the `10000 = 100%` scale) | |
| individual slash (`penaltyFee`) | 0.01 RBTC | post-claim LP failure |
| global slash | one `penaltyFee` total, split proportionally across registered LPs | keeps the network-wide hit modest |
| `minCollateral` | reuse the current LBC value | |
| pre-claim deadline | 30 min | time for an LP to claim before global slash |
| `callTime` (LP action after claim) | 2 h | LP delivers BTC and submits proof |
| `expireTime` (refund-enable) | `callTime` + 30 min overlap buffer | strictly later than `callTime` |
| `deliveryGrace` tolerance | 2x `btcBlockTime` | absorbs BTC timestamp jitter, treats LP gently |
| registration grace window | 100 blocks | no global slash for a freshly registered LP |
| confirmation tiers | small to 1, medium to 3, large to 6 | regtest-friendly low counts |

## Fee-floor gas check (security gate)

The fee floor is the one value with a security consequence: if it does not cover worst-case RSK gas, a bait-peg-in attacker can create minimum-amount peg-ins that no LP finds profitable to claim, triggering a global slash.

Procedure:

1. Measure gas for `requestPegIn` + `resolvePegIn` on regtest under load.
2. Multiply by the regtest gas price to get the worst-case cost.
3. Set `fixedFee` to at least 3x that figure.

## Bait-peg-in validation

Even with these uncalibrated values, run the bait-peg-in case explicitly: create minimum-amount peg-ins and confirm an LP still finds them profitable to claim, so no global slash is triggered by unserved minimum peg-ins.

## Prod adjustment path

Every value here is changeable on-chain through the E1.5 time-locked setters, bounded by the immutable deployment-time bounds. Final values come from the calibration PRD before prod.
