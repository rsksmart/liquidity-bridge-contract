# EB.1 Decision record — settlement-compatible peg-in address derivation

**Date:** 2026-06-30 · **Status:** RESOLVED on live regtest (option 1, with one extra correction). Human adoption decision pending.
**Constraint honored:** no edits to powpeg-node / rskj / the bridge. The bridge is used AS-IS; only our LBC contracts conform to it.
**Scope:** design spike + working regtest prototype. The prototype contracts (`src/PegInSettleProto.sol`, `src/PegInAddressRegistryV2Proto.sol`) are spike artifacts, NOT the production wiring.

---

## 1. The exact bridge derivation formula (cited from the legacy code that still settles)

The native fast bridge re-derives the *flyover deposit address* from the arguments passed to
`registerFastBridgeBtcTransaction`. The LBC **legacy** quote-based flow — which settled in
production against this same unmodified bridge — encodes the bridge's expected construction. Two
independent legacy citations agree byte-for-byte:

- `src/legacy/LiquidityBridgeContract.sol:798-812` (`validatePeginDepositAddress`)
- `src/legacy/LiquidityBridgeContractV2.sol:756-773` (`validatePeginDepositAddress`)

and the bridge call site is `src/legacy/LiquidityBridgeContract.sol:903-921` (`registerBridge`),
invoked from `registerPegIn` (`:528-534`) with `derivationHash = quoteHash`.

### 1a. The derivation value (the 32-byte tag mixed into the redeem script)

```
derivationValue = keccak256(
    derivationArgumentsHash      // = hashQuote(quote) in legacy; the value passed to the bridge
    ++ userRefundBtcAddress      // quote.btcRefundAddress  (21 or 33 bytes)
    ++ bytes20(lbcAddress)       // the LBC contract that CALLS registerFastBridgeBtcTransaction
    ++ liquidityProviderBtcAddress  // quote.liquidityProviderBtcAddress (21 bytes)
)
```

i.e. the bridge mixes the `derivationArgumentsHash` with the three address arguments. The
`derivationArgumentsHash` we pass to the bridge is the FIRST member of that concatenation; the
bridge does NOT use it as the redeem-script tag directly — it re-hashes it with the addresses.

### 1b. The redeem script and the address

```
flyoverRedeemScript = OP_PUSHBYTES_32(0x20) ++ derivationValue ++ OP_DROP(0x75) ++ getActivePowpegRedeemScript()
depositP2SH         = base58check( version(0x05 mainnet / 0xC4 testnet) ++ HASH160(flyoverRedeemScript) )
```

**Critical (and the part the legacy `validate…` helper got WRONG vs. the real bridge):** the bridge
wraps the `flyoverRedeemScript` as a **plain P2SH** — `HASH160(flyoverRedeemScript)` directly. The
legacy `validatePeginDepositAddress` helper (and the redesign's copy of it) instead built a
**P2SH-of-P2WSH** (segwit-wrapped: `HASH160(OP_0 OP_PUSHBYTES_32 sha256(flyoverRedeemScript))`).
That helper only ever validated the address the LBC *showed the user*; the actual settlement address
the bridge scans for is the plain P2SH. On regtest the segwit-wrapped form returns `-304`
(VALUE_ZERO: address parsed but zero value attributed); the plain P2SH settles. See §4.

### 1c. `shouldTransferToContract`

`registerFastBridgeBtcTransaction(..., shouldTransferToContract)` — when `true`, the released RBTC
is credited to the **`liquidityBridgeContractAddress`** (the caller / lbcAddress), regardless of the
`liquidityProviderBtcAddress` value. Proven: with `shouldTransferToContract=true` the funds landed in
the calling contract (§4), and the LP-placeholder BTC address never received anything on success.

---

## 2. Why E2 (the redesign) diverged

The shipped registry and settlement (`src/PegInAddressRegistry.sol`, `src/PegInContract.sol`) made
**two** independent departures from the formula above:

1. **No address mixing.** `PegInAddressRegistry._derivationValue` (`:267-269`) and
   `PegInContract._derivationValue` (`:1037-1039`) use
   `keccak256(abi.encodePacked("FLYOVER_PEGIN_V1", rskAddr))` **as the redeem-script tag directly**.
   But `_settleWithBridge` (`PegInContract.sol:485-501`) passes that same value as
   `derivationArgumentsHash` with `userRefundBtcAddress = new bytes(0)`, `lbcAddress = this`,
   `liquidityProviderBtcAddress = new bytes(0)`. So the bridge computed
   `keccak256(thatValue ++ "" ++ bytes20(this) ++ "")` as its tag — a *different* value than the one
   the registry baked into the deposit address. Result: `-900` (FAST_BRIDGE_GENERIC_ERROR).

2. **Segwit-wrapped P2SH.** Even once the mixing is fixed, the registry builds the deposit address as
   a P2SH-of-P2WSH (`PegInAddressRegistry._segwitScript` `:238-251`), not the plain P2SH the bridge
   uses. This independently produces a different address.

Both had to be corrected for `resolvePegIn` to settle.

---

## 3. The option-1 fix (LP-agnostic, no bridge edit)

Make the registry derive the deposit address the bridge's way, and make the settlement pass the
identical inputs:

```
derivationArgumentsHash       = keccak256("FLYOVER_PEGIN_V1", rskAddr)   // rskAddr-keyed, deterministic
userRefundBtcAddress          = REFUND_PLACEHOLDER   // FIXED protocol-wide 21-byte constant
liquidityBridgeContractAddress = address(PegInContract)  // the contract that calls the bridge
liquidityProviderBtcAddress   = LP_PLACEHOLDER       // FIXED protocol-wide 21-byte constant (NOT the serving LP)
shouldTransferToContract      = true
```

and derive the deposit address as the **plain P2SH** of
`OP_PUSHBYTES_32 ++ keccak256(argsHash ++ REFUND_PLACEHOLDER ++ bytes20(pegInContract) ++ LP_PLACEHOLDER) ++ OP_DROP ++ activePowpegRedeemScript`.

The placeholders are **constants**, not the serving LP's address, so the deposit address stays
deterministic-from-RSK-address and LP-agnostic. The registry must additionally know the
PegInContract address (`lbcAddress`) it derives against — a one-time wiring value.

### Placeholder choice (empirically required)

The placeholders MUST be **real, well-formed 21-byte BTC addresses** (version || hash160), not empty
byte strings. Empty placeholders (`""`) caused the bridge to fail at `-900`; switching to a valid
21-byte address advanced past derivation to a value check (`-304`), and then the plain-P2SH fix
settled. The prototype used a fresh regtest P2PKH address
`mfujgzmRixnsDfxN9u9yck1k3xtx9qCf2F` → 21-byte `0x6f044f0ba3d3a2bd0724db5e6d59a0bb62f4ef0cc2` for both
placeholders. Production should pick a single fixed protocol-owned address (see §6).

---

## 4. Regtest proof (real outputs — rskj 9.0.2, real bridge precompile 0x…1000006)

Live regtest, real powpeg bridge. BtcUtils library redeployed at
`0xd063D3A566291604Fd1532A5982e1fC3275658b4` (the prior one had been wiped by a regtest restart).

### Diagnostic ladder (each change isolated)

| Deposit address built as | placeholders | `registerFastBridgeBtcTransaction` result |
|---|---|---|
| segwit-wrapped P2SH (shipped E2 form) | empty `""` | **-900** FAST_BRIDGE_GENERIC_ERROR (no/À-derivation) |
| segwit-wrapped P2SH | real 21-byte | **-304** VALUE_ZERO (bridge derived a plain-P2SH addr; the segwit deposit pays it 0) |
| **plain P2SH (bridge form)** | real 21-byte | **+1000000000000000000** = **1.0 RBTC released** ✅ |

(`-304` decoded from revert `0xd4fb298c…fed0`; `-900` from `…fc7c`.)

### Clean end-to-end (registry-derived address, full runbook)

- Registry `PegInAddressRegistryV2Proto` @ `0x6F17D5bebf11236359d00f66A0105681298139fE`
  (lbcAddress wired to the settle proto), settle `PegInSettleProto` @ `0xE16533e0d9a7947e83C866682d8e72cFC14221C1`.
- `getPegInAddress(0x…DeaDBeef)` → **`2Mw27AKgd6qfNSaJBYLRSsLgsN63CXw5sgg`** (scriptPubKey
  `a91429656595684f60a0c76ab3ba98b0927fc712c92c87`), validated by `bitcoin-cli validateaddress`.
- Funded 1.0 BTC → mined → bridge confirmed (11 confs) → `registerAddress` succeeded (read-only SPV
  gating, isRegistered=true).
- **`resolvePegIn` (real tx `0x84faa8e4b10f7cb774c2a20b72d3483403dcbb7785d67dd8d55c154da502fa0f`,
  status 1):** settle-contract RBTC balance **0 → 1000000000000000000 wei (1.0 RBTC)**. `Settled`
  event: `bridgeResult = 0x…0de0b6b3a7640000 = 1e18`, `balanceAfter = 1e18`, rskAddr topic `…deadbeef`.
- **Idempotency:** re-resolving the same tx returns **-302** (UNPROCESSABLE_TX_ALREADY_PROCESSED) —
  the bridge enforces one-shot settlement per BTC tx. (Decoded from `0xd4fb298c…fed2`.)

This is the proof the story asked for: a real `resolvePegIn` that SETTLES (bridge releases funds to
the LBC, return ≥ 0) for a peg-in to a registry-derived address.

---

## 5. LP-agnosticism — does it hold?

**Yes.** Confirmed empirically:

- The `liquidityProviderBtcAddress` mixed into the address and passed to the bridge is a **fixed
  protocol constant**, never the serving LP's address. The deposit address therefore depends only on
  (rskAddr, the PegInContract address, the active powpeg) — not on which LP serves it.
- The bridge does **not** require `liquidityProviderBtcAddress` to be a registered/federation-known
  address. The placeholder used is an arbitrary fresh regtest wallet address with no LP role, and
  settlement still released the funds. So there is no bridge constraint that breaks LP-agnosticism.
- `resolvePegIn` on the settle prototype has no LP-identity access control, and with
  `shouldTransferToContract=true` the success funds route to the LBC contract regardless of the LP
  placeholder. Any LP (or any caller) can drive settlement; reimbursement is then an LBC-internal
  accounting concern, exactly as in the redesign's `_reimburseClaim`.

---

## 6. The placeholder design and its failure-refund implication

The bridge uses `userRefundBtcAddress` / `liquidityProviderBtcAddress` on its **refund paths** (when
a fast-bridge peg-in is rejected after the BTC is locked, e.g. amount below minimum or a locking-cap
breach, the bridge returns the BTC to one of those addresses rather than completing the peg-in).

Implications of a fixed protocol-owned placeholder:

- **Success path is unaffected.** With `shouldTransferToContract=true`, a successful settlement sends
  RBTC to the LBC, never to the placeholder. Proven in §4.
- **Failure path sends BTC to the placeholder address.** If the bridge ever takes a refund branch,
  the locked BTC goes to the fixed placeholder BTC address — NOT back to the depositing user and NOT
  to the serving LP. This is the one real cost of the placeholder design.
- **Recommendation for the placeholder:** it must be a **single, protocol-owned, monitored BTC
  address** (e.g. a Flyover-treasury / multisig address), identical in the registry and in
  `_settleWithBridge`, and ideally documented as a recovery sink. Because the registry's deposit-gating
  and `requestPegIn`'s own checks already enforce the Flyover minimum/validity *before* an LP fronts,
  the bridge-side refund branch should be unreachable in normal operation; the placeholder is a
  belt-and-suspenders sink, not a routine path. It must never be an EOA whose key can be lost, and it
  must not be the zero/empty address (which the bridge rejects — that is exactly the `-900` we hit).

---

## 7. Recommendation

**Adopt option 1.** It is validated end-to-end on the unmodified bridge, preserves the
deterministic-from-RSK-address property, and preserves LP-agnosticism. Concretely, the production
changes are:

1. **`PegInAddressRegistry`** — change the deposit-address derivation to:
   - mix the bridge's inputs:
     `derivationValue = keccak256(keccak256(DOMAIN, rskAddr) ++ REFUND_PLACEHOLDER ++ bytes20(pegInContract) ++ LP_PLACEHOLDER)`, and
   - build the address as a **plain P2SH** of the flyover redeem script (drop the P2SH-of-P2WSH /
     segwit wrapping in `_segwitScript` / `_p2shScriptPubkey`).
   - introduce a wired `pegInContract` (lbcAddress) reference and two fixed `REFUND_PLACEHOLDER` /
     `LP_PLACEHOLDER` constants (a single protocol-owned 21-byte BTC address).
2. **`PegInContract._settleWithBridge`** — pass the IDENTICAL values:
   `derivationArgumentsHash = keccak256(DOMAIN, rskAddr)`, `userRefundBtcAddress = REFUND_PLACEHOLDER`,
   `liquidityBridgeContractAddress = address(this)`, `liquidityProviderBtcAddress = LP_PLACEHOLDER`,
   `shouldTransferToContract = true`. (The `lbcAddress` mixed by the registry MUST equal
   `address(PegInContract)`, since that is the contract that calls the bridge.)
3. **Tighten the docstrings** in both contracts that currently claim the registry "mirrors
   `validatePegInDepositAddress`" — that helper is segwit-wrapped and does NOT match the bridge; the
   production derivation must be the plain-P2SH form proven here.

**Option 2 (alternative settlement) is NOT needed** — option 1 settles against the unmodified bridge.
Keep option 2 in reserve only if a future bridge version changes the derivation.

### Residual considerations for implementation (EB.2+)

- The registry's `getPegInAddress` and `PegInContract.validatePegInDepositAddress` must be reconciled
  to the SAME plain-P2SH construction (today they diverge from the bridge).
- Pick and document the single protocol-owned placeholder BTC address; wire it as a constant in both
  contracts; add a test asserting registry-address == bridge-derived address for a range of rskAddrs.
- A federation/powpeg change rotates every derived address (already handled by reading
  `getActivePowpegRedeemScript` live) — unchanged by this fix.

---

## Appendix — spike artifacts (do not ship as-is; not committed)

- `lbc/src/PegInAddressRegistryV2Proto.sol` — registry prototype (plain-P2SH + placeholder mixing + wired lbcAddress).
- `lbc/src/PegInSettleProto.sol` — minimal settlement harness calling the bridge with the matching inputs.
- BtcUtils library redeployed @ `0xd063D3A566291604Fd1532A5982e1fC3275658b4`.
- Settling tx: `0x84faa8e4b10f7cb774c2a20b72d3483403dcbb7785d67dd8d55c154da502fa0f` (and an earlier
  proof against a hand-funded plain-P2SH deposit, tx
  `0x3e2b2db22851f4ed26d0280ea6c55cca31246ee8c37cefe22e5a0792fd14d78c`).
