#!/usr/bin/env bash
# Step 06 — the LP claims: fronts RBTC to the user. THIS IS THE PEG-IN SUCCESS.
# The claim takes a FULL SPV proof (finding A): the rskj bridge has no by-hash confirmation lookup.
# (The live PoC used `requestPegInWithProof` on the interim patched proxy; after the EB.finding-A
#  consolidation the canonical entrypoint is `requestPegIn` with the proof params shown here.)
set -euo pipefail
cd "$(dirname "$0")"; source config.env
: "${TXBE:?run step 02}"; : "${BHBE:?}"; : "${BRANCH:?}"

FEE=$(cast call "$CONFIGS" "calculatePegInFee(uint256)(uint256)" "$AMOUNT" --rpc-url "$RPC" | awk '{print $1}')
NET=$(python3 -c "print(int('$AMOUNT')-int('$FEE'))")
echo "amount=$AMOUNT fee=$FEE net(value)=$NET"

echo "user RBTC BEFORE: $(cast balance "$USER" --rpc-url "$RPC")"
cast send "$PEGIN" \
  "requestPegIn(address,uint256,bytes32,bytes,bytes32,uint256,bytes32[])" \
  "$USER" "$AMOUNT" "$TXBE" "0x" "$BHBE" "$PATH_BITS" "$BRANCH" \
  --value "$NET" --private-key "$COWKEY" --rpc-url "$RPC" --legacy
echo "user RBTC AFTER:  $(cast balance "$USER" --rpc-url "$RPC")"
echo "Expected delta = net = $NET  (= amount - fee). Peg-in succeeded if the balance increased by that."
