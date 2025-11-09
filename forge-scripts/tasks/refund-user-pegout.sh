#!/bin/bash

# Foundry Refund User PegOut Script Wrapper
# This script provides an easy interface to refund users for expired PegOut quotes

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Default values
QUOTE_HASH=""
QUOTE_FILE=""
NETWORK="${NETWORK:-rskTestnet}"
BROADCAST=false
PRIVATE_KEY=""
LEDGER=false
INTERACTIVE=false
CUSTOM_RPC_URL=""

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

# Function to display usage
usage() {
    cat << EOF
${CYAN}╔════════════════════════════════════════════════════════════╗${NC}
${CYAN}║${NC}  ${YELLOW}Refund User PegOut - Foundry Script${NC}                     ${CYAN}║${NC}
${CYAN}╚════════════════════════════════════════════════════════════╝${NC}

${YELLOW}Description:${NC}
  Refund a user that didn't receive their PegOut in the agreed time.
  This script allows both simulation (dry-run) and broadcast (execution) modes.

${YELLOW}Usage:${NC}
  $0 --quote-hash <hash> [OPTIONS]
  $0 --file <json-file> [OPTIONS]

${YELLOW}Required Arguments (choose one):${NC}
  --quote-hash <hash>     The hash of the accepted PegOut quote (with or without 0x prefix)
  --file <json-file>      Path to JSON file containing the pegout quote (will auto-hash)

${YELLOW}Optional Arguments:${NC}
  --network <network>     Network: mainnet, testnet, regtest, local (default: testnet)
  --rpc-url <url>         Custom RPC URL (overrides network default)
  --lbc-address <addr>    LBC contract address (overrides addresses.json)
  --broadcast             Broadcast the transaction (required for actual execution)

${YELLOW}Private Key Options (choose one, required with --broadcast):${NC}
  --private-key <key>     Private key for signing
  --ledger                Use Ledger hardware wallet
  --interactive           Use interactive keystore

${YELLOW}Supported Networks:${NC}
  ${GREEN}mainnet, rskMainnet${NC}     - RSK Mainnet
  ${GREEN}testnet, rskTestnet${NC}     - RSK Testnet
  ${GREEN}regtest, rskRegtest${NC}     - Local Regtest
  ${GREEN}local${NC}                   - Alias for regtest

${YELLOW}Environment Variables:${NC}
  NETWORK             - Default network (default: rskTestnet)
  MAINNET_RPC_URL     - Mainnet RPC endpoint
  TESTNET_RPC_URL     - Testnet RPC endpoint
  REGTEST_RPC_URL     - Regtest RPC endpoint
  LBC_ADDRESS         - LBC contract address override

${YELLOW}Examples:${NC}
  # Simulate refund on testnet using quote hash (dry-run with gas estimation)
  $0 --quote-hash abc123def456... --network testnet

  # Simulate refund on testnet using quote file (auto-hashes)
  $0 --file tasks/hash-quote-pegout.example.json --network testnet

  # Execute refund on testnet with private key
  $0 --quote-hash abc123def456... \\
     --network testnet \\
     --broadcast \\
     --private-key \$TESTNET_PRIVATE_KEY

  # Execute refund from file on testnet
  $0 --file tasks/hash-quote-pegout.example.json \\
     --network testnet \\
     --broadcast \\
     --private-key \$TESTNET_PRIVATE_KEY

  # Execute refund on mainnet with ledger (most secure)
  $0 --quote-hash abc123def456... \\
     --network mainnet \\
     --broadcast \\
     --ledger

  # Use custom RPC URL
  $0 --quote-hash abc123def456... \\
     --rpc-url http://custom-node:4444 \\
     --broadcast \\
     --private-key \$PRIVATE_KEY

  # Simulate with custom LBC address
  LBC_ADDRESS=0x1234... $0 --quote-hash abc123def456... --network testnet

${YELLOW}Modes:${NC}
${YELLOW}Input Methods:${NC}
  ${GREEN}Quote Hash${NC} (--quote-hash):
    - Use when you already have the quote hash
    - Fast, no need for FFI or JSON parsing

  ${GREEN}Quote File${NC} (--file):
    - Use when you have the quote JSON file
    - Script will automatically hash the quote for you
    - Requires FFI enabled and Bitcoin address parsing

${YELLOW}Modes:${NC}
  ${GREEN}Simulation Mode${NC} (no --broadcast):
    - Validates the quote hash/file format
    - Checks if the quote exists and is expired
    - Estimates gas costs
    - Does NOT execute the transaction
    - Useful for testing before actual execution

  ${YELLOW}Broadcast Mode${NC} (with --broadcast):
    - Performs all simulation checks
    - Executes the actual refund transaction
    - Requires a private key option
    - Transaction will be sent to the blockchain

EOF
    exit 1
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --quote-hash|--quotehash)
            QUOTE_HASH="$2"
            shift 2
            ;;
        --file)
            QUOTE_FILE="$2"
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
if [ -z "$QUOTE_HASH" ] && [ -z "$QUOTE_FILE" ]; then
    echo -e "${RED}Error: Either --quote-hash or --file is required${NC}"
    usage
fi

if [ -n "$QUOTE_HASH" ] && [ -n "$QUOTE_FILE" ]; then
    echo -e "${RED}Error: Cannot specify both --quote-hash and --file${NC}"
    echo -e "${YELLOW}Please use one or the other${NC}"
    exit 1
fi

# If using file mode, validate file exists
if [ -n "$QUOTE_FILE" ]; then
    if [ ! -f "$QUOTE_FILE" ]; then
        echo -e "${RED}Error: Quote file not found: $QUOTE_FILE${NC}"
        exit 1
    fi
    USE_FILE_MODE=true
else
    USE_FILE_MODE=false

    # Remove 0x prefix if present
    QUOTE_HASH="${QUOTE_HASH#0x}"
    QUOTE_HASH="${QUOTE_HASH#0X}"

    # Validate quote hash format (should be 64 hex characters)
    if ! [[ "$QUOTE_HASH" =~ ^[0-9a-fA-F]{64}$ ]]; then
        echo -e "${RED}Error: Invalid quote hash format${NC}"
        echo -e "${YELLOW}Expected: 64 hexadecimal characters (with or without 0x prefix)${NC}"
        echo -e "${YELLOW}Got: $QUOTE_HASH (${#QUOTE_HASH} characters)${NC}"
        exit 1
    fi
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
echo -e "${CYAN}║${NC}  ${YELLOW}Refund User PegOut - Configuration${NC}                      ${CYAN}║${NC}"
echo -e "${CYAN}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""
if [ "$USE_FILE_MODE" = true ]; then
    echo -e "${CYAN}Mode:${NC}            ${GREEN}File Mode (auto-hash)${NC}"
    echo -e "${CYAN}Quote File:${NC}      ${GREEN}${QUOTE_FILE}${NC}"
else
    echo -e "${CYAN}Mode:${NC}            ${GREEN}Hash Mode${NC}"
    echo -e "${CYAN}Quote Hash:${NC}      ${GREEN}${QUOTE_HASH}${NC}"
fi
echo -e "${CYAN}Network:${NC}         ${GREEN}${NORMALIZED_NETWORK}${NC}"
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

# Export network for the script to use
export NETWORK="$NORMALIZED_NETWORK"

# Build forge script command
SCRIPT_PATH="forge-scripts/tasks/RefundUserPegout.s.sol:RefundUserPegout"

if [ "$USE_FILE_MODE" = true ]; then
    FUNCTION_SIG="refundUserPegoutFromFile(string)"
    FUNCTION_ARG="$QUOTE_FILE"
    CMD="forge script $SCRIPT_PATH --sig \"$FUNCTION_SIG\" \"$FUNCTION_ARG\" --rpc-url \"$RPC_URL\" --ffi"
else
    FUNCTION_SIG="refundUserPegout(string)"
    FUNCTION_ARG="$QUOTE_HASH"
    CMD="forge script $SCRIPT_PATH --sig \"$FUNCTION_SIG\" \"$FUNCTION_ARG\" --rpc-url \"$RPC_URL\""
fi

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
        echo -e "${GREEN}║  ✓ Refund transaction executed successfully!             ║${NC}"
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
