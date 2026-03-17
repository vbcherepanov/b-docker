#!/bin/bash
# ============================================================================
# HOST SETUP SCRIPT — Production Server Preparation
# Run ONCE on a fresh server BEFORE docker-compose up
#
# Usage (as root):
#   sudo ./scripts/setup-host.sh
#
# What it does:
#   1. Configures Docker daemon (log limits, overlay2, live-restore)
#   2. Sets up Docker cleanup cron (weekly)
#   3. Sets up disk monitoring cron
#   4. Optimizes kernel parameters for production
#   5. Configures firewall basics
# ============================================================================

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_ok() { echo -e "${GREEN}[OK]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# ============================================================================
# Check root
# ============================================================================
if [ "$(id -u)" -ne 0 ]; then
    log_error "This script must be run as root (sudo)"
    exit 1
fi

echo ""
echo "╔════════════════════════════════════════════════════════════╗"
echo "║          PRODUCTION HOST SETUP                             ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""

# ============================================================================
# Step 1: Docker daemon.json
# ============================================================================
log_info "Step 1/5: Configuring Docker daemon..."

DAEMON_JSON="/etc/docker/daemon.json"
if [ -f "$DAEMON_JSON" ]; then
    cp "$DAEMON_JSON" "${DAEMON_JSON}.bak.$(date +%s)"
    log_warn "Existing daemon.json backed up"
fi

cat > "$DAEMON_JSON" << 'EOF'
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  },
  "storage-driver": "overlay2",
  "live-restore": true,
  "default-ulimits": {
    "nofile": {
      "Name": "nofile",
      "Hard": 65536,
      "Soft": 65536
    }
  },
  "builder": {
    "gc": {
      "enabled": true,
      "defaultKeepStorage": "10GB"
    }
  }
}
EOF

systemctl restart docker
log_ok "Docker daemon configured and restarted"

# ============================================================================
# Step 2: Docker cleanup cron
# ============================================================================
log_info "Step 2/5: Setting up Docker cleanup cron..."

CLEANUP_CRON="0 4 * * 0 ${PROJECT_DIR}/scripts/docker-cleanup.sh --soft >> /var/log/docker-cleanup.log 2>&1"

if crontab -l 2>/dev/null | grep -q "docker-cleanup.sh"; then
    log_warn "Docker cleanup cron already exists, skipping"
else
    (crontab -l 2>/dev/null || true; echo "# Docker weekly cleanup (Sunday 4:00 AM)"; echo "$CLEANUP_CRON") | crontab -
    log_ok "Docker cleanup cron installed (Sunday 4:00 AM)"
fi

# ============================================================================
# Step 3: Disk monitoring cron
# ============================================================================
log_info "Step 3/5: Setting up disk monitoring..."

chmod +x "${SCRIPT_DIR}/disk-alert.sh"

DISK_CRON="0 */6 * * * ${PROJECT_DIR}/scripts/disk-alert.sh >> /var/log/disk-alert.log 2>&1"

if crontab -l 2>/dev/null | grep -q "disk-alert.sh"; then
    log_warn "Disk alert cron already exists, skipping"
else
    (crontab -l 2>/dev/null || true; echo "# Disk usage alert (every 6 hours)"; echo "$DISK_CRON") | crontab -
    log_ok "Disk monitoring cron installed (every 6 hours)"
fi

log_warn "Don't forget to configure Telegram credentials in disk-alert.sh!"
echo "  Edit: ${SCRIPT_DIR}/disk-alert.sh"
echo "  Or set env in cron: TELEGRAM_BOT_TOKEN=... TELEGRAM_CHAT_ID=..."

# ============================================================================
# Step 4: Kernel tuning for production
# ============================================================================
log_info "Step 4/5: Optimizing kernel parameters..."

SYSCTL_FILE="/etc/sysctl.d/99-bitrix-docker.conf"

cat > "$SYSCTL_FILE" << 'EOF'
# ============================================================================
# Kernel tuning for Bitrix Docker production
# ============================================================================

# Network performance
net.core.somaxconn = 65535
net.core.netdev_max_backlog = 65535
net.ipv4.tcp_max_syn_backlog = 65535
net.ipv4.tcp_fin_timeout = 15
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_keepalive_time = 600
net.ipv4.tcp_keepalive_intvl = 30
net.ipv4.tcp_keepalive_probes = 5

# Memory
vm.swappiness = 10
vm.overcommit_memory = 1
vm.dirty_ratio = 15
vm.dirty_background_ratio = 5

# File descriptors
fs.file-max = 2097152
fs.inotify.max_user_watches = 524288
fs.inotify.max_user_instances = 512

# Connection tracking (for Docker)
net.netfilter.nf_conntrack_max = 262144
EOF

sysctl --system > /dev/null 2>&1
log_ok "Kernel parameters optimized"

# ============================================================================
# Step 5: Limits for bitrix user
# ============================================================================
log_info "Step 5/5: Setting up user limits..."

LIMITS_FILE="/etc/security/limits.d/99-bitrix.conf"
cat > "$LIMITS_FILE" << 'EOF'
# Limits for bitrix user (Docker containers)
bitrix soft nofile 65536
bitrix hard nofile 65536
bitrix soft nproc 32768
bitrix hard nproc 32768
EOF

log_ok "User limits configured"

# ============================================================================
# Summary
# ============================================================================
echo ""
echo "╔════════════════════════════════════════════════════════════╗"
echo "║  ✅ HOST SETUP COMPLETE                                    ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""
echo "  Configured:"
echo "    ✓ Docker daemon (log limits, overlay2, live-restore)"
echo "    ✓ Docker cleanup cron (Sunday 4:00 AM)"
echo "    ✓ Disk monitoring cron (every 6 hours)"
echo "    ✓ Kernel tuning (network, memory, file descriptors)"
echo "    ✓ User limits (nofile, nproc)"
echo ""
echo "  Current cron jobs:"
crontab -l 2>/dev/null | grep -v "^#" | grep -v "^$" || echo "    (none)"
echo ""
echo "  ⚠️  TODO:"
echo "    1. Configure Telegram in disk-alert.sh"
echo "    2. Copy .env_olymp.txt → .env"
echo "    3. Run: make setup"
echo "    4. Run: make first-run-prod"
echo ""
