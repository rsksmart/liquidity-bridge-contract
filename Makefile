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

# Hash-quote defaults
QUOTE_TYPE ?= pegin
QUOTE_FILE ?= tasks/hash-quote.example.json

# Pause-system defaults
PAUSE_REASON ?= Emergency maintenance
USE_LEDGER ?= false

# Refund-user-pegout defaults
QUOTE_HASH ?=
QUOTE_FILE ?=

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
REGTEST_CHAIN_ID := 33
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

# Map simplified network names to RSK network names for forge scripts
define get_rsk_network_name
$(if $(filter mainnet,$(1)),rskMainnet,$(if $(filter testnet,$(1)),rskTestnet,rskRegtest))
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
	@echo "  hash-quote        - Hash a PegIn or PegOut quote"
	@echo "  get-btc-height    - Get current BTC block height"
	@echo "  get-versions      - Get contract versions"
	@echo "  pause-status      - Check pause status of all system contracts"
	@echo "  pause-system      - Pause all system contracts (simulation)"
	@echo "  pause-system-broadcast - Pause all system contracts (actual)"
	@echo "  unpause-system    - Unpause all system contracts (simulation)"
	@echo "  unpause-system-broadcast - Unpause all system contracts (actual)"
	@echo "  refund-user-pegout - Refund user for expired PegOut (simulation)"
	@echo "  refund-user-pegout-broadcast - Refund user for expired PegOut (actual)"
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
	@echo "  make hash-quote pegin testnet                      # Hash PegIn quote"
	@echo "  make hash-quote pegout mainnet my-quote.json       # Hash PegOut with custom file"
	@echo "  make pause-status NETWORK=testnet                  # Check pause status"
	@echo "  make pause-system NETWORK=testnet PAUSE_REASON=\"Security incident\" # Pause (simulation)"
	@echo "  make pause-system-broadcast NETWORK=mainnet USE_LEDGER=true PAUSE_REASON=\"Emergency\" # Pause mainnet with Ledger"
	@echo "  make unpause-system-broadcast NETWORK=testnet      # Unpause testnet"
	@echo "  make refund-user-pegout NETWORK=testnet QUOTE_HASH=abc123...  # Refund user (simulation)"
	@echo "  make refund-user-pegout NETWORK=testnet QUOTE_FILE=tasks/quote.json # Refund from file (simulation)"
	@echo "  make refund-user-pegout-broadcast NETWORK=testnet QUOTE_HASH=abc123... # Refund user (actual)"

# Deploy LiquidityBridgeContract (simulation)
.PHONY: deploy-lbc
deploy-lbc:
	@echo "Deploying LiquidityBridgeContract on $(NETWORK) (SIMULATION)..."
	@echo "RPC URL: $(call get_network_config,$(NETWORK))"
	@echo "Chain ID: $(call get_chain_id,$(NETWORK))"
	@echo "Fork Block: $(FORK_BLOCK)"
	@echo "Gas Limit: $(GAS_LIMIT)"
	$(FORGE) forge-scripts/deployment/DeployLBC.s.sol:DeployLBC \
		$(FORK_OPTS) \
		$(PRIVATE_KEY_OPTS) \
		--gas-limit $(GAS_LIMIT) \
		--legacy

# Deploy LiquidityBridgeContract (actual deployment)
.PHONY: deploy-lbc-broadcast
deploy-lbc-broadcast:
	@echo "Deploying LiquidityBridgeContract on $(NETWORK) (ACTUAL DEPLOYMENT)..."
	@echo "RPC URL: $(call get_network_config,$(NETWORK))"
	@echo "Chain ID: $(call get_chain_id,$(NETWORK))"
	@echo "Fork Block: $(FORK_BLOCK)"
	@echo "Gas Limit: $(GAS_LIMIT)"
	$(FORGE) forge-scripts/deployment/DeployLBC.s.sol:DeployLBC \
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
	$(FORGE) forge-scripts/deployment/DeployLBC.s.sol:DeployLBC \
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

# Deploy V2 implementation (without upgrading proxy)
.PHONY: prepare-upgrade
prepare-upgrade:
	@echo "Deploying LiquidityBridgeContractV2 implementation on $(NETWORK)..."
	@echo "RPC URL: $(call get_network_config,$(NETWORK))"
	@echo "Chain ID: $(call get_chain_id,$(NETWORK))"
	$(FORGE) forge-scripts/deployment/PrepareUpgrade.s.sol:PrepareUpgrade \
		$(DEPLOY_OPTS) \
		$(PRIVATE_KEY_OPTS) \
		--gas-limit $(GAS_LIMIT) \
		--legacy \
		--broadcast \
		--verify

# Upgrade LiquidityBridgeContract to V2 (simulation)
.PHONY: upgrade-lbc
upgrade-lbc:
	@echo "Upgrading LiquidityBridgeContract to V2 on $(NETWORK) (SIMULATION)..."
	@echo "RPC URL: $(call get_network_config,$(NETWORK))"
	@echo "Chain ID: $(call get_chain_id,$(NETWORK))"
	@echo "Fork Block: $(FORK_BLOCK)"
	$(FORGE) forge-scripts/deployment/UpgradeLBC.s.sol:UpgradeLBC \
		$(FORK_OPTS) \
		$(PRIVATE_KEY_OPTS) \
		--gas-limit $(GAS_LIMIT) \
		--legacy

# Upgrade LiquidityBridgeContract to V2 (actual deployment)
.PHONY: upgrade-lbc-broadcast
upgrade-lbc-broadcast:
	@echo "Upgrading LiquidityBridgeContract to V2 on $(NETWORK) (ACTUAL DEPLOYMENT)..."
	@echo "RPC URL: $(call get_network_config,$(NETWORK))"
	@echo "Chain ID: $(call get_chain_id,$(NETWORK))"
	@echo "Fork Block: $(FORK_BLOCK)"
	$(FORGE) forge-scripts/deployment/UpgradeLBC.s.sol:UpgradeLBC \
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
	$(FORGE) forge-scripts/deployment/ChangeOwnerToMultiSig.s.sol:ChangeOwnerToMultiSig \
		$(FORK_OPTS) \
		$(PRIVATE_KEY_OPTS) \
		--gas-limit $(GAS_LIMIT) \
		--legacy

# Change ownership to multisig (actual deployment)
.PHONY: change-owner-broadcast
change-owner-broadcast:
	@echo "Transferring ownership to multisig on $(NETWORK) (ACTUAL DEPLOYMENT)..."
	@echo "RPC URL: $(call get_network_config,$(NETWORK))"
	@echo "Chain ID: $(call get_chain_id,$(NETWORK))"
	@echo "Fork Block: $(FORK_BLOCK)"
	$(FORGE) forge-scripts/deployment/ChangeOwnerToMultiSig.s.sol:ChangeOwnerToMultiSig \
		$(FORK_OPTS) \
		$(PRIVATE_KEY_OPTS) \
		--gas-limit $(GAS_LIMIT) \
		--legacy \
		--broadcast

# Get BTC block height
.PHONY: get-btc-height
get-btc-height:
	@echo "Getting BTC block height..."
	@bash forge-scripts/tasks/GetBtcHeight.sh

# Get contract versions
.PHONY: get-versions
get-versions:
	@echo "Getting contract versions..."
	@bash forge-scripts/tasks/GetVersions.sh

# Hash quote - supports both syntaxes:
# make hash-quote pegin testnet
# make hash-quote QUOTE_TYPE=pegin NETWORK=testnet QUOTE_FILE=file.json
.PHONY: hash-quote
hash-quote:
	@$(eval ARGS := $(filter-out $@,$(MAKECMDGOALS)))
	@$(eval QUOTE_TYPE_ARG := $(word 1,$(ARGS)))
	@$(eval NETWORK_ARG := $(word 2,$(ARGS)))
	@$(eval FILE_ARG := $(word 3,$(ARGS)))
	@$(eval FINAL_TYPE := $(if $(QUOTE_TYPE_ARG),$(QUOTE_TYPE_ARG),$(QUOTE_TYPE)))
	@$(eval FINAL_NETWORK := $(if $(NETWORK_ARG),$(NETWORK_ARG),$(NETWORK)))
	@$(eval FINAL_FILE := $(if $(FILE_ARG),$(FILE_ARG),$(QUOTE_FILE)))
	@if [ "$(FINAL_TYPE)" != "pegin" ] && [ "$(FINAL_TYPE)" != "pegout" ]; then \
		echo "Error: Type must be 'pegin' or 'pegout'"; \
		exit 1; \
	fi
	@echo "Hashing $(FINAL_TYPE) quote on $(FINAL_NETWORK)..."
	@echo "File: $(FINAL_FILE)"
	@echo "RPC URL: $(call get_network_config,$(FINAL_NETWORK))"
	@bash forge-scripts/tasks/hash-quote.sh \
		--type $(FINAL_TYPE) \
		--file $(FINAL_FILE) \
		--network $(FINAL_NETWORK) \
		--rpc-url $(call get_network_config,$(FINAL_NETWORK))

# Check pause status of all system contracts
.PHONY: pause-status
pause-status:
	@echo "Checking pause status on $(NETWORK)..."
	@echo "RPC URL: $(call get_network_config,$(NETWORK))"
	@bash forge-scripts/tasks/pause-system.sh \
		--action status \
		--network $(call get_rsk_network_name,$(NETWORK))

# Pause all system contracts (simulation)
.PHONY: pause-system
pause-system:
	@echo "Pausing system contracts on $(NETWORK) (SIMULATION)..."
	@echo "RPC URL: $(call get_network_config,$(NETWORK))"
	@echo "Reason: $(PAUSE_REASON)"
	@bash forge-scripts/tasks/pause-system.sh \
		--action pause \
		--reason "$(PAUSE_REASON)" \
		--network $(call get_rsk_network_name,$(NETWORK))

# Pause all system contracts (actual broadcast)
.PHONY: pause-system-broadcast
pause-system-broadcast:
	@echo "Pausing system contracts on $(NETWORK) (ACTUAL BROADCAST)..."
	@echo "RPC URL: $(call get_network_config,$(NETWORK))"
	@echo "Reason: $(PAUSE_REASON)"
	@if [ "$(USE_LEDGER)" = "true" ]; then \
		echo "Using Ledger hardware wallet..."; \
		bash forge-scripts/tasks/pause-system.sh \
			--action pause \
			--reason "$(PAUSE_REASON)" \
			--network $(call get_rsk_network_name,$(NETWORK)) \
			--broadcast \
			--ledger; \
	else \
		bash forge-scripts/tasks/pause-system.sh \
			--action pause \
			--reason "$(PAUSE_REASON)" \
			--network $(call get_rsk_network_name,$(NETWORK)) \
			--broadcast \
			--private-key $(call get_network_key,$(NETWORK)); \
	fi

# Unpause all system contracts (simulation)
.PHONY: unpause-system
unpause-system:
	@echo "Unpausing system contracts on $(NETWORK) (SIMULATION)..."
	@echo "RPC URL: $(call get_network_config,$(NETWORK))"
	@bash forge-scripts/tasks/pause-system.sh \
		--action unpause \
		--network $(call get_rsk_network_name,$(NETWORK))

# Unpause all system contracts (actual broadcast)
.PHONY: unpause-system-broadcast
unpause-system-broadcast:
	@echo "Unpausing system contracts on $(NETWORK) (ACTUAL BROADCAST)..."
	@echo "RPC URL: $(call get_network_config,$(NETWORK))"
	@if [ "$(USE_LEDGER)" = "true" ]; then \
		echo "Using Ledger hardware wallet..."; \
		bash forge-scripts/tasks/pause-system.sh \
			--action unpause \
			--network $(call get_rsk_network_name,$(NETWORK)) \
			--broadcast \
			--ledger; \
	else \
		bash forge-scripts/tasks/pause-system.sh \
			--action unpause \
			--network $(call get_rsk_network_name,$(NETWORK)) \
			--broadcast \
			--private-key $(call get_network_key,$(NETWORK)); \
	fi

# Refund user PegOut (simulation)
.PHONY: refund-user-pegout
refund-user-pegout:
	@if [ -z "$(QUOTE_HASH)" ] && [ -z "$(QUOTE_FILE)" ]; then \
		echo "Error: Either QUOTE_HASH or QUOTE_FILE is required"; \
		echo "Usage: make refund-user-pegout NETWORK=testnet QUOTE_HASH=abc123..."; \
		echo "   or: make refund-user-pegout NETWORK=testnet QUOTE_FILE=tasks/quote.json"; \
		exit 1; \
	fi
	@if [ -n "$(QUOTE_HASH)" ] && [ -n "$(QUOTE_FILE)" ]; then \
		echo "Error: Cannot specify both QUOTE_HASH and QUOTE_FILE"; \
		exit 1; \
	fi
	@echo "Refunding user PegOut on $(NETWORK) (SIMULATION)..."
	@echo "RPC URL: $(call get_network_config,$(NETWORK))"
	@if [ -n "$(QUOTE_FILE)" ]; then \
		echo "Quote File: $(QUOTE_FILE)"; \
		bash forge-scripts/tasks/refund-user-pegout.sh \
			--file $(QUOTE_FILE) \
			--network $(call get_rsk_network_name,$(NETWORK)); \
	else \
		echo "Quote Hash: $(QUOTE_HASH)"; \
		bash forge-scripts/tasks/refund-user-pegout.sh \
			--quote-hash $(QUOTE_HASH) \
			--network $(call get_rsk_network_name,$(NETWORK)); \
	fi

# Refund user PegOut (actual broadcast)
.PHONY: refund-user-pegout-broadcast
refund-user-pegout-broadcast:
	@if [ -z "$(QUOTE_HASH)" ] && [ -z "$(QUOTE_FILE)" ]; then \
		echo "Error: Either QUOTE_HASH or QUOTE_FILE is required"; \
		echo "Usage: make refund-user-pegout-broadcast NETWORK=testnet QUOTE_HASH=abc123..."; \
		echo "   or: make refund-user-pegout-broadcast NETWORK=testnet QUOTE_FILE=tasks/quote.json"; \
		exit 1; \
	fi
	@if [ -n "$(QUOTE_HASH)" ] && [ -n "$(QUOTE_FILE)" ]; then \
		echo "Error: Cannot specify both QUOTE_HASH and QUOTE_FILE"; \
		exit 1; \
	fi
	@echo "Refunding user PegOut on $(NETWORK) (ACTUAL BROADCAST)..."
	@echo "RPC URL: $(call get_network_config,$(NETWORK))"
	@if [ -n "$(QUOTE_FILE)" ]; then \
		echo "Quote File: $(QUOTE_FILE)"; \
		if [ "$(USE_LEDGER)" = "true" ]; then \
			echo "Using Ledger hardware wallet..."; \
			bash forge-scripts/tasks/refund-user-pegout.sh \
				--file $(QUOTE_FILE) \
				--network $(call get_rsk_network_name,$(NETWORK)) \
				--broadcast \
				--ledger; \
		else \
			bash forge-scripts/tasks/refund-user-pegout.sh \
				--file $(QUOTE_FILE) \
				--network $(call get_rsk_network_name,$(NETWORK)) \
				--broadcast \
				--private-key $(call get_network_key,$(NETWORK)); \
		fi; \
	else \
		echo "Quote Hash: $(QUOTE_HASH)"; \
		if [ "$(USE_LEDGER)" = "true" ]; then \
			echo "Using Ledger hardware wallet..."; \
			bash forge-scripts/tasks/refund-user-pegout.sh \
				--quote-hash $(QUOTE_HASH) \
				--network $(call get_rsk_network_name,$(NETWORK)) \
				--broadcast \
				--ledger; \
		else \
			bash forge-scripts/tasks/refund-user-pegout.sh \
				--quote-hash $(QUOTE_HASH) \
				--network $(call get_rsk_network_name,$(NETWORK)) \
				--broadcast \
				--private-key $(call get_network_key,$(NETWORK)); \
		fi; \
	fi

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
	@echo "Documentation is available in docs/FOUNDRY_MAKEFILE_GUIDE.md"

# Catch-all target for hash-quote arguments (pegin/pegout, network names, file paths)
# This prevents make from complaining about unknown targets when using: make hash-quote pegin testnet
ifneq (,$(findstring hash-quote,$(MAKECMDGOALS)))
pegin pegout mainnet testnet local regtest rskMainnet rskTestnet rskRegtest rskDevelopment:
	@:
# Also catch file arguments (anything ending in .json)
%.json:
	@:
endif
