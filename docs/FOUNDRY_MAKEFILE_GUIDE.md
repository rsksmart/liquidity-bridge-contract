# Foundry and Makefile Guide for Liquidity Bridge Contract

This guide explains how to use Foundry and the Makefile for deploying, upgrading, and managing the Liquidity Bridge Contract across different networks.

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [Environment Setup](#environment-setup)
3. [Foundry Basics](#foundry-basics)
4. [Makefile Overview](#makefile-overview)
5. [Deployment Commands](#deployment-commands)
6. [Network Configuration](#network-configuration)
7. [Fork Testing](#fork-testing)
8. [Safety Features](#safety-features)
9. [Troubleshooting](#troubleshooting)
10. [Examples](#examples)

## Prerequisites

### Required Software
- **Foundry**: Install from [getfoundry.sh](https://getfoundry.sh)
- **Git**: For version control
- **Node.js**: For additional dependencies

### Install Foundry
```bash
curl -L https://foundry.paradigm.xyz | bash
foundryup
```

### Verify Installation
```bash
forge --version
cast --version
anvil --version
```

## Environment Setup

### 1. Clone the Repository
```bash
git clone <repository-url>
cd liquidity-bridge-contract
```

### 2. Install Dependencies
```bash
# Install Foundry dependencies
forge install

# Install Node.js dependencies (if any)
npm install
```

### 3. Environment Configuration
Copy the example environment file and configure it:

```bash
cp example.env .env
```

Edit `.env` with your configuration:

```bash
# RPC URLs
MAINNET_RPC_URL=https://public-node.rsk.co
TESTNET_RPC_URL=https://public-node.testnet.rsk.co
REGTEST_RPC_URL=http://localhost:4444

# Private Keys (NEVER commit these!)
MAINNET_SIGNER_PRIVATE_KEY=your_mainnet_private_key
TESTNET_SIGNER_PRIVATE_KEY=your_testnet_private_key
DEV_SIGNER_PRIVATE_KEY=your_dev_private_key

# Existing contract addresses (for upgrades)
EXISTING_PROXY_MAINNET=0x...
EXISTING_ADMIN_MAINNET=0x...
EXISTING_PROXY_TESTNET=0x...
EXISTING_ADMIN_TESTNET=0x...

# Multisig configuration
MULTISIG_ADDRESS_MAINNET=0x...
MULTISIG_OWNER_1_MAINNET=0x...
# ... add more owners as needed
```

## Foundry Basics

### Key Foundry Commands

#### `forge build`
Compile all contracts:
```bash
forge build
```

#### `forge test`
Run tests:
```bash
forge test
forge test --gas-report  # With gas reporting
```

#### `forge script`
Execute deployment scripts:
```bash
forge script <script_path> --rpc-url <url> --private-key <key> --broadcast
```

#### `forge verify-contract`
Verify contracts on block explorers:
```bash
forge verify-contract <address> <contract_name> --chain-id <id> --etherscan-api-key <key>
```

### Foundry Configuration (`foundry.toml`)

The project uses a custom `foundry.toml` configuration:

```toml
[profile.default]
src = "contracts"
test = "forge-test"
out = "out"
cache_path = "forge-cache"
solc_version = "0.8.25"
optimizer = true
optimizer_runs = 1

[rpc_endpoints]
rskRegtest = "${REGTEST_RPC_URL}"
rskTestnet = "${TESTNET_RPC_URL}"
rskMainnet = "${MAINNET_RPC_URL}"
```

## Makefile Overview

The Makefile provides a convenient interface for all Foundry operations with built-in safety features.

### Key Features
- **Network Support**: Mainnet, Testnet, Dev environments
- **Fork Testing**: Test against forked networks
- **Safety Validation**: Environment checks and mainnet confirmations
- **Simulation vs Deployment**: Separate commands for testing and actual deployment

### Basic Usage
```bash
make <target> [NETWORK=<network>] [FORK_BLOCK=<block>] [VERIFY=<true|false>]
```

## Deployment Commands

### Simulation Commands (Safe Testing)

These commands simulate deployments without broadcasting transactions:

```bash
# Deploy LiquidityBridgeContract (simulation)
make deploy-lbc NETWORK=testnet

# Upgrade to V2 (simulation)
make upgrade-lbc NETWORK=testnet

# Transfer ownership (simulation)
make change-owner NETWORK=testnet

# High gas deployment (simulation)
make deploy-lbc-high-gas NETWORK=testnet
```

### Actual Deployment Commands

These commands broadcast real transactions:

```bash
# Deploy LiquidityBridgeContract (actual)
make deploy-lbc-broadcast NETWORK=testnet

# Upgrade to V2 (actual)
make upgrade-lbc-broadcast NETWORK=testnet

# Transfer ownership (actual)
make change-owner-broadcast NETWORK=testnet

# High gas deployment (actual)
make deploy-lbc-high-gas-broadcast NETWORK=testnet
```

### Safe Deployment Commands

These include additional validation:

```bash
# Safe deployment with validation
make safe-deploy-lbc-broadcast NETWORK=mainnet

# Safe upgrade with validation
make safe-upgrade-lbc-broadcast NETWORK=mainnet

# Safe ownership transfer with validation
make safe-change-owner-broadcast NETWORK=mainnet
```

## Network Configuration

### Supported Networks

| Network | Chain ID | RPC URL | Description |
|---------|----------|---------|-------------|
| mainnet | 30 | RSK Mainnet | Production network |
| testnet | 31 | RSK Testnet | Test network |
| dev | 1337 | Local | Development network |

### Network-Specific Commands

```bash
# Mainnet operations
make deploy-lbc NETWORK=mainnet
make upgrade-lbc-broadcast NETWORK=mainnet

# Testnet operations
make deploy-lbc NETWORK=testnet
make change-owner-broadcast NETWORK=testnet

# Dev operations
make dev-deploy
make dev-deploy-broadcast
```

## Fork Testing

Fork testing allows you to test against real network state without using real funds.

### Fork Commands

```bash
# Testnet fork simulation
make testnet-fork-deploy

# Testnet fork actual deployment
make testnet-fork-deploy-broadcast

# Mainnet fork simulation
make mainnet-fork-deploy

# Mainnet fork actual deployment
make mainnet-fork-deploy-broadcast
```

### Fork Configuration

```bash
# Specify fork block
make deploy-lbc NETWORK=testnet FORK_BLOCK=6020639

# Use latest block
make deploy-lbc NETWORK=mainnet FORK_BLOCK=latest
```

## Safety Features

### Environment Validation

The Makefile includes built-in safety checks:

```bash
# Check environment configuration
make check-env NETWORK=testnet

# Validate deployment prerequisites
make validate-deploy NETWORK=mainnet
```

### Mainnet Protection

Mainnet deployments require explicit confirmation:

```bash
# This will prompt for confirmation
make safe-deploy-lbc-broadcast NETWORK=mainnet
```

### Gas Management

```bash
# Default gas limit (10M)
make deploy-lbc NETWORK=testnet

# High gas limit (15M)
make deploy-lbc-high-gas NETWORK=testnet

# Custom gas limit
make deploy-lbc NETWORK=testnet GAS_LIMIT=20000000
```

## Utility Commands

### Contract Information

```bash
# Get contract versions
make get-versions

# Get BTC block height
make get-btc-height
```

### Development Commands

```bash
# Build contracts
make build

# Run tests
make test

# Run tests with coverage
make coverage

# Clean build artifacts
make clean

# Install dependencies
make install

# Update dependencies
make update
```

### Documentation

```bash
# Generate documentation
make docs

# Show help
make help
```

## Troubleshooting

### Common Issues

#### 1. Gas Price Errors
**Error**: `invalid value 'auto' for '--gas-price'`

**Solution**: The Makefile now uses `--legacy` flag and proper gas price handling.

#### 2. Out of Gas Errors
**Error**: `execution reverted: EvmError: OutOfGas`

**Solution**: Use high gas commands:
```bash
make deploy-lbc-high-gas NETWORK=testnet
```

#### 3. EIP-1559 Fee Errors
**Error**: `Failed to get EIP-1559 fees`

**Solution**: The Makefile automatically uses `--legacy` flag.

#### 4. Missing Dependencies
**Error**: `No such file or directory: forge-std/Script.sol`

**Solution**: Install dependencies:
```bash
make install
# or
forge install
```

#### 5. Nonce Errors
**Error**: `transaction nonce too low`

**Solution**: This is expected when using a private key that has already been used. Use a fresh private key for testing.

### Environment Issues

#### Private Key Not Set
```bash
# Check if private key is set
make check-env NETWORK=testnet

# Set in .env file
TESTNET_SIGNER_PRIVATE_KEY=your_private_key
```

#### RPC URL Issues
```bash
# Test RPC connection
curl -X POST -H "Content-Type: application/json" --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' https://public-node.testnet.rsk.co
```

## Examples

### Complete Deployment Workflow

```bash
# 1. Setup environment
cp example.env .env
# Edit .env with your configuration

# 2. Install dependencies
make install

# 3. Build contracts
make build

# 4. Test deployment (simulation)
make deploy-lbc NETWORK=testnet

# 5. Check environment
make check-env NETWORK=testnet

# 6. Actual deployment
make deploy-lbc-broadcast NETWORK=testnet

# 7. Verify deployment
make get-versions
```

### Fork Testing Workflow

```bash
# 1. Test on forked testnet
make testnet-fork-deploy

# 2. Test on forked mainnet
make mainnet-fork-deploy

# 3. Deploy on forked testnet
make testnet-fork-deploy-broadcast
```

### Upgrade Workflow

```bash
# 1. Test upgrade (simulation)
make upgrade-lbc NETWORK=testnet

# 2. Check environment
make check-env NETWORK=testnet

# 3. Perform upgrade
make upgrade-lbc-broadcast NETWORK=testnet

# 4. Verify upgrade
make get-versions
```

### Ownership Transfer Workflow

```bash
# 1. Test ownership transfer (simulation)
make change-owner NETWORK=testnet

# 2. Validate multisig configuration
make check-env NETWORK=testnet

# 3. Transfer ownership
make change-owner-broadcast NETWORK=testnet
```

## Best Practices

### 1. Always Test First
```bash
# Always run simulation before actual deployment
make deploy-lbc NETWORK=testnet
make deploy-lbc-broadcast NETWORK=testnet
```

### 2. Use Fork Testing
```bash
# Test against real network state
make testnet-fork-deploy
make mainnet-fork-deploy
```

### 3. Validate Environment
```bash
# Check configuration before deployment
make check-env NETWORK=mainnet
```

### 4. Use Safe Commands for Mainnet
```bash
# Safe commands include additional validation
make safe-deploy-lbc-broadcast NETWORK=mainnet
```

### 5. Monitor Gas Usage
```bash
# Use gas reporting
make gas-report

# Use high gas for complex deployments
make deploy-lbc-high-gas NETWORK=testnet
```

### 6. Keep Dependencies Updated
```bash
# Regular updates
make update
```

## Security Considerations

### Private Key Management
- **NEVER** commit private keys to version control
- Use environment variables for all private keys
- Consider using hardware wallets for mainnet operations

### Network Selection
- Always double-check the network before deployment
- Use simulation commands first
- Use safe commands for mainnet

### Gas Management
- Monitor gas prices and limits
- Use appropriate gas limits for complex operations
- Consider gas price fluctuations

### Verification
- Verify all contracts after deployment
- Use `make get-versions` to confirm deployments
- Monitor contract interactions

## Support

For issues and questions:
1. Check the troubleshooting section
2. Review the Foundry documentation
3. Check the project's README.md
4. Open an issue in the project repository

---

**Remember**: Always test thoroughly before deploying to mainnet, and never use real private keys in development environments.
