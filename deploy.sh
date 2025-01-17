#!/bin/bash

npm config set //npm.pkg.github.com/:_authToken "$GITHUB_TOKEN"

npx hardhat run scripts/deployment/deploy-lbc.ts --network "$NETWORK_NAME"
npx hardhat run scripts/deployment/upgrade-lbc.ts --network "$NETWORK_NAME"

LBC_ADDRESS=$(jq -r '.rskRegtest.LiquidityBridgeContract.address' ./addresses.json)
echo "LBC_ADDRESS=$LBC_ADDRESS"
