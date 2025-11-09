#!/bin/bash

# Foundry Pause System Script Wrapper
# This script provides an easy interface to pause/unpause all Flyover system contracts

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default values
ACTION=""
REASON=""
RPC_URL=""
BROADCAST=false
PRIVATE_KEY=""
LEDGER=false
INTERACTIVE=false
NETWORK="${NETWORK:-rskRegtest}"
USE_NAMED_RPC=false

# Function to display usage
usage() {
    cat << EOF
${BLUE}Foundry Pause System Script${NC}

Usage: $0 --action <pause|unpause|status> [OPTIONS]

${YELLOW}Required Arguments:${NC}
  --action <action>        Action to perform: 'pause', 'unpause', or 'status' (dry-run)

${YELLOW}RPC Options (choose one):${NC}
  --rpc-url <url>         Direct RPC endpoint URL
  --network <network>     Use named RPC from foundry.toml (rskRegtest, rskTestnet, rskMainnet)

${YELLOW}Optional Arguments:${NC}
  --reason <reason>       Reason for pausing (required when action=pause)
  --broadcast             Broadcast transactions (required for pause/unpause)

${YELLOW}Private Key Options (choose one):${NC}
  --private-key <key>     Private key for signing
  --ledger                Use Ledger hardware wallet
  --interactive           Use interactive keystore

${YELLOW}Environment Variables:${NC}
  NETWORK                           Network name (default: rskRegtest)
  REGTEST_RPC_URL                   RPC URL for rskRegtest
  TESTNET_RPC_URL                   RPC URL for rskTestnet
  MAINNET_RPC_URL                   RPC URL for rskMainnet
  FLYOVER_DISCOVERY_ADDRESS         FlyoverDiscovery contract address
  PEGIN_CONTRACT_ADDRESS            PegInContract address
  PEGOUT_CONTRACT_ADDRESS           PegOutContract address
  COLLATERAL_MANAGEMENT_ADDRESS     CollateralManagementContract address

${YELLOW}Examples:${NC}
  # Local development - check status
  $0 --action status --network rskRegtest

  # Testnet - pause with simulation
  $0 --action pause --reason "Testing pause" --network rskTestnet

  # Testnet - pause with broadcast
  $0 --action pause --reason "Emergency maintenance" \\
     --network rskTestnet --broadcast --private-key \$TESTNET_PRIVATE_KEY

  # Mainnet - status check with custom RPC
  $0 --action status --rpc-url https://public-node.rsk.co --network rskMainnet

  # Mainnet - unpause with ledger (most secure)
  $0 --action unpause --network rskMainnet --broadcast --ledger

  # Using custom RPC URL (not in foundry.toml)
  $0 --action status --rpc-url http://custom-node:4444 --network customNetwork

${YELLOW}Network Presets:${NC}
  ${GREEN}rskRegtest${NC}  - Local development (requires REGTEST_RPC_URL env var)
  ${GREEN}rskTestnet${NC}  - RSK Testnet (requires TESTNET_RPC_URL env var)
  ${GREEN}rskMainnet${NC}  - RSK Mainnet (requires MAINNET_RPC_URL env var)

EOF
    exit 1
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --action)
            ACTION="$2"
            shift 2
            ;;
        --reason)
            REASON="$2"
            shift 2
            ;;
        --rpc-url)
            RPC_URL="$2"
            shift 2
            ;;
        --network)
            NETWORK="$2"
            USE_NAMED_RPC=true
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
        -h|--help)
            usage
            ;;
        *)
            echo -e "${RED}Unknown option: $1${NC}"
            usage
            ;;
    esac
done

# Validate required arguments
if [ -z "$ACTION" ]; then
    echo -e "${RED}Error: --action is required${NC}"
    usage
fi

# Handle RPC URL - either direct or via named network
if [ -z "$RPC_URL" ] && [ "$USE_NAMED_RPC" = false ]; then
    echo -e "${RED}Error: Either --rpc-url or --network is required${NC}"
    usage
fi

# If --network is provided without --rpc-url, use named RPC from foundry.toml
if [ "$USE_NAMED_RPC" = true ] && [ -z "$RPC_URL" ]; then
    case $NETWORK in
        rskRegtest)
            if [ -z "$REGTEST_RPC_URL" ]; then
                echo -e "${RED}Error: REGTEST_RPC_URL environment variable not set${NC}"
                echo -e "${YELLOW}Set it with: export REGTEST_RPC_URL=http://localhost:4444${NC}"
                exit 1
            fi
            RPC_URL="$REGTEST_RPC_URL"
            ;;
        rskTestnet)
            if [ -z "$TESTNET_RPC_URL" ]; then
                echo -e "${RED}Error: TESTNET_RPC_URL environment variable not set${NC}"
                echo -e "${YELLOW}Set it with: export TESTNET_RPC_URL=https://public-node.testnet.rsk.co${NC}"
                exit 1
            fi
            RPC_URL="$TESTNET_RPC_URL"
            ;;
        rskMainnet)
            if [ -z "$MAINNET_RPC_URL" ]; then
                echo -e "${RED}Error: MAINNET_RPC_URL environment variable not set${NC}"
                echo -e "${YELLOW}Set it with: export MAINNET_RPC_URL=https://public-node.rsk.co${NC}"
                exit 1
            fi
            RPC_URL="$MAINNET_RPC_URL"
            ;;
        *)
            echo -e "${RED}Error: Unknown network '$NETWORK'${NC}"
            echo -e "${YELLOW}Supported networks: rskRegtest, rskTestnet, rskMainnet${NC}"
            echo -e "${YELLOW}Or use --rpc-url to specify a custom RPC endpoint${NC}"
            exit 1
            ;;
    esac
    echo -e "${GREEN}Using named RPC endpoint for $NETWORK${NC}"
fi

# Validate action
if [[ ! "$ACTION" =~ ^(pause|unpause|status)$ ]]; then
    echo -e "${RED}Error: --action must be 'pause', 'unpause', or 'status'${NC}"
    usage
fi

# Validate reason for pause action
if [ "$ACTION" = "pause" ] && [ -z "$REASON" ]; then
    echo -e "${RED}Error: --reason is required when action is 'pause'${NC}"
    usage
fi

# Validate broadcast requirements for pause/unpause
if [ "$ACTION" != "status" ] && [ "$BROADCAST" = false ]; then
    echo -e "${YELLOW}Warning: Running in simulation mode. Use --broadcast to actually execute transactions.${NC}"
fi

# Validate private key options
KEY_OPTIONS=0
[ -n "$PRIVATE_KEY" ] && ((KEY_OPTIONS++))
[ "$LEDGER" = true ] && ((KEY_OPTIONS++))
[ "$INTERACTIVE" = true ] && ((KEY_OPTIONS++))

if [ "$BROADCAST" = true ] && [ "$KEY_OPTIONS" -eq 0 ]; then
    echo -e "${RED}Error: When using --broadcast, you must specify one of: --private-key, --ledger, or --interactive${NC}"
    usage
fi

if [ "$KEY_OPTIONS" -gt 1 ]; then
    echo -e "${RED}Error: Only one private key option can be specified${NC}"
    usage
fi

# Build forge script command
SCRIPT_PATH="forge-scripts/tasks/PauseSystem.s.sol:PauseSystem"

# Determine function signature based on action
case $ACTION in
    status)
        FUNCTION_SIG="checkStatus()"
        FUNCTION_ARGS=""
        ;;
    pause)
        FUNCTION_SIG="pauseAll(string)"
        FUNCTION_ARGS="\"$REASON\""
        ;;
    unpause)
        FUNCTION_SIG="unpauseAll()"
        FUNCTION_ARGS=""
        ;;
esac

# Build command
# Use --rpc-url with named endpoint if using named RPC, otherwise use direct URL
if [ "$USE_NAMED_RPC" = true ]; then
    CMD="forge script $SCRIPT_PATH --sig \"$FUNCTION_SIG\" $FUNCTION_ARGS --rpc-url \"$NETWORK\""
else
    CMD="forge script $SCRIPT_PATH --sig \"$FUNCTION_SIG\" $FUNCTION_ARGS --rpc-url \"$RPC_URL\""
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

# Export network for script
export NETWORK="$NETWORK"

# Display command info
echo -e "${BLUE}=== Foundry Pause System ===${NC}"
echo -e "${BLUE}Action:${NC} $ACTION"
echo -e "${BLUE}Network:${NC} $NETWORK"
echo -e "${BLUE}RPC URL:${NC} $RPC_URL"
if [ "$ACTION" = "pause" ]; then
    echo -e "${BLUE}Reason:${NC} $REASON"
fi
if [ "$BROADCAST" = true ]; then
    echo -e "${YELLOW}Mode: BROADCAST (transactions will be sent)${NC}"
else
    echo -e "${GREEN}Mode: SIMULATION (dry-run, no transactions will be sent)${NC}"
fi
echo ""

# Confirm for broadcast operations
if [ "$BROADCAST" = true ] && [ "$ACTION" != "status" ]; then
    echo -e "${YELLOW}WARNING: You are about to ${ACTION} all Flyover system contracts!${NC}"
    echo -e "${YELLOW}This will affect:${NC}"
    echo "  - FlyoverDiscovery"
    echo "  - PegInContract"
    echo "  - PegOutContract"
    echo "  - CollateralManagementContract"
    echo ""
    read -r -p "Are you sure you want to continue? (yes/no): " CONFIRM
    if [ "$CONFIRM" != "yes" ]; then
        echo -e "${RED}Operation cancelled${NC}"
        exit 1
    fi
    echo ""
fi

# Execute command
echo -e "${GREEN}Executing forge script...${NC}"
echo ""

# Check exit code directly
if eval "$CMD"; then
    echo ""
    echo -e "${GREEN}=== Operation completed successfully ===${NC}"
else
    echo ""
    echo -e "${RED}=== Operation failed ===${NC}"
    exit 1
fi
