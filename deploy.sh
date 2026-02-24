#!/bin/bash

npm config set //npm.pkg.github.com/:_authToken "$GITHUB_TOKEN"

make deploy-lbc-broadcast NETWORK="$NETWORK_NAME" VERIFY=true
make upgrade-lbc-broadcast NETWORK="$NETWORK_NAME" VERIFY=true

LBC_ADDRESS=$(jq -r '.[env.NETWORK_NAME].LiquidityBridgeContract.address' ./addresses.json)
echo "LBC_ADDRESS=$LBC_ADDRESS"
