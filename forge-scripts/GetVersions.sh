#!/bin/bash

# Script to print the versions of the LiquidityBridgeContract and its libraries
# Usage: ./forge-scripts/get-versions.sh [rpc-url]

RPC_URL="${1:-https://rootstock-testnet.drpc.org}"

# Get contract addresses from addresses.json
LBC_ADDRESS=$(jq -r '.rskTestnet.LiquidityBridgeContract.address' ./addresses.json 2>/dev/null || echo "")
BTC_UTILS_ADDRESS=$(jq -r '.rskTestnet.BtcUtils.address' ./addresses.json 2>/dev/null || echo "")

if [ -z "$LBC_ADDRESS" ] || [ "$LBC_ADDRESS" = "null" ]; then
    echo "❌ Error: LiquidityBridgeContract address not found in addresses.json"
    echo "   Make sure the contract is deployed and addresses.json is up to date"
    exit 1
fi

if [ -z "$BTC_UTILS_ADDRESS" ] || [ "$BTC_UTILS_ADDRESS" = "null" ]; then
    echo "❌ Error: BtcUtils address not found in addresses.json"
    echo "   Make sure the contract is deployed and addresses.json is up to date"
    exit 1
fi

echo "Getting contract versions..."
echo "LBC address: $LBC_ADDRESS"
echo "BtcUtils address: $BTC_UTILS_ADDRESS"
echo "RPC URL: $RPC_URL"
echo ""

# Get LBC version
echo "Getting LiquidityBridgeContract version..."
if LBC_VERSION=$(cast call "$LBC_ADDRESS" "version()" --rpc-url "$RPC_URL" 2>/dev/null); then
    # Convert hex to string
    LBC_VERSION_STR=$(cast --to-ascii "$LBC_VERSION" 2>/dev/null || echo "Failed to decode")
    echo "✅ LiquidityBridgeContract version: $LBC_VERSION_STR"
else
    echo "⚠️  LiquidityBridgeContract version: Not found"
fi

# Get BtcUtils version
echo "Getting BtcUtils version..."
if BTC_UTILS_VERSION=$(cast call "$BTC_UTILS_ADDRESS" "version()" --rpc-url "$RPC_URL" 2>/dev/null); then
    # Convert hex to string
    BTC_UTILS_VERSION_STR=$(cast --to-ascii "$BTC_UTILS_VERSION" 2>/dev/null || echo "Failed to decode")
    echo "✅ BtcUtils version: $BTC_UTILS_VERSION_STR"
else
    echo "⚠️  BtcUtils version: Not found"
fi

echo ""
echo "======================================="
