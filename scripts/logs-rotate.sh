#!/bin/bash
# ============================================================================
# LOG ROTATION SCRIPT FOR BITRIX DOCKER
# Rotates and cleans up old logs
#
# Usage:
#   ./scripts/logs-rotate.sh [OPTIONS]
#
# Options:
#   --rotate     Rotate logs now
#   --cleanup    Delete logs older than RETENTION_DAYS
#   --status     Show log disk usage
#   --force      Force rotation even if not due
#
# Environment:
#   RETENTION_DAYS  Days to keep logs (default: 30)
#   LOGS_DIR        Path to logs directory (default: ./volume/logs)
# ============================================================================

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
LOGS_DIR="${LOGS_DIR:-$PROJECT_DIR/volume/logs}"
RETENTION_DAYS="${RETENTION_DAYS:-30}"
LOGROTATE_CONF="$PROJECT_DIR/config/logrotate/logrotate.conf"

# ============================================================================
# FUNCTIONS
# ============================================================================

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[OK]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Show disk usage of logs
show_status() {
    echo ""
    echo "╔════════════════════════════════════════════════════════════╗"
    echo "║              LOG DISK USAGE STATUS                         ║"
    echo "╚════════════════════════════════════════════════════════════╝"
    echo ""

    if [ ! -d "$LOGS_DIR" ]; then
        log_error "Logs directory not found: $LOGS_DIR"
        return 1
    fi

    echo "📁 Logs directory: $LOGS_DIR"
    echo ""

    # Total size
    total_size=$(du -sh "$LOGS_DIR" 2>/dev/null | cut -f1)
    echo "📊 Total size: $total_size"
    echo ""

    # Per-service breakdown
    echo "📋 Per-service breakdown:"
    echo "-----------------------------------------------------------"

    for dir in "$LOGS_DIR"/*/; do
        if [ -d "$dir" ]; then
            service=$(basename "$dir")
            size=$(du -sh "$dir" 2>/dev/null | cut -f1)
            count=$(find "$dir" -type f -name "*.log*" 2>/dev/null | wc -l | tr -d ' ')
            printf "   %-20s %10s (%d files)\n" "$service" "$size" "$count"
        fi
    done
    echo ""

    # Old files
    old_count=$(find "$LOGS_DIR" -type f -name "*.log*" -mtime +${RETENTION_DAYS} 2>/dev/null | wc -l | tr -d ' ')
    if [ "$old_count" -gt 0 ]; then
        log_warning "Found $old_count files older than $RETENTION_DAYS days"
        old_size=$(find "$LOGS_DIR" -type f -name "*.log*" -mtime +${RETENTION_DAYS} -exec du -ch {} + 2>/dev/null | tail -1 | cut -f1)
        echo "   These files take: $old_size"
        echo "   Run: make logs-cleanup to remove them"
    else
        log_success "No files older than $RETENTION_DAYS days"
    fi
    echo ""
}

# Rotate logs using logrotate
rotate_logs() {
    local force_flag=""
    if [ "$1" = "--force" ]; then
        force_flag="--force"
    fi

    echo ""
    echo "╔════════════════════════════════════════════════════════════╗"
    echo "║              ROTATING LOGS                                 ║"
    echo "╚════════════════════════════════════════════════════════════╝"
    echo ""

    # Check if logrotate is available
    if command -v logrotate &> /dev/null; then
        log_info "Running logrotate..."

        # Create state file directory
        mkdir -p "$PROJECT_DIR/volume/logrotate"

        # Create modified config with correct paths
        local temp_conf=$(mktemp)
        sed "s|/var/log/app|$LOGS_DIR|g" "$LOGROTATE_CONF" > "$temp_conf"

        logrotate $force_flag --state "$PROJECT_DIR/volume/logrotate/status" "$temp_conf" 2>&1 || true
        rm -f "$temp_conf"

        log_success "Logrotate completed"
    else
        log_warning "logrotate not installed, using manual rotation..."
        manual_rotate
    fi

    echo ""
}

# Manual rotation for systems without logrotate
manual_rotate() {
    log_info "Performing manual log rotation..."

    local timestamp=$(date +%Y%m%d_%H%M%S)

    for dir in "$LOGS_DIR"/*/; do
        if [ -d "$dir" ]; then
            service=$(basename "$dir")

            for logfile in "$dir"/*.log; do
                if [ -f "$logfile" ] && [ -s "$logfile" ]; then
                    # Check if file is large enough to rotate (>10MB)
                    size=$(stat -f%z "$logfile" 2>/dev/null || stat -c%s "$logfile" 2>/dev/null || echo "0")
                    if [ "$size" -gt 10485760 ]; then
                        mv "$logfile" "${logfile}.${timestamp}"
                        touch "$logfile"
                        gzip "${logfile}.${timestamp}" 2>/dev/null || true
                        log_info "  Rotated: $(basename "$logfile")"
                    fi
                fi
            done
        fi
    done

    log_success "Manual rotation completed"
}

# Cleanup old logs
cleanup_logs() {
    echo ""
    echo "╔════════════════════════════════════════════════════════════╗"
    echo "║              CLEANING UP OLD LOGS                          ║"
    echo "╚════════════════════════════════════════════════════════════╝"
    echo ""

    log_info "Removing logs older than $RETENTION_DAYS days..."

    if [ ! -d "$LOGS_DIR" ]; then
        log_error "Logs directory not found: $LOGS_DIR"
        return 1
    fi

    # Count files to delete
    count=$(find "$LOGS_DIR" -type f \( -name "*.log.*" -o -name "*.gz" \) -mtime +${RETENTION_DAYS} 2>/dev/null | wc -l | tr -d ' ')

    if [ "$count" -eq 0 ]; then
        log_success "No old log files to remove"
        return 0
    fi

    # Calculate size
    size=$(find "$LOGS_DIR" -type f \( -name "*.log.*" -o -name "*.gz" \) -mtime +${RETENTION_DAYS} -exec du -ch {} + 2>/dev/null | tail -1 | cut -f1)

    log_info "Found $count files ($size) to delete"

    # Delete old rotated logs and compressed files
    find "$LOGS_DIR" -type f \( -name "*.log.*" -o -name "*.gz" \) -mtime +${RETENTION_DAYS} -delete 2>/dev/null

    # Delete empty directories
    find "$LOGS_DIR" -type d -empty -delete 2>/dev/null || true

    log_success "Cleanup completed"
    echo ""
}

# Setup cron for automatic rotation
setup_cron() {
    echo ""
    echo "╔════════════════════════════════════════════════════════════╗"
    echo "║              SETUP AUTOMATIC ROTATION                      ║"
    echo "╚════════════════════════════════════════════════════════════╝"
    echo ""

    local cron_line="0 2 * * * cd $PROJECT_DIR && ./scripts/logs-rotate.sh --rotate --cleanup >> /var/log/logrotate-bitrix.log 2>&1"

    # Check if already installed
    if crontab -l 2>/dev/null | grep -q "logs-rotate.sh"; then
        log_warning "Cron job already exists"
        return 0
    fi

    log_info "Adding cron job for daily log rotation at 2:00 AM..."

    # Add to crontab
    (crontab -l 2>/dev/null || true; echo "$cron_line") | crontab -

    log_success "Cron job installed"
    echo ""
    echo "To view: crontab -l"
    echo "To remove: crontab -e (and delete the line)"
    echo ""
}

# Show help
show_help() {
    echo ""
    echo "╔════════════════════════════════════════════════════════════╗"
    echo "║              LOG ROTATION UTILITY                          ║"
    echo "╚════════════════════════════════════════════════════════════╝"
    echo ""
    echo "Usage: $0 [COMMAND] [OPTIONS]"
    echo ""
    echo "Commands:"
    echo "  --status       Show log disk usage"
    echo "  --rotate       Rotate logs now"
    echo "  --cleanup      Delete logs older than RETENTION_DAYS"
    echo "  --setup-cron   Setup automatic daily rotation"
    echo "  --force        Force rotation (with --rotate)"
    echo "  --help         Show this help"
    echo ""
    echo "Environment variables:"
    echo "  RETENTION_DAYS  Days to keep logs (default: 30)"
    echo "  LOGS_DIR        Path to logs (default: ./volume/logs)"
    echo ""
    echo "Examples:"
    echo "  $0 --status"
    echo "  $0 --rotate"
    echo "  $0 --rotate --force"
    echo "  $0 --cleanup"
    echo "  RETENTION_DAYS=7 $0 --cleanup"
    echo ""
}

# ============================================================================
# MAIN
# ============================================================================

main() {
    case "$1" in
        --status)
            show_status
            ;;
        --rotate)
            rotate_logs "$2"
            ;;
        --cleanup)
            cleanup_logs
            ;;
        --setup-cron)
            setup_cron
            ;;
        --help|-h)
            show_help
            ;;
        "")
            # Default: show status
            show_status
            ;;
        *)
            log_error "Unknown command: $1"
            show_help
            exit 1
            ;;
    esac
}

main "$@"
