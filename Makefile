-include .env

# Network configurations
NETWORKS = sepolia arbitrum optimism

# Common parameters
SCRIPT = script/Deploy.s.sol:DeployFlexStake
VERBOSITY = -vvvv
DEPLOY_ARGS = --broadcast --verify

# Colors for output
GREEN := $(shell tput setaf 2)
YELLOW := $(shell tput setaf 3)
RED := $(shell tput setaf 1)
RESET := $(shell tput sgr0)

.PHONY: help $(NETWORKS:%=deploy-%)

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

# Generic deploy rule for all networks
deploy-%: check-env
	@echo "$(GREEN)Deploying to $* network...$(RESET)"
	@echo "$(YELLOW)Using primary RPC...$(RESET)"
	@if [ -z "$(${*}_RPC)" ]; then \
		echo "$(RED)Error: ${*}_RPC not set in .env$(RESET)" && exit 1; \
	fi
	@forge script $(SCRIPT) --rpc-url $(${*}_RPC) $(DEPLOY_ARGS) $(VERBOSITY) || \
	( \
		echo "$(YELLOW)Primary RPC failed, trying public RPC...$(RESET)" && \
		forge script $(SCRIPT) --rpc-url $*_public $(DEPLOY_ARGS) $(VERBOSITY) || \
		( \
			echo "$(RED)Deployment failed on both RPCs$(RESET)" && \
			echo "$(RED)Please check:$(RESET)" && \
			echo "- RPC endpoints" && \
			echo "- Network status" && \
			echo "- Account balance" && \
			exit 1 \
		) \
	)
	@echo "$(GREEN)Deployment to $* completed successfully!$(RESET)"

# Check for required environment variables
check-env:
	@if [ -z "$(PRIVATE_KEY)" ]; then \
		echo "$(RED)Error: PRIVATE_KEY not set in .env$(RESET)" && exit 1; \
	fi

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