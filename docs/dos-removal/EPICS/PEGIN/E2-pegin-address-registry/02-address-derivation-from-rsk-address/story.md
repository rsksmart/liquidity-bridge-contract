# E2.2 Address derivation from RSK address

**Epic:** E2 PegInAddressRegistry (Peg-in track)
**Type:** Enabler

## Statement

As a user or LP, I want a deterministic BTC deposit address derived from the RSK address against the current powpeg, so it is stable and whitelist-once.

## Frozen inputs

- `getPegInAddress(address) returns (bytes, Encoding)` from the frozen interface.
- Current derivation reference: `PegInContract.validatePegInDepositAddress`, which today keys on the quote hash. E2.2 keys on the RSK address instead.

## Derivation scheme (locked 2026-06-29)

**Decision:** derive the BTC deposit address from the RSK address with a versioned domain tag, reusing the existing redeem-script wrapping:

- `derivationValue = keccak256(abi.encodePacked(DERIVATION_DOMAIN, rskAddress))`, where `DERIVATION_DOMAIN` is a constant scheme tag (for example `"FLYOVER_PEGIN_V1"`).
- `flyoverRedeemScript = OP_PUSHBYTES_32 <derivationValue> OP_DROP <activePowpegRedeemScript>`
- `segwitScript = OP_0 OP_PUSHBYTES_32 sha256(flyoverRedeemScript)`
- address = P2SH of `segwitScript`, encoded for the current network via `BtcUtils`.

This is the current `validatePegInDepositAddress` construction with the derivation value sourced from the RSK address plus a domain tag instead of the quote hash.

**Rationale:** the address is stable per RSK address and reuses the proven redeem-script wrapping and `BtcUtils`, so it is low risk. The `DERIVATION_DOMAIN` tag makes a future scheme version explicit: bumping the tag changes every derived address deterministically, which is the same path the system already handles for a federation change.

**Tradeoff:** keying only on the RSK address makes a user's deposit address publicly computable by anyone. This is acceptable and intended, since the address is public like any deposit address and deposit-gated registration means a computable address grants no advantage. The domain tag costs one constant; omitting it would be marginally simpler but lose clean versioning.

## Acceptance criteria

- `getPegInAddress(rskAddr)` returns the same address across calls for one RSK address.
- The derivation reads the current powpeg redeem script from the Bridge.
- The scheme is documented in this file.

## Children

Tasks: see `tasks/`. Tests: see `tests/`.

## Depends on

E2.1.

**Estimate:** 5. **Labels:** enabler, P0, lbc.
