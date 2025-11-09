#!/bin/bash

# Foundry Register PegIn Script Wrapper
# This script provides an easy interface to register PegIn Bitcoin transactions

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Default values
QUOTE_FILE=""
SIGNATURE=""
TXID=""
NETWORK="${NETWORK:-rskTestnet}"
BROADCAST=false
PRIVATE_KEY=""
LEDGER=false
INTERACTIVE=false
CUSTOM_RPC_URL=""
BTC_NETWORK=""

# Network configurations
declare -A RPC_URLS=(
    ["rskMainnet"]="${MAINNET_RPC_URL:-https://public-node.rsk.co}"
    ["rskTestnet"]="${TESTNET_RPC_URL:-https://public-node.testnet.rsk.co}"
    ["rskRegtest"]="${REGTEST_RPC_URL:-http://localhost:4444}"
    ["rskDevelopment"]="${TESTNET_RPC_URL:-https://public-node.testnet.rsk.co}"
    ["mainnet"]="${MAINNET_RPC_URL:-https://public-node.rsk.co}"
    ["testnet"]="${TESTNET_RPC_URL:-https://public-node.testnet.rsk.co}"
    ["regtest"]="${REGTEST_RPC_URL:-http://localhost:4444}"
    ["local"]="${REGTEST_RPC_URL:-http://localhost:4444}"
)

# Network name normalization
declare -A NETWORK_ALIASES=(
    ["mainnet"]="rskMainnet"
    ["testnet"]="rskTestnet"
    ["regtest"]="rskRegtest"
    ["local"]="rskRegtest"
    ["dev"]="rskDevelopment"
)

# Auto-detect Bitcoin network from RSK network
declare -A BTC_NETWORKS=(
    ["rskMainnet"]="mainnet"
    ["rskTestnet"]="testnet"
    ["rskRegtest"]="testnet"
    ["rskDevelopment"]="testnet"
)

# Function to display usage
usage() {
    cat << EOF
${CYAN}╔════════════════════════════════════════════════════════════╗${NC}
${CYAN}║${NC}  ${YELLOW}Register PegIn - Foundry Script${NC}                         ${CYAN}║${NC}
${CYAN}╚════════════════════════════════════════════════════════════╝${NC}

${YELLOW}Description:${NC}
  Register a PegIn bitcoin transaction within the Liquidity Bridge Contract.
  This script fetches Bitcoin transaction data from mempool.space and registers it.

${YELLOW}Usage:${NC}
  $0 --file <quote-json> --signature <sig> --txid <bitcoin-txid> [OPTIONS]

${YELLOW}Required Arguments:${NC}
  --file <json-file>      Path to JSON file containing the PegIn quote
  --signature <sig>       LP signature (with or without 0x prefix)
  --txid <bitcoin-txid>   Bitcoin transaction ID to register

${YELLOW}Optional Arguments:${NC}
  --network <network>     Network: mainnet, testnet, regtest, local (default: testnet)
  --rpc-url <url>         Custom RPC URL (overrides network default)
  --lbc-address <addr>    LBC contract address (overrides addresses.json)
  --btc-network <net>     Bitcoin network: mainnet or testnet (auto-detected if not set)
  --broadcast             Broadcast the transaction (required for actual execution)

${YELLOW}Private Key Options (choose one, required with --broadcast):${NC}
  --private-key <key>     Private key for signing
  --ledger                Use Ledger hardware wallet
  --interactive           Use interactive keystore

${YELLOW}Supported Networks:${NC}
  ${GREEN}mainnet, rskMainnet${NC}     - RSK Mainnet (uses Bitcoin mainnet)
  ${GREEN}testnet, rskTestnet${NC}     - RSK Testnet (uses Bitcoin testnet)
  ${GREEN}regtest, rskRegtest${NC}     - Local Regtest (uses Bitcoin testnet)
  ${GREEN}local${NC}                   - Alias for regtest

${YELLOW}Environment Variables:${NC}
  NETWORK             - Default network (default: rskTestnet)
  MAINNET_RPC_URL     - Mainnet RPC endpoint
  TESTNET_RPC_URL     - Testnet RPC endpoint
  REGTEST_RPC_URL     - Regtest RPC endpoint
  LBC_ADDRESS         - LBC contract address override
  BTC_NETWORK         - Bitcoin network (mainnet or testnet)

${YELLOW}Prerequisites:${NC}
  - FFI must be enabled in foundry.toml
  - Node.js packages: @mempool/mempool.js, bitcoinjs-lib, @rsksmart/pmt-builder
  - Bitcoin transaction must be confirmed on-chain

${YELLOW}Examples:${NC}
  # Simulate registration on testnet
  $0 --file tasks/hash-quote.example.json \\
     --signature 0xabcd1234... \\
     --txid a1b2c3d4e5f6... \\
     --network testnet

  # Execute registration on testnet with private key
  $0 --file tasks/hash-quote.example.json \\
     --signature 0xabcd1234... \\
     --txid a1b2c3d4e5f6... \\
     --network testnet \\
     --broadcast \\
     --private-key \$TESTNET_PRIVATE_KEY

  # Execute on mainnet with Ledger (most secure)
  $0 --file quote.json \\
     --signature 0xabcd... \\
     --txid abc123... \\
     --network mainnet \\
     --broadcast \\
     --ledger

${YELLOW}Modes:${NC}
  ${GREEN}Simulation Mode${NC} (no --broadcast):
    - Fetches Bitcoin transaction data from mempool.space
    - Validates the quote and signature
    - Estimates gas costs
    - Does NOT execute the transaction

  ${YELLOW}Broadcast Mode${NC} (with --broadcast):
    - Performs all simulation checks
    - Executes the actual registration transaction
    - Requires a private key option
    - Transaction will be sent to the blockchain

EOF
    exit 1
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --file)
            QUOTE_FILE="$2"
            shift 2
            ;;
        --signature|--sig)
            SIGNATURE="$2"
            shift 2
            ;;
        --txid)
            TXID="$2"
            shift 2
            ;;
        --network)
            NETWORK="$2"
            shift 2
            ;;
        --rpc-url)
            CUSTOM_RPC_URL="$2"
            shift 2
            ;;
        --lbc-address)
            export LBC_ADDRESS="$2"
            shift 2
            ;;
        --btc-network)
            BTC_NETWORK="$2"
            shift 2
            ;;
        --broadcast)
            BROADCAST=true
            shift
            ;;
        --private-key)
            PRIVATE_KEY="$2"
            shift 2
            ;;
        --ledger)
            LEDGER=true
            shift
            ;;
        --interactive)
            INTERACTIVE=true
            shift
            ;;
        --help|-h)
            usage
            ;;
        *)
            echo -e "${RED}Error: Unknown option $1${NC}"
            usage
            ;;
    esac
done

# Validate required arguments
if [ -z "$QUOTE_FILE" ]; then
    echo -e "${RED}Error: --file is required${NC}"
    usage
fi

if [ -z "$SIGNATURE" ]; then
    echo -e "${RED}Error: --signature is required${NC}"
    usage
fi

if [ -z "$TXID" ]; then
    echo -e "${RED}Error: --txid is required${NC}"
    usage
fi

# Validate file exists
if [ ! -f "$QUOTE_FILE" ]; then
    echo -e "${RED}Error: Quote file not found: $QUOTE_FILE${NC}"
    exit 1
fi

# Normalize network name
if [ -n "${NETWORK_ALIASES[$NETWORK]}" ]; then
    NORMALIZED_NETWORK="${NETWORK_ALIASES[$NETWORK]}"
else
    NORMALIZED_NETWORK="$NETWORK"
fi

# Determine RPC URL
if [ -n "$CUSTOM_RPC_URL" ]; then
    RPC_URL="$CUSTOM_RPC_URL"
elif [ -n "${RPC_URLS[$NETWORK]}" ]; then
    RPC_URL="${RPC_URLS[$NETWORK]}"
elif [ -n "${RPC_URLS[$NORMALIZED_NETWORK]}" ]; then
    RPC_URL="${RPC_URLS[$NORMALIZED_NETWORK]}"
else
    echo -e "${RED}Error: Unknown network: $NETWORK${NC}"
    echo "Supported networks: mainnet, testnet, regtest, local"
    exit 1
fi

# Auto-detect Bitcoin network if not specified
if [ -z "$BTC_NETWORK" ]; then
    if [ -n "${BTC_NETWORKS[$NORMALIZED_NETWORK]}" ]; then
        BTC_NETWORK="${BTC_NETWORKS[$NORMALIZED_NETWORK]}"
    else
        BTC_NETWORK="testnet"  # Default to testnet
    fi
fi

# Validate Bitcoin network
if [ "$BTC_NETWORK" != "mainnet" ] && [ "$BTC_NETWORK" != "testnet" ]; then
    echo -e "${RED}Error: --btc-network must be 'mainnet' or 'testnet'${NC}"
    exit 1
fi

# Validate broadcast requirements
if [ "$BROADCAST" = true ]; then
    # Validate private key options
    KEY_OPTIONS=0
    [ -n "$PRIVATE_KEY" ] && ((KEY_OPTIONS++))
    [ "$LEDGER" = true ] && ((KEY_OPTIONS++))
    [ "$INTERACTIVE" = true ] && ((KEY_OPTIONS++))

    if [ "$KEY_OPTIONS" -eq 0 ]; then
        echo -e "${RED}Error: When using --broadcast, you must specify one of: --private-key, --ledger, or --interactive${NC}"
        usage
    fi

    if [ "$KEY_OPTIONS" -gt 1 ]; then
        echo -e "${RED}Error: Only one private key option can be specified${NC}"
        usage
    fi
fi

# Display configuration
echo -e "${CYAN}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║${NC}  ${YELLOW}Register PegIn - Configuration${NC}                          ${CYAN}║${NC}"
echo -e "${CYAN}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${CYAN}Quote File:${NC}      ${GREEN}${QUOTE_FILE}${NC}"
echo -e "${CYAN}Signature:${NC}       ${GREEN}${SIGNATURE:0:20}...${NC}"
echo -e "${CYAN}BTC TX ID:${NC}       ${GREEN}${TXID}${NC}"
echo -e "${CYAN}Network:${NC}         ${GREEN}${NORMALIZED_NETWORK}${NC}"
echo -e "${CYAN}BTC Network:${NC}     ${GREEN}${BTC_NETWORK}${NC}"
echo -e "${CYAN}RPC URL:${NC}         ${GREEN}${RPC_URL}${NC}"
if [ -n "$LBC_ADDRESS" ]; then
    echo -e "${CYAN}LBC Address:${NC}     ${GREEN}${LBC_ADDRESS}${NC} ${YELLOW}(override)${NC}"
else
    echo -e "${CYAN}LBC Address:${NC}     ${CYAN}Auto-detect from addresses.json${NC}"
fi
echo ""

if [ "$BROADCAST" = true ]; then
    echo -e "${YELLOW}╔═══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${YELLOW}║  MODE: BROADCAST - Transaction will be executed!         ║${NC}"
    echo -e "${YELLOW}╚═══════════════════════════════════════════════════════════╝${NC}"
    echo ""
else
    echo -e "${GREEN}╔═══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║  MODE: SIMULATION - Dry-run (no transaction sent)        ║${NC}"
    echo -e "${GREEN}╚═══════════════════════════════════════════════════════════╝${NC}"
    echo ""
fi

# Export environment variables for the script
export NETWORK="$NORMALIZED_NETWORK"
export BTC_NETWORK="$BTC_NETWORK"

# Build forge script command
SCRIPT_PATH="forge-scripts/tasks/RegisterPegin.s.sol:RegisterPegin"
FUNCTION_SIG="registerPegin(string,string,string)"

CMD="forge script $SCRIPT_PATH --sig \"$FUNCTION_SIG\" \"$QUOTE_FILE\" \"$SIGNATURE\" \"$TXID\" --rpc-url \"$RPC_URL\" --ffi"

# Add broadcast flag if needed
if [ "$BROADCAST" = true ]; then
    CMD="$CMD --broadcast"
fi

# Add private key option
if [ -n "$PRIVATE_KEY" ]; then
    CMD="$CMD --private-key \"$PRIVATE_KEY\""
elif [ "$LEDGER" = true ]; then
    CMD="$CMD --ledger"
elif [ "$INTERACTIVE" = true ]; then
    CMD="$CMD --interactive"
fi

# Add verbosity
CMD="$CMD -vv"

# Execute command
echo -e "${YELLOW}Executing forge script...${NC}"
echo ""

if eval "$CMD"; then
    echo ""
    if [ "$BROADCAST" = true ]; then
        echo -e "${GREEN}╔═══════════════════════════════════════════════════════════╗${NC}"
        echo -e "${GREEN}║  ✓ Registration transaction executed successfully!       ║${NC}"
        echo -e "${GREEN}╚═══════════════════════════════════════════════════════════╝${NC}"
    else
        echo -e "${GREEN}╔═══════════════════════════════════════════════════════════╗${NC}"
        echo -e "${GREEN}║  ✓ Simulation completed successfully!                    ║${NC}"
        echo -e "${GREEN}║                                                           ║${NC}"
        echo -e "${GREEN}║  To execute the transaction, run with --broadcast        ║${NC}"
        echo -e "${GREEN}╚═══════════════════════════════════════════════════════════╝${NC}"
    fi
else
    echo ""
    echo -e "${RED}╔═══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${RED}║  ✗ Operation failed!                                     ║${NC}"
    echo -e "${RED}╚═══════════════════════════════════════════════════════════╝${NC}"
    exit 1
fi
