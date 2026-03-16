#!/bin/bash
# ============================================================================
# ENTRYPOINT FOR SUPERVISOR CONTAINER (SPLIT ARCHITECTURE)
# Sources base entrypoint, then adds supervisor-specific initialization
# ============================================================================

set -e

# Identify this container role
export CONTAINER_ROLE="supervisor"

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
# SUPERVISOR-SPECIFIC: PER-SITE CONFIG LOADING
# ============================================================================
echo -e "${YELLOW}[SUP 1/1] Loading per-site supervisor configs...${NC}"

SUPERVISOR_CONF_DIR="/etc/supervisor/conf.d"
SITES_CONFIG_DIR="/etc/bitrix-sites"
SITE_CONF_COUNT=0

# Create supervisor directories
mkdir -p /var/run/supervisor /var/log/supervisor "$SUPERVISOR_CONF_DIR"
chown -R "${UGN}:${UGN}" /var/run/supervisor /var/log/supervisor 2>/dev/null || true

if [ -d "$SITES_CONFIG_DIR" ]; then
    for site_sup_dir in "$SITES_CONFIG_DIR"/*/supervisor; do
        if [ -d "$site_sup_dir" ]; then
            site_domain=$(basename "$(dirname "$site_sup_dir")")
            for conf_file in "$site_sup_dir"/*.conf; do
                if [ -f "$conf_file" ]; then
                    conf_name="${site_domain}_$(basename "$conf_file")"
                    cp "$conf_file" "$SUPERVISOR_CONF_DIR/$conf_name"
                    SITE_CONF_COUNT=$((SITE_CONF_COUNT + 1))
                    echo -e "${BLUE}  + $site_domain: $(basename "$conf_file")${NC}"
                fi
            done
        fi
    done
fi

if [ $SITE_CONF_COUNT -gt 0 ]; then
    echo -e "${GREEN}  Loaded ${SITE_CONF_COUNT} per-site supervisor configs${NC}"
else
    echo -e "${YELLOW}  No per-site supervisor configs found${NC}"
fi

# ============================================================================
# START
# ============================================================================
echo ""
echo -e "${BLUE}============================================================================${NC}"
echo -e "${GREEN}Supervisor initialization complete!${NC}"
echo -e "${BLUE}============================================================================${NC}"
echo -e "${YELLOW}Starting: $@${NC}"
echo ""

exec "$@"
