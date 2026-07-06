#!/usr/bin/env bash
# Step 01 — derive the deterministic BTC deposit address for USER from the registry.
# getPegInAddress returns (bytes,uint8); the bytes are the RAW base58check payload
# (version || hash160 || checksum). base58-ENCODE them to get the address string.
set -euo pipefail
cd "$(dirname "$0")"; source config.env

RAW=$(cast call "$REGISTRY" "getPegInAddress(address)(bytes,uint8)" "$USER" --rpc-url "$RPC" | head -1)
echo "raw payload: $RAW"

DEPOSIT_ADDR=$(python3 - "$RAW" <<'PY'
import sys
raw=sys.argv[1][2:]
b=bytes.fromhex(raw)
alpha='123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz'
n=int.from_bytes(b,'big'); s=''
while n>0: n,r=divmod(n,58); s=alpha[r]+s
print('1'*(len(b)-len(b.lstrip(b'\x00')))+s)
PY
)
echo "DEPOSIT_ADDR=$DEPOSIT_ADDR"
echo "(verify) bitcoin-cli validateaddress:"
./bcli.sh validateaddress "$DEPOSIT_ADDR" | python3 -c 'import sys,json;d=json.load(sys.stdin);print("  isvalid:",d["isvalid"],"scriptPubKey:",d.get("scriptPubKey"))'
echo
echo "Put DEPOSIT_ADDR into config.env before step 02."
