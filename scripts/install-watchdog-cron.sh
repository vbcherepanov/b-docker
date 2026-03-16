#!/bin/bash
# ============================================================================
# INSTALL HEALTH WATCHDOG CRON JOB
# Adds a cron entry to check container health every 5 minutes.
#
# Usage:
#   sudo ./scripts/install-watchdog-cron.sh          # Install
#   sudo ./scripts/install-watchdog-cron.sh remove    # Remove
# ============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WATCHDOG_SCRIPT="$SCRIPT_DIR/health-watchdog.sh"
CRON_LINE="*/5 * * * * $WATCHDOG_SCRIPT >> /var/log/bitrix-docker-watchdog.log 2>&1"

# Ensure watchdog script is executable
chmod +x "$WATCHDOG_SCRIPT"

case "${1:-install}" in
    install)
        if crontab -l 2>/dev/null | grep -q "health-watchdog.sh"; then
            echo "Watchdog cron already installed"
            crontab -l 2>/dev/null | grep "health-watchdog.sh"
        else
            (crontab -l 2>/dev/null; echo "$CRON_LINE") | crontab -
            echo "Watchdog cron installed: every 5 minutes"
            echo "  $CRON_LINE"
        fi
        ;;
    remove|uninstall)
        if crontab -l 2>/dev/null | grep -q "health-watchdog.sh"; then
            crontab -l 2>/dev/null | grep -v "health-watchdog.sh" | crontab -
            echo "Watchdog cron removed"
        else
            echo "Watchdog cron not found"
        fi
        ;;
    *)
        echo "Usage: $0 [install|remove]"
        exit 1
        ;;
esac
