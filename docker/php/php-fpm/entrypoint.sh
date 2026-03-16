#!/bin/bash
# ============================================================================
# ENTRYPOINT FOR PHP-FPM CONTAINER (SPLIT ARCHITECTURE)
# Sources base entrypoint, then adds FPM-specific initialization
# ============================================================================

set -e

# Identify this container role
export CONTAINER_ROLE="php-fpm"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# ============================================================================
# SOURCE BASE ENTRYPOINT (directories, permissions, PHP config)
# ============================================================================
source /usr/local/bin/entrypoint-base

# ============================================================================
# FPM-SPECIFIC: PHP-FPM CONFIG CHECK
# ============================================================================
echo -e "${YELLOW}[FPM 1/6] Configuring PHP-FPM...${NC}"

if [ ! -f "/usr/local/etc/php-fpm.d/www.conf" ]; then
    echo -e "${RED}  PHP-FPM configuration not found!${NC}"
    exit 1
fi

# Dynamic PHP-FPM pool settings based on environment
if [ "${ENVIRONMENT}" = "prod" ] || [ "${ENVIRONMENT}" = "production" ]; then
    export PHP_FPM_PM="ondemand"
    export PHP_FPM_MAX_CHILDREN="${PHP_FPM_MAX_CHILDREN:-50}"
else
    export PHP_FPM_PM="dynamic"
    export PHP_FPM_MAX_CHILDREN="${PHP_FPM_MAX_CHILDREN:-20}"
fi

# Create FPM-specific log directories
mkdir -p /var/log/php-fpm
chown -R "${UGN}:${UGN}" /var/log/php-fpm 2>/dev/null || true

echo -e "${GREEN}  PHP-FPM configured (pm=${PHP_FPM_PM})${NC}"

# ============================================================================
# FPM-SPECIFIC: MSMTP CONFIGURATION (mail sending)
# ============================================================================
echo -e "${YELLOW}[FPM 2/6] Configuring msmtp...${NC}"

# Remove stale /etc/msmtprc if it's a directory (Docker creates dir when bind source missing)
if [ -d "/etc/msmtprc" ]; then
    rm -rf /etc/msmtprc
    echo -e "${YELLOW}  Removed stale /etc/msmtprc directory${NC}"
fi

# Generate fallback /etc/msmtprc based on environment
if [ "${ENVIRONMENT}" = "local" ] || [ "${ENVIRONMENT}" = "dev" ]; then
    cat > /etc/msmtprc <<MSMTP_EOF
# Auto-generated fallback msmtp config (${ENVIRONMENT})
defaults
logfile -
syslog on

account mailhog
host mailhog
port 1025
from noreply@${DOMAIN}
auth off
tls off

account default : mailhog
MSMTP_EOF
    echo -e "${GREEN}  Generated fallback msmtp config (mailhog)${NC}"
else
    cat > /etc/msmtprc <<MSMTP_EOF
# Auto-generated fallback msmtp config (${ENVIRONMENT})
# NOTE: For production, configure per-site SMTP in /etc/bitrix-sites/{domain}/msmtp.conf
defaults
logfile /var/log/msmtp/default.log
syslog on

account default
host localhost
port 25
from noreply@${DOMAIN}
auth off
tls off
MSMTP_EOF
    echo -e "${YELLOW}  Generated minimal fallback msmtp config (configure per-site SMTP!)${NC}"
fi

# Set ownership for msmtp (requires file owned by calling user)
chown "${UGN}:${UGN}" /etc/msmtprc
chmod 600 /etc/msmtprc

# Copy per-site msmtp configs to writable location with correct permissions
SITES_CONFIG="/etc/bitrix-sites"
MSMTP_RUNTIME_DIR="/var/lib/msmtp/sites"
MSMTP_SITE_COUNT=0

mkdir -p "$MSMTP_RUNTIME_DIR"

if [ -d "$SITES_CONFIG" ]; then
    for site_msmtp in "$SITES_CONFIG"/*/msmtp.conf; do
        if [ -f "$site_msmtp" ]; then
            site_name=$(basename "$(dirname "$site_msmtp")")
            dest_dir="$MSMTP_RUNTIME_DIR/$site_name"
            mkdir -p "$dest_dir"
            cp "$site_msmtp" "$dest_dir/msmtp.conf"
            chown "${UGN}:${UGN}" "$dest_dir/msmtp.conf"
            chmod 600 "$dest_dir/msmtp.conf"
            MSMTP_SITE_COUNT=$((MSMTP_SITE_COUNT + 1))
            echo -e "${BLUE}  + Per-site SMTP: $site_name${NC}"
        fi
    done
fi

if [ $MSMTP_SITE_COUNT -gt 0 ]; then
    echo -e "${GREEN}  Prepared ${MSMTP_SITE_COUNT} per-site msmtp configs${NC}"
fi

# Ensure msmtp log directory is writable
mkdir -p /var/log/msmtp
chown -R "${UGN}:${UGN}" /var/log/msmtp 2>/dev/null || true

# ============================================================================
# FPM-SPECIFIC: DATABASE WAIT
# ============================================================================
echo -e "${YELLOW}[FPM 3/6] Checking database connection...${NC}"

DB_HOST="${DB_HOST:-mysql}"
DB_PORT="${DB_PORT:-3306}"
MAX_TRIES=30
COUNT=0

while [ $COUNT -lt $MAX_TRIES ]; do
    if nc -z "${DB_HOST}" "${DB_PORT}" 2>/dev/null; then
        echo -e "${GREEN}  Database is available at ${DB_HOST}:${DB_PORT}${NC}"
        break
    fi

    COUNT=$((COUNT + 1))
    if [ $COUNT -eq $MAX_TRIES ]; then
        echo -e "${RED}  Database is not available after ${MAX_TRIES} attempts${NC}"
        echo -e "${YELLOW}  Continuing anyway...${NC}"
    else
        echo -e "${YELLOW}  Waiting for database... (${COUNT}/${MAX_TRIES})${NC}"
        sleep 2
    fi
done

# ============================================================================
# FPM-SPECIFIC: REDIS WAIT
# ============================================================================
echo -e "${YELLOW}[FPM 4/6] Checking Redis connection...${NC}"

REDIS_HOST="${REDIS_HOST:-redis}"
REDIS_PORT="${REDIS_PORT:-6379}"
MAX_TRIES=15
COUNT=0

while [ $COUNT -lt $MAX_TRIES ]; do
    if nc -z "${REDIS_HOST}" "${REDIS_PORT}" 2>/dev/null; then
        echo -e "${GREEN}  Redis is available at ${REDIS_HOST}:${REDIS_PORT}${NC}"
        break
    fi

    COUNT=$((COUNT + 1))
    if [ $COUNT -eq $MAX_TRIES ]; then
        echo -e "${YELLOW}  Redis is not available after ${MAX_TRIES} attempts${NC}"
        echo -e "${YELLOW}  Continuing anyway...${NC}"
        break
    else
        echo -e "${YELLOW}  Waiting for Redis... (${COUNT}/${MAX_TRIES})${NC}"
        sleep 1
    fi
done

# ============================================================================
# FPM-SPECIFIC: /etc/hosts FOR NGINX
# ============================================================================
echo -e "${YELLOW}[FPM 5/6] Configuring /etc/hosts for nginx access...${NC}"

# Small delay for Docker DNS initialization
sleep 2

MAX_TRIES=30
COUNT=0
NGINX_IP=""

while [ $COUNT -lt $MAX_TRIES ]; do
    NGINX_IP=$(getent hosts nginx 2>/dev/null | awk '{ print $1 }')

    if [ -n "$NGINX_IP" ]; then
        echo -e "${GREEN}  Nginx container found at ${NGINX_IP}${NC}"
        break
    fi

    COUNT=$((COUNT + 1))
    if [ $COUNT -eq $MAX_TRIES ]; then
        echo -e "${YELLOW}  Nginx container not found after ${MAX_TRIES} attempts${NC}"
        echo -e "${YELLOW}  Skipping /etc/hosts update${NC}"
        break
    else
        if [ $((COUNT % 5)) -eq 0 ]; then
            echo -e "${YELLOW}  Waiting for nginx... (${COUNT}/${MAX_TRIES})${NC}"
        fi
        sleep 1
    fi
done

# Update /etc/hosts if nginx found
if [ -n "$NGINX_IP" ]; then
    grep -v 'bitrix\.local' /etc/hosts | grep -v "${DOMAIN}" | grep -v 'mailhog' > /tmp/hosts.tmp || true
    cat /tmp/hosts.tmp > /etc/hosts

    echo "$NGINX_IP bitrix.local" >> /etc/hosts
    echo "$NGINX_IP ${DOMAIN}" >> /etc/hosts

    MAILHOG_IP=$(getent hosts mailhog 2>/dev/null | awk '{ print $1 }')
    if [ -n "$MAILHOG_IP" ]; then
        echo "$MAILHOG_IP mailhog" >> /etc/hosts
        echo -e "${GREEN}  Added mailhog IP ($MAILHOG_IP) to /etc/hosts${NC}"
    fi

    rm -f /tmp/hosts.tmp
    echo -e "${GREEN}  Added nginx IP ($NGINX_IP) to /etc/hosts as bitrix.local and ${DOMAIN}${NC}"
fi

# ============================================================================
# FPM-SPECIFIC: SSL CERTIFICATE TRUST
# ============================================================================
echo -e "${YELLOW}[FPM 6/6] Adding internal SSL certificate to trusted CA...${NC}"

if [ "$SSL" = "0" ] || [ -z "$SSL" ]; then
    echo -e "${YELLOW}  SSL disabled (SSL=$SSL), skipping certificate trust setup${NC}"
elif [ -n "$NGINX_IP" ]; then
    MAX_TRIES=30
    COUNT=0
    CERT_ADDED=false

    while [ $COUNT -lt $MAX_TRIES ]; do
        NGINX_CERT=$(echo | timeout 5 openssl s_client -connect "${NGINX_IP}:443" -servername "${DOMAIN}" 2>/dev/null | openssl x509 2>/dev/null)

        if [ -n "$NGINX_CERT" ]; then
            echo "$NGINX_CERT" >> /etc/ssl/cert.pem
            echo -e "${GREEN}  Internal nginx SSL certificate added to PHP CA bundle${NC}"
            CERT_ADDED=true
            break
        fi

        COUNT=$((COUNT + 1))
        if [ $COUNT -eq $MAX_TRIES ]; then
            echo -e "${YELLOW}  Could not get nginx SSL certificate after ${MAX_TRIES} attempts${NC}"
        else
            if [ $((COUNT % 10)) -eq 0 ]; then
                echo -e "${YELLOW}  Waiting for nginx SSL... (${COUNT}/${MAX_TRIES})${NC}"
            fi
            sleep 1
        fi
    done
else
    echo -e "${YELLOW}  Nginx IP not found, skipping SSL certificate trust${NC}"
fi

# ============================================================================
# START
# ============================================================================
echo ""
echo -e "${BLUE}============================================================================${NC}"
echo -e "${GREEN}PHP-FPM initialization complete!${NC}"
echo -e "${BLUE}============================================================================${NC}"
echo -e "${YELLOW}Starting: $@${NC}"
echo ""

exec "$@"
