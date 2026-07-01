# E11 scope & known constraints

## What this epic is

The happy path (LP fronts → bridge reimburses LP, proven in E4.3) is one of several
outcomes. E11 builds the **non-happy paths** — everything that happens when a deposit is
not served cleanly — with a deliberate scope boundary:

- **In scope now (address-safe): the RBTC rail.** All settlement/distribution logic that
  runs *on RSK* after the bridge releases funds to the LBC: forwarding to the user when no
  LP fronted, triggering the global slash, SC-call-revert refunds, and the permissionless
  resolve/watchtower incentive. **None of this touches the deposit-address derivation, so
  none of it changes the static BTC address.**
- **Deferred to last (address-rotating): the BTC refund field decision (E11.5).** Choosing
  what 21-byte value goes in `userRefundBtcAddress` / `liquidityProviderBtcAddress`
  (federation sink vs computed vs user-supplied) **is hashed into the derivation and rotates
  every deposit address.** It is parked as the final, non-blocking story so the RBTC-rail
  work can proceed without churning addresses, and the address-changing decision is made
  once, late, before any address is published for real.

## The funds model (the thing to keep straight while reviewing)

Almost nothing is stored in the contract:

- The RBTC the **user** receives is fronted from the **LP's own wallet** (`msg.value` on
  `requestPegIn`, forwarded to the user in the same tx; enforced by `IncorrectFronting`).
- The RBTC that **reimburses the LP** comes from the **bridge** (the user's own deposited
  BTC, released to the LBC at `resolvePegIn`; contract balance `0 → amount`).
- The only pre-stored funds are **LP collateral**, used for slashing only, never to fund a
  peg-in.

Net: the LP is a *bridge-of-time*. The user is always made whole from their **own** deposit;
LP fronting only buys speed (few confs vs ~100). A slash punishes LPs for the delay, it does
not cover a shortfall.

## The two refund rails (mutually exclusive)

| Rail | Mover | Fires when | Lands |
|------|-------|-----------|-------|
| **RBTC** | LBC, on RSK | after a **successful** bridge settlement | user `rskAddr` / LP reimbursement (contract-controlled) |
| **BTC** | federation, on Bitcoin | only on bridge **rejection** (locking-cap breach) | the 21-byte refund field (the placeholder) — leaves RSK |

A peg-in takes one rail or the other, never both. E11.1–E11.4 are the RBTC rail. The BTC rail
matters only on the cap-breach edge and is addressed by E11.5 plus the locking-cap gate.

## "All LPs fail" is the RBTC rail, not a native peg-in

The deposit sits at a flyover-derived address (`… ‖ OP_DROP ‖ powpegRedeemScript`) that is
federation-controlled and redeemable **only** via `registerFastBridgeBtcTransaction`. If no
LP fronts, a watchtower (or anyone) still calls `resolvePegIn` — the same fast-bridge
settlement — the bridge releases RBTC to the LBC, and the LBC forwards it to the user's
`rskAddr`. The user never "goes through the native powpeg."

**The one true failure mode:** if nobody ever calls `resolvePegIn`, the coins stay stuck at
the federation address. This is why the watchtower is incentivized (E11.4).

## Built vs designed (entering E11)

| Behavior | Status |
|----------|--------|
| Happy path: LP fronts → bridge reimburses LP | built & proven (E4.3) |
| No-claimer → forward to user's `rskAddr` | **not built** → E11.1 |
| Unclaimed past deadline → `globalSlash` | specced E4.4, `globalSlash` exists (E3), **not wired** → E11.2 |
| SC-call reverts → refund | partial (E4.2) → E11.3 |
| Permissionless resolve / peg-in watchtower incentive | **not built** → E11.4 |
| BTC refund field solution | **open decision, deferred** → E11.5 |

## Source

`POC-FINDINGS.md`, proposal "Negative scenarios" (peg-in), proposal "New role: Flyover
Watchtower", and the refund-paths analysis captured in `VALIDATION-GUIDE.html` §G.
