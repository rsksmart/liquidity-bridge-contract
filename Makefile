# Makefile for Liquidity Bridge Contract Forge Scripts
# Supports mainnet, testnet, and dev environments with fork capabilities

# Default values
NETWORK ?= testnet
FORK_BLOCK ?= latest
VERIFY ?= false
BROADCAST ?= true
GAS_LIMIT ?= 10000000
GAS_PRICE ?= 0
PRIORITY_GAS_PRICE ?= 0

# Environment file
ENV_FILE ?= .env

# Load environment variables if .env file exists
ifneq (,$(wildcard $(ENV_FILE)))
    include $(ENV_FILE)
    export
endif

# Network configurations
MAINNET_RPC := $(or $(MAINNET_RPC_URL),https://public-node.rsk.co)
TESTNET_RPC := $(or $(TESTNET_RPC_URL),https://public-node.testnet.rsk.co)
REGTEST_RPC := $(or $(REGTEST_RPC_URL),http://localhost:4444)

# Chain IDs
MAINNET_CHAIN_ID := 30
TESTNET_CHAIN_ID := 31
LOCAL_CHAIN_ID := 1337

# Private keys
MAINNET_KEY := $(MAINNET_SIGNER_PRIVATE_KEY)
TESTNET_KEY := $(TESTNET_SIGNER_PRIVATE_KEY)
DEV_KEY := $(DEV_SIGNER_PRIVATE_KEY)

# Forge command base
FORGE := forge script

# Common forge options
FORGE_OPTS := --gas-limit $(GAS_LIMIT) --legacy
ifneq ($(GAS_PRICE),0)
    FORGE_OPTS += --gas-price $(GAS_PRICE)
endif
ifneq ($(PRIORITY_GAS_PRICE),0)
    FORGE_OPTS += --priority-gas-price $(PRIORITY_GAS_PRICE)
endif

# Broadcast and verify options
ifeq ($(BROADCAST),true)
    FORGE_OPTS += --broadcast
endif

ifeq ($(VERIFY),true)
    FORGE_OPTS += --verify
endif

# Network-specific RPC and key
define get_network_config
$(if $(filter mainnet,$(1)),$(MAINNET_RPC),$(if $(filter testnet,$(1)),$(TESTNET_RPC),$(REGTEST_RPC)))
endef

define get_network_key
$(if $(filter mainnet,$(1)),$(MAINNET_KEY),$(if $(filter testnet,$(1)),$(TESTNET_KEY),$(DEV_KEY)))
endef

define get_chain_id
$(if $(filter mainnet,$(1)),$(MAINNET_CHAIN_ID),$(if $(filter testnet,$(1)),$(TESTNET_CHAIN_ID),$(LOCAL_CHAIN_ID)))
endef

# Fork options
FORK_OPTS := --fork-url $(call get_network_config,$(NETWORK))
ifneq ($(FORK_BLOCK),latest)
    FORK_OPTS += --fork-block-number $(FORK_BLOCK)
endif

# Private key option
PRIVATE_KEY_OPTS := --private-key $(call get_network_key,$(NETWORK))

# Help target
.PHONY: help
help:
	@echo "Liquidity Bridge Contract Forge Scripts Makefile"
	@echo ""
	@echo "Usage: make <target> [NETWORK=<network>] [FORK_BLOCK=<block>] [VERIFY=<true|false>] [BROADCAST=<true|false>]"
	@echo ""
	@echo "Networks:"
	@echo "  mainnet  - RSK Mainnet (Chain ID: 30)"
	@echo "  testnet  - RSK Testnet (Chain ID: 31)"
	@echo "  dev      - Local development (Chain ID: 1337)"
	@echo ""
	@echo "Targets:"
	@echo "  deploy-lbc        - Deploy LiquidityBridgeContract (simulation)"
	@echo "  deploy-lbc-broadcast - Deploy LiquidityBridgeContract (actual)"
	@echo "  upgrade-lbc       - Upgrade LiquidityBridgeContract to V2 (simulation)"
	@echo "  upgrade-lbc-broadcast - Upgrade LiquidityBridgeContract to V2 (actual)"
	@echo "  change-owner      - Transfer ownership to multisig (simulation)"
	@echo "  change-owner-broadcast - Transfer ownership to multisig (actual)"
	@echo "  deploy-lbc-high-gas - Deploy with high gas limit (15M) (simulation)"
	@echo "  deploy-lbc-high-gas-broadcast - Deploy with high gas limit (15M) (actual)"
	@echo "  get-btc-height    - Get current BTC block height"
	@echo "  get-versions      - Get contract versions"
	@echo "  clean             - Clean build artifacts"
	@echo "  build             - Build contracts"
	@echo "  test              - Run tests"
	@echo "  coverage          - Run tests with coverage"
	@echo ""
	@echo "Examples:"
	@echo "  make deploy-lbc NETWORK=testnet                    # Simulation"
	@echo "  make deploy-lbc-broadcast NETWORK=testnet          # Actual deployment"
	@echo "  make testnet-fork-deploy                           # Testnet fork simulation"
	@echo "  make testnet-fork-deploy-broadcast                 # Testnet fork actual deployment"
	@echo "  make upgrade-lbc NETWORK=mainnet FORK_BLOCK=6020639 # Simulation"
	@echo "  make upgrade-lbc-broadcast NETWORK=mainnet         # Actual upgrade"

# Deploy LiquidityBridgeContract (simulation)
.PHONY: deploy-lbc
deploy-lbc:
	@echo "Deploying LiquidityBridgeContract on $(NETWORK) (SIMULATION)..."
	@echo "RPC URL: $(call get_network_config,$(NETWORK))"
	@echo "Chain ID: $(call get_chain_id,$(NETWORK))"
	@echo "Fork Block: $(FORK_BLOCK)"
	@echo "Gas Limit: $(GAS_LIMIT)"
	$(FORGE) forge-scripts/DeployLBC.s.sol:DeployLBC \
		$(FORK_OPTS) \
		$(PRIVATE_KEY_OPTS) \
		$(FORGE_OPTS)

# Deploy LiquidityBridgeContract (actual deployment)
.PHONY: deploy-lbc-broadcast
deploy-lbc-broadcast:
	@echo "Deploying LiquidityBridgeContract on $(NETWORK) (ACTUAL DEPLOYMENT)..."
	@echo "RPC URL: $(call get_network_config,$(NETWORK))"
	@echo "Chain ID: $(call get_chain_id,$(NETWORK))"
	@echo "Fork Block: $(FORK_BLOCK)"
	@echo "Gas Limit: $(GAS_LIMIT)"
	$(FORGE) forge-scripts/DeployLBC.s.sol:DeployLBC \
		$(FORK_OPTS) \
		$(PRIVATE_KEY_OPTS) \
		--gas-limit $(GAS_LIMIT) \
		--legacy \
		--broadcast

# Deploy LiquidityBridgeContract with high gas limit (simulation)
.PHONY: deploy-lbc-high-gas
deploy-lbc-high-gas:
	@echo "Deploying LiquidityBridgeContract on $(NETWORK) with high gas limit (SIMULATION)..."
	@echo "RPC URL: $(call get_network_config,$(NETWORK))"
	@echo "Chain ID: $(call get_chain_id,$(NETWORK))"
	@echo "Fork Block: $(FORK_BLOCK)"
	@echo "Gas Limit: 15000000"
	$(FORGE) forge-scripts/DeployLBC.s.sol:DeployLBC \
		$(FORK_OPTS) \
		$(PRIVATE_KEY_OPTS) \
		--gas-limit 15000000 \
		--legacy

# Deploy LiquidityBridgeContract with high gas limit (actual deployment)
.PHONY: deploy-lbc-high-gas-broadcast
deploy-lbc-high-gas-broadcast:
	@echo "Deploying LiquidityBridgeContract on $(NETWORK) with high gas limit (ACTUAL DEPLOYMENT)..."
	@echo "RPC URL: $(call get_network_config,$(NETWORK))"
	@echo "Chain ID: $(call get_chain_id,$(NETWORK))"
	@echo "Fork Block: $(FORK_BLOCK)"
	@echo "Gas Limit: 15000000"
	$(FORGE) forge-scripts/DeployLBC.s.sol:DeployLBC \
		$(FORK_OPTS) \
		$(PRIVATE_KEY_OPTS) \
		--gas-limit 15000000 \
		--legacy \
		--broadcast

# Upgrade LiquidityBridgeContract to V2 (simulation)
.PHONY: upgrade-lbc
upgrade-lbc:
	@echo "Upgrading LiquidityBridgeContract to V2 on $(NETWORK) (SIMULATION)..."
	@echo "RPC URL: $(call get_network_config,$(NETWORK))"
	@echo "Chain ID: $(call get_chain_id,$(NETWORK))"
	@echo "Fork Block: $(FORK_BLOCK)"
	$(FORGE) forge-scripts/UpgradeLBC.s.sol:UpgradeLBC \
		$(FORK_OPTS) \
		$(PRIVATE_KEY_OPTS) \
		$(FORGE_OPTS)

# Upgrade LiquidityBridgeContract to V2 (actual deployment)
.PHONY: upgrade-lbc-broadcast
upgrade-lbc-broadcast:
	@echo "Upgrading LiquidityBridgeContract to V2 on $(NETWORK) (ACTUAL DEPLOYMENT)..."
	@echo "RPC URL: $(call get_network_config,$(NETWORK))"
	@echo "Chain ID: $(call get_chain_id,$(NETWORK))"
	@echo "Fork Block: $(FORK_BLOCK)"
	$(FORGE) forge-scripts/UpgradeLBC.s.sol:UpgradeLBC \
		$(FORK_OPTS) \
		$(PRIVATE_KEY_OPTS) \
		--gas-limit $(GAS_LIMIT) \
		--legacy \
		--broadcast

# Change ownership to multisig (simulation)
.PHONY: change-owner
change-owner:
	@echo "Transferring ownership to multisig on $(NETWORK) (SIMULATION)..."
	@echo "RPC URL: $(call get_network_config,$(NETWORK))"
	@echo "Chain ID: $(call get_chain_id,$(NETWORK))"
	@echo "Fork Block: $(FORK_BLOCK)"
	$(FORGE) forge-scripts/ChangeOwnerToMultiSig.s.sol:ChangeOwnerToMultiSig \
		$(FORK_OPTS) \
		$(PRIVATE_KEY_OPTS) \
		$(FORGE_OPTS)

# Change ownership to multisig (actual deployment)
.PHONY: change-owner-broadcast
change-owner-broadcast:
	@echo "Transferring ownership to multisig on $(NETWORK) (ACTUAL DEPLOYMENT)..."
	@echo "RPC URL: $(call get_network_config,$(NETWORK))"
	@echo "Chain ID: $(call get_chain_id,$(NETWORK))"
	@echo "Fork Block: $(FORK_BLOCK)"
	$(FORGE) forge-scripts/ChangeOwnerToMultiSig.s.sol:ChangeOwnerToMultiSig \
		$(FORK_OPTS) \
		$(PRIVATE_KEY_OPTS) \
		--gas-limit $(GAS_LIMIT) \
		--legacy \
		--broadcast

# Get BTC block height
.PHONY: get-btc-height
get-btc-height:
	@echo "Getting BTC block height..."
	@bash forge-scripts/GetBtcHeight.sh

# Get contract versions
.PHONY: get-versions
get-versions:
	@echo "Getting contract versions..."
	@bash forge-scripts/GetVersions.sh

# Build contracts
.PHONY: build
build:
	@echo "Building contracts..."
	forge build

# Run tests
.PHONY: test
test:
	@echo "Running tests..."
	forge test

# Run tests with coverage
.PHONY: coverage
coverage:
	@echo "Running tests with coverage..."
	forge coverage

# Clean build artifacts
.PHONY: clean
clean:
	@echo "Cleaning build artifacts..."
	forge clean
	rm -rf cache/
	rm -rf out/
	rm -rf broadcast/

# Install dependencies
.PHONY: install
install:
	@echo "Installing dependencies..."
	forge install

# Update dependencies
.PHONY: update
update:
	@echo "Updating dependencies..."
	forge update

# Remap dependencies
.PHONY: remappings
remappings:
	@echo "Generating remappings..."
	forge remappings > remappings.txt

# Snapshot
.PHONY: snapshot
snapshot:
	@echo "Creating snapshot..."
	forge snapshot

# Gas report
.PHONY: gas-report
gas-report:
	@echo "Generating gas report..."
	forge test --gas-report

# Verify contracts (for mainnet/testnet)
.PHONY: verify
verify:
	@echo "Verifying contracts on $(NETWORK)..."
	@if [ "$(NETWORK)" = "mainnet" ] || [ "$(NETWORK)" = "testnet" ]; then \
		echo "Verification requires manual intervention. Please use:"; \
		echo "forge verify-contract <CONTRACT_ADDRESS> <CONTRACT_NAME> --chain-id $(call get_chain_id,$(NETWORK)) --etherscan-api-key <API_KEY>"; \
	else \
		echo "Verification not supported for $(NETWORK)"; \
	fi

# Deploy all (deploy + upgrade + change owner) - for testing purposes
.PHONY: deploy-all
deploy-all: deploy-lbc upgrade-lbc change-owner

# Quick test deployment on dev network (simulation)
.PHONY: dev-deploy
dev-deploy:
	@echo "Quick deployment on dev network (SIMULATION)..."
	$(MAKE) deploy-lbc NETWORK=dev BROADCAST=false VERIFY=false

# Quick test deployment on dev network (actual)
.PHONY: dev-deploy-broadcast
dev-deploy-broadcast:
	@echo "Quick deployment on dev network (ACTUAL DEPLOYMENT)..."
	$(MAKE) deploy-lbc-broadcast NETWORK=dev VERIFY=false

# Test deployment on testnet fork (simulation)
.PHONY: testnet-fork-deploy
testnet-fork-deploy:
	@echo "Test deployment on testnet fork (SIMULATION)..."
	$(MAKE) deploy-lbc NETWORK=testnet FORK_BLOCK=6020639 BROADCAST=false VERIFY=false

# Test deployment on testnet fork (actual)
.PHONY: testnet-fork-deploy-broadcast
testnet-fork-deploy-broadcast:
	@echo "Test deployment on testnet fork (ACTUAL DEPLOYMENT)..."
	$(MAKE) deploy-lbc-broadcast NETWORK=testnet FORK_BLOCK=6020639 VERIFY=false

# Mainnet fork deployment (simulation)
.PHONY: mainnet-fork-deploy
mainnet-fork-deploy:
	@echo "Mainnet fork deployment (SIMULATION)..."
	$(MAKE) deploy-lbc NETWORK=mainnet FORK_BLOCK=latest BROADCAST=false VERIFY=false

# Mainnet fork deployment (actual)
.PHONY: mainnet-fork-deploy-broadcast
mainnet-fork-deploy-broadcast:
	@echo "Mainnet fork deployment (ACTUAL DEPLOYMENT)..."
	$(MAKE) deploy-lbc-broadcast NETWORK=mainnet FORK_BLOCK=latest VERIFY=false

# Environment setup check
.PHONY: check-env
check-env:
	@echo "Checking environment configuration..."
	@echo "Network: $(NETWORK)"
	@echo "RPC URL: $(call get_network_config,$(NETWORK))"
	@echo "Chain ID: $(call get_chain_id,$(NETWORK))"
	@echo "Private Key Set: $(if $(call get_network_key,$(NETWORK)),YES,NO)"
	@if [ -z "$(call get_network_key,$(NETWORK))" ]; then \
		echo "ERROR: Private key not set for $(NETWORK)"; \
		echo "Please set $(NETWORK)_SIGNER_PRIVATE_KEY in your environment"; \
		exit 1; \
	fi
	@echo "Environment check passed!"

# Validate deployment prerequisites
.PHONY: validate-deploy
validate-deploy: check-env
	@echo "Validating deployment prerequisites..."
	@if [ "$(NETWORK)" = "mainnet" ] && [ "$(BROADCAST)" = "true" ]; then \
		echo "WARNING: You are about to deploy to MAINNET!"; \
		echo "This will broadcast real transactions."; \
		read -p "Are you sure? (y/N): " confirm; \
		if [ "$$confirm" != "y" ] && [ "$$confirm" != "Y" ]; then \
			echo "Deployment cancelled."; \
			exit 1; \
		fi; \
	fi
	@echo "Deployment validation passed!"

# Safe deployment with validation
.PHONY: safe-deploy-lbc
safe-deploy-lbc: validate-deploy deploy-lbc

.PHONY: safe-upgrade-lbc
safe-upgrade-lbc: validate-deploy upgrade-lbc

.PHONY: safe-change-owner
safe-change-owner: validate-deploy change-owner

# Documentation
.PHONY: docs
docs:
	@echo "Generating documentation..."
	@echo "Forge Scripts Documentation:" > docs/forge-scripts.md
	@echo "" >> docs/forge-scripts.md
	@echo "## Available Scripts" >> docs/forge-scripts.md
	@echo "" >> docs/forge-scripts.md
	@echo "### DeployLBC.s.sol" >> docs/forge-scripts.md
	@echo "Deploys the LiquidityBridgeContract with proxy and admin." >> docs/forge-scripts.md
	@echo "" >> docs/forge-scripts.md
	@echo "### UpgradeLBC.s.sol" >> docs/forge-scripts.md
	@echo "Upgrades the LiquidityBridgeContract to V2." >> docs/forge-scripts.md
	@echo "" >> docs/forge-scripts.md
	@echo "### ChangeOwnerToMultiSig.s.sol" >> docs/forge-scripts.md
	@echo "Transfers ownership to a multisig wallet." >> docs/forge-scripts.md
	@echo "" >> docs/forge-scripts.md
	@echo "Documentation generated in docs/forge-scripts.md"
