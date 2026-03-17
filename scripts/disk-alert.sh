#!/bin/bash
# ============================================================================
# DISK USAGE ALERT — Telegram notification
# Sends alert when disk usage exceeds threshold
#
# Usage:
#   ./scripts/disk-alert.sh
#   ./scripts/disk-alert.sh --test    # Send test message
#   ./scripts/disk-alert.sh --setup   # Show cron setup instructions
#
# Environment variables (or edit below):
#   TELEGRAM_BOT_TOKEN  — Bot token from @BotFather
#   TELEGRAM_CHAT_ID    — Chat ID (use @userinfobot to get)
#   DISK_THRESHOLD      — Alert threshold in percent (default: 80)
#
# Cron (every 6 hours):
#   0 */6 * * * /home/bitrix/bitrix/scripts/disk-alert.sh >> /var/log/disk-alert.log 2>&1
# ============================================================================

set -euo pipefail

# ============================================================================
# CONFIGURATION — CHANGE THESE
# ============================================================================
TELEGRAM_BOT_TOKEN="${TELEGRAM_BOT_TOKEN:-YOUR_BOT_TOKEN_HERE}"
TELEGRAM_CHAT_ID="${TELEGRAM_CHAT_ID:-YOUR_CHAT_ID_HERE}"
DISK_THRESHOLD="${DISK_THRESHOLD:-80}"

# ============================================================================
# CONSTANTS
# ============================================================================
HOSTNAME=$(hostname)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ALERT_SENT_FILE="/tmp/.disk-alert-sent"
TELEGRAM_API="https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage"

# ============================================================================
# FUNCTIONS
# ============================================================================

send_telegram() {
    local message="$1"
    curl -s -X POST "$TELEGRAM_API" \
        -d "chat_id=${TELEGRAM_CHAT_ID}" \
        -d "text=${message}" \
        -d "parse_mode=HTML" \
        --max-time 10 > /dev/null 2>&1
}

check_disk() {
    local alerts=""
    local has_alert=false

    while IFS= read -r line; do
        local usage
        local partition
        usage=$(echo "$line" | awk '{print $5}' | tr -d '%')
        partition=$(echo "$line" | awk '{print $6}')

        # Skip virtual filesystems
        case "$partition" in
            /dev|/dev/*|/proc|/sys|/run|/snap/*|/boot/efi) continue ;;
        esac

        # Skip if usage is not a number
        [[ "$usage" =~ ^[0-9]+$ ]] || continue

        if [ "$usage" -ge "$DISK_THRESHOLD" ]; then
            local size
            local used
            local avail
            size=$(echo "$line" | awk '{print $2}')
            used=$(echo "$line" | awk '{print $3}')
            avail=$(echo "$line" | awk '{print $4}')
            alerts="${alerts}\n  <b>${partition}</b>: ${usage}% (${used}/${size}, free: ${avail})"
            has_alert=true
        fi
    done < <(df -H | tail -n +2)

    if [ "$has_alert" = true ]; then
        # Check if we already sent alert in last 6 hours
        if [ -f "$ALERT_SENT_FILE" ]; then
            local last_sent
            last_sent=$(stat -c %Y "$ALERT_SENT_FILE" 2>/dev/null || stat -f %m "$ALERT_SENT_FILE" 2>/dev/null)
            local now
            now=$(date +%s)
            local diff=$(( now - last_sent ))
            # Skip if alert was sent less than 6 hours ago
            if [ "$diff" -lt 21600 ]; then
                echo "[$(date '+%Y-%m-%d %H:%M:%S')] Alert already sent recently, skipping"
                return 0
            fi
        fi

        local message="⚠️ <b>DISK ALERT</b> [${HOSTNAME}]"
        message="${message}\nThreshold: ${DISK_THRESHOLD}%"
        message="${message}\n${alerts}"
        message="${message}\n\n🕐 $(date '+%Y-%m-%d %H:%M:%S')"

        # Docker disk usage info
        if command -v docker &>/dev/null; then
            local docker_usage
            docker_usage=$(docker system df --format 'table {{.Type}}\t{{.Size}}\t{{.Reclaimable}}' 2>/dev/null | tail -n +2 || echo "N/A")
            if [ "$docker_usage" != "N/A" ]; then
                message="${message}\n\n🐳 Docker:"
                message="${message}\n<pre>${docker_usage}</pre>"
                message="${message}\n\n💡 Run: <code>docker system prune -af --filter 'until=168h'</code>"
            fi
        fi

        send_telegram "$message"
        touch "$ALERT_SENT_FILE"
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] ALERT sent: disk threshold exceeded"
    else
        # Remove alert file when resolved
        rm -f "$ALERT_SENT_FILE"
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] OK: all partitions below ${DISK_THRESHOLD}%"
    fi
}

send_test() {
    echo "Sending test message to Telegram..."
    local message="✅ <b>Disk Alert Test</b> [${HOSTNAME}]"
    message="${message}\nThreshold: ${DISK_THRESHOLD}%"
    message="${message}\n\nDisk status:"

    while IFS= read -r line; do
        local usage partition size avail
        usage=$(echo "$line" | awk '{print $5}')
        partition=$(echo "$line" | awk '{print $6}')
        size=$(echo "$line" | awk '{print $2}')
        avail=$(echo "$line" | awk '{print $4}')
        [[ "$partition" =~ ^(/dev|/proc|/sys|/run|/snap) ]] && continue
        message="${message}\n  ${partition}: ${usage} (total: ${size}, free: ${avail})"
    done < <(df -H | tail -n +2)

    message="${message}\n\n🕐 $(date '+%Y-%m-%d %H:%M:%S')"
    send_telegram "$message"
    echo "Test message sent!"
}

show_setup() {
    echo ""
    echo "╔════════════════════════════════════════════════════════════╗"
    echo "║              DISK ALERT SETUP                              ║"
    echo "╚════════════════════════════════════════════════════════════╝"
    echo ""
    echo "1. Create Telegram bot:"
    echo "   - Message @BotFather → /newbot → get token"
    echo "   - Message @userinfobot → get your chat_id"
    echo ""
    echo "2. Edit this script or export env vars:"
    echo "   export TELEGRAM_BOT_TOKEN='123456:ABC...'"
    echo "   export TELEGRAM_CHAT_ID='123456789'"
    echo ""
    echo "3. Test:"
    echo "   $SCRIPT_DIR/disk-alert.sh --test"
    echo ""
    echo "4. Add to cron (as root or bitrix user):"
    echo "   crontab -e"
    echo "   # Add:"
    echo "   0 */6 * * * TELEGRAM_BOT_TOKEN='YOUR_TOKEN' TELEGRAM_CHAT_ID='YOUR_ID' $SCRIPT_DIR/disk-alert.sh >> /var/log/disk-alert.log 2>&1"
    echo ""
}

# ============================================================================
# MAIN
# ============================================================================
case "${1:-}" in
    --test)
        send_test
        ;;
    --setup)
        show_setup
        ;;
    *)
        check_disk
        ;;
esac
