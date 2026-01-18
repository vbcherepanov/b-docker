#!/bin/bash
# ============================================================================
# MULTISITE CRON DISPATCHER
# Runs Bitrix cron tasks for ALL sites in the multisite environment
# Usage: multisite-cron.sh [agents|mail_queue|all]
# ============================================================================

set -euo pipefail

# Configuration
APP_DIR="${APP_DIR:-/home/bitrix/app}"
PHP_BIN="${PHP_BIN:-/usr/local/bin/php}"
LOG_DIR="${LOG_DIR:-/var/log/cron}"
RUN_USER="${RUN_USER:-bitrix}"

# Task type to run (agents, mail_queue, or all)
TASK_TYPE="${1:-agents}"

# Ensure log directory exists
mkdir -p "$LOG_DIR"

# Logging function with domain prefix
log() {
    local domain="$1"
    local level="$2"
    local message="$3"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] [$domain] [$level] $message" | tee -a "$LOG_DIR/multisite-cron.log"
}

# Run Bitrix agents for a single site
run_agents() {
    local site_www="$1"
    local domain="$2"
    local cron_file="$site_www/bitrix/modules/main/tools/cron_events.php"

    if [ -f "$cron_file" ]; then
        log "$domain" "INFO" "Running agents..."
        cd "$site_www"

        # Run as specified user if we're root
        if [ "$(id -u)" = "0" ] && id "$RUN_USER" >/dev/null 2>&1; then
            su -s /bin/bash "$RUN_USER" -c "$PHP_BIN $cron_file" 2>&1 | while read -r line; do
                log "$domain" "AGENT" "$line"
            done
        else
            $PHP_BIN "$cron_file" 2>&1 | while read -r line; do
                log "$domain" "AGENT" "$line"
            done
        fi

        log "$domain" "OK" "Agents completed"
    fi
}

# Run mail queue processing for a single site
run_mail_queue() {
    local site_www="$1"
    local domain="$2"
    local mail_file="$site_www/bitrix/modules/main/tools/mail_queue.php"

    if [ -f "$mail_file" ]; then
        log "$domain" "INFO" "Processing mail queue..."
        cd "$site_www"

        # Run as specified user if we're root
        if [ "$(id -u)" = "0" ] && id "$RUN_USER" >/dev/null 2>&1; then
            su -s /bin/bash "$RUN_USER" -c "$PHP_BIN $mail_file" 2>&1 | while read -r line; do
                log "$domain" "MAIL" "$line"
            done
        else
            $PHP_BIN "$mail_file" 2>&1 | while read -r line; do
                log "$domain" "MAIL" "$line"
            done
        fi

        log "$domain" "OK" "Mail queue completed"
    fi
}

# Main execution
main() {
    local start_time
    start_time=$(date +%s)

    log "SYSTEM" "INFO" "Starting multisite cron: $TASK_TYPE"

    # Count processed sites
    local site_count=0

    # Iterate over all domain directories
    for domain_dir in "$APP_DIR"/*/; do
        if [ -d "$domain_dir" ]; then
            domain=$(basename "$domain_dir")
            site_www="$domain_dir/www"

            # Skip template and hidden directories
            [[ "$domain" == _* ]] && continue
            [[ "$domain" == .* ]] && continue

            # Only process directories with www/ subdirectory (valid sites)
            if [ -d "$site_www" ]; then
                case "$TASK_TYPE" in
                    agents)
                        run_agents "$site_www" "$domain"
                        ;;
                    mail_queue|mail)
                        run_mail_queue "$site_www" "$domain"
                        ;;
                    all)
                        run_agents "$site_www" "$domain"
                        run_mail_queue "$site_www" "$domain"
                        ;;
                    *)
                        log "SYSTEM" "ERROR" "Unknown task type: $TASK_TYPE"
                        exit 1
                        ;;
                esac
                ((site_count++))
            fi
        fi
    done

    local end_time
    end_time=$(date +%s)
    local duration=$((end_time - start_time))

    log "SYSTEM" "OK" "Multisite cron completed: $site_count sites, ${duration}s"
}

# Run main function
main
