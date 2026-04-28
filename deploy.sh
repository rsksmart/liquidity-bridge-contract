#!/bin/bash

npx hardhat run scripts/deployment/deploy-lbc.ts --network "$NETWORK_NAME"
npx hardhat run scripts/deployment/upgrade-lbc.ts --network "$NETWORK_NAME"

LBC_ADDRESS=$(jq -r '.[env.NETWORK_NAME].LiquidityBridgeContract.address' ./addresses.json)
echo "LBC_ADDRESS=$LBC_ADDRESS"
