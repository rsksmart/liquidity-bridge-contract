#!/usr/bin/env bash
# Step 05 — register the deposit address (read-only SPV deposit-gating; does NOT consume the peg-in).
set -euo pipefail
cd "$(dirname "$0")"; source config.env
: "${RAWTX:?run step 02}"; : "${BHBE:?}"; : "${BRANCH:?}"

cast send "$REGISTRY" \
  "registerAddress(address,bytes,bytes32,uint256,bytes32[])" \
  "$USER" "$RAWTX" "$BHBE" "$PATH_BITS" "$BRANCH" \
  --private-key "$COWKEY" --rpc-url "$RPC" --legacy
echo "isRegistered(user) = $(cast call "$REGISTRY" "isRegistered(address)(bool)" "$USER" --rpc-url "$RPC")"
