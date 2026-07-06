# EB.1 Resolve deposit-address vs fast-bridge derivation (design spike)

**Epic:** EB Settlement-compatible address derivation (Foundation track, P0 blocker)
**Type:** Story (design spike, human-decided)

## Statement

As an architect, I want a decided approach to the conflict between the registry's deterministic deposit-address derivation and the native fast-bridge settlement derivation, so that `resolvePegIn` can release funds and the LP is reimbursed, without giving up the LP-agnostic "address from the RSK address" property.

## The conflict (from POC-FINDINGS.md, finding B)

- `getPegInAddress` derives the P2SH from `derivationValue = keccak256("FLYOVER_PEGIN_V1", rskAddr)` wrapped around the powpeg redeem script.
- The bridge's `registerFastBridgeBtcTransaction` derives its flyover address from a hash of `(derivationArgumentsHash, userRefundBtcAddress, lbcAddress, liquidityProviderBtcAddress)`.
- They differ, so the bridge re-derives a different address, finds no matching UTXO, and returns `-900`. The user is served (LP fronts RBTC) but the LP cannot recover from the bridge.

## Output (the deliverable)

A decision record `decision-settlement-derivation.md` that:

1. States the EXACT bridge derivation (confirmed from powpeg-node/bridge source or empirically), especially how `userRefundBtcAddress` / `lbcAddress` / `liquidityProviderBtcAddress` enter the hash.
2. Evaluates the options and picks one, with rationale and tradeoff.
3. If the chosen option is validated on regtest (a real `resolvePegIn` settles), records that proof.

## Options to evaluate

1. **Placeholder-consistency (test first; the proposal hints "use placeholder refund addresses").** Derive `getPegInAddress` the bridge's way, using FIXED placeholder values for `userRefundBtcAddress` / `lbcAddress` / `liquidityProviderBtcAddress`, and have `resolvePegIn` pass the same placeholders. If the bridge accepts a fixed (LP-independent) `liquidityProviderBtcAddress`, the address is both deterministic-from-RSK-address and LP-agnostic and settlement-compatible. Lowest-cost if it works.
2. **Alternative settlement.** Do not rely on the native fast bridge for LP reimbursement; the LP recovers via a native peg-in plus LBC-internal accounting/refund. Preserves the address scheme; changes economics/latency and adds contract logic.
3. **Bridge change.** ~~Extend the RSK bridge~~ — **RULED OUT by directive (2026-06-30): do not edit powpeg/bridge code; work around the bridge as-is.**

**Primary hypothesis (option 1):** the LBC *legacy* (quote-based) flow already derives a bridge-compatible address — the bridge derives its flyover address from `keccak256(derivationArgumentsHash, userRefundBtcAddress, lbcAddress, liquidityProviderBtcAddress)` and the legacy `getDerivationValueHash` mixes the same inputs. So make `getPegInAddress` derive the address the bridge's way, using a `derivationArgumentsHash = keccak256(DOMAIN, rskAddr)` plus FIXED protocol-wide placeholder values for `userRefundBtcAddress` / `liquidityProviderBtcAddress` (and the real `lbcAddress`), and have `resolvePegIn` pass the identical placeholders. That keeps the address deterministic-from-RSK-address and LP-agnostic while matching what the unmodified bridge expects. Prove it by a regtest `resolvePegIn` that settles.

## Acceptance criteria

- The exact bridge derivation is documented and cited.
- Option 1 is prototyped on regtest (derive with placeholders, fund, `resolvePegIn`) and either validated (bridge settles) or shown to fail with the reason.
- A single approach is chosen with rationale and tradeoff, and the LP-agnostic property is either preserved or its loss explicitly accepted and justified.

## Children

Tasks: see `tasks/`. Tests: see `tests/`.

## Feeds / blocks

Unblocks `resolvePegIn` completion, the peg-out track (E7, E8, E9 settle through the same bridge), and prod. Implementation stories (EB.2+) are defined from this decision.

## Depends on

E0. Builds on the live PoC (E2/E4 deployed).

**Estimate:** 5. **Labels:** story, design, lbc, blocker.
