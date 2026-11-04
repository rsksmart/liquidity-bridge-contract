#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Register PegIn using cast (avoids forge local simulation bridge checks).

Usage:
  script/tasks/register-pegin-cast.sh \
    --network development \
    --quote-file script/tasks/hash-quote.example.json \
    --signature <lp-signature-hex> \
    --txid <bitcoin-txid> \
    [--broadcast --private-key <hex-key>]

Options:
  --network        mainnet|testnet|development|dev (default: development)
  --quote-file     Path to PegIn quote JSON (required)
  --signature      LP signature (required)
  --txid           BTC transaction id (required)
  --rpc-url        Override RPC URL
  --pegin-address  Override PegIn contract address
  --btc-network    mainnet|testnet (default inferred from network)
  --broadcast      Send transaction (default: eth_call only)
  --private-key    Required when --broadcast
  --gas-limit      Tx gas limit for broadcast (default: 10000000)
  -h, --help       Show this message
EOF
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Error: missing required command '$1'" >&2
    exit 1
  }
}

with_0x() {
  local value="${1:-}"
  if [[ -z "$value" ]]; then
    echo "0x"
    return
  fi
  if [[ "$value" == 0x* ]]; then
    echo "$value"
  else
    echo "0x${value}"
  fi
}

btc_addr_to_hex() {
  local btc_addr="$1"
  npx ts-node script/helpers/parse-btc-address.ts "$btc_addr" | tr -d '\n'
}

NETWORK="${NETWORK:-development}"
QUOTE_FILE="${PEGIN_QUOTE_FILE:-}"
SIGNATURE="${PEGIN_SIGNATURE:-}"
TXID="${PEGIN_TXID:-}"
RPC_URL="${RPC_URL:-}"
PEGIN_ADDRESS="${PEGIN_CONTRACT_ADDRESS:-}"
BTC_NETWORK="${BTC_NETWORK:-}"
PRIVATE_KEY="${PRIVATE_KEY:-}"
GAS_LIMIT="${GAS_LIMIT:-10000000}"
BROADCAST=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --network) NETWORK="$2"; shift 2 ;;
    --quote-file) QUOTE_FILE="$2"; shift 2 ;;
    --signature) SIGNATURE="$2"; shift 2 ;;
    --txid) TXID="$2"; shift 2 ;;
    --rpc-url) RPC_URL="$2"; shift 2 ;;
    --pegin-address) PEGIN_ADDRESS="$2"; shift 2 ;;
    --btc-network) BTC_NETWORK="$2"; shift 2 ;;
    --private-key) PRIVATE_KEY="$2"; shift 2 ;;
    --gas-limit) GAS_LIMIT="$2"; shift 2 ;;
    --broadcast) BROADCAST=true; shift 1 ;;
    -h|--help) usage; exit 0 ;;
    *)
      echo "Error: unknown argument '$1'" >&2
      usage
      exit 1
      ;;
  esac
done

[[ -n "$QUOTE_FILE" ]] || { echo "Error: quote file is required (PEGIN_QUOTE_FILE or --quote-file)" >&2; exit 1; }
[[ -f "$QUOTE_FILE" ]] || { echo "Error: quote file not found: $QUOTE_FILE" >&2; exit 1; }
[[ -n "$SIGNATURE" ]] || { echo "Error: signature is required (PEGIN_SIGNATURE or --signature)" >&2; exit 1; }
[[ -n "$TXID" ]] || { echo "Error: txid is required (PEGIN_TXID or --txid)" >&2; exit 1; }

require_cmd jq
require_cmd cast
require_cmd npx

case "$NETWORK" in
  mainnet)
    [[ -n "$RPC_URL" ]] || RPC_URL="${MAINNET_RPC_URL:-https://public-node.rsk.co}"
    [[ -n "$BTC_NETWORK" ]] || BTC_NETWORK="mainnet"
    RSK_NETWORK_NAME="rskMainnet"
    ;;
  testnet)
    [[ -n "$RPC_URL" ]] || RPC_URL="${TESTNET_RPC_URL:-https://public-node.testnet.rsk.co}"
    [[ -n "$BTC_NETWORK" ]] || BTC_NETWORK="testnet"
    RSK_NETWORK_NAME="rskTestnet"
    ;;
  development)
    [[ -n "$RPC_URL" ]] || RPC_URL="${TESTNET_RPC_URL:-https://public-node.testnet.rsk.co}"
    [[ -n "$BTC_NETWORK" ]] || BTC_NETWORK="testnet"
    RSK_NETWORK_NAME="rskDevelopment"
    ;;
  dev)
    [[ -n "$RPC_URL" ]] || RPC_URL="${REGTEST_RPC_URL:-http://localhost:4444}"
    [[ -n "$BTC_NETWORK" ]] || BTC_NETWORK="testnet"
    RSK_NETWORK_NAME="rskRegtest"
    ;;
  *)
    echo "Error: unsupported network '$NETWORK'" >&2
    exit 1
    ;;
esac

if [[ -z "$PEGIN_ADDRESS" ]]; then
  PEGIN_ADDRESS="$(jq -r --arg network "$RSK_NETWORK_NAME" '.[$network].PegInContract.address // empty' addresses.json)"
fi
[[ -n "$PEGIN_ADDRESS" ]] || {
  echo "Error: could not resolve PegIn address (set PEGIN_CONTRACT_ADDRESS or --pegin-address)" >&2
  exit 1
}

CHAIN_ID="$(cast chain-id --rpc-url "$RPC_URL")"

FED_BTC_ADDR="$(jq -r '.fedBTCAddr' "$QUOTE_FILE")"
LBC_ADDR="$(jq -r '.lbcAddr' "$QUOTE_FILE")"
LP_RSK_ADDR="$(jq -r '.lpRSKAddr' "$QUOTE_FILE")"
BTC_REFUND_ADDR="$(jq -r '.btcRefundAddr' "$QUOTE_FILE")"
RSK_REFUND_ADDR="$(jq -r '.rskRefundAddr' "$QUOTE_FILE")"
LP_BTC_ADDR="$(jq -r '.lpBTCAddr' "$QUOTE_FILE")"

CALL_FEE="$(jq -r '.callFee|tostring' "$QUOTE_FILE")"
PENALTY_FEE="$(jq -r '.penaltyFee|tostring' "$QUOTE_FILE")"
VALUE="$(jq -r '.value|tostring' "$QUOTE_FILE")"
GAS_FEE="$(jq -r '.gasFee|tostring' "$QUOTE_FILE")"
CONTRACT_ADDR="$(jq -r '.contractAddr' "$QUOTE_FILE")"
DATA="$(jq -r '.data' "$QUOTE_FILE")"
GAS_LIMIT_QUOTE="$(jq -r '.gasLimit|tostring' "$QUOTE_FILE")"
NONCE="$(jq -r '.nonce|tostring' "$QUOTE_FILE")"
AGREEMENT_TIMESTAMP="$(jq -r '.agreementTimestamp|tostring' "$QUOTE_FILE")"
TIME_FOR_DEPOSIT="$(jq -r '.timeForDeposit|tostring' "$QUOTE_FILE")"
LP_CALL_TIME="$(jq -r '.lpCallTime|tostring' "$QUOTE_FILE")"
CONFIRMATIONS="$(jq -r '.confirmations|tostring' "$QUOTE_FILE")"
CALL_ON_REGISTER="$(jq -r '.callOnRegister' "$QUOTE_FILE")"

FED_ADDR_FULL_HEX="$(btc_addr_to_hex "$FED_BTC_ADDR")"
FED_ADDR_FULL_HEX="${FED_ADDR_FULL_HEX#0x}"
if [[ "${#FED_ADDR_FULL_HEX}" -lt 42 ]]; then
  echo "Error: parsed fedBTCAddr has invalid length: $FED_BTC_ADDR" >&2
  exit 1
fi
FED_BTC_BYTES20="0x${FED_ADDR_FULL_HEX:2:40}"
BTC_REFUND_BYTES="$(with_0x "$(btc_addr_to_hex "$BTC_REFUND_ADDR")")"
LP_BTC_BYTES="$(with_0x "$(btc_addr_to_hex "$LP_BTC_ADDR")")"
DATA="$(with_0x "$DATA")"
SIGNATURE="$(with_0x "$SIGNATURE")"

TX_JSON="$(npx ts-node script/helpers/fetch-btc-tx-data.ts "$TXID" "$BTC_NETWORK")"
RAW_TX="$(with_0x "$(jq -r '.rawTx' <<<"$TX_JSON")")"
PMT="$(with_0x "$(jq -r '.pmt' <<<"$TX_JSON")")"
HEIGHT="$(jq -r '.height|tostring' <<<"$TX_JSON")"

ABI_SIG='registerPegIn((uint256,uint256,uint256,uint256,uint256,bytes20,address,address,address,address,int64,uint32,uint32,uint32,uint32,uint16,bool,bytes,bytes,bytes),bytes,bytes,bytes,uint256)'
QUOTE_TUPLE="(${CHAIN_ID},${CALL_FEE},${PENALTY_FEE},${VALUE},${GAS_FEE},${FED_BTC_BYTES20},${LBC_ADDR},${LP_RSK_ADDR},${CONTRACT_ADDR},${RSK_REFUND_ADDR},${NONCE},${GAS_LIMIT_QUOTE},${AGREEMENT_TIMESTAMP},${TIME_FOR_DEPOSIT},${LP_CALL_TIME},${CONFIRMATIONS},${CALL_ON_REGISTER},${BTC_REFUND_BYTES},${LP_BTC_BYTES},${DATA})"

echo "Registering PegIn via cast on $NETWORK"
echo "RPC URL: $RPC_URL"
echo "PegIn Contract: $PEGIN_ADDRESS"
echo "BTC tx height: $HEIGHT"

if [[ "$BROADCAST" == true ]]; then
  [[ -n "$PRIVATE_KEY" ]] || { echo "Error: private key is required in broadcast mode" >&2; exit 1; }
  cast send "$PEGIN_ADDRESS" "$ABI_SIG" "$QUOTE_TUPLE" "$SIGNATURE" "$RAW_TX" "$PMT" "$HEIGHT" \
    --rpc-url "$RPC_URL" \
    --private-key "$(with_0x "$PRIVATE_KEY")" \
    --legacy \
    --gas-limit "$GAS_LIMIT"
else
  cast call "$PEGIN_ADDRESS" "$ABI_SIG" "$QUOTE_TUPLE" "$SIGNATURE" "$RAW_TX" "$PMT" "$HEIGHT" \
    --rpc-url "$RPC_URL"
fi
