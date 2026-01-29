#!/bin/bash
# ============================================================================
# INSTALL/UNINSTALL SYSTEMD SERVICE FOR BITRIX DOCKER
# Makes containers auto-start after server reboot
#
# Usage:
#   ./scripts/install-service.sh install    # Install and enable service
#   ./scripts/install-service.sh uninstall  # Remove service
#   ./scripts/install-service.sh status     # Check service status
#   ./scripts/install-service.sh logs       # View service logs
# ============================================================================

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
SERVICE_NAME="bitrix-docker"
SERVICE_FILE="$SCRIPT_DIR/${SERVICE_NAME}.service"
SYSTEMD_DIR="/etc/systemd/system"

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[OK]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Check if running as root
check_root() {
    if [ "$EUID" -ne 0 ]; then
        log_error "This script must be run as root"
        echo "Try: sudo $0 $*"
        exit 1
    fi
}

# Check if systemd is available
check_systemd() {
    if ! command -v systemctl &> /dev/null; then
        log_error "systemd is not available on this system"
        echo ""
        echo "Alternative: Add to /etc/rc.local:"
        echo "  cd $PROJECT_DIR && docker compose -f docker-compose.bitrix.yml --profile prod up -d"
        exit 1
    fi
}

# Install service
# Usage: install_service [--yes]
install_service() {
    local auto_yes=false
    if [ "$1" = "--yes" ] || [ "$1" = "-y" ]; then
        auto_yes=true
    fi

    check_root
    check_systemd

    echo ""
    echo "╔════════════════════════════════════════════════════════════╗"
    echo "║          INSTALLING BITRIX DOCKER SERVICE                  ║"
    echo "╚════════════════════════════════════════════════════════════╝"
    echo ""

    # Check if service file exists
    if [ ! -f "$SERVICE_FILE" ]; then
        log_error "Service file not found: $SERVICE_FILE"
        exit 1
    fi

    # Create customized service file
    log_info "Creating service file..."

    # Read template and replace paths
    local temp_file=$(mktemp)
    sed "s|WorkingDirectory=.*|WorkingDirectory=$PROJECT_DIR|g" "$SERVICE_FILE" > "$temp_file"
    # Use different sed syntax for macOS vs Linux
    if [[ "$OSTYPE" == "darwin"* ]]; then
        sed -i '' "s|EnvironmentFile=.*|EnvironmentFile=-$PROJECT_DIR/.env|g" "$temp_file"
    else
        sed -i "s|EnvironmentFile=.*|EnvironmentFile=-$PROJECT_DIR/.env|g" "$temp_file"
    fi

    # Copy to systemd
    cp "$temp_file" "$SYSTEMD_DIR/${SERVICE_NAME}.service"
    rm -f "$temp_file"

    log_success "Service file installed to $SYSTEMD_DIR/${SERVICE_NAME}.service"

    # Reload systemd
    log_info "Reloading systemd..."
    systemctl daemon-reload

    # Enable service
    log_info "Enabling service..."
    systemctl enable "$SERVICE_NAME"

    log_success "Service enabled for auto-start"

    echo ""
    echo "╔════════════════════════════════════════════════════════════╗"
    echo "║  ✅ SERVICE INSTALLED SUCCESSFULLY                         ║"
    echo "╚════════════════════════════════════════════════════════════╝"
    echo ""
    echo "Commands:"
    echo "  systemctl start $SERVICE_NAME    # Start now"
    echo "  systemctl stop $SERVICE_NAME     # Stop"
    echo "  systemctl status $SERVICE_NAME   # Check status"
    echo "  systemctl disable $SERVICE_NAME  # Disable auto-start"
    echo "  journalctl -u $SERVICE_NAME      # View logs"
    echo ""
    echo "The service will auto-start containers after reboot."
    echo ""

    # Ask to start now (skip if --yes)
    if [ "$auto_yes" = true ]; then
        # In auto mode, don't start - containers are already running
        log_info "Skipping service start (containers already running)"
    else
        read -p "Start service now? [Y/n]: " start_now
        if [ "$start_now" != "n" ] && [ "$start_now" != "N" ]; then
            log_info "Starting service..."
            systemctl start "$SERVICE_NAME"
            sleep 2
            systemctl status "$SERVICE_NAME" --no-pager || true
        fi
    fi
}

# Uninstall service
uninstall_service() {
    check_root
    check_systemd

    echo ""
    echo "╔════════════════════════════════════════════════════════════╗"
    echo "║          UNINSTALLING BITRIX DOCKER SERVICE                ║"
    echo "╚════════════════════════════════════════════════════════════╝"
    echo ""

    if [ ! -f "$SYSTEMD_DIR/${SERVICE_NAME}.service" ]; then
        log_warning "Service not installed"
        return 0
    fi

    # Stop service
    log_info "Stopping service..."
    systemctl stop "$SERVICE_NAME" 2>/dev/null || true

    # Disable service
    log_info "Disabling service..."
    systemctl disable "$SERVICE_NAME" 2>/dev/null || true

    # Remove service file
    log_info "Removing service file..."
    rm -f "$SYSTEMD_DIR/${SERVICE_NAME}.service"

    # Reload systemd
    log_info "Reloading systemd..."
    systemctl daemon-reload
    systemctl reset-failed

    log_success "Service uninstalled"
    echo ""
}

# Show service status
show_status() {
    check_systemd

    echo ""
    echo "╔════════════════════════════════════════════════════════════╗"
    echo "║          BITRIX DOCKER SERVICE STATUS                      ║"
    echo "╚════════════════════════════════════════════════════════════╝"
    echo ""

    if [ ! -f "$SYSTEMD_DIR/${SERVICE_NAME}.service" ]; then
        log_warning "Service not installed"
        echo ""
        echo "Install with: sudo $0 install"
        return 0
    fi

    # Show systemctl status
    systemctl status "$SERVICE_NAME" --no-pager || true
    echo ""

    # Show if enabled
    if systemctl is-enabled "$SERVICE_NAME" &>/dev/null; then
        log_success "Service is ENABLED (will auto-start on boot)"
    else
        log_warning "Service is DISABLED (will NOT auto-start)"
    fi
    echo ""
}

# Show service logs
show_logs() {
    check_systemd

    echo "Showing last 50 lines of service logs..."
    echo "Press Ctrl+C to exit"
    echo ""

    journalctl -u "$SERVICE_NAME" -n 50 -f
}

# Show help
show_help() {
    echo ""
    echo "╔════════════════════════════════════════════════════════════╗"
    echo "║          BITRIX DOCKER SERVICE MANAGER                     ║"
    echo "╚════════════════════════════════════════════════════════════╝"
    echo ""
    echo "Usage: $0 [COMMAND]"
    echo ""
    echo "Commands:"
    echo "  install     Install and enable systemd service"
    echo "  uninstall   Remove systemd service"
    echo "  status      Show service status"
    echo "  logs        View service logs (journalctl)"
    echo "  help        Show this help"
    echo ""
    echo "After installation, containers will auto-start on server reboot."
    echo ""
    echo "Manual commands:"
    echo "  systemctl start bitrix-docker    # Start containers"
    echo "  systemctl stop bitrix-docker     # Stop containers"
    echo "  systemctl restart bitrix-docker  # Restart containers"
    echo ""
}

# Main
case "$1" in
    install)
        install_service "$2"
        ;;
    uninstall|remove)
        uninstall_service
        ;;
    status)
        show_status
        ;;
    logs)
        show_logs
        ;;
    help|--help|-h)
        show_help
        ;;
    *)
        show_help
        exit 1
        ;;
esac
