#!/usr/bin/env bash
# Step 02 — fund the deposit address with AMOUNT (in BTC) and mine a SINGLE-TX block
# (coinbase + deposit only) so the merkle branch is one sibling.
set -euo pipefail
cd "$(dirname "$0")"; source config.env
: "${DEPOSIT_ADDR:?set DEPOSIT_ADDR in config.env from step 01}"

BTC=$(python3 -c "print(int('$AMOUNT')/1e18)")
TXID=$(./bcli.sh -rpcwallet=main sendtoaddress "$DEPOSIT_ADDR" "$BTC")
echo "FUNDING_TXID=$TXID"

MINEADDR=$(./bcli.sh -rpcwallet=main getnewaddress)
BLOCKHASH=$(./bcli.sh -rpcwallet=main generatetoaddress 1 "$MINEADDR" | python3 -c 'import sys,json;print(json.load(sys.stdin)[0])')
HEIGHT=$(./bcli.sh getblock "$BLOCKHASH" | python3 -c 'import sys,json;print(json.load(sys.stdin)["height"])')
RAWTX=$(./bcli.sh getrawtransaction "$TXID")
# coinbase txid = the OTHER tx in the block
COINBASE=$(./bcli.sh getblock "$BLOCKHASH" | python3 -c 'import sys,json;t=json.load(sys.stdin)["tx"];print([x for x in t if x!="'"$TXID"'"][0])')

echo "BLOCKHASH(BE)=$BLOCKHASH  HEIGHT=$HEIGHT"
echo "COINBASE(BE)=$COINBASE"
echo "TXBE=0x$TXID"
echo "BHBE=0x$BLOCKHASH"
echo "BRANCH=[0x$COINBASE]"
echo "RAWTX=0x$RAWTX"
echo
echo "Copy TXBE/BHBE/BRANCH/HEIGHT/RAWTX into config.env, then step 03."
