#!/bin/bash
# ============================================================================
# ENTRYPOINT FOR PHP-CLI CONTAINER (SPLIT ARCHITECTURE)
# Sources base entrypoint for PHP config generation, then executes CMD
# ============================================================================

set -e

# Identify this container role
export CONTAINER_ROLE="php-cli"

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# ============================================================================
# SOURCE BASE ENTRYPOINT (directories, permissions, PHP config)
# ============================================================================
source /usr/local/bin/entrypoint-base

# ============================================================================
# START
# ============================================================================
echo ""
echo -e "${BLUE}============================================================================${NC}"
echo -e "${GREEN}PHP-CLI initialization complete!${NC}"
echo -e "${BLUE}============================================================================${NC}"
echo -e "${YELLOW}Starting: $@${NC}"
echo ""

exec "$@"
