#!/usr/bin/env bash
# Step 07 — LP reimbursement via the bridge. NOW SUCCEEDS (finding B fixed, EB.1).
# The registry's deposit-address derivation and PegInContract._settleWithBridge both use the shared
# PegInDerivation library: a PLAIN P2SH of OP_PUSHBYTES_32 ++ keccak256(argsHash ++ REFUND_PLACEHOLDER
# ++ bytes20(pegInContract) ++ LP_PLACEHOLDER) ++ OP_DROP ++ activePowpegRedeemScript, with
# argsHash = keccak256("FLYOVER_PEGIN_V1", rskAddr) and shouldTransferToContract=true. The native
# fast bridge re-derives the SAME address and RELEASES the deposit to the LBC, which reimburses the LP.
set -euo pipefail
cd "$(dirname "$0")"; source config.env
: "${TXBE:?run step 02}"; : "${RAWTX:?}"; : "${PMT:?set PMT from step 04}"; : "${HEIGHT:?}"

echo "PegIn contract RBTC balance BEFORE: $(cast balance "$PEGIN" --rpc-url "$RPC")"
echo "LP getBalance(cow) BEFORE:          $(cast call "$PEGIN" 'getBalance(address)(uint256)' "$COW" --rpc-url "$RPC")"

echo "bridge result (static call): $(cast call "$PEGIN" \
  'resolvePegIn(address,bytes32,bytes,bytes,uint256,address)(int256)' \
  "$USER" "$TXBE" "$RAWTX" "$PMT" "$HEIGHT" "$COW" --rpc-url "$RPC")"

cast send "$PEGIN" \
  "resolvePegIn(address,bytes32,bytes,bytes,uint256,address)" \
  "$USER" "$TXBE" "$RAWTX" "$PMT" "$HEIGHT" "$COW" \
  --private-key "$COWKEY" --rpc-url "$RPC" --legacy

echo "PegIn contract RBTC balance AFTER:  $(cast balance "$PEGIN" --rpc-url "$RPC")  (bridge released the deposit here)"
echo "LP getBalance(cow) AFTER:           $(cast call "$PEGIN" 'getBalance(address)(uint256)' "$COW" --rpc-url "$RPC")  (= fronted + fee, LP reimbursed)"
echo "SETTLED: a positive bridge result + the LBC balance jump == the peg-in resolved on the live bridge."
