#!/bin/bash
# ============================================================================
# DOCKER CLEANUP SCRIPT
# Cleans up Docker resources to free disk space
#
# Usage:
#   ./scripts/docker-cleanup.sh [OPTIONS]
#
# Options:
#   --soft       Safe cleanup (dangling only)
#   --full       Full cleanup (all unused)
#   --aggressive Maximum cleanup (including build cache)
#   --status     Show disk usage
#   --setup-cron Setup automatic weekly cleanup
#
# Recommended: Run weekly via cron
# ============================================================================

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[OK]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Show Docker disk usage
show_status() {
    echo ""
    echo "╔════════════════════════════════════════════════════════════╗"
    echo "║              DOCKER DISK USAGE                             ║"
    echo "╚════════════════════════════════════════════════════════════╝"
    echo ""

    # Docker system df
    log_info "Docker disk usage:"
    docker system df
    echo ""

    # Detailed breakdown
    log_info "Detailed breakdown:"
    docker system df -v 2>/dev/null | head -50 || true
    echo ""

    # Host directories
    log_info "Host directories:"
    if [ -d "/var/lib/docker" ]; then
        echo "  /var/lib/docker:     $(du -sh /var/lib/docker 2>/dev/null | cut -f1)"
    fi
    if [ -d "/var/lib/containerd" ]; then
        echo "  /var/lib/containerd: $(du -sh /var/lib/containerd 2>/dev/null | cut -f1)"
    fi
    echo ""

    # Reclaimable space
    log_info "Reclaimable space (estimated):"
    echo "  Dangling images:    $(docker images -f 'dangling=true' -q 2>/dev/null | wc -l) images"
    echo "  Unused volumes:     $(docker volume ls -f 'dangling=true' -q 2>/dev/null | wc -l) volumes"
    echo "  Build cache:        $(docker builder du 2>/dev/null | tail -1 | awk '{print $NF}' || echo 'N/A')"
    echo ""
}

# Soft cleanup - safe, only dangling/unused
soft_cleanup() {
    echo ""
    echo "╔════════════════════════════════════════════════════════════╗"
    echo "║              SOFT CLEANUP (SAFE)                           ║"
    echo "╚════════════════════════════════════════════════════════════╝"
    echo ""

    local before=$(docker system df --format '{{.Size}}' | head -1)

    # Remove stopped containers
    log_info "Removing stopped containers..."
    docker container prune -f 2>/dev/null || true

    # Remove dangling images (untagged)
    log_info "Removing dangling images..."
    docker image prune -f 2>/dev/null || true

    # Remove unused networks
    log_info "Removing unused networks..."
    docker network prune -f 2>/dev/null || true

    # Remove dangling volumes (not attached to any container)
    log_info "Removing dangling volumes..."
    docker volume prune -f 2>/dev/null || true

    local after=$(docker system df --format '{{.Size}}' | head -1)
    log_success "Soft cleanup completed"
    echo "  Before: $before"
    echo "  After:  $after"
    echo ""
}

# Full cleanup - removes all unused
full_cleanup() {
    echo ""
    echo "╔════════════════════════════════════════════════════════════╗"
    echo "║              FULL CLEANUP                                  ║"
    echo "╚════════════════════════════════════════════════════════════╝"
    echo ""

    local before=$(docker system df --format '{{.Size}}' | head -1)

    # System prune (containers, networks, dangling images)
    log_info "Running docker system prune..."
    docker system prune -f 2>/dev/null || true

    # Remove ALL unused images (not just dangling)
    log_info "Removing unused images..."
    docker image prune -a -f 2>/dev/null || true

    # Remove unused volumes
    log_info "Removing unused volumes..."
    docker volume prune -f 2>/dev/null || true

    local after=$(docker system df --format '{{.Size}}' | head -1)
    log_success "Full cleanup completed"
    echo "  Before: $before"
    echo "  After:  $after"
    echo ""
}

# Aggressive cleanup - maximum space recovery
aggressive_cleanup() {
    echo ""
    echo "╔════════════════════════════════════════════════════════════╗"
    echo "║              AGGRESSIVE CLEANUP                            ║"
    echo "╚════════════════════════════════════════════════════════════╝"
    echo ""

    log_warning "This will remove ALL unused data including build cache!"
    echo ""

    local before=$(docker system df --format '{{.Size}}' | head -1)

    # Full system prune including volumes
    log_info "Running docker system prune -a --volumes..."
    docker system prune -a -f --volumes 2>/dev/null || true

    # Clear builder cache
    log_info "Clearing builder cache..."
    docker builder prune -a -f 2>/dev/null || true

    # Clear buildx cache if exists
    if docker buildx ls &>/dev/null; then
        log_info "Clearing buildx cache..."
        docker buildx prune -a -f 2>/dev/null || true
    fi

    # Containerd cleanup (if using containerd runtime)
    if command -v ctr &>/dev/null; then
        log_info "Cleaning containerd snapshots..."
        ctr -n moby content ls -q 2>/dev/null | xargs -r ctr -n moby content rm 2>/dev/null || true
    fi

    local after=$(docker system df --format '{{.Size}}' | head -1)
    log_success "Aggressive cleanup completed"
    echo "  Before: $before"
    echo "  After:  $after"
    echo ""

    log_warning "Note: Next build will be slower (cache cleared)"
    echo ""
}

# Setup automatic cleanup via cron
setup_cron() {
    echo ""
    echo "╔════════════════════════════════════════════════════════════╗"
    echo "║              SETUP AUTOMATIC CLEANUP                       ║"
    echo "╚════════════════════════════════════════════════════════════╝"
    echo ""

    # Weekly cleanup at 4:00 AM on Sunday
    local cron_line="0 4 * * 0 $PROJECT_DIR/scripts/docker-cleanup.sh --soft >> /var/log/docker-cleanup.log 2>&1"

    if crontab -l 2>/dev/null | grep -q "docker-cleanup.sh"; then
        log_warning "Cron job already exists"
        return 0
    fi

    log_info "Adding weekly cleanup cron job (Sunday 4:00 AM)..."
    (crontab -l 2>/dev/null || true; echo "$cron_line") | crontab -

    log_success "Cron job installed"
    echo ""
    echo "To view: crontab -l"
    echo "To edit: crontab -e"
    echo ""
}

# Configure Docker daemon for better disk management
show_daemon_config() {
    echo ""
    echo "╔════════════════════════════════════════════════════════════╗"
    echo "║              RECOMMENDED DAEMON CONFIG                     ║"
    echo "╚════════════════════════════════════════════════════════════╝"
    echo ""
    echo "Add to /etc/docker/daemon.json:"
    echo ""
    cat << 'EOF'
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  },
  "storage-driver": "overlay2",
  "builder": {
    "gc": {
      "enabled": true,
      "defaultKeepStorage": "5GB"
    }
  }
}
EOF
    echo ""
    echo "Then restart Docker: sudo systemctl restart docker"
    echo ""
}

# Show help
show_help() {
    echo ""
    echo "╔════════════════════════════════════════════════════════════╗"
    echo "║              DOCKER CLEANUP UTILITY                        ║"
    echo "╚════════════════════════════════════════════════════════════╝"
    echo ""
    echo "Usage: $0 [COMMAND]"
    echo ""
    echo "Commands:"
    echo "  --status       Show Docker disk usage"
    echo "  --soft         Safe cleanup (dangling only)"
    echo "  --full         Full cleanup (all unused images)"
    echo "  --aggressive   Maximum cleanup (including build cache)"
    echo "  --setup-cron   Setup automatic weekly cleanup"
    echo "  --daemon-config Show recommended daemon.json"
    echo "  --help         Show this help"
    echo ""
    echo "Recommended:"
    echo "  - Run --soft weekly (via cron)"
    echo "  - Run --full monthly"
    echo "  - Run --aggressive only when disk is critically low"
    echo ""
    echo "Examples:"
    echo "  $0 --status           # Check disk usage"
    echo "  $0 --soft             # Safe weekly cleanup"
    echo "  $0 --full             # Monthly deep clean"
    echo "  sudo $0 --setup-cron  # Enable auto-cleanup"
    echo ""
}

# Main
case "$1" in
    --status)
        show_status
        ;;
    --soft)
        soft_cleanup
        ;;
    --full)
        full_cleanup
        ;;
    --aggressive)
        aggressive_cleanup
        ;;
    --setup-cron)
        setup_cron
        ;;
    --daemon-config)
        show_daemon_config
        ;;
    --help|-h|"")
        show_help
        ;;
    *)
        log_error "Unknown command: $1"
        show_help
        exit 1
        ;;
esac
