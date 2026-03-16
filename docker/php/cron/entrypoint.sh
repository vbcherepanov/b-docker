#!/bin/bash
# ============================================================================
# ENTRYPOINT FOR CRON CONTAINER (SPLIT ARCHITECTURE)
# Sources base entrypoint, then adds cron-specific initialization
# ============================================================================

set -e

# Identify this container role
export CONTAINER_ROLE="cron"

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
# CRON-SPECIFIC: MERGE CRONTABS (base + per-site)
# ============================================================================
echo -e "${YELLOW}[CRON 1/1] Configuring cron...${NC}"

# NOTE: dcron in Alpine requires root crontab for reliable execution
# Base crontab is mounted read-only to /etc/crontabs/root.base
# Per-site crontabs are in /etc/bitrix-sites/{domain}/crontab
# We merge them into /etc/crontabs/root at startup

CRONTAB_BASE="/etc/crontabs/root.base"
CRONTAB_TARGET="/etc/crontabs/root"
SITES_CRONTAB_DIR="/etc/bitrix-sites"

# Create cron log directory
mkdir -p /var/log/cron
chown -R "${UGN}:${UGN}" /var/log/cron 2>/dev/null || true

if [ -f "$CRONTAB_BASE" ]; then
    # Start with base crontab
    cp "$CRONTAB_BASE" "$CRONTAB_TARGET"

    # Append per-site crontabs
    SITE_CRON_COUNT=0
    if [ -d "$SITES_CRONTAB_DIR" ]; then
        for site_crontab in "$SITES_CRONTAB_DIR"/*/crontab; do
            if [ -f "$site_crontab" ] && [ -s "$site_crontab" ]; then
                site_domain=$(basename "$(dirname "$site_crontab")")
                echo "" >> "$CRONTAB_TARGET"
                echo "# === PER-SITE CRON: $site_domain ===" >> "$CRONTAB_TARGET"
                cat "$site_crontab" >> "$CRONTAB_TARGET"
                SITE_CRON_COUNT=$((SITE_CRON_COUNT + 1))
                echo -e "${BLUE}  + Added crontab for: $site_domain${NC}"
            fi
        done
    fi

    # Set permissions
    chmod 600 "$CRONTAB_TARGET"
    chown root:root "$CRONTAB_TARGET"

    # Summary
    CRON_TASKS=$(grep -v "^#" "$CRONTAB_TARGET" | grep -v "^$" | grep -v "run-parts" | wc -l)
    echo -e "${GREEN}  Crontab merged (base + ${SITE_CRON_COUNT} site crontabs)${NC}"
    echo -e "${BLUE}  Active tasks: ${CRON_TASKS}${NC}"
else
    echo -e "${YELLOW}  Base crontab not found at $CRONTAB_BASE${NC}"
    echo -e "${YELLOW}  Creating empty crontab${NC}"
    echo "# Empty crontab - no base crontab found" > "$CRONTAB_TARGET"
    chmod 600 "$CRONTAB_TARGET"
    chown root:root "$CRONTAB_TARGET"
fi

echo -e "${GREEN}  Cron configured${NC}"

# ============================================================================
# START
# ============================================================================
echo ""
echo -e "${BLUE}============================================================================${NC}"
echo -e "${GREEN}Cron initialization complete!${NC}"
echo -e "${BLUE}============================================================================${NC}"
echo -e "${YELLOW}Starting: $@${NC}"
echo ""

exec "$@"
