#!/bin/bash

npm config set //npm.pkg.github.com/:_authToken "$GITHUB_TOKEN"

make deploy-lbc-broadcast NETWORK="$NETWORK_NAME" VERIFY=true
make upgrade-lbc-broadcast NETWORK="$NETWORK_NAME" VERIFY=true

get_addresses_network_name() {
  case "$1" in
    mainnet|rskMainnet) echo "rskMainnet" ;;
    testnet|rskTestnet) echo "rskTestnet" ;;
    development|rskDevelopment) echo "rskDevelopment" ;;
    dev|regtest|rskRegtest) echo "rskRegtest" ;;
    *) echo "$1" ;;
  esac
}

ADDRESSES_NETWORK_NAME=$(get_addresses_network_name "$NETWORK_NAME")
LBC_ADDRESS=$(jq -r --arg network "$ADDRESSES_NETWORK_NAME" '.[$network].LiquidityBridgeContract.address' ./addresses.json)
echo "LBC_ADDRESS=$LBC_ADDRESS"
