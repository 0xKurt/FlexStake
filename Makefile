-include .env

# Network configurations
NETWORKS = sepolia arbitrum optimism

# Common parameters
SCRIPT = script/Deploy.s.sol:DeployScript
VERBOSITY = -vvvv
DEPLOY_ARGS = --broadcast --verify

# Colors for output
GREEN := $(shell tput setaf 2)
YELLOW := $(shell tput setaf 3)
RED := $(shell tput setaf 1)
RESET := $(shell tput sgr0)

# Define deploy targets explicitly
deploy-sepolia: NETWORK = SEPOLIA
deploy-arbitrum: NETWORK = ARBITRUM
deploy-optimism: NETWORK = OPTIMISM

# Make all targets phony
.PHONY: $(addprefix deploy-,$(NETWORKS)) check-env build test clean status-% help FORCE

help:
	@echo "$(GREEN)Available commands:$(RESET)"
	@echo "  make deploy-sepolia     - Deploy to Sepolia testnet"
	@echo "  make deploy-arbitrum    - Deploy to Arbitrum network"
	@echo "  make deploy-optimism    - Deploy to Optimism network"
	@echo "\n$(YELLOW)Before deploying:$(RESET)"
	@echo "1. Create .env file with required variables"
	@echo "2. Ensure you have enough funds for deployment"
	@echo "3. Check your RPC endpoints"
	@echo "\n$(YELLOW)Environment variables needed:$(RESET)"
	@echo "- PRIVATE_KEY"
	@echo "- *_RPC (network specific RPC URLs)"

# Deployment rule (used by all deploy-* targets)
deploy-sepolia deploy-arbitrum deploy-optimism: check-env build
	@echo "$(YELLOW)Starting deployment process for $(NETWORK) network...$(RESET)"
	@echo "$(YELLOW)Checking RPC configuration...$(RESET)"
	@echo "Network: $(NETWORK)"
	@echo "RPC Variable Name: $(NETWORK)_RPC"
	@echo "RPC Value: $($(NETWORK)_RPC)"
	
	@if [ -z "$($(NETWORK)_RPC)" ]; then \
		echo "$(RED)Error: $(NETWORK)_RPC not set in .env$(RESET)" && \
		echo "$(YELLOW)Please ensure your .env file contains $(NETWORK)_RPC=$(RESET)" && \
		exit 1; \
	fi
	
	@echo "$(GREEN)RPC check passed$(RESET)"
	@echo "$(YELLOW)Starting deployment with primary RPC...$(RESET)"
	@forge script $(SCRIPT) --rpc-url $($(NETWORK)_RPC) $(DEPLOY_ARGS) $(VERBOSITY)

# Check for required environment variables
check-env:
	@echo "$(YELLOW)Checking environment variables...$(RESET)"
	@if [ ! -f .env ]; then \
		echo "$(RED)Error: .env file not found$(RESET)" && \
		echo "$(YELLOW)Please copy .env.example to .env and fill in your values$(RESET)" && \
		exit 1; \
	fi
	@if [ -z "$(PRIVATE_KEY)" ]; then \
		echo "$(RED)Error: PRIVATE_KEY not set in .env$(RESET)" && \
		exit 1; \
	fi
	@echo "$(GREEN)Environment check passed$(RESET)"

# Clean build artifacts
clean:
	forge clean
	rm -rf broadcast/
	
	rm -rf out/

# Show current network status
status-%:
	@echo "$(GREEN)Checking $* network status...$(RESET)"
	@forge script $(SCRIPT) --rpc-url $(${*}_RPC) --dry-run || \
		forge script $(SCRIPT) --rpc-url $*_public --dry-run

# Build without deployment
build:
	@echo "$(GREEN)Building contracts...$(RESET)"
	@forge build

# Run tests
test:
	@echo "$(GREEN)Running tests...$(RESET)"
	@forge test -vv 

# Force target to ensure rules always run
FORCE: 