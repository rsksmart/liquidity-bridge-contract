# Makefile for Liquidity Bridge Contract Forge Scripts
# Supports mainnet, testnet, and dev environments with fork capabilities

# Default values
NETWORK ?= testnet
FORK_BLOCK ?= latest
VERIFY ?= false
BROADCAST ?= true
GAS_LIMIT ?= 100000000
GAS_PRICE ?= 0
PRIORITY_GAS_PRICE ?= 0

# Hash-quote defaults
QUOTE_TYPE ?= pegin
HASH_QUOTE_FILE ?= script/legacy/tasks/hash-quote.example.json

# Pause-system defaults
PAUSE_REASON ?= Emergency maintenance

# Refund-user-pegout defaults
QUOTE_HASH ?=
QUOTE_FILE ?=

# Register-pegin defaults
PEGIN_QUOTE_FILE ?=
PEGIN_SIGNATURE ?=
PEGIN_TXID ?=

# Flyover library addresses are read from addresses.json at build time

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
DEVELOPMENT_KEY := $(or $(DEVELOPMENT_SIGNER_PRIVATE_KEY),$(DEV_SIGNER_PRIVATE_KEY))

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

# Read library addresses from addresses.json using jq
# Usage: $(call get_lib_address,network,library)
define get_lib_address
$(shell jq -r '.["$(1)"]["$(2)"].address // empty' addresses.json 2>/dev/null)
endef

# Build library linking flags from addresses.json
define get_library_flags
$(if $(call get_lib_address,$(1),Quotes),--libraries src/libraries/Quotes.sol:Quotes:$(call get_lib_address,$(1),Quotes)) \
$(if $(call get_lib_address,$(1),SignatureValidator),--libraries src/libraries/SignatureValidator.sol:SignatureValidator:$(call get_lib_address,$(1),SignatureValidator)) \
$(if $(call get_lib_address,$(1),BtcUtils),--libraries node_modules/@rsksmart/btc-transaction-solidity-helper/contracts/BtcUtils.sol:BtcUtils:$(call get_lib_address,$(1),BtcUtils))
endef

# Network-specific RPC and key
# Note: development uses testnet RPC (same chain) but different library addresses
define get_network_config
$(if $(filter mainnet,$(1)),$(MAINNET_RPC),$(if $(filter testnet development,$(1)),$(TESTNET_RPC),$(REGTEST_RPC)))
endef

define get_network_key
$(if $(filter mainnet,$(1)),$(MAINNET_KEY),$(if $(filter testnet,$(1)),$(TESTNET_KEY),$(if $(filter development,$(1)),$(DEVELOPMENT_KEY),$(DEV_KEY))))
endef

define get_chain_id
$(if $(filter mainnet,$(1)),$(MAINNET_CHAIN_ID),$(if $(filter testnet development,$(1)),$(TESTNET_CHAIN_ID),$(LOCAL_CHAIN_ID)))
endef

# Map simplified network names to RSK network names for forge script
# development uses rskDevelopment addresses (different from rskTestnet)
define get_rsk_network_name
$(if $(filter mainnet,$(1)),rskMainnet,$(if $(filter testnet,$(1)),rskTestnet,$(if $(filter development,$(1)),rskDevelopment,rskRegtest)))
endef

# Fork options (for simulation/testing)
FORK_OPTS := --fork-url $(call get_network_config,$(NETWORK))
ifneq ($(FORK_BLOCK),latest)
    FORK_OPTS += --fork-block-number $(FORK_BLOCK)
endif

# RPC options (for actual deployments)
RPC_OPTS := --rpc-url $(call get_network_config,$(NETWORK))

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
	@echo "  mainnet     - RSK Mainnet (Chain ID: 30)"
	@echo "  testnet     - RSK Testnet (Chain ID: 31)"
	@echo "  development - RSK Testnet with development library addresses (Chain ID: 31)"
	@echo "  dev         - Local development (Chain ID: 1337)"
	@echo ""
	@echo "Targets:"
	@echo ""
	@echo "Flyover Deployment:"
	@echo "  deploy-flyover-fork      - Deploy full Flyover system (fork simulation)"
	@echo "  deploy-flyover-broadcast - Deploy full Flyover system (actual deployment)"
	@echo "  deploy-collateral-fork   - Deploy CollateralManagement (fork simulation)"
	@echo "  deploy-collateral-broadcast - Deploy CollateralManagement (actual deployment)"
	@echo "  deploy-discovery-fork    - Deploy FlyoverDiscovery (fork simulation)"
	@echo "  deploy-discovery-broadcast - Deploy FlyoverDiscovery (actual deployment)"
	@echo "  deploy-pegin-fork        - Deploy PegInContract (fork simulation)"
	@echo "  deploy-pegin-broadcast   - Deploy PegInContract (actual deployment)"
	@echo "  deploy-pegout-fork       - Deploy PegOutContract (fork simulation)"
	@echo "  deploy-pegout-broadcast  - Deploy PegOutContract (actual deployment)"
	@echo ""
	@echo "Legacy LBC Deployment:"
	@echo "  deploy-lbc-fork        - Deploy LiquidityBridgeContract (fork simulation)"
	@echo "  deploy-lbc-broadcast  - Deploy LiquidityBridgeContract (actual deployment)"
	@echo "  upgrade-lbc-fork      - Upgrade LiquidityBridgeContract to V2 (fork simulation)"
	@echo "  upgrade-lbc-broadcast - Upgrade LiquidityBridgeContract to V2 (actual deployment)"
	@echo "  change-owner-fork     - Transfer ownership to multisig (fork simulation)"
	@echo "  change-owner-broadcast - Transfer ownership to multisig (actual deployment)"
	@echo "  deploy-lbc-high-gas-fork - Deploy with high gas limit (15M) (fork simulation)"
	@echo "  deploy-lbc-high-gas-broadcast - Deploy with high gas limit (15M) (actual deployment)"
	@echo ""
	@echo "Development Network Deployment (testnet chain with rskDevelopment addresses):"
	@echo "  development-fork-deploy           - Deploy LBC on development (fork simulation)"
	@echo "  development-fork-deploy-broadcast - Deploy LBC on development (actual deployment)"
	@echo "  development-deploy-flyover-fork   - Deploy Flyover on development (fork simulation)"
	@echo "  development-deploy-flyover-broadcast - Deploy Flyover on development (actual deployment)"
	@echo "  development-upgrade-lbc-fork      - Upgrade LBC on development (fork simulation)"
	@echo "  development-upgrade-lbc-broadcast - Upgrade LBC on development (actual deployment)"
	@echo ""
	@echo "Task Scripts:"
	@echo "  hash-quote               - Hash a PegIn or PegOut quote"
	@echo "  get-btc-height           - Get current BTC block height"
	@echo "  get-versions             - Get contract versions"
	@echo "  pause-status             - Check pause status of all system contracts"
	@echo "  pause-system             - Pause all system contracts (simulation)"
	@echo "  pause-system-broadcast   - Pause all system contracts (actual)"
	@echo "  unpause-system           - Unpause all system contracts (simulation)"
	@echo "  unpause-system-broadcast - Unpause all system contracts (actual)"
	@echo "  refund-user-pegout       - Refund user for expired PegOut (simulation)"
	@echo "  refund-user-pegout-broadcast - Refund user for expired PegOut (actual)"
	@echo "  register-pegin           - Register a PegIn Bitcoin transaction (simulation)"
	@echo "  register-pegin-broadcast - Register a PegIn Bitcoin transaction (actual)"
	@echo ""
	@echo "Setup:"
	@echo "  python-setup      - Create .venv/ with pinned Python deps (Halmos + pre-commit)"
	@echo ""
	@echo "Build & Clean:"
	@echo "  clean             - Clean build artifacts"
	@echo "  build             - Build contracts"
	@echo ""
	@echo "Testing:"
	@echo "  test              - Run all tests (unit + fuzz)"
	@echo "  test-unit         - Run unit tests only (excludes fuzz/invariant/differential)"
	@echo "  test-differential - Run differential tests"
	@echo "  test-v            - Run all tests with verbosity"
	@echo "  test-tasks        - Run task script tests"
	@echo "  test-pegin        - Run PegIn contract tests"
	@echo "  test-pegout       - Run PegOut contract tests"
	@echo "  test-collateral   - Run Collateral contract tests"
	@echo "  test-discovery    - Run Discovery contract tests"
	@echo "  test-integration  - Run integration tests"
	@echo "  test-legacy       - Run legacy LBC tests"
	@echo "  test-flyover      - Run all Flyover system tests"
	@echo "  test-file         - Run a specific test file"
	@echo "  test-func         - Run a specific test function"
	@echo "  coverage          - Run tests with coverage"
	@echo ""
	@echo "Fuzz Tests:"
	@echo "  test-fuzz             - Run all fuzz tests"
	@echo "  test-fuzz-collateral  - Run collateral fuzz tests"
	@echo "  test-fuzz-discovery   - Run discovery fuzz tests"
	@echo "  test-fuzz-pegin       - Run pegin fuzz tests"
	@echo "  test-fuzz-pegout      - Run pegout fuzz tests"
	@echo "  test-fuzz-libraries   - Run libraries fuzz tests"
	@echo ""
	@echo "Deployment examples:"
	@echo "  make deploy-flyover-fork NETWORK=testnet               # Deploy with auto-linked libraries"
	@echo "  make deploy-flyover-broadcast NETWORK=testnet          # Deploy full Flyover system (actual)"
	@echo "  (Libraries are auto-linked from addresses.json via foundry.toml profiles)"
	@echo "  make deploy-pegin-fork NETWORK=testnet                 # Deploy PegIn only (simulation)"
	@echo "  make deploy-collateral-fork NETWORK=testnet            # Deploy Collateral only (simulation)"
	@echo "  make deploy-lbc-fork NETWORK=testnet                   # Legacy LBC fork simulation"
	@echo "  make deploy-lbc-broadcast NETWORK=testnet              # Legacy LBC actual deployment"
	@echo "  make testnet-fork-deploy                               # Testnet fork simulation"
	@echo ""
	@echo "Development network examples (testnet chain with rskDevelopment addresses):"
	@echo "  make development-fork-deploy                           # Development LBC fork simulation"
	@echo "  make development-fork-deploy-broadcast                 # Development LBC actual deployment"
	@echo "  make development-deploy-flyover-fork                   # Development Flyover fork simulation"
	@echo "  make development-deploy-flyover-broadcast              # Development Flyover actual deployment"
	@echo "  make deploy-lbc-fork NETWORK=development               # Same as development-fork-deploy"
	@echo "Fuzz Tests:"
	@echo "  test-fuzz             - Run all fuzz tests"
	@echo "  test-fuzz-collateral  - Run collateral fuzz tests"
	@echo "  test-fuzz-discovery   - Run discovery fuzz tests"
	@echo "  test-fuzz-pegin       - Run pegin fuzz tests"
	@echo "  test-fuzz-pegout      - Run pegout fuzz tests"
	@echo "  test-fuzz-libraries   - Run libraries fuzz tests"
	@echo ""
	@echo "Examples:"
	@echo "  make deploy-lbc-fork NETWORK=testnet                    # Fork simulation"
	@echo "  make deploy-lbc-broadcast NETWORK=testnet               # Actual deployment"
	@echo "  make testnet-fork-deploy                                # Testnet fork simulation"
	@echo "  make upgrade-lbc-fork NETWORK=mainnet FORK_BLOCK=6020639 # Fork simulation"
	@echo "  make upgrade-lbc-broadcast NETWORK=mainnet             # Actual upgrade"
	@echo "  make hash-quote pegin testnet                      # Hash PegIn quote"
	@echo "  make hash-quote pegout mainnet my-quote.json       # Hash PegOut with custom file"
	@echo "  make hash-quote HASH_QUOTE_FILE=my-quote.json     # Hash with named file parameter"
	@echo "  make pause-status NETWORK=testnet                  # Check pause status"
	@echo "  make pause-system NETWORK=testnet PAUSE_REASON=\"Security incident\" # Pause (simulation)"
	@echo "  make pause-system-broadcast NETWORK=mainnet PAUSE_REASON=\"Emergency\" # Pause mainnet"
	@echo "  make unpause-system-broadcast NETWORK=testnet      # Unpause testnet"
	@echo "  make refund-user-pegout NETWORK=testnet QUOTE_HASH=abc123...  # Refund user (simulation)"
	@echo "  make refund-user-pegout NETWORK=testnet QUOTE_FILE=script/tasks/quote.json # Refund from file (simulation)"
	@echo "  make refund-user-pegout-broadcast NETWORK=testnet QUOTE_HASH=abc123... # Refund user (actual)"
	@echo "  make register-pegin NETWORK=testnet PEGIN_QUOTE_FILE=quote.json PEGIN_SIGNATURE=0x... PEGIN_TXID=abc... # Register PegIn (simulation)"
	@echo "  make register-pegin-broadcast NETWORK=testnet PEGIN_QUOTE_FILE=quote.json PEGIN_SIGNATURE=0x... PEGIN_TXID=abc... # Register PegIn (actual)"
	@echo ""
	@echo "Test examples:"
	@echo "  make test                                     # Run all tests (unit + fuzz)"
	@echo "  make test-unit                                # Run unit tests only (no fuzz)"
	@echo "  make test-v                                   # Run all tests with verbosity"
	@echo "  make test-tasks                               # Run task script tests"
	@echo "  make test-pegin                               # Run PegIn tests"
	@echo "  make test-pegout                              # Run PegOut tests"
	@echo "  make test-collateral                          # Run Collateral tests"
	@echo "  make test-discovery                           # Run Discovery tests"
	@echo "  make test-integration                         # Run integration tests"
	@echo "  make test-flyover                             # Run all Flyover system tests"
	@echo "  make test-file FILE=test/tasks/HashQuote.t.sol  # Run specific test file"
	@echo "  make test-func FUNC=test_HashPeginQuote       # Run specific test function"

# =============================================================================
# FLYOVER DEPLOYMENT SCRIPTS
# =============================================================================

# Deploy full Flyover system (fork simulation)
# Libraries are auto-linked from addresses.json
.PHONY: deploy-flyover-fork
deploy-flyover-fork:
	@echo "Deploying full Flyover system on $(NETWORK) (FORK SIMULATION)..."
	@echo "RPC URL: $(call get_network_config,$(NETWORK))"
	@echo "Libraries from addresses.json ($(call get_rsk_network_name,$(NETWORK))):"
	@echo "  Quotes: $(call get_lib_address,$(call get_rsk_network_name,$(NETWORK)),Quotes)"
	@echo "  SignatureValidator: $(call get_lib_address,$(call get_rsk_network_name,$(NETWORK)),SignatureValidator)"
	@echo "  BtcUtils: $(call get_lib_address,$(call get_rsk_network_name,$(NETWORK)),BtcUtils)"
	@export NETWORK=$(call get_rsk_network_name,$(NETWORK)); \
	$(FORGE) script/deployment/DeployFlyover.s.sol:DeployFlyover \
		$(FORK_OPTS) \
		$(PRIVATE_KEY_OPTS) \
		$(call get_library_flags,$(call get_rsk_network_name,$(NETWORK))) \
		--gas-limit $(GAS_LIMIT) \
		--legacy

# Deploy full Flyover system (actual deployment)
# Libraries are auto-linked from addresses.json
.PHONY: deploy-flyover-broadcast
deploy-flyover-broadcast:
	@echo "Deploying full Flyover system on $(NETWORK) (ACTUAL DEPLOYMENT)..."
	@echo "RPC URL: $(call get_network_config,$(NETWORK))"
	@echo "Libraries from addresses.json ($(call get_rsk_network_name,$(NETWORK))):"
	@echo "  Quotes: $(call get_lib_address,$(call get_rsk_network_name,$(NETWORK)),Quotes)"
	@echo "  SignatureValidator: $(call get_lib_address,$(call get_rsk_network_name,$(NETWORK)),SignatureValidator)"
	@echo "  BtcUtils: $(call get_lib_address,$(call get_rsk_network_name,$(NETWORK)),BtcUtils)"
	@export NETWORK=$(call get_rsk_network_name,$(NETWORK)); \
	$(FORGE) script/deployment/DeployFlyover.s.sol:DeployFlyover \
		$(RPC_OPTS) \
		$(PRIVATE_KEY_OPTS) \
		$(call get_library_flags,$(call get_rsk_network_name,$(NETWORK))) \
		--gas-limit $(GAS_LIMIT) \
		--legacy \
		--broadcast

# Deploy CollateralManagement (fork simulation)
.PHONY: deploy-collateral-fork
deploy-collateral-fork:
	@echo "Deploying CollateralManagement on $(NETWORK) (FORK SIMULATION)..."
	@echo "RPC URL: $(call get_network_config,$(NETWORK))"
	@export NETWORK=$(call get_rsk_network_name,$(NETWORK)); \
	$(FORGE) script/deployment/DeployCollateralManagement.s.sol:DeployCollateralManagement \
		$(FORK_OPTS) \
		$(PRIVATE_KEY_OPTS) \
		--gas-limit $(GAS_LIMIT) \
		--legacy

# Deploy CollateralManagement (actual deployment)
.PHONY: deploy-collateral-broadcast
deploy-collateral-broadcast:
	@echo "Deploying CollateralManagement on $(NETWORK) (ACTUAL DEPLOYMENT)..."
	@echo "RPC URL: $(call get_network_config,$(NETWORK))"
	@export NETWORK=$(call get_rsk_network_name,$(NETWORK)); \
	$(FORGE) script/deployment/DeployCollateralManagement.s.sol:DeployCollateralManagement \
		$(RPC_OPTS) \
		$(PRIVATE_KEY_OPTS) \
		--gas-limit $(GAS_LIMIT) \
		--legacy \
		--broadcast

# Deploy FlyoverDiscovery (fork simulation)
.PHONY: deploy-discovery-fork
deploy-discovery-fork:
	@echo "Deploying FlyoverDiscovery on $(NETWORK) (FORK SIMULATION)..."
	@echo "RPC URL: $(call get_network_config,$(NETWORK))"
	@export NETWORK=$(call get_rsk_network_name,$(NETWORK)); \
	$(FORGE) script/deployment/DeployFlyoverDiscovery.s.sol:DeployFlyoverDiscovery \
		$(FORK_OPTS) \
		$(PRIVATE_KEY_OPTS) \
		--gas-limit $(GAS_LIMIT) \
		--legacy

# Deploy FlyoverDiscovery (actual deployment)
.PHONY: deploy-discovery-broadcast
deploy-discovery-broadcast:
	@echo "Deploying FlyoverDiscovery on $(NETWORK) (ACTUAL DEPLOYMENT)..."
	@echo "RPC URL: $(call get_network_config,$(NETWORK))"
	@export NETWORK=$(call get_rsk_network_name,$(NETWORK)); \
	$(FORGE) script/deployment/DeployFlyoverDiscovery.s.sol:DeployFlyoverDiscovery \
		$(RPC_OPTS) \
		$(PRIVATE_KEY_OPTS) \
		--gas-limit $(GAS_LIMIT) \
		--legacy \
		--broadcast

# Deploy PegInContract (fork simulation)
.PHONY: deploy-pegin-fork
deploy-pegin-fork:
	@echo "Deploying PegInContract on $(NETWORK) (FORK SIMULATION)..."
	@echo "RPC URL: $(call get_network_config,$(NETWORK))"
	@export NETWORK=$(call get_rsk_network_name,$(NETWORK)); \
	$(FORGE) script/deployment/DeployPegIn.s.sol:DeployPegIn \
		$(FORK_OPTS) \
		$(PRIVATE_KEY_OPTS) \
		--gas-limit $(GAS_LIMIT) \
		--legacy

# Deploy PegInContract (actual deployment)
.PHONY: deploy-pegin-broadcast
deploy-pegin-broadcast:
	@echo "Deploying PegInContract on $(NETWORK) (ACTUAL DEPLOYMENT)..."
	@echo "RPC URL: $(call get_network_config,$(NETWORK))"
	@export NETWORK=$(call get_rsk_network_name,$(NETWORK)); \
	$(FORGE) script/deployment/DeployPegIn.s.sol:DeployPegIn \
		$(RPC_OPTS) \
		$(PRIVATE_KEY_OPTS) \
		--gas-limit $(GAS_LIMIT) \
		--legacy \
		--broadcast

# Deploy PegOutContract (fork simulation)
.PHONY: deploy-pegout-fork
deploy-pegout-fork:
	@echo "Deploying PegOutContract on $(NETWORK) (FORK SIMULATION)..."
	@echo "RPC URL: $(call get_network_config,$(NETWORK))"
	@export NETWORK=$(call get_rsk_network_name,$(NETWORK)); \
	$(FORGE) script/deployment/DeployPegOut.s.sol:DeployPegOut \
		$(FORK_OPTS) \
		$(PRIVATE_KEY_OPTS) \
		--gas-limit $(GAS_LIMIT) \
		--legacy

# Deploy PegOutContract (actual deployment)
.PHONY: deploy-pegout-broadcast
deploy-pegout-broadcast:
	@echo "Deploying PegOutContract on $(NETWORK) (ACTUAL DEPLOYMENT)..."
	@echo "RPC URL: $(call get_network_config,$(NETWORK))"
	@export NETWORK=$(call get_rsk_network_name,$(NETWORK)); \
	$(FORGE) script/deployment/DeployPegOut.s.sol:DeployPegOut \
		$(RPC_OPTS) \
		$(PRIVATE_KEY_OPTS) \
		--gas-limit $(GAS_LIMIT) \
		--legacy \
		--broadcast

# =============================================================================
# LEGACY LBC DEPLOYMENT SCRIPTS
# =============================================================================

# Deploy LiquidityBridgeContract (fork simulation)
.PHONY: deploy-lbc-fork
deploy-lbc-fork:
	@echo "Deploying LiquidityBridgeContract on $(NETWORK) (FORK SIMULATION)..."
	@echo "RPC URL: $(call get_network_config,$(NETWORK))"
	@echo "Chain ID: $(call get_chain_id,$(NETWORK))"
	@echo "Fork Block: $(FORK_BLOCK)"
	@echo "Gas Limit: $(GAS_LIMIT)"
	$(FORGE) script/deployment/DeployLBC.s.sol:DeployLBC \
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
	@echo "Gas Limit: $(GAS_LIMIT)"
	$(FORGE) script/deployment/DeployLBC.s.sol:DeployLBC \
		$(RPC_OPTS) \
		$(PRIVATE_KEY_OPTS) \
		--gas-limit $(GAS_LIMIT) \
		--legacy \
		--broadcast

# Deploy LiquidityBridgeContract with high gas limit (fork simulation)
.PHONY: deploy-lbc-high-gas-fork
deploy-lbc-high-gas-fork:
	@echo "Deploying LiquidityBridgeContract on $(NETWORK) with high gas limit (FORK SIMULATION)..."
	@echo "RPC URL: $(call get_network_config,$(NETWORK))"
	@echo "Chain ID: $(call get_chain_id,$(NETWORK))"
	@echo "Fork Block: $(FORK_BLOCK)"
	@echo "Gas Limit: 15000000"
	$(FORGE) script/deployment/DeployLBC.s.sol:DeployLBC \
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
	@echo "Gas Limit: 15000000"
	$(FORGE) script/deployment/DeployLBC.s.sol:DeployLBC \
		$(RPC_OPTS) \
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
	$(FORGE) script/deployment/PrepareUpgrade.s.sol:PrepareUpgrade \
		$(DEPLOY_OPTS) \
		$(PRIVATE_KEY_OPTS) \
		--gas-limit $(GAS_LIMIT) \
		--legacy \
		--broadcast \
		--verify

# Upgrade LiquidityBridgeContract to V2 (fork simulation)
.PHONY: upgrade-lbc-fork
upgrade-lbc-fork:
	@echo "Upgrading LiquidityBridgeContract to V2 on $(NETWORK) (FORK SIMULATION)..."
	@echo "RPC URL: $(call get_network_config,$(NETWORK))"
	@echo "Chain ID: $(call get_chain_id,$(NETWORK))"
	@echo "Fork Block: $(FORK_BLOCK)"
	$(FORGE) script/deployment/UpgradeLBC.s.sol:UpgradeLBC \
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
	$(FORGE) script/deployment/UpgradeLBC.s.sol:UpgradeLBC \
		$(RPC_OPTS) \
		$(PRIVATE_KEY_OPTS) \
		--gas-limit $(GAS_LIMIT) \
		--legacy \
		--broadcast

# Change ownership to multisig (fork simulation)
.PHONY: change-owner-fork
change-owner-fork:
	@echo "Transferring ownership to multisig on $(NETWORK) (FORK SIMULATION)..."
	@echo "RPC URL: $(call get_network_config,$(NETWORK))"
	@echo "Chain ID: $(call get_chain_id,$(NETWORK))"
	@echo "Fork Block: $(FORK_BLOCK)"
	$(FORGE) script/deployment/ChangeOwnerToMultiSig.s.sol:ChangeOwnerToMultiSig \
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
	$(FORGE) script/deployment/ChangeOwnerToMultiSig.s.sol:ChangeOwnerToMultiSig \
		$(RPC_OPTS) \
		$(PRIVATE_KEY_OPTS) \
		--gas-limit $(GAS_LIMIT) \
		--legacy \
		--broadcast

# Get BTC block height
.PHONY: get-btc-height
get-btc-height:
	@echo "Getting BTC block height..."
	@bash script/tasks/GetBtcHeight.sh

# Get contract versions
.PHONY: get-versions
get-versions:
	@echo "Getting contract versions..."
	@bash script/tasks/GetVersions.sh

# Hash quote - supports both syntaxes:
# make hash-quote pegin testnet
# make hash-quote QUOTE_TYPE=pegin NETWORK=testnet HASH_QUOTE_FILE=file.json
.PHONY: hash-quote
hash-quote:
	@$(eval ARGS := $(filter-out $@,$(MAKECMDGOALS)))
	@$(eval QUOTE_TYPE_ARG := $(word 1,$(ARGS)))
	@$(eval NETWORK_ARG := $(word 2,$(ARGS)))
	@$(eval FILE_ARG := $(word 3,$(ARGS)))
	@$(eval FINAL_TYPE := $(if $(QUOTE_TYPE_ARG),$(QUOTE_TYPE_ARG),$(QUOTE_TYPE)))
	@$(eval FINAL_NETWORK := $(if $(NETWORK_ARG),$(NETWORK_ARG),$(NETWORK)))
	@$(eval FINAL_FILE := $(if $(FILE_ARG),$(FILE_ARG),$(HASH_QUOTE_FILE)))
	@if [ "$(FINAL_TYPE)" != "pegin" ] && [ "$(FINAL_TYPE)" != "pegout" ]; then \
		echo "Error: Type must be 'pegin' or 'pegout'"; \
		exit 1; \
	fi
	@echo "Hashing $(FINAL_TYPE) quote on $(FINAL_NETWORK)..."
	@echo "File: $(FINAL_FILE)"
	@echo "RPC URL: $(call get_network_config,$(FINAL_NETWORK))"
	@export NETWORK=$(call get_rsk_network_name,$(FINAL_NETWORK)); \
	if [ "$(FINAL_TYPE)" = "pegin" ]; then \
		forge script script/tasks/HashQuote.s.sol:HashQuote \
			--sig "hashPeginQuote(string)" "$(FINAL_FILE)" \
			--rpc-url $(call get_network_config,$(FINAL_NETWORK)) \
			--ffi -vv; \
	else \
		forge script script/tasks/HashQuote.s.sol:HashQuote \
			--sig "hashPegoutQuote(string)" "$(FINAL_FILE)" \
			--rpc-url $(call get_network_config,$(FINAL_NETWORK)) \
			--ffi -vv; \
	fi

# Check pause status of all system contracts
.PHONY: pause-status
pause-status:
	@echo "Checking pause status on $(NETWORK)..."
	@echo "RPC URL: $(call get_network_config,$(NETWORK))"
	@export NETWORK=$(call get_rsk_network_name,$(NETWORK)); \
	forge script script/tasks/PauseSystem.s.sol:PauseSystem \
		--sig "checkStatus()" \
		--rpc-url $(call get_network_config,$(NETWORK)) \
		-vv

# Pause all system contracts (simulation)
.PHONY: pause-system
pause-system:
	@echo "Pausing system contracts on $(NETWORK) (SIMULATION)..."
	@echo "RPC URL: $(call get_network_config,$(NETWORK))"
	@echo "Reason: $(PAUSE_REASON)"
	@export NETWORK=$(call get_rsk_network_name,$(NETWORK)); \
	forge script script/tasks/PauseSystem.s.sol:PauseSystem \
		--sig "pauseAll(string)" "$(PAUSE_REASON)" \
		--rpc-url $(call get_network_config,$(NETWORK)) \
		-vv

# Pause all system contracts (actual broadcast)
.PHONY: pause-system-broadcast
pause-system-broadcast:
	@echo "Pausing system contracts on $(NETWORK) (ACTUAL BROADCAST)..."
	@echo "RPC URL: $(call get_network_config,$(NETWORK))"
	@echo "Reason: $(PAUSE_REASON)"
	@export NETWORK=$(call get_rsk_network_name,$(NETWORK)); \
	forge script script/tasks/PauseSystem.s.sol:PauseSystem \
		--sig "pauseAll(string)" "$(PAUSE_REASON)" \
		--rpc-url $(call get_network_config,$(NETWORK)) \
		--broadcast --private-key $(call get_network_key,$(NETWORK)) -vv

# Unpause all system contracts (simulation)
.PHONY: unpause-system
unpause-system:
	@echo "Unpausing system contracts on $(NETWORK) (SIMULATION)..."
	@echo "RPC URL: $(call get_network_config,$(NETWORK))"
	@export NETWORK=$(call get_rsk_network_name,$(NETWORK)); \
	forge script script/tasks/PauseSystem.s.sol:PauseSystem \
		--sig "unpauseAll()" \
		--rpc-url $(call get_network_config,$(NETWORK)) \
		-vv

# Unpause all system contracts (actual broadcast)
.PHONY: unpause-system-broadcast
unpause-system-broadcast:
	@echo "Unpausing system contracts on $(NETWORK) (ACTUAL BROADCAST)..."
	@echo "RPC URL: $(call get_network_config,$(NETWORK))"
	@export NETWORK=$(call get_rsk_network_name,$(NETWORK)); \
	forge script script/tasks/PauseSystem.s.sol:PauseSystem \
		--sig "unpauseAll()" \
		--rpc-url $(call get_network_config,$(NETWORK)) \
		--broadcast --private-key $(call get_network_key,$(NETWORK)) -vv

# Refund user PegOut (simulation)
.PHONY: refund-user-pegout
refund-user-pegout:
	@if [ -z "$(QUOTE_HASH)" ] && [ -z "$(QUOTE_FILE)" ]; then \
		echo "Error: Either QUOTE_HASH or QUOTE_FILE is required"; \
		echo "Usage: make refund-user-pegout NETWORK=testnet QUOTE_HASH=abc123..."; \
		echo "   or: make refund-user-pegout NETWORK=testnet QUOTE_FILE=script/tasks/quote.json"; \
		exit 1; \
	fi
	@if [ -n "$(QUOTE_HASH)" ] && [ -n "$(QUOTE_FILE)" ]; then \
		echo "Error: Cannot specify both QUOTE_HASH and QUOTE_FILE"; \
		exit 1; \
	fi
	@echo "Refunding user PegOut on $(NETWORK) (SIMULATION)..."
	@echo "RPC URL: $(call get_network_config,$(NETWORK))"
	@export NETWORK=$(call get_rsk_network_name,$(NETWORK)); \
	if [ -n "$(QUOTE_FILE)" ]; then \
		echo "Quote File: $(QUOTE_FILE)"; \
		forge script script/tasks/RefundUserPegout.s.sol:RefundUserPegout \
			--sig "refundUserPegoutFromFile(string)" "$(QUOTE_FILE)" \
			--rpc-url $(call get_network_config,$(NETWORK)) \
			--ffi -vv; \
	else \
		echo "Quote Hash: $(QUOTE_HASH)"; \
		forge script script/tasks/RefundUserPegout.s.sol:RefundUserPegout \
			--sig "refundUserPegout(string)" "$(QUOTE_HASH)" \
			--rpc-url $(call get_network_config,$(NETWORK)) \
			-vv; \
	fi

# Refund user PegOut (actual broadcast)
.PHONY: refund-user-pegout-broadcast
refund-user-pegout-broadcast:
	@if [ -z "$(QUOTE_HASH)" ] && [ -z "$(QUOTE_FILE)" ]; then \
		echo "Error: Either QUOTE_HASH or QUOTE_FILE is required"; \
		echo "Usage: make refund-user-pegout-broadcast NETWORK=testnet QUOTE_HASH=abc123..."; \
		echo "   or: make refund-user-pegout-broadcast NETWORK=testnet QUOTE_FILE=script/tasks/quote.json"; \
		exit 1; \
	fi
	@if [ -n "$(QUOTE_HASH)" ] && [ -n "$(QUOTE_FILE)" ]; then \
		echo "Error: Cannot specify both QUOTE_HASH and QUOTE_FILE"; \
		exit 1; \
	fi
	@echo "Refunding user PegOut on $(NETWORK) (ACTUAL BROADCAST)..."
	@echo "RPC URL: $(call get_network_config,$(NETWORK))"
	@export NETWORK=$(call get_rsk_network_name,$(NETWORK)); \
	if [ -n "$(QUOTE_FILE)" ]; then \
		echo "Quote File: $(QUOTE_FILE)"; \
		forge script script/tasks/RefundUserPegout.s.sol:RefundUserPegout \
			--sig "refundUserPegoutFromFile(string)" "$(QUOTE_FILE)" \
			--rpc-url $(call get_network_config,$(NETWORK)) \
			--broadcast --private-key $(call get_network_key,$(NETWORK)) --ffi -vv; \
	else \
		echo "Quote Hash: $(QUOTE_HASH)"; \
		forge script script/tasks/RefundUserPegout.s.sol:RefundUserPegout \
			--sig "refundUserPegout(string)" "$(QUOTE_HASH)" \
			--rpc-url $(call get_network_config,$(NETWORK)) \
			--broadcast --private-key $(call get_network_key,$(NETWORK)) -vv; \
	fi

# Register PegIn (simulation)
.PHONY: register-pegin
register-pegin:
	@if [ -z "$(PEGIN_QUOTE_FILE)" ]; then \
		echo "Error: PEGIN_QUOTE_FILE is required"; \
		echo "Usage: make register-pegin NETWORK=testnet PEGIN_QUOTE_FILE=quote.json PEGIN_SIGNATURE=0x... PEGIN_TXID=abc..."; \
		exit 1; \
	fi
	@if [ -z "$(PEGIN_SIGNATURE)" ]; then \
		echo "Error: PEGIN_SIGNATURE is required"; \
		echo "Usage: make register-pegin NETWORK=testnet PEGIN_QUOTE_FILE=quote.json PEGIN_SIGNATURE=0x... PEGIN_TXID=abc..."; \
		exit 1; \
	fi
	@if [ -z "$(PEGIN_TXID)" ]; then \
		echo "Error: PEGIN_TXID is required"; \
		echo "Usage: make register-pegin NETWORK=testnet PEGIN_QUOTE_FILE=quote.json PEGIN_SIGNATURE=0x... PEGIN_TXID=abc..."; \
		exit 1; \
	fi
	@echo "Registering PegIn on $(NETWORK) (SIMULATION)..."
	@echo "RPC URL: $(call get_network_config,$(NETWORK))"
	@echo "Quote File: $(PEGIN_QUOTE_FILE)"
	@echo "TX ID: $(PEGIN_TXID)"
	@export NETWORK=$(call get_rsk_network_name,$(NETWORK)); \
	export BTC_NETWORK=$(if $(filter mainnet,$(NETWORK)),mainnet,testnet); \
	forge script script/tasks/RegisterPegin.s.sol:RegisterPegin \
		--sig "registerPegin(string,string,string)" "$(PEGIN_QUOTE_FILE)" "$(PEGIN_SIGNATURE)" "$(PEGIN_TXID)" \
		--rpc-url $(call get_network_config,$(NETWORK)) \
		--ffi -vv

# Register PegIn (actual broadcast)
.PHONY: register-pegin-broadcast
register-pegin-broadcast:
	@if [ -z "$(PEGIN_QUOTE_FILE)" ]; then \
		echo "Error: PEGIN_QUOTE_FILE is required"; \
		echo "Usage: make register-pegin-broadcast NETWORK=testnet PEGIN_QUOTE_FILE=quote.json PEGIN_SIGNATURE=0x... PEGIN_TXID=abc..."; \
		exit 1; \
	fi
	@if [ -z "$(PEGIN_SIGNATURE)" ]; then \
		echo "Error: PEGIN_SIGNATURE is required"; \
		echo "Usage: make register-pegin-broadcast NETWORK=testnet PEGIN_QUOTE_FILE=quote.json PEGIN_SIGNATURE=0x... PEGIN_TXID=abc..."; \
		exit 1; \
	fi
	@if [ -z "$(PEGIN_TXID)" ]; then \
		echo "Error: PEGIN_TXID is required"; \
		echo "Usage: make register-pegin-broadcast NETWORK=testnet PEGIN_QUOTE_FILE=quote.json PEGIN_SIGNATURE=0x... PEGIN_TXID=abc..."; \
		exit 1; \
	fi
	@echo "Registering PegIn on $(NETWORK) (ACTUAL BROADCAST)..."
	@echo "RPC URL: $(call get_network_config,$(NETWORK))"
	@echo "Quote File: $(PEGIN_QUOTE_FILE)"
	@echo "TX ID: $(PEGIN_TXID)"
	@export NETWORK=$(call get_rsk_network_name,$(NETWORK)); \
	export BTC_NETWORK=$(if $(filter mainnet,$(NETWORK)),mainnet,testnet); \
	forge script script/tasks/RegisterPegin.s.sol:RegisterPegin \
		--sig "registerPegin(string,string,string)" "$(PEGIN_QUOTE_FILE)" "$(PEGIN_SIGNATURE)" "$(PEGIN_TXID)" \
		--rpc-url $(call get_network_config,$(NETWORK)) \
		--broadcast --private-key $(call get_network_key,$(NETWORK)) --ffi -vv

# Build contracts
.PHONY: build
build:
	@echo "Building contracts..."
	forge build

# Run all tests (unit + fuzz)
.PHONY: test
test:
	@echo "Running all tests..."
	forge test

# Run unit tests only (excludes fuzz/invariant/differential/formal)
.PHONY: test-unit
test-unit:
	@echo "Running unit tests only (excluding fuzz/invariant/differential/formal)..."
	forge test --no-match-path "test/{fuzz,invariant,differential,formal}/**/*"

# Run differential tests
.PHONY: test-differential
test-differential:
	@echo "Running differential tests..."
	forge test --match-path "test/differential/**/*.sol" -vv

# Run tests with verbosity
.PHONY: test-v
test-v:
	@echo "Running tests with verbosity..."
	forge test -vvv

# Run task tests
.PHONY: test-tasks
test-tasks:
	@echo "Running task tests..."
	forge test --match-path "test/tasks/*.t.sol" -vv

# Run PegIn tests
.PHONY: test-pegin
test-pegin:
	@echo "Running PegIn tests..."
	forge test --match-path "test/pegin/*.t.sol" -vv

# Run PegOut tests
.PHONY: test-pegout
test-pegout:
	@echo "Running PegOut tests..."
	forge test --match-path "test/pegout/*.t.sol" -vv

# Run Collateral tests
.PHONY: test-collateral
test-collateral:
	@echo "Running Collateral tests..."
	forge test --match-path "test/collateral/*.t.sol" -vv

# Run Discovery tests
.PHONY: test-discovery
test-discovery:
	@echo "Running Discovery tests..."
	forge test --match-path "test/discovery/*.t.sol" -vv

# Run Integration tests
.PHONY: test-integration
test-integration:
	@echo "Running Integration tests..."
	forge test --match-path "test/integration/*.t.sol" -vv

# Run Legacy tests
.PHONY: test-legacy
test-legacy:
	@echo "Running Legacy tests..."
	forge test --match-path "test/legacy/*.t.sol" -vv

# Run Flyover system tests (pegin, pegout, collateral, discovery)
.PHONY: test-flyover
test-flyover:
	@echo "Running Flyover system tests..."
	forge test --match-path "test/pegin/*.t.sol" --match-path "test/pegout/*.t.sol" --match-path "test/collateral/*.t.sol" --match-path "test/discovery/*.t.sol" -vv

# Run a specific test file
# Usage: make test-file FILE=test/tasks/HashQuote.t.sol
.PHONY: test-file
test-file:
	@if [ -z "$(FILE)" ]; then \
		echo "Error: FILE is required"; \
		echo "Usage: make test-file FILE=test/tasks/HashQuote.t.sol"; \
		exit 1; \
	fi
	@echo "Running tests in $(FILE)..."
	forge test --match-path "$(FILE)" -vvv

# Run a specific test function
# Usage: make test-func FUNC=test_HashPeginQuote
.PHONY: test-func
test-func:
	@if [ -z "$(FUNC)" ]; then \
		echo "Error: FUNC is required"; \
		echo "Usage: make test-func FUNC=test_HashPeginQuote"; \
		exit 1; \
	fi
	@echo "Running test function $(FUNC)..."
	forge test --match-test "$(FUNC)" -vvv

# Run tests with coverage
.PHONY: coverage
coverage:
	@echo "Running tests with coverage..."
	forge coverage

# ============ Fuzz Tests ============

# Run all fuzz tests
.PHONY: test-fuzz
test-fuzz:
	@echo "Running all fuzz tests..."
	forge test --match-path "test/fuzz/**/*.sol" -vv

# Run collateral fuzz tests
.PHONY: test-fuzz-collateral
test-fuzz-collateral:
	@echo "Running collateral fuzz tests..."
	forge test --match-path "test/fuzz/collateral/*.sol" -vv

# Run discovery fuzz tests
.PHONY: test-fuzz-discovery
test-fuzz-discovery:
	@echo "Running discovery fuzz tests..."
	forge test --match-path "test/fuzz/discovery/*.sol" -vv

# Run pegin fuzz tests
.PHONY: test-fuzz-pegin
test-fuzz-pegin:
	@echo "Running pegin fuzz tests..."
	forge test --match-path "test/fuzz/pegin/*.sol" -vv

# Run pegout fuzz tests
.PHONY: test-fuzz-pegout
test-fuzz-pegout:
	@echo "Running pegout fuzz tests..."
	forge test --match-path "test/fuzz/pegout/*.sol" -vv

# Run libraries fuzz tests
.PHONY: test-fuzz-libraries
test-fuzz-libraries:
	@echo "Running libraries fuzz tests..."
	forge test --match-path "test/fuzz/libraries/*.sol" -vv

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
deploy-all: deploy-lbc-fork upgrade-lbc-fork change-owner-fork

# Quick test deployment on dev network (simulation)
.PHONY: dev-deploy
dev-deploy:
	@echo "Quick deployment on dev network (SIMULATION)..."
	$(MAKE) deploy-lbc-fork NETWORK=dev VERIFY=false

# Quick test deployment on dev network (actual)
.PHONY: dev-deploy-broadcast
dev-deploy-broadcast:
	@echo "Quick deployment on dev network (ACTUAL DEPLOYMENT)..."
	$(MAKE) deploy-lbc-broadcast NETWORK=dev VERIFY=false

# Test deployment on testnet fork (simulation)
.PHONY: testnet-fork-deploy
testnet-fork-deploy:
	@echo "Test deployment on testnet fork (SIMULATION)..."
	$(MAKE) deploy-lbc-fork NETWORK=testnet FORK_BLOCK=6020639 VERIFY=false

# Test deployment on testnet fork (actual)
.PHONY: testnet-fork-deploy-broadcast
testnet-fork-deploy-broadcast:
	@echo "Test deployment on testnet fork (ACTUAL DEPLOYMENT)..."
	$(MAKE) deploy-lbc-broadcast NETWORK=testnet FORK_BLOCK=6020639 VERIFY=false

# =============================================================================
# DEVELOPMENT NETWORK DEPLOYMENT (Testnet chain with development library addresses)
# =============================================================================

# Development network fork deploy (simulation)
.PHONY: development-fork-deploy
development-fork-deploy:
	@echo "Development network deployment (SIMULATION)..."
	@echo "Using rskDevelopment library addresses on testnet chain"
	$(MAKE) deploy-lbc-fork NETWORK=development VERIFY=false

# Development network fork deploy (actual)
.PHONY: development-fork-deploy-broadcast
development-fork-deploy-broadcast:
	@echo "Development network deployment (ACTUAL DEPLOYMENT)..."
	@echo "Using rskDevelopment library addresses on testnet chain"
	$(MAKE) deploy-lbc-broadcast NETWORK=development VERIFY=false

# Deploy Flyover on development network (simulation)
.PHONY: development-deploy-flyover-fork
development-deploy-flyover-fork:
	@echo "Deploying Flyover on development network (SIMULATION)..."
	@echo "Using rskDevelopment library addresses on testnet chain"
	$(MAKE) deploy-flyover-fork NETWORK=development

# Deploy Flyover on development network (actual)
.PHONY: development-deploy-flyover-broadcast
development-deploy-flyover-broadcast:
	@echo "Deploying Flyover on development network (ACTUAL DEPLOYMENT)..."
	@echo "Using rskDevelopment library addresses on testnet chain"
	$(MAKE) deploy-flyover-broadcast NETWORK=development

# Upgrade LBC on development network (simulation)
.PHONY: development-upgrade-lbc-fork
development-upgrade-lbc-fork:
	@echo "Upgrading LBC on development network (SIMULATION)..."
	@echo "Using rskDevelopment library addresses on testnet chain"
	$(MAKE) upgrade-lbc-fork NETWORK=development

# Upgrade LBC on development network (actual)
.PHONY: development-upgrade-lbc-broadcast
development-upgrade-lbc-broadcast:
	@echo "Upgrading LBC on development network (ACTUAL DEPLOYMENT)..."
	@echo "Using rskDevelopment library addresses on testnet chain"
	$(MAKE) upgrade-lbc-broadcast NETWORK=development

# Mainnet fork deployment (simulation)
.PHONY: mainnet-fork-deploy
mainnet-fork-deploy:
	@echo "Mainnet fork deployment (SIMULATION)..."
	$(MAKE) deploy-lbc-fork NETWORK=mainnet FORK_BLOCK=latest VERIFY=false

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
safe-deploy-lbc: validate-deploy deploy-lbc-fork

.PHONY: safe-upgrade-lbc
safe-upgrade-lbc: validate-deploy upgrade-lbc-fork

.PHONY: safe-change-owner
safe-change-owner: validate-deploy change-owner-fork

# Documentation
.PHONY: docs
docs:
	@echo "Documentation is available in docs/FOUNDRY_MAKEFILE_GUIDE.md"

# Invariant tests
.PHONY: test-invariant
test-invariant:
	@echo "Running invariant tests..."
	forge test --match-path "test/invariant/**/*.t.sol" -vv

# Formal verification (Halmos symbolic tests)
# Uses the 'halmos' Foundry profile (shanghai EVM) to avoid unsupported Cancun opcodes.
.PHONY: test-formal
test-formal:
	@echo "Running formal verification tests (Halmos)..."
	FOUNDRY_PROFILE=halmos halmos --match-contract FormalTest --function check --solver-timeout-assertion 10000

# Python development environment setup (Halmos + pre-commit)
# Creates `.venv/` at the repo root with the pinned versions from
# requirements.txt. Prefers `uv` if available,
# otherwise falls back to system python3.12 or python3.11. Idempotent.
.PHONY: python-setup
python-setup:
	@scripts/setup-python.sh

# Catch-all target for hash-quote arguments (pegin/pegout, network names, file paths)
# This prevents make from complaining about unknown targets when using: make hash-quote pegin testnet
ifneq (,$(findstring hash-quote,$(MAKECMDGOALS)))
pegin pegout mainnet testnet development local regtest rskMainnet rskTestnet rskRegtest rskDevelopment:
	@:
# Also catch file arguments (anything ending in .json)
%.json:
	@:
endif
