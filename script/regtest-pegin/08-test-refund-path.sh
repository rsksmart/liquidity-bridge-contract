#!/usr/bin/env bash
# Step 08 (E11) — prove the no-claimer REFUND RAIL end to end on a live regtest.
# Mirrors steps 01..05 (derive -> fund BTC -> advance bridge -> build SPV proof -> register) for a
# dedicated REFUND_USER, then **SKIPS step 06 (requestPegIn)** so NO LP fronts. It advances the RSK
# chain past the claim deadline (anchored to the registration block) so the global slash fires, then
# calls resolvePegIn (E11.1/E11.2) and asserts:
#   - the user's rskAddr balance rose by amount - fee (funds forwarded on the RBTC rail),
#   - the registered LP (cow) collateral was slashed (globalSlash on the same resolve),
#   - the peg-in is marked processed.
# Re-runnable: each run uses a fresh BTC deposit (new txid). Exits non-zero on any failed assertion.
set -euo pipefail
cd "$(dirname "$0")"; source config.env

U="$REFUND_USER"
MIN_CONF=11   # fast-bridge settlement depth proven on this regtest (happy path settled at 11)
fail() { echo "ASSERT FAIL: $1" >&2; exit 1; }

echo "== 08 refund-rail: user=$U amount=$AMOUNT =="

# --- step 01: derive the deposit address for the refund user ---------------------------------------
RAW=$(cast call "$REGISTRY" "getPegInAddress(address)(bytes,uint8)" "$U" --rpc-url "$RPC" | head -1)
DEP=$(python3 - "$RAW" <<'PY'
import sys
raw=sys.argv[1][2:]; b=bytes.fromhex(raw)
alpha='123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz'
n=int.from_bytes(b,'big'); s=''
while n>0: n,r=divmod(n,58); s=alpha[r]+s
print('1'*(len(b)-len(b.lstrip(b'\x00')))+s)
PY
)
echo "deposit address: $DEP"

# --- step 02: fund the deposit address and mine a single-tx block ----------------------------------
# Unlock the (encrypted) main wallet; idempotent, extends the unlock window.
./bcli.sh -rpcwallet=main walletpassphrase "test-password" 3600 >/dev/null 2>&1 || true
BTC=$(python3 -c "print(int('$AMOUNT')/1e18)")
TXID=$(./bcli.sh -rpcwallet=main sendtoaddress "$DEP" "$BTC")
MINEADDR=$(./bcli.sh -rpcwallet=main getnewaddress)
BLOCKHASH=$(./bcli.sh -rpcwallet=main generatetoaddress 1 "$MINEADDR" | python3 -c 'import sys,json;print(json.load(sys.stdin)[0])')
HEIGHT=$(./bcli.sh getblock "$BLOCKHASH" | python3 -c 'import sys,json;print(json.load(sys.stdin)["height"])')
RAWTX=$(./bcli.sh getrawtransaction "$TXID")
COINBASE=$(./bcli.sh getblock "$BLOCKHASH" | python3 -c 'import sys,json;t=json.load(sys.stdin)["tx"];print([x for x in t if x!="'"$TXID"'"][0])')
TXBE="0x$TXID"; BHBE="0x$BLOCKHASH"; BRANCH="[0x$COINBASE]"
echo "funded txid=$TXID height=$HEIGHT"

# --- step 03: advance the bridge's BTC best chain until the deposit has MIN_CONF confirmations ------
MINEADDR2=$(./bcli.sh -rpcwallet=main getnewaddress)
./bcli.sh -rpcwallet=main generatetoaddress 15 "$MINEADDR2" >/dev/null
CONF="err"
for i in $(seq 1 90); do
  CONF=$(cast call "$BRIDGE" "getBtcTransactionConfirmations(bytes32,bytes32,uint256,bytes32[])(int256)" \
        "$TXBE" "$BHBE" 1 "$BRANCH" --rpc-url "$RPC" 2>/dev/null || echo "err")
  [ "$CONF" != "err" ] && [ "${CONF%% *}" -ge "$MIN_CONF" ] 2>/dev/null && break
  cast send "$COW" --value 0 --private-key "$COWKEY" --rpc-url "$RPC" --legacy >/dev/null 2>&1 || true
  sleep 3   # let auto-tick + federator receiveHeaders advance the bridge best chain
done
[ "$CONF" != "err" ] && [ "${CONF%% *}" -ge "$MIN_CONF" ] 2>/dev/null \
  || fail "bridge did not reach $MIN_CONF confirmations (conf=$CONF); check auto-tick"
echo "bridge confirmations: $CONF"

# --- step 04: build the SPV proof / PMT (big-endian) for resolvePegIn ------------------------------
PMT=$(NODE_PATH=../../../flyover-sdk/node_modules node 04-build-proof.js "$TXID" "$COINBASE" "$BLOCKHASH" \
      | sed -n 's/^PMT=//p')
[ -n "$PMT" ] || fail "PMT build failed (need flyover-sdk/node_modules for @rsksmart/pmt-builder)"

# --- step 05: register the refund user (deposit-gated), if not already registered ------------------
if [ "$(cast call "$REGISTRY" 'isRegistered(address)(bool)' "$U" --rpc-url "$RPC")" != "true" ]; then
  cast send "$REGISTRY" "registerAddress(address,bytes,bytes32,uint256,bytes32[])" \
    "$U" "0x$RAWTX" "$BHBE" 1 "$BRANCH" --private-key "$COWKEY" --rpc-url "$RPC" --legacy >/dev/null
fi
[ "$(cast call "$REGISTRY" 'isRegistered(address)(bool)' "$U" --rpc-url "$RPC")" = "true" ] \
  || fail "user not registered"

# --- SKIP step 06 (requestPegIn): NO LP fronts this peg-in -----------------------------------------
echo "skipping requestPegIn (no LP fronts) -- this is the refund rail"

# --- advance the RSK chain past the claim deadline (registration block + CLAIM_DEADLINE_BLOCKS) ----
REGBLK=$(cast call "$REGISTRY" 'getRegistrationBlock(address)(uint256)' "$U" --rpc-url "$RPC" | awk '{print $1}')
DEADLINE=$((REGBLK + CLAIM_DEADLINE_BLOCKS))
echo "registration block=$REGBLK  claim deadline block=$DEADLINE"
for i in $(seq 1 120); do
  [ "$(cast block-number --rpc-url "$RPC")" -gt "$DEADLINE" ] && break
  cast send "$COW" --value 0 --private-key "$COWKEY" --rpc-url "$RPC" --legacy >/dev/null 2>&1 || true
  sleep 2   # auto-tick also advances RSK blocks toward the deadline
done
[ "$(cast block-number --rpc-url "$RPC")" -gt "$DEADLINE" ] || fail "could not advance past the claim deadline"

# --- capture pre-state, then resolve (no-claimer refund rail: settle -> forward -> slash) ----------
FEE=$(cast call "$CONFIGS" "calculatePegInFee(uint256)(uint256)" "$AMOUNT" --rpc-url "$RPC" | awk '{print $1}')
NET=$(python3 -c "print(int('$AMOUNT')-int('$FEE'))")
USER_BEFORE=$(cast balance "$U" --rpc-url "$RPC")
COLL_BEFORE=$(cast call "$COLLATERAL" 'getPegInCollateral(address)(uint256)' "$COW" --rpc-url "$RPC" | awk '{print $1}')
echo "amount=$AMOUNT fee=$FEE net=$NET  user_before=$USER_BEFORE coll_before=$COLL_BEFORE"

echo "resolvePegIn (no prior requestPegIn) ..."
cast send "$PEGIN" "resolvePegIn(address,bytes32,bytes,bytes,uint256,address)" \
  "$U" "$TXBE" "0x$RAWTX" "$PMT" "$HEIGHT" "$COW" \
  --private-key "$COWKEY" --rpc-url "$RPC" --legacy >/dev/null

USER_AFTER=$(cast balance "$U" --rpc-url "$RPC")
COLL_AFTER=$(cast call "$COLLATERAL" 'getPegInCollateral(address)(uint256)' "$COW" --rpc-url "$RPC" | awk '{print $1}')
CLAIM=$(cast call "$PEGIN" 'getPegInClaim(address,bytes32)((address,uint256,uint256,uint256,bool))' "$U" "$TXBE" --rpc-url "$RPC")
echo "user_after=$USER_AFTER coll_after=$COLL_AFTER"
echo "claim record: $CLAIM"

# --- assertions -----------------------------------------------------------------------------------
DELTA=$(python3 -c "print(int('$USER_AFTER')-int('$USER_BEFORE'))")
[ "$DELTA" = "$NET" ] || fail "user delta $DELTA != net $NET (amount-fee)"
python3 -c "import sys; sys.exit(0 if int('$COLL_AFTER')<int('$COLL_BEFORE') else 1)" \
  || fail "LP collateral not slashed ($COLL_BEFORE -> $COLL_AFTER)"
echo "$CLAIM" | grep -qi 'true' || fail "peg-in not marked processed: $CLAIM"

echo
echo "PASS (E11 refund rail):"
echo "  user forwarded  : +$DELTA wei (= amount - fee)"
echo "  LP global-slash : $COLL_BEFORE -> $COLL_AFTER"
echo "  peg-in processed: yes"
