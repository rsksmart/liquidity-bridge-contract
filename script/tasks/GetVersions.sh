#!/bin/bash

# Print Flyover contract versions for a network in addresses.json
# Usage: ./script/tasks/GetVersions.sh [rpc-url] [addresses.json-network-key]
#   e.g. ./script/tasks/GetVersions.sh http://localhost:4444 rskRegtest

RPC_URL="${1:-https://public-node.testnet.rsk.co}"
NETWORK_KEY="${2:-rskTestnet}"

CM_ADDRESS=$(jq -r ".[\"${NETWORK_KEY}\"].CollateralManagementContract.address" ./addresses.json 2>/dev/null || echo "")
FD_ADDRESS=$(jq -r ".[\"${NETWORK_KEY}\"].FlyoverDiscovery.address" ./addresses.json 2>/dev/null || echo "")
PEGIN_ADDRESS=$(jq -r ".[\"${NETWORK_KEY}\"].PegInContract.address" ./addresses.json 2>/dev/null || echo "")
PEGOUT_ADDRESS=$(jq -r ".[\"${NETWORK_KEY}\"].PegOutContract.address" ./addresses.json 2>/dev/null || echo "")

echo "Getting Flyover contract versions..."
echo "Network: $NETWORK_KEY"
echo "RPC URL: $RPC_URL"
echo ""

get_version() {
    local name=$1
    local address=$2

    if [ -z "$address" ] || [ "$address" = "null" ]; then
        echo "⚠️  $name: Address not found in addresses.json"
        return
    fi

    echo "Checking $name at $address..."
    if VERSION=$(cast call "$address" "VERSION()" --rpc-url "$RPC_URL" 2>/dev/null); then
        VERSION_STR=$(cast --to-ascii "$VERSION" 2>/dev/null || echo "Failed to decode")
        echo "✅ $name: $VERSION_STR"
    else
        echo "⚠️  $name: Could not get version"
    fi
}

get_version "CollateralManagement" "$CM_ADDRESS"
get_version "FlyoverDiscovery" "$FD_ADDRESS"
get_version "PegInContract" "$PEGIN_ADDRESS"
get_version "PegOutContract" "$PEGOUT_ADDRESS"

echo ""
echo "======================================="
