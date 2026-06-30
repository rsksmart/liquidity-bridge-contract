#!/usr/bin/env bash
# bitcoin-cli against the core regtest bitcoind.
docker exec bitcoind01 bitcoin-cli -rpcport=5555 -rpcuser=test -rpcpassword=test "$@"
