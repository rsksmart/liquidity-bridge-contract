# E11.5 BTC refund field decision (DEFERRED — do last)

**Epic:** E11 Peg-in refund & non-happy-path settlement (Peg-in track)
**Type:** Spike + Enabler · **Address impact:** ROTATES THE DEPOSIT ADDRESS · **Blocking:** none

> **Deferred deliberately.** This is the only part of the refund work that changes the static
> BTC address, because `userRefundBtcAddress` / `liquidityProviderBtcAddress` are hashed into
> the derivation (`derivationValue = keccak256(argsHash ‖ userRefundBtc ‖ lbc ‖ lpBtc)`).
> Doing it rotates **every** deposit address — the same class of event as a federation change,
> handled by `registrationRoot` + re-derivation. It does **not** block E11.1–E11.4 (RBTC
> rail), so it is parked here to be decided once, late, before any address is published for
> real. After mainnet it becomes a migration event.

## Problem

The bridge's fast-bridge derivation requires two well-formed 21-byte BTC addresses. Legacy
filled them from the quote (real user + real LP). The redesign deleted the quote, so there is
nothing real to put there. The value must be reproducible at derive- and settle-time and the
LP-slot must be LP-agnostic (the user pays before any LP is chosen). This field is used by the
bridge on **only one branch**: the locking-cap rejection (the BTC rail).

## Candidate solutions (from the five-agent study)

1. **Computed from `rskAddr`** (store nothing). 🟡 smallest; refund lands at an unspendable
   address (funds lost) — but that branch is unreachable for a served deposit. Proven P2PKH
   version byte.
2. **User-supplied refund address** (per-user, SPV-bound at registration). 🟡 recoverable to
   the user; re-opens a front-first double-spend on the cap-breach branch; needs a locking-cap
   gate + interface change; ~1.5 wk.
3. **Federation-derived sink** (read `getActivePowpegRedeemScript` live; hash to 21 bytes).
   🟢🟡 nothing stored; refunds route back into federation custody (recoverable); smallest diff
   (reuses `flyoverScriptHash`); adds no new federation-change fragility. Gate: confirm the
   bridge accepts + can pay a **P2SH-versioned** refund field.
4. **Alternative bridge entrypoint.** 🔴 none exists in rskj 9.x (source-grounded, VETIVER-9.0.2).
5. **Drop fast-bridge settlement.** 🔴 kills the per-user derived address, no latency gain,
   2–4 wk rewrite.

## Recommendation

Adopt **Solution 3 (federation sink)** with **Solution 1 (computed) as fallback**, gated on a
~1–2h spike:
1. Confirm a 21-byte **P2SH-versioned** field settles the success path (length-only gate per
   VETIVER-9.0.2 source, so near-certain).
2. Force the cap-breach refund branch and confirm the BTC lands at the federation P2SH
   (recoverable) vs. reverts.

Pair with the **locking-cap headroom check in `requestPegIn`** so the cap-breach branch is
unreachable for any deposit an LP actually fronts (belt-and-suspenders regardless of the field
choice).

## Acceptance criteria

- Spike outcomes (1) and (2) recorded in a decision note (like `decision-settlement-derivation.md`).
- Chosen scheme implemented in `PegInDerivation.sol` + the two callers
  (`PegInAddressRegistry`, `PegInContract._settleWithBridge`); no static BTC address in
  contracts or configs.
- Registry-derived address == bridge-derived address end-to-end on regtest.
- Locking-cap headroom check added to `requestPegIn`.
- The address rotation is announced/coordinated (no real published address relies on the old
  scheme).

## Depends on

EB (derivation library), E11.1 (so the RBTC rail already covers the common refund). Do LAST.

**Estimate:** 5 (spike S + change S). **Labels:** spike, enabler, P2, lbc, address-rotating.
