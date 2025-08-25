#!/bin/bash

# Script to get Bitcoin blockchain best chain height from RSK Bridge
# Usage: ./scripts/get-btc-height.sh [rpc-url]

BRIDGE_ADDRESS="0x0000000000000000000000000000000001000006"
RPC_URL=${1:-"https://rootstock-testnet.drpc.org"}

echo "Getting Bitcoin blockchain best chain height..."
echo "Bridge address: $BRIDGE_ADDRESS"
echo "RPC URL: $RPC_URL"
echo ""

# Get the height in hex
if HEX_RESULT=$(cast call "$BRIDGE_ADDRESS" "getBtcBlockchainBestChainHeight()" --rpc-url "$RPC_URL"); then
    # Convert to decimal
    DECIMAL_RESULT=$(cast --to-dec "$HEX_RESULT")
    echo "✅ Success!"
    echo "Best BTC blockchain height: $DECIMAL_RESULT"
else
    echo "❌ Error: Failed to get Bitcoin blockchain height"
    exit 1
fi
