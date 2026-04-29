#!/bin/bash

# Script to print the versions of all Flyover contracts
# Usage: ./script/tasks/GetVersions.sh [rpc-url]

RPC_URL="${1:-https://public-node.testnet.rsk.co}"

# Get contract addresses from addresses.json
CM_ADDRESS=$(jq -r '.rskTestnet.CollateralManagement.address' ./addresses.json 2>/dev/null || echo "")
FD_ADDRESS=$(jq -r '.rskTestnet.FlyoverDiscovery.address' ./addresses.json 2>/dev/null || echo "")
PEGIN_ADDRESS=$(jq -r '.rskTestnet.PegInContract.address' ./addresses.json 2>/dev/null || echo "")
PEGOUT_ADDRESS=$(jq -r '.rskTestnet.PegOutContract.address' ./addresses.json 2>/dev/null || echo "")

echo "Getting Flyover contract versions..."
echo "RPC URL: $RPC_URL"
echo ""

# Function to get version from a contract
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

# Get versions for all contracts
get_version "CollateralManagement" "$CM_ADDRESS"
get_version "FlyoverDiscovery" "$FD_ADDRESS"
get_version "PegInContract" "$PEGIN_ADDRESS"
get_version "PegOutContract" "$PEGOUT_ADDRESS"

echo ""
echo "======================================="
