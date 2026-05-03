# Makefile for pg-embedding-gen-by-yhw - Build instructions

.DEFAULT_GOAL := help

.PHONY: help build clean deploy test install

help: ## Show this help message
	@echo "pg-embedding-gen-by-yhw - PostgreSQL Embedding Extension"
	@echo ""
	@echo "Available targets:"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-20s\033[0m %s\n", $$1, $$2}'

build: ## Build C extension
	@echo "Building pg-embedding-gen-by-yhw..."
	@mkdir -p build
	@gcc -fPIC -shared \
		-o build/pg-embedding-gen-by-yhw.so \
		src/pg_embedding_gen.c \
		-I/usr/local/pgsql/include/server \
		-Wno-implicit-function-declaration \
		-Wno-incompatible-pointer-types 2>&1 || \
	gcc -fPIC -shared \
		-o build/pg-embedding-gen-by-yhw.so \
		src/pg_embedding_gen.c \
		-I/usr/local/pgsql/include/server \
		2>&1
	@echo "Build complete: build/pg-embedding-gen-by-yhw.so"

clean: ## Remove build artifacts
	@echo "Cleaning..."
	@rm -rf build/*
	@find . -name "*.pyc" -delete
	@find . -name "__pycache__" -type d -exec rm -rf {} + 2>/dev/null || true
	@echo "Clean complete."

deploy: ## Create deployment package
	@echo "Creating deployment package..."
	@mkdir -p deploy
	@cp -r src lib scripts config.example.yaml README.md LICENSE .gitignore deploy/
	@chmod +x deploy/scripts/*.sh
	@echo "Deployment package created in deploy/"

test: ## Run extension tests (requires PostgreSQL)
	@echo "Running extension tests..."
	@psql -d memory_graph -f scripts/test_extension.sql 2>&1 | grep -v "Pseudo-terminal\|Activate the web console"

install: build deploy ## Build, deploy and test
	@echo ""
	@echo "=== Full Installation ==="
	@echo "1. Built extension (build/pg-embedding-gen-by-yhw.so)"
	@echo "2. Created deployment package (deploy/)"
	@echo "3. To install on remote server:"
	@echo "   cd deploy && ./scripts/deploy_to_pg.sh [server] [database]"

# Target for creating ZIP package
zip: build deploy ## Create ZIP package for distribution
	@echo "Creating ZIP package..."
	@cd .. && zip -r pg-embedding-gen-by-yhw.zip pg_embedding_gen/ -x "*.git*"
	@mv pg-embedding-gen-by-yhw.zip .
	@echo "ZIP package created: pg-embedding-gen-by-yhw.zip"
