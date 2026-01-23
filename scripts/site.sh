#!/bin/bash
# ============================================================================
# BITRIX DOCKER - SITE MANAGER v2.0
# Multi-site management with auto SSL
# Usage: ./site.sh <command> [options]
# ============================================================================

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Script directory and project root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Load environment
if [ -f "$PROJECT_ROOT/.env" ]; then
    while IFS='=' read -r key value; do
        [[ "$key" =~ ^[[:space:]]*# ]] && continue
        [[ -z "$key" ]] && continue
        key=$(echo "$key" | xargs 2>/dev/null) || continue
        [[ -z "$value" ]] && continue
        [[ "$key" == "DOLLAR" ]] && continue
        [[ "$key" == "UID" || "$key" == "EUID" || "$key" == "GID" || "$key" == "PPID" ]] && continue
        export "$key=$value" 2>/dev/null || true
    done < "$PROJECT_ROOT/.env"
fi

# Configuration
ENVIRONMENT="${ENVIRONMENT:-local}"
UGN="${UGN:-bitrix}"
DEFAULT_PHP="${PHP_VERSION:-8.4}"
SSL_MODE="${SSL:-0}"

# Directories (relative to project root)
WWW_DIR="$PROJECT_ROOT/www"
SITES_DIR="$PROJECT_ROOT/config/nginx/sites"
SSL_DIR="$PROJECT_ROOT/config/nginx/ssl"
TEMPLATES_DIR="$PROJECT_ROOT/docker/common/nginx/templates"
SITES_CONFIG_DIR="$PROJECT_ROOT/config/sites"
SITES_TEMPLATES_DIR="$SITES_CONFIG_DIR/_template"

# Ensure directories exist
mkdir -p "$WWW_DIR" "$SITES_DIR" "$SSL_DIR" "$SITES_CONFIG_DIR"

# Logging
log() {
    local level="$1"
    local message="$2"
    case "$level" in
        "INFO")  echo -e "${BLUE}ℹ${NC} $message" ;;
        "OK")    echo -e "${GREEN}✓${NC} $message" ;;
        "WARN")  echo -e "${YELLOW}⚠${NC} $message" ;;
        "ERROR") echo -e "${RED}✗${NC} $message" ;;
    esac
}

# ============================================================================
# PER-SITE CONFIGURATION FUNCTIONS
# ============================================================================

# Convert domain to database-safe name (e.g., shop.local -> shop_local)
domain_to_db_name() {
    local domain="$1"
    echo "$domain" | sed 's/[^a-zA-Z0-9]/_/g' | tr '[:upper:]' '[:lower:]'
}

# Generate secure random password
generate_password() {
    local length="${1:-24}"
    # Use /dev/urandom for cryptographically secure randomness
    # Remove characters that might cause issues in shell/SQL
    head -c 100 /dev/urandom | LC_ALL=C tr -dc 'a-zA-Z0-9' | head -c "$length"
}

# Create per-site configuration files
create_site_configs() {
    local domain="$1"
    local php_version="$2"
    local with_ssl="$3"
    local site_config_dir="$SITES_CONFIG_DIR/$domain"

    # Skip if config already exists
    if [ -f "$site_config_dir/site.env" ]; then
        log "INFO" "Site config already exists: $site_config_dir/site.env"
        return 0
    fi

    log "INFO" "Creating per-site configuration for $domain..."

    mkdir -p "$site_config_dir"

    # Generate unique credentials
    local db_name
    db_name=$(domain_to_db_name "$domain")
    local db_user="${db_name}_user"
    local db_password
    db_password=$(generate_password 24)
    local generated_date
    generated_date=$(date '+%Y-%m-%d %H:%M:%S')

    # SMTP settings from main .env or defaults
    local smtp_host="${SMTP_HOST:-mailhog}"
    local smtp_port="${SMTP_PORT:-1025}"
    local smtp_from="noreply@${domain}"
    local smtp_from_name="${domain}"
    local smtp_auth="${SMTP_AUTH:-off}"
    local smtp_user="${SMTP_USER:-}"
    local smtp_password="${SMTP_PASSWORD:-}"
    local smtp_tls="${SMTP_TLS:-off}"
    local smtp_starttls="${SMTP_STARTTLS:-off}"

    # Create site.env from template
    cat > "$site_config_dir/site.env" << EOF
# ============================================================================
# SITE CONFIGURATION: ${domain}
# Generated: ${generated_date}
# ============================================================================

# Database Configuration
# These credentials are unique to this site
DB_NAME=${db_name}
DB_USER=${db_user}
DB_PASSWORD=${db_password}

# SMTP Configuration (per-site FROM address)
SMTP_FROM=${smtp_from}
SMTP_FROM_NAME=${smtp_from_name}

# Site-specific settings
SITE_DOMAIN=${domain}
SITE_PHP_VERSION=${php_version}
SITE_SSL_ENABLED=${with_ssl}

# Optional: Site-specific Redis prefix (to avoid key collisions)
REDIS_PREFIX=${db_name}_

# Optional: Site-specific session settings
# SESSION_NAME=PHPSESSID_${db_name}
EOF

    chmod 600 "$site_config_dir/site.env"
    log "OK" "Created: $site_config_dir/site.env"

    # Create database-init.sql
    cat > "$site_config_dir/database-init.sql" << EOF
-- ============================================================================
-- DATABASE INITIALIZATION: ${domain}
-- Generated: ${generated_date}
-- ============================================================================

-- Create database if not exists
CREATE DATABASE IF NOT EXISTS \`${db_name}\`
    CHARACTER SET utf8mb4
    COLLATE utf8mb4_unicode_ci;

-- Create user if not exists and set password
CREATE USER IF NOT EXISTS '${db_user}'@'%'
    IDENTIFIED BY '${db_password}';

-- Grant privileges on the site database only
GRANT ALL PRIVILEGES ON \`${db_name}\`.* TO '${db_user}'@'%';

-- Apply changes
FLUSH PRIVILEGES;

-- Verification (will be shown in output)
SELECT
    'Database created' AS status,
    '${db_name}' AS database_name,
    '${db_user}' AS user_name;
EOF

    log "OK" "Created: $site_config_dir/database-init.sql"

    # Create msmtp.conf
    local smtp_user_line=""
    local smtp_password_line=""
    local smtp_tls_line="tls off"
    local smtp_starttls_line="tls_starttls off"

    if [ -n "$smtp_user" ]; then
        smtp_user_line="user $smtp_user"
    fi
    if [ -n "$smtp_password" ]; then
        smtp_password_line="password $smtp_password"
    fi
    if [ "$smtp_tls" = "on" ]; then
        smtp_tls_line="tls on"
        smtp_starttls_line="tls_starttls on"
    fi

    cat > "$site_config_dir/msmtp.conf" << EOF
# ============================================================================
# MSMTP CONFIGURATION: ${domain}
# Generated: ${generated_date}
# ============================================================================
# This file is used by sendmail-wrapper.sh for per-site email routing

# Account for this site
account ${db_name}
host ${smtp_host}
port ${smtp_port}
from ${smtp_from}
auth ${smtp_auth}
${smtp_user_line}
${smtp_password_line}
${smtp_tls_line}
${smtp_starttls_line}
logfile /var/log/msmtp/${domain}.log

# Set as default for this config
account default : ${db_name}
EOF

    chmod 600 "$site_config_dir/msmtp.conf"
    log "OK" "Created: $site_config_dir/msmtp.conf"

    # Create per-site crontab (empty template with examples)
    cat > "$site_config_dir/crontab" << EOF
# ============================================================================
# PER-SITE CRONTAB: ${domain}
# Generated: ${generated_date}
# ============================================================================
# These tasks run IN ADDITION to the base crontab (config/cron/crontab)
# Base already handles: Bitrix agents, mail queue, log rotation
#
# Available paths:
#   Document root: /home/bitrix/app/${domain}/www
#   PHP binary:    /usr/local/bin/php
#
# Examples:
#   # Import products every 2 hours
#   0 */2 * * * /usr/local/bin/php /home/bitrix/app/${domain}/www/local/cron/import.php 2>&1 | logger -t ${db_name}-import
#
#   # Sync prices daily at 6:00
#   0 6 * * * /usr/local/bin/php /home/bitrix/app/${domain}/www/local/cron/sync-prices.php 2>&1 | logger -t ${db_name}-sync
#
#   # Custom cleanup weekly (Sunday at 4:00)
#   0 4 * * 0 /usr/local/bin/php /home/bitrix/app/${domain}/www/local/cron/cleanup.php 2>&1 | logger -t ${db_name}-cleanup
# ============================================================================

EOF

    log "OK" "Created: $site_config_dir/crontab"

    # Create per-site supervisor directory with example
    mkdir -p "$site_config_dir/supervisor"
    cat > "$site_config_dir/supervisor/.gitkeep" << 'EOF'
EOF
    cat > "$site_config_dir/supervisor/README" << EOF
# ============================================================================
# PER-SITE SUPERVISOR PROGRAMS: ${domain}
# ============================================================================
# Place .conf files here for long-running processes specific to this site.
# They are loaded automatically at container startup.
#
# Example worker (${domain}-worker.conf):
#
#   [program:${db_name}-worker]
#   command=/usr/local/bin/php /home/bitrix/app/${domain}/www/local/worker/queue.php
#   user=bitrix
#   numprocs=1
#   autostart=true
#   autorestart=true
#   startsecs=5
#   stopwaitsecs=30
#   stdout_logfile=/var/log/supervisor/${db_name}-worker.log
#   stderr_logfile=/var/log/supervisor/${db_name}-worker.err.log
#
# Example RabbitMQ consumer:
#
#   [program:${db_name}-consumer]
#   command=/usr/local/bin/php /home/bitrix/app/${domain}/www/local/consumer/run.php
#   user=bitrix
#   numprocs=2
#   process_name=%(program_name)s_%(process_num)02d
#   autostart=true
#   autorestart=true
#   startsecs=10
#   stopwaitsecs=60
#   stdout_logfile=/var/log/supervisor/${db_name}-consumer-%(process_num)02d.log
#   stderr_logfile=/var/log/supervisor/${db_name}-consumer-%(process_num)02d.err.log
# ============================================================================
EOF

    log "OK" "Created: $site_config_dir/supervisor/"

    log "OK" "Per-site configuration created for $domain"
}

# Apply database configuration (create DB and user in MySQL)
apply_database_config() {
    local domain="$1"
    local site_config_dir="$SITES_CONFIG_DIR/$domain"
    local sql_file="$site_config_dir/database-init.sql"

    if [ ! -f "$sql_file" ]; then
        log "ERROR" "Database init file not found: $sql_file"
        return 1
    fi

    local mysql_container="${DOMAIN:-bitrix}_mysql"

    # Check if MySQL container is running
    if ! docker ps --format '{{.Names}}' | grep -q "^${mysql_container}$"; then
        log "WARN" "MySQL container not running: $mysql_container"
        log "INFO" "Database will be created when you run: make db-init SITE=$domain"
        return 0
    fi

    log "INFO" "Creating database and user for $domain..."

    # Execute SQL using MYSQL_ROOT_PASSWORD from container environment
    # This ensures we always use the password that matches the actual DB state
    if docker exec -i "$mysql_container" bash -c 'mysql -uroot -p"$MYSQL_ROOT_PASSWORD"' \
        < "$sql_file" 2>/dev/null; then
        log "OK" "Database and user created for $domain"
    else
        log "WARN" "Failed to create database (MySQL may not be ready yet)"
        log "INFO" "Run manually: make db-init SITE=$domain"
    fi
}

# Show help
show_help() {
    cat << 'EOF'
╔════════════════════════════════════════════════════════════╗
║          BITRIX DOCKER - SITE MANAGER v2.0                 ║
╚════════════════════════════════════════════════════════════╝

USAGE:
    ./site.sh <command> [options]

COMMANDS:
    add <domain>        Add new site with auto SSL
    remove <domain>     Remove site completely
    list                List all sites with status
    enable <domain>     Enable site (create nginx config)
    disable <domain>    Disable site (remove nginx config)
    ssl <domain>        Generate/renew SSL certificate
    ssl-le <domain>     Get Let's Encrypt certificate
    reload              Reload nginx configuration

EXAMPLES:
    ./site.sh add shop.local                    # Add site with default PHP
    ./site.sh add api.local --php=8.4           # Add site with PHP 8.4
    ./site.sh add prod.com --ssl                # Add site with SSL
    ./site.sh add prod.com --ssl=letsencrypt    # Add with Let's Encrypt
    ./site.sh remove old.local                  # Remove site
    ./site.sh list                              # Show all sites
    ./site.sh ssl shop.local                    # Generate self-signed SSL
    ./site.sh ssl-le prod.com                   # Get Let's Encrypt cert
    ./site.sh reload                            # Reload nginx

OPTIONS:
    --php=VERSION       PHP version (7.4, 8.3, 8.4)
    --ssl               Generate self-signed SSL
    --ssl=letsencrypt   Use Let's Encrypt
    --no-confirm        Skip confirmation prompts
    --help              Show this help

DIRECTORY STRUCTURE:
    www/
    └── example.com/
        └── www/            <- Document root
            ├── index.php
            └── bitrix/

EOF
}

# Generate nginx config for a site
generate_nginx_config() {
    local domain="$1"
    local php_version="$2"
    local with_ssl="$3"
    local ssl_type="${4:-self}"  # "self" or "letsencrypt"
    local config_file="$SITES_DIR/${domain}.conf"

    log "INFO" "Generating nginx config for $domain..."

    # PHP-FPM upstream name (bitrix is our main container)
    local php_upstream="bitrix:9000"

    # SSL certificate paths
    local ssl_cert ssl_key
    if [ "$ssl_type" = "letsencrypt" ]; then
        ssl_cert="/etc/letsencrypt/live/$domain/fullchain.pem"
        ssl_key="/etc/letsencrypt/live/$domain/privkey.pem"
    else
        ssl_cert="/etc/nginx/ssl/$domain/$domain.crt"
        ssl_key="/etc/nginx/ssl/$domain/$domain.key"
    fi

    if [ "$with_ssl" = "true" ]; then
        # SSL mode: HTTPS server + HTTP redirect
        cat > "$config_file" << NGINX_SSL
# ============================================================================
# Site: $domain (SSL)
# Generated: $(date '+%Y-%m-%d %H:%M:%S')
# PHP: $php_version
# ============================================================================

# HTTPS Server
server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name $domain www.$domain;

    root /home/$UGN/app/$domain/www;
    index index.php index.html index.htm;

    # SSL Certificates
    ssl_certificate $ssl_cert;
    ssl_certificate_key $ssl_key;

    # SSL Settings
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384;
    ssl_prefer_server_ciphers off;
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 1d;
    ssl_session_tickets off;

    # HSTS
    add_header Strict-Transport-Security "max-age=63072000" always;

    # Logging
    access_log /var/log/nginx/${domain}.access.log main_json;
    error_log /var/log/nginx/${domain}.error.log warn;

    # Security headers
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;

    # Gzip
    gzip on;
    gzip_types text/plain text/css application/json application/javascript text/xml application/xml;

    # Main location
    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }

    # PHP processing
    location ~ \.php\$ {
        fastcgi_pass $php_upstream;
        fastcgi_index index.php;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        include fastcgi_params;
        fastcgi_read_timeout 600;
        fastcgi_send_timeout 600;
        fastcgi_buffer_size 64k;
        fastcgi_buffers 4 64k;
    }

    # Bitrix specific
    location ~* ^/bitrix/(modules|local_cache|stack_cache|managed_cache|cache)/ {
        deny all;
    }

    location ~* ^/upload/1c_exchange/ {
        deny all;
    }

    # Static files caching
    location ~* \.(jpg|jpeg|gif|png|svg|ico|css|js|woff|woff2|ttf|eot)\$ {
        expires 30d;
        add_header Cache-Control "public, immutable";
        access_log off;
    }

    # Deny hidden files
    location ~ /\. {
        deny all;
        access_log off;
        log_not_found off;
    }

    # Health check
    location = /health {
        access_log off;
        return 200 "OK";
        add_header Content-Type text/plain;
    }
}

# Redirect HTTP to HTTPS
server {
    listen 80;
    listen [::]:80;
    server_name $domain www.$domain;
    return 301 https://\$server_name\$request_uri;
}
NGINX_SSL
    else
        # HTTP-only mode
        cat > "$config_file" << NGINX
# ============================================================================
# Site: $domain
# Generated: $(date '+%Y-%m-%d %H:%M:%S')
# PHP: $php_version
# ============================================================================

server {
    listen 80;
    listen [::]:80;
    server_name $domain www.$domain;

    root /home/$UGN/app/$domain/www;
    index index.php index.html index.htm;

    # Logging
    access_log /var/log/nginx/${domain}.access.log main_json;
    error_log /var/log/nginx/${domain}.error.log warn;

    # Security headers
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;

    # Gzip
    gzip on;
    gzip_types text/plain text/css application/json application/javascript text/xml application/xml;

    # Main location
    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }

    # PHP processing
    location ~ \.php\$ {
        fastcgi_pass $php_upstream;
        fastcgi_index index.php;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        include fastcgi_params;

        # Timeouts
        fastcgi_read_timeout 600;
        fastcgi_send_timeout 600;

        # Buffers
        fastcgi_buffer_size 64k;
        fastcgi_buffers 4 64k;
    }

    # Bitrix specific
    location ~* ^/bitrix/(modules|local_cache|stack_cache|managed_cache|cache)/ {
        deny all;
    }

    location ~* ^/upload/1c_exchange/ {
        deny all;
    }

    # Static files caching
    location ~* \.(jpg|jpeg|gif|png|svg|ico|css|js|woff|woff2|ttf|eot)\$ {
        expires 30d;
        add_header Cache-Control "public, immutable";
        access_log off;
    }

    # Deny hidden files
    location ~ /\. {
        deny all;
        access_log off;
        log_not_found off;
    }

    # Health check
    location = /health {
        access_log off;
        return 200 "OK";
        add_header Content-Type text/plain;
    }
}
NGINX
    fi

    log "OK" "Nginx config created: $config_file"
}

# Generate self-signed SSL certificate
generate_ssl_cert() {
    local domain="$1"
    local ssl_domain_dir="$SSL_DIR/$domain"

    mkdir -p "$ssl_domain_dir"

    log "INFO" "Generating self-signed SSL certificate for $domain..."

    # Generate private key
    openssl genrsa -out "$ssl_domain_dir/$domain.key" 2048 2>/dev/null

    # Generate certificate
    openssl req -new -x509 \
        -key "$ssl_domain_dir/$domain.key" \
        -out "$ssl_domain_dir/$domain.crt" \
        -days 365 \
        -subj "/C=RU/ST=Moscow/L=Moscow/O=BitrixDocker/CN=$domain" \
        -addext "subjectAltName=DNS:$domain,DNS:www.$domain" \
        2>/dev/null

    chmod 600 "$ssl_domain_dir/$domain.key"
    chmod 644 "$ssl_domain_dir/$domain.crt"

    log "OK" "SSL certificate created:"
    log "INFO" "  Certificate: $ssl_domain_dir/$domain.crt"
    log "INFO" "  Private key: $ssl_domain_dir/$domain.key"
}

# Get Let's Encrypt certificate
get_letsencrypt_cert() {
    local domain="$1"
    local email="${EMAIL:-admin@$domain}"

    log "INFO" "Requesting Let's Encrypt certificate for $domain..."

    local container="${DOMAIN:-bitrix}_nginx"

    # Skip if container is not running
    if ! docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^${container}$"; then
        log "WARN" "Nginx container not running, skip Let's Encrypt (run: make ssl-le SITE=$domain)"
        return 0
    fi

    # Check if certbot is available in nginx container
    if ! docker exec "$container" which certbot >/dev/null 2>&1; then
        log "ERROR" "Certbot not available. Set SSL=free in .env and rebuild nginx."
        return 1
    fi

    # Request certificate
    docker exec "$container" certbot certonly \
        --nginx \
        --non-interactive \
        --agree-tos \
        --email "$email" \
        -d "$domain" \
        -d "www.$domain" || {
        log "ERROR" "Failed to get Let's Encrypt certificate"
        return 1
    }

    log "OK" "Let's Encrypt certificate obtained for $domain"
}

# Create site directory structure
create_site_structure() {
    local domain="$1"
    local site_dir="$WWW_DIR/$domain/www"

    mkdir -p "$site_dir"

    # Create default index.php
    cat > "$site_dir/index.php" << 'PHPFILE'
<?php
$domain = $_SERVER['HTTP_HOST'] ?? 'unknown';
$php_version = PHP_VERSION;
$date = date('Y-m-d H:i:s');
?>
<!DOCTYPE html>
<html>
<head>
    <title><?= htmlspecialchars($domain) ?> - Bitrix Docker</title>
    <style>
        body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
               max-width: 800px; margin: 50px auto; padding: 20px; }
        .success { color: #27ae60; }
        .info { background: #f8f9fa; padding: 20px; border-radius: 8px; margin: 20px 0; }
        code { background: #e9ecef; padding: 2px 6px; border-radius: 4px; }
    </style>
</head>
<body>
    <h1 class="success">✓ Site is working!</h1>
    <div class="info">
        <p><strong>Domain:</strong> <?= htmlspecialchars($domain) ?></p>
        <p><strong>PHP Version:</strong> <?= $php_version ?></p>
        <p><strong>Server Time:</strong> <?= $date ?></p>
        <p><strong>Document Root:</strong> <?= $_SERVER['DOCUMENT_ROOT'] ?></p>
    </div>
    <h2>Next Steps</h2>
    <ol>
        <li>Upload Bitrix files to <code>www/<?= htmlspecialchars($domain) ?>/www/</code></li>
        <li>Create database for this site</li>
        <li>Run Bitrix installer</li>
    </ol>
</body>
</html>
PHPFILE

    log "OK" "Site structure created: $WWW_DIR/$domain/"
}

# Add new site
add_site() {
    local domain=""
    local php_version="$DEFAULT_PHP"
    local with_ssl="false"
    local ssl_type="self"

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --php=*)
                php_version="${1#*=}"
                ;;
            --ssl)
                with_ssl="true"
                ;;
            --ssl=*)
                with_ssl="true"
                ssl_type="${1#*=}"
                ;;
            --no-confirm)
                NO_CONFIRM="true"
                ;;
            *)
                if [ -z "$domain" ]; then
                    domain="$1"
                fi
                ;;
        esac
        shift
    done

    if [ -z "$domain" ]; then
        log "ERROR" "Domain is required: ./site.sh add example.com"
        exit 1
    fi

    # Validate PHP version
    if [[ ! "$php_version" =~ ^(7\.4|8\.3|8\.4)$ ]]; then
        log "ERROR" "Invalid PHP version. Supported: 7.4, 8.3, 8.4"
        exit 1
    fi

    echo ""
    echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}  Adding Site: $domain${NC}"
    echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"
    echo ""

    # Check if site exists
    if [ -d "$WWW_DIR/$domain" ]; then
        log "WARN" "Site directory already exists: $WWW_DIR/$domain"
        if [ "${NO_CONFIRM:-}" != "true" ]; then
            echo -n "Continue anyway? [y/N]: "
            read -r confirm
            if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
                log "INFO" "Aborted"
                exit 0
            fi
        else
            log "INFO" "Continuing (--no-confirm mode)"
        fi
    fi

    # Create site structure
    create_site_structure "$domain"

    # Create per-site configuration (DB credentials, SMTP, etc.)
    create_site_configs "$domain" "$php_version" "$with_ssl"

    # Try to apply database configuration (create DB and user)
    apply_database_config "$domain"

    # Generate SSL if requested
    if [ "$with_ssl" = "true" ]; then
        if [ "$ssl_type" = "letsencrypt" ]; then
            # Step 1: Generate HTTP config first (needed for ACME challenge)
            generate_nginx_config "$domain" "$php_version" "false"
            reload_nginx || true

            # Step 2: Try to get Let's Encrypt certificate
            if get_letsencrypt_cert "$domain"; then
                # Step 3: Upgrade to HTTPS config with LE cert paths
                generate_nginx_config "$domain" "$php_version" "true" "letsencrypt"
                reload_nginx || true
            else
                log "WARN" "Let's Encrypt skipped — HTTP config active. Run later: make ssl-le SITE=$domain"
            fi
        else
            generate_ssl_cert "$domain"
            generate_nginx_config "$domain" "$php_version" "true"
            reload_nginx || log "WARN" "Nginx reload failed, will apply on next restart"
        fi
    else
        generate_nginx_config "$domain" "$php_version" "false"
        reload_nginx || log "WARN" "Nginx reload failed, will apply on next restart"
    fi

    echo ""
    echo -e "${GREEN}════════════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}  ✓ Site $domain added successfully!${NC}"
    echo -e "${GREEN}════════════════════════════════════════════════════════════${NC}"
    echo ""
    echo -e "  ${CYAN}Document Root:${NC}  $WWW_DIR/$domain/www/"
    echo -e "  ${CYAN}Site Config:${NC}    $SITES_CONFIG_DIR/$domain/"
    echo -e "  ${CYAN}Nginx Config:${NC}   $SITES_DIR/${domain}.conf"
    if [ "$with_ssl" = "true" ]; then
        echo -e "  ${CYAN}SSL Cert:${NC}       $SSL_DIR/$domain/"
        echo -e "  ${CYAN}URL:${NC}            https://$domain"
    else
        echo -e "  ${CYAN}URL:${NC}            http://$domain"
    fi
    echo ""

    # Show database credentials from site.env
    local site_env="$SITES_CONFIG_DIR/$domain/site.env"
    if [ -f "$site_env" ]; then
        local db_name db_user db_password
        db_name=$(grep '^DB_NAME=' "$site_env" | cut -d'=' -f2)
        db_user=$(grep '^DB_USER=' "$site_env" | cut -d'=' -f2)
        db_password=$(grep '^DB_PASSWORD=' "$site_env" | cut -d'=' -f2)

        echo -e "  ${CYAN}Database:${NC}"
        echo -e "    Name:     $db_name"
        echo -e "    User:     $db_user"
        echo -e "    Password: $db_password"
        echo ""
    fi

    echo -e "  ${YELLOW}Don't forget to add to /etc/hosts:${NC}"
    echo -e "  127.0.0.1 $domain www.$domain"
    echo ""
}

# Remove site
remove_site() {
    local domain="$1"
    local no_confirm="${2:-false}"

    if [ -z "$domain" ]; then
        log "ERROR" "Domain is required: ./site.sh remove example.com"
        exit 1
    fi

    if [ ! -d "$WWW_DIR/$domain" ] && [ ! -f "$SITES_DIR/${domain}.conf" ]; then
        log "ERROR" "Site not found: $domain"
        exit 1
    fi

    if [ "$no_confirm" != "--no-confirm" ]; then
        log "WARN" "This will DELETE all files for $domain!"
        echo -n "Are you sure? [y/N]: "
        read -r confirm
        if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
            log "INFO" "Aborted"
            exit 0
        fi
    fi

    log "INFO" "Removing site $domain..."

    # Remove site directory
    [ -d "$WWW_DIR/$domain" ] && rm -rf "$WWW_DIR/$domain"
    log "OK" "Removed: $WWW_DIR/$domain"

    # Remove per-site configuration
    [ -d "$SITES_CONFIG_DIR/$domain" ] && rm -rf "$SITES_CONFIG_DIR/$domain"
    log "OK" "Removed: $SITES_CONFIG_DIR/$domain"

    # Remove nginx config
    [ -f "$SITES_DIR/${domain}.conf" ] && rm -f "$SITES_DIR/${domain}.conf"
    log "OK" "Removed: $SITES_DIR/${domain}.conf"

    # Remove SSL certificates
    [ -d "$SSL_DIR/$domain" ] && rm -rf "$SSL_DIR/$domain"
    log "OK" "Removed: $SSL_DIR/$domain"

    # Reload nginx
    reload_nginx

    log "WARN" "Note: Database and user were NOT removed automatically"
    log "INFO" "To remove database, run: docker exec mysql mysql -e \"DROP DATABASE IF EXISTS $(domain_to_db_name "$domain");\""

    log "OK" "Site $domain removed completely"
}

# List all sites
list_sites() {
    echo ""
    echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}  Configured Sites${NC}"
    echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"
    echo ""

    printf "%-30s %-10s %-10s %-10s\n" "DOMAIN" "FILES" "NGINX" "SSL"
    printf "%-30s %-10s %-10s %-10s\n" "------" "-----" "-----" "---"

    # List from www directory
    if [ -d "$WWW_DIR" ]; then
        for dir in "$WWW_DIR"/*/; do
            if [ -d "$dir" ]; then
                local domain=$(basename "$dir")
                local files_status="${GREEN}✓${NC}"
                local nginx_status="${RED}✗${NC}"
                local ssl_status="${RED}✗${NC}"

                [ -f "$SITES_DIR/${domain}.conf" ] && nginx_status="${GREEN}✓${NC}"
                [ -d "$SSL_DIR/$domain" ] && ssl_status="${GREEN}✓${NC}"

                printf "%-30s %-10b %-10b %-10b\n" "$domain" "$files_status" "$nginx_status" "$ssl_status"
            fi
        done
    fi

    echo ""

    # Show disk usage
    if [ -d "$WWW_DIR" ]; then
        echo -e "${CYAN}Disk Usage:${NC}"
        du -sh "$WWW_DIR"/*/ 2>/dev/null | awk '{print "  " $2 ": " $1}'
    fi
    echo ""
}

# Reload nginx configuration
reload_nginx() {
    local container="${DOMAIN:-bitrix}_nginx"

    # Skip if container is not running
    if ! docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^${container}$"; then
        log "INFO" "Nginx container not running, skip reload (will apply on next start)"
        return 0
    fi

    log "INFO" "Reloading nginx configuration..."

    # Test config first
    if docker exec "$container" nginx -t 2>/dev/null; then
        docker exec "$container" nginx -s reload 2>/dev/null
        log "OK" "Nginx reloaded successfully"
    else
        log "ERROR" "Nginx configuration test failed!"
        log "INFO" "Check config: docker exec $container nginx -t"
        return 1
    fi
}

# Generate SSL for existing site
ssl_site() {
    local domain="$1"

    if [ -z "$domain" ]; then
        log "ERROR" "Domain is required: ./site.sh ssl example.com"
        exit 1
    fi

    if [ ! -d "$WWW_DIR/$domain" ]; then
        log "ERROR" "Site not found: $domain"
        log "INFO" "Add site first: ./site.sh add $domain"
        exit 1
    fi

    generate_ssl_cert "$domain"

    # Regenerate nginx config with SSL
    local php_version="$DEFAULT_PHP"
    generate_nginx_config "$domain" "$php_version" "true"

    reload_nginx

    log "OK" "SSL enabled for $domain"
    echo ""
    echo -e "  ${CYAN}URL:${NC} https://$domain"
    echo ""
}

# Main command handler
case "${1:-}" in
    "add")
        shift
        add_site "$@"
        ;;
    "remove"|"rm"|"delete")
        remove_site "${2:-}" "${3:-}"
        ;;
    "list"|"ls")
        list_sites
        ;;
    "enable")
        log "INFO" "Site enable - regenerating config..."
        generate_nginx_config "${2:-}" "$DEFAULT_PHP" "false"
        reload_nginx
        ;;
    "disable")
        if [ -n "${2:-}" ]; then
            rm -f "$SITES_DIR/${2}.conf"
            reload_nginx
            log "OK" "Site ${2} disabled"
        fi
        ;;
    "ssl")
        ssl_site "${2:-}"
        ;;
    "ssl-le"|"letsencrypt")
        # Generate HTTP config first for ACME challenge
        generate_nginx_config "${2:-}" "$DEFAULT_PHP" "false"
        reload_nginx || true
        # Get certificate
        get_letsencrypt_cert "${2:-}"
        # Upgrade to HTTPS config with LE paths
        generate_nginx_config "${2:-}" "$DEFAULT_PHP" "true" "letsencrypt"
        reload_nginx
        ;;
    "reload")
        reload_nginx
        ;;
    "help"|"--help"|"-h"|"")
        show_help
        ;;
    *)
        log "ERROR" "Unknown command: $1"
        show_help
        exit 1
        ;;
esac
