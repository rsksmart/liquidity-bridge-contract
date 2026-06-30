#!/usr/bin/env bash
# Step 07 — LP reimbursement via the bridge. CURRENTLY BLOCKED by finding B (EB epic):
# the registry's deposit-address derivation differs from the native fast-bridge derivation,
# so registerFastBridgeBtcTransaction returns -900 (no matching UTXO). Documented, not yet fixed.
set -euo pipefail
cd "$(dirname "$0")"; source config.env
: "${TXBE:?run step 02}"; : "${RAWTX:?}"; : "${PMT:?set PMT from step 04}"; : "${HEIGHT:?}"

set +e
cast send "$PEGIN" \
  "resolvePegIn(address,bytes32,bytes,bytes,uint256,address)" \
  "$USER" "$TXBE" "$RAWTX" "$PMT" "$HEIGHT" "$COW" \
  --private-key "$COWKEY" --rpc-url "$RPC" --legacy
echo "If this reverts BridgeSettlementFailed(-900): that is finding B (see ../../../POC-FINDINGS.md, epic EB)."
