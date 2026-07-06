#!/usr/bin/env bash
# Step 03 — advance the bridge's BTC best-chain height past the deposit block and confirm.
# Mine BTC blocks for confirmations; auto-tick + RSK blocks feed headers to the bridge.
# Then verify the bridge actually confirms the deposit BEFORE spending gas on registerAddress.
set -euo pipefail
cd "$(dirname "$0")"; source config.env
: "${TXBE:?run step 02}"; : "${BHBE:?}"; : "${BRANCH:?}"

MINEADDR=$(./bcli.sh -rpcwallet=main getnewaddress)
./bcli.sh -rpcwallet=main generatetoaddress 10 "$MINEADDR" >/dev/null
echo "mined 10 BTC blocks; waiting for the bridge to ingest headers (auto-tick must be running)..."

for i in $(seq 1 30); do
  H=$(cast call "$BRIDGE" "getBtcBlockchainBestChainHeight()(int256)" --rpc-url "$RPC")
  CONF=$(cast call "$BRIDGE" "getBtcTransactionConfirmations(bytes32,bytes32,uint256,bytes32[])(int256)" \
        "$TXBE" "$BHBE" "$PATH_BITS" "$BRANCH" --rpc-url "$RPC" 2>/dev/null || echo "err")
  echo "  bridge BTC height=$H  confirmations=$CONF"
  [ "$CONF" != "err" ] && [ "${CONF%% *}" -ge 1 ] 2>/dev/null && { echo "CONFIRMED ($CONF) — proceed to step 05."; exit 0; }
  cast send "$COW" --value 0 --private-key "$COWKEY" --rpc-url "$RPC" --legacy >/dev/null 2>&1 || true  # nudge an RSK block
  sleep 4
done
echo "bridge did not confirm in time; mine more BTC / check auto-tick."; exit 1
