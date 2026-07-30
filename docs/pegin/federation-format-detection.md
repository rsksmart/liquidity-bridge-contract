# Peg-in federation format detection

Operators migrating to or running against a segwit powpeg federation (`P2SH_P2WSH_ERP_FEDERATION`, format version **4000** in rskj) do not configure a manual flag on `PegInAddressRegistry`. Format is inferred automatically at derivation and registration time from on-chain bridge state.

## Algorithm

For each derive or register path, the registry reads once per call:

1. `IBridge.getActivePowpegRedeemScript()` — active powpeg redeem script bytes.
2. `IBridge.getFederationAddress()` — federation P2SH address (base58 string).

`PegInDerivation.inferFederationFormat` decodes the federation address (base58check), extracts its 20-byte script hash, and compares it against both wrapping candidates of the powpeg redeem script (replicating rskj `PegUtils.getFlyoverFederationOutputScript` @ `4c8eed1a`):

| Candidate         | Script hash                                                    |
| ----------------- | -------------------------------------------------------------- |
| Legacy plain P2SH | `HASH160(powpegRedeemScript)`                                  |
| Segwit P2SH-P2WSH | `HASH160(OP_0 ‖ OP_PUSHBYTES_32 ‖ sha256(powpegRedeemScript))` |

The matching candidate selects the wrapping used for flyover deposit derivation (steps 4–5). Both `_deriveAddress` and `_expectedDepositPkScript` consume the same inferred format at a single choke point.

If neither candidate matches the decoded federation script hash, derivation reverts with `UnrecognizedFederationFormat()`.

## Live-network evidence

Mainnet and testnet powpegs currently use segwit federation wrapping:

- Mainnet federation: `3GX89qzyQVaJqUJjq5noZbLJEHuYDvVrHq`
- Testnet federation: `2N88sMiizxmbb8Y3yA4AtYmL1RxHogWfoHa`

These addresses are P2SH commitments to segwit witness programs, not plain `HASH160(redeemScript)` wraps.

## Operator checklist during powpeg migration

1. Follow existing federation rotation runbooks for drain-then-rotate sequencing (not restated here).
2. No registry admin flag flip is required — inference uses `getFederationAddress()` at call time after the bridge reports the new federation.
3. Expect every derived deposit address to rotate when either the powpeg redeem script or federation wrapping format changes (same rule as any federation change).
4. Before first testnet deployment after this change, run optional segwit-federation regtest end-to-end validation if not executed in CI.

## Out of scope

- `PegInContract.validatePegInDepositAddress` (quote path) — unchanged; uses nested P2SH-P2WSH with quote-hash derivation until quote-path alignment with `PegInDerivation`.
- LPS / SDK — no public registry ABI change; library linked at compile time only.

## References

- rskj: `PegUtils.getFlyoverFederationOutputScript`, `FederationFormatVersion.P2SH_P2WSH_ERP_FEDERATION` (4000)
- LBC: `src/libraries/PegInDerivation.sol` — `inferFederationFormat`, `scriptHashForFormat`
- LBC: `src/PegInAddressRegistry.sol` — `_depositValueForRegistration`, `_deriveAddress`
