#!/bin/bash
# ============================================================================
# BITRIX DOCKER HEALTH WATCHDOG
# Monitors critical containers and restarts them if unhealthy or stopped.
# Run via cron: */5 * * * * /path/to/scripts/health-watchdog.sh
#
# Logs actions to /var/log/bitrix-docker-watchdog.log
# ============================================================================

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPOSE_FILE="$PROJECT_DIR/docker-compose.bitrix.yml"
LOG_FILE="/var/log/bitrix-docker-watchdog.log"
LOCK_FILE="/tmp/bitrix-watchdog.lock"

# Critical services that must always be running
CRITICAL_SERVICES=("nginx" "mysql" "redis")

# Source .env for DOMAIN and other variables
if [ -f "$PROJECT_DIR/.env" ]; then
    set -a
    source "$PROJECT_DIR/.env"
    set +a
fi

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [$1] $2" >> "$LOG_FILE"
}

# Prevent overlapping runs via lock file
cleanup() {
    rm -f "$LOCK_FILE"
}
trap cleanup EXIT

if [ -f "$LOCK_FILE" ]; then
    # Check if the lock is stale (older than 10 minutes)
    if [ "$(find "$LOCK_FILE" -mmin +10 2>/dev/null)" ]; then
        log "WARN" "Removing stale lock file"
        rm -f "$LOCK_FILE"
    else
        exit 0
    fi
fi
echo $$ > "$LOCK_FILE"

# Rotate log file if larger than 10MB
if [ -f "$LOG_FILE" ] && [ "$(stat -c%s "$LOG_FILE" 2>/dev/null || stat -f%z "$LOG_FILE" 2>/dev/null || echo 0)" -gt 10485760 ]; then
    mv "$LOG_FILE" "${LOG_FILE}.old"
    log "INFO" "Log rotated"
fi

cd "$PROJECT_DIR"

# Check Docker daemon availability
if ! docker info >/dev/null 2>&1; then
    log "CRIT" "Docker daemon is not running!"
    exit 1
fi

# Check each critical service
RESTART_NEEDED=false
FAILED_SERVICES=()

for service in "${CRITICAL_SERVICES[@]}"; do
    # Build container name from DOMAIN variable (matches docker compose naming)
    container="${DOMAIN:-bitrix.local}_${service}"

    # Get container status
    status=$(docker inspect --format='{{.State.Status}}' "$container" 2>/dev/null || echo "not_found")
    health=$(docker inspect --format='{{if .State.Health}}{{.State.Health.Status}}{{else}}no_healthcheck{{end}}' "$container" 2>/dev/null || echo "unknown")

    if [ "$status" = "not_found" ]; then
        log "WARN" "$service container not found ($container), scheduling full restart"
        RESTART_NEEDED=true
        FAILED_SERVICES+=("$service")
    elif [ "$status" != "running" ]; then
        log "WARN" "$service is $status (expected: running), scheduling full restart"
        RESTART_NEEDED=true
        FAILED_SERVICES+=("$service")
    elif [ "$health" = "unhealthy" ]; then
        log "WARN" "$service is unhealthy, attempting individual restart"
        if docker restart "$container" >/dev/null 2>&1; then
            log "INFO" "$service restarted successfully"
        else
            log "ERROR" "Failed to restart $service individually, scheduling full restart"
            RESTART_NEEDED=true
            FAILED_SERVICES+=("$service")
        fi
    fi
done

# Full restart if any critical service requires it
if [ "$RESTART_NEEDED" = true ]; then
    log "WARN" "Full restart triggered. Failed services: ${FAILED_SERVICES[*]}"
    if docker compose -f "$COMPOSE_FILE" \
        --profile prod --profile monitoring --profile backup --profile push --profile security \
        up -d --remove-orphans 2>&1 | while read -r line; do log "INFO" "compose: $line"; done; then
        log "INFO" "Full restart completed successfully"
    else
        log "ERROR" "Full restart failed!"
    fi
fi
