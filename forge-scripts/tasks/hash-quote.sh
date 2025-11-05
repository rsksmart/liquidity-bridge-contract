#!/bin/bash

# Enhanced wrapper script for HashQuote.s.sol
# Automatically handles mainnet, testnet, and local networks

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Load .env file if it exists (safer loading)
if [ -f .env ]; then
    # shellcheck disable=SC2046
    export $(grep -v '^#' .env | grep -v '^$' | xargs) 2>/dev/null || true
fi

# Default values
TYPE=""
FILE=""
NETWORK="${NETWORK:-rskTestnet}"

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

# Parse arguments
show_usage() {
    echo "Usage: $0 --type <pegin|pegout> --file <json-file> [options]"
    echo ""
    echo "Options:"
    echo "  --type          Type of quote: 'pegin' or 'pegout' (required)"
    echo "  --file          Path to JSON file containing the quote (required)"
    echo "  --network       Network: mainnet, testnet, regtest, local, dev (default: testnet)"
    echo "  --rpc-url       Custom RPC URL (optional, overrides network default)"
    echo "  --lbc-address   LBC contract address (optional, overrides addresses.json)"
    echo ""
    echo "Supported Networks:"
    echo "  mainnet, rskMainnet     - RSK Mainnet (https://public-node.rsk.co)"
    echo "  testnet, rskTestnet     - RSK Testnet (https://public-node.testnet.rsk.co)"
    echo "  regtest, rskRegtest     - Local Regtest (http://localhost:4444)"
    echo "  local                   - Alias for regtest"
    echo "  dev, rskDevelopment     - Development network"
    echo ""
    echo "Environment variables (from .env):"
    echo "  NETWORK             - Default network"
    echo "  MAINNET_RPC_URL     - Mainnet RPC endpoint"
    echo "  TESTNET_RPC_URL     - Testnet RPC endpoint"
    echo "  REGTEST_RPC_URL     - Regtest RPC endpoint"
    echo "  LBC_ADDRESS         - LBC contract address override"
    echo ""
    echo "Examples:"
    echo "  # Use testnet (default)"
    echo "  $0 --type pegin --file quote.json"
    echo ""
    echo "  # Use mainnet"
    echo "  $0 --type pegout --file quote.json --network mainnet"
    echo ""
    echo "  # Use local regtest node"
    echo "  $0 --type pegin --file quote.json --network local"
    echo ""
    echo "  # Custom RPC URL"
    echo "  $0 --type pegin --file quote.json --rpc-url http://my-node:4444"
    echo ""
    echo "  # With custom LBC address"
    echo "  LBC_ADDRESS=0x... $0 --type pegin --file quote.json --network testnet"
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --type)
            TYPE="$2"
            shift 2
            ;;
        --file)
            FILE="$2"
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
        --help|-h)
            show_usage
            exit 0
            ;;
        *)
            echo -e "${RED}Error: Unknown option $1${NC}"
            show_usage
            exit 1
            ;;
    esac
done

# Validate required arguments
if [ -z "$TYPE" ]; then
    echo -e "${RED}Error: --type is required${NC}"
    show_usage
    exit 1
fi

if [ -z "$FILE" ]; then
    echo -e "${RED}Error: --file is required${NC}"
    show_usage
    exit 1
fi

if [ ! -f "$FILE" ]; then
    echo -e "${RED}Error: File not found: $FILE${NC}"
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
    echo "Supported networks: mainnet, testnet, regtest, local, dev"
    exit 1
fi

# Validate type
TYPE_LOWER=$(echo "$TYPE" | tr '[:upper:]' '[:lower:]')
if [ "$TYPE_LOWER" != "pegin" ] && [ "$TYPE_LOWER" != "pegout" ]; then
    echo -e "${RED}Error: Type must be 'pegin' or 'pegout'${NC}"
    exit 1
fi

# Determine function signature
if [ "$TYPE_LOWER" = "pegin" ]; then
    FUNCTION_SIG="hashPeginQuote(string)"
else
    FUNCTION_SIG="hashPegoutQuote(string)"
fi

# Display configuration
echo -e "${CYAN}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║${NC}  ${YELLOW}Hash Quote - Foundry Script${NC}                              ${CYAN}║${NC}"
echo -e "${CYAN}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${CYAN}Configuration:${NC}"
echo -e "  Type:           ${GREEN}$TYPE_LOWER${NC}"
echo -e "  File:           ${GREEN}$FILE${NC}"
echo -e "  Network:        ${GREEN}$NORMALIZED_NETWORK${NC}"
echo -e "  RPC URL:        ${GREEN}$RPC_URL${NC}"
if [ -n "$LBC_ADDRESS" ]; then
    echo -e "  LBC Address:    ${GREEN}$LBC_ADDRESS${NC} ${YELLOW}(override)${NC}"
else
    echo -e "  LBC Address:    ${CYAN}Auto-detect from addresses.json${NC}"
fi
echo ""

# Export network for the script to use
export NETWORK="$NORMALIZED_NETWORK"

# Run forge script
echo -e "${YELLOW}Running Foundry script...${NC}"
echo ""

forge script forge-scripts/tasks/HashQuote.s.sol:HashQuote \
    --sig "$FUNCTION_SIG" "$FILE" \
    --rpc-url "$RPC_URL" \
    --ffi \
    -vv

FORGE_EXIT_CODE=$?

echo ""
if [ $FORGE_EXIT_CODE -eq 0 ]; then
    echo -e "${GREEN}✓ Script completed successfully${NC}"
else
    echo -e "${RED}✗ Script failed with exit code $FORGE_EXIT_CODE${NC}"
    exit $FORGE_EXIT_CODE
fi
