#!/bin/bash
# ============================================================================
# BASE ENTRYPOINT — SHARED INITIALIZATION FOR ALL SPLIT PHP SERVICES
# Common logic: directories, permissions, PHP config generation
# Used by: php-fpm, php-cli, cron, supervisor containers
# ============================================================================

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Container role for logging (set by each service entrypoint)
CONTAINER_ROLE="${CONTAINER_ROLE:-unknown}"

echo -e "${BLUE}============================================================================${NC}"
echo -e "${BLUE}BITRIX DOCKER — ${CONTAINER_ROLE} INITIALIZATION${NC}"
echo -e "${BLUE}============================================================================${NC}"

# ============================================================================
# ENVIRONMENT INFO
# ============================================================================
echo -e "${GREEN}Environment: ${ENVIRONMENT}${NC}"
echo -e "${GREEN}Domain: ${DOMAIN}${NC}"
echo -e "${GREEN}PHP Version: $(php -v | head -n 1)${NC}"
echo -e "${GREEN}User: ${UGN} (UID:${UID}, GID:${GID})${NC}"
echo -e "${GREEN}Timezone: ${TZ}${NC}"
echo -e "${GREEN}Container Role: ${CONTAINER_ROLE}${NC}"
echo ""

# ============================================================================
# STEP 1: CREATE SYSTEM DIRECTORIES
# ============================================================================
echo -e "${YELLOW}[1/4] Checking directories...${NC}"

# System directories (NOT in www/)
SYSTEM_DIRS=(
    "/home/${UGN}/tmp"
    "/var/log/php"
    "/var/log/bitrix"
    "/var/lib/php/sessions"
)

for dir in "${SYSTEM_DIRS[@]}"; do
    if [ ! -d "$dir" ]; then
        echo -e "  ${YELLOW}Creating directory: $dir${NC}"
        mkdir -p "$dir"
    fi
done

# Multisite: create directories INSIDE each domain folder
# Structure: /home/bitrix/app/{domain}/www/bitrix/cache, /home/bitrix/app/{domain}/www/upload, etc.
APP_DIR="/home/${UGN}/app"
if [ -d "$APP_DIR" ]; then
    for domain_dir in "$APP_DIR"/*/; do
        if [ -d "$domain_dir" ]; then
            domain=$(basename "$domain_dir")
            site_www="$domain_dir/www"

            # Only process valid domain folders (those with www/ subdirectory)
            if [ -d "$site_www" ]; then
                echo -e "  ${BLUE}Checking site: $domain${NC}"

                # Create required Bitrix directories inside each site
                for subdir in "bitrix/cache" "bitrix/managed_cache" "upload" "local"; do
                    target="$site_www/$subdir"
                    if [ ! -d "$target" ]; then
                        echo -e "    ${YELLOW}Creating: $subdir${NC}"
                        mkdir -p "$target"
                    fi
                done
            fi
        fi
    done
fi

echo -e "${GREEN}  Directories checked${NC}"

# ============================================================================
# STEP 2: SET PERMISSIONS
# ============================================================================
echo -e "${YELLOW}[2/4] Setting up permissions...${NC}"

# Change ownership of app directory for macOS compatibility
if [ -d "/home/${UGN}/app" ]; then
    echo -e "${BLUE}  Changing ownership of /home/${UGN}/app to ${UGN}...${NC}"
    chown -R "${UGN}:${UGN}" "/home/${UGN}/app" 2>/dev/null || true
    echo -e "${GREEN}  Ownership changed${NC}"
fi

# Multisite: set permissions for each site's directories
# 775 instead of 777 for security
APP_DIR="/home/${UGN}/app"
if [ -d "$APP_DIR" ]; then
    for domain_dir in "$APP_DIR"/*/; do
        if [ -d "$domain_dir" ]; then
            site_www="$domain_dir/www"
            if [ -d "$site_www" ]; then
                for subdir in "upload" "bitrix/cache" "bitrix/managed_cache"; do
                    target="$site_www/$subdir"
                    if [ -d "$target" ]; then
                        chmod -R 775 "$target" 2>/dev/null || true
                    fi
                done
            fi
        fi
    done
fi

# Logs must be writable
chown -R "${UGN}:${UGN}" \
    "/var/log/php" \
    "/var/log/bitrix" \
    2>/dev/null || true

# PHP Sessions — critical for Bitrix
# 770 — only owner and group have access (security)
if [ -d "/var/lib/php/sessions" ]; then
    chown -R "${UGN}:${UGN}" "/var/lib/php/sessions" 2>/dev/null || true
    chmod 770 "/var/lib/php/sessions" 2>/dev/null || true
fi

echo -e "${GREEN}  Permissions configured${NC}"

# ============================================================================
# STEP 3: PHP VERSION-SPECIFIC SETTINGS (compatibility 7.4, 8.3, 8.4)
# ============================================================================
echo -e "${YELLOW}[3/4] Configuring PHP version-specific settings...${NC}"

# Detect PHP version
PHP_VERSION=$(php -r "echo PHP_MAJOR_VERSION.'.'.PHP_MINOR_VERSION;")
echo -e "${BLUE}  PHP Version detected: ${PHP_VERSION}${NC}"

# Create version-specific config
VERSION_INI="/usr/local/etc/php/conf.d/00-version-compat.ini"

cat > "${VERSION_INI}" <<EOF
; =============================================================================
; PHP VERSION-SPECIFIC SETTINGS
; Auto-generated for PHP ${PHP_VERSION}
; =============================================================================
EOF

case "${PHP_VERSION}" in
    7.4)
        cat >> "${VERSION_INI}" <<EOF

; mbstring internal encoding (required for PHP 7.4)
mbstring.internal_encoding = UTF-8

; Session ID settings for enhanced security
session.sid_length = 48
session.sid_bits_per_character = 6
EOF
        echo -e "${GREEN}  Added PHP 7.4 settings${NC}"
        ;;
    8.0|8.1|8.2|8.3)
        cat >> "${VERSION_INI}" <<EOF

; mbstring.internal_encoding is deprecated in PHP 8.0+, UTF-8 is default
; Session ID settings for enhanced security (deprecated in PHP 8.4)
session.sid_length = 48
session.sid_bits_per_character = 6
EOF
        echo -e "${GREEN}  Added PHP ${PHP_VERSION} settings${NC}"
        ;;
    8.4|8.5|9.*)
        cat >> "${VERSION_INI}" <<EOF

; PHP ${PHP_VERSION}: using modern defaults
; - mbstring uses UTF-8 by default
; - session IDs are generated securely by default
EOF
        echo -e "${GREEN}  Using modern defaults for PHP ${PHP_VERSION}${NC}"
        ;;
    *)
        echo -e "${YELLOW}  Unknown PHP version ${PHP_VERSION}, using safe defaults${NC}"
        ;;
esac

echo -e "${GREEN}  Version-specific settings configured${NC}"

# ============================================================================
# STEP 4: ENVIRONMENT-SPECIFIC PHP SETTINGS (OPcache, runtime, display_errors)
# ============================================================================
echo -e "${YELLOW}[4/4] Configuring environment-specific PHP settings...${NC}"

# --- OPcache settings from ENV ---
OPCACHE_MEMORY="${PHP_OPCACHE_MEMORY:-256}"
OPCACHE_INTERNED="${PHP_OPCACHE_INTERNED_STRINGS:-64}"
OPCACHE_MAX_FILES="${PHP_OPCACHE_MAX_FILES:-100000}"

if [ "${ENVIRONMENT}" = "prod" ] || [ "${ENVIRONMENT}" = "production" ]; then
    OPCACHE_REVALIDATE="${PHP_OPCACHE_REVALIDATE_FREQ:-2}"
else
    OPCACHE_REVALIDATE="${PHP_OPCACHE_REVALIDATE_FREQ:-0}"
fi

cat > /usr/local/etc/php/conf.d/98-opcache-runtime.ini <<EOF
; Auto-generated OPcache settings at container startup
; Environment: ${ENVIRONMENT}

; Memory settings (Bitrix official: 471MB)
opcache.memory_consumption = ${OPCACHE_MEMORY}
opcache.interned_strings_buffer = ${OPCACHE_INTERNED}

; File cache settings (Bitrix official: 100000)
opcache.max_accelerated_files = ${OPCACHE_MAX_FILES}

; File validation frequency
; 0=every request (dev), 2=every 2 sec (prod)
opcache.revalidate_freq = ${OPCACHE_REVALIDATE}
EOF

echo -e "${GREEN}  OPcache: memory=${OPCACHE_MEMORY}M, files=${OPCACHE_MAX_FILES}, revalidate=${OPCACHE_REVALIDATE}s${NC}"

# --- PHP resource limits from ENV ---
MEMORY_LIMIT="${PHP_MEMORY_LIMIT:-512M}"
UPLOAD_MAX="${PHP_UPLOAD_MAX_FILESIZE:-1024M}"
POST_MAX="${PHP_POST_MAX_SIZE:-1024M}"
MAX_EXEC_TIME="${PHP_MAX_EXECUTION_TIME:-300}"
MAX_INPUT_TIME="${PHP_MAX_INPUT_TIME:-60}"
TZ_VALUE="${TZ:-UTC}"

# --- display_errors ---
DISPLAY_ERRORS="Off"
ERROR_REPORTING="E_ALL & ~E_NOTICE & ~E_WARNING"
if [ "${ENVIRONMENT}" != "prod" ] && [ "${ENVIRONMENT}" != "production" ]; then
    DISPLAY_ERRORS="On"
    ERROR_REPORTING="E_ALL"
    echo -e "${GREEN}  Development mode: display_errors=On${NC}"
else
    echo -e "${BLUE}  Production mode: display_errors=Off${NC}"
fi

# --- session.cookie_secure ---
SESSION_SECURE="Off"
if [ "$SSL" = "free" ] || [ "$SSL" = "self" ]; then
    SESSION_SECURE="On"
    echo -e "${GREEN}  SSL enabled (SSL=$SSL), session.cookie_secure=On${NC}"
else
    echo -e "${YELLOW}  SSL disabled (SSL=$SSL), session.cookie_secure=Off${NC}"
fi

# Generate PHP runtime config
cat > /usr/local/etc/php/conf.d/98-php-runtime.ini <<EOF
; Auto-generated PHP settings at container startup
; Environment: ${ENVIRONMENT}, SSL: ${SSL}

; Resource limits
memory_limit = ${MEMORY_LIMIT}
upload_max_filesize = ${UPLOAD_MAX}
post_max_size = ${POST_MAX}
max_execution_time = ${MAX_EXEC_TIME}
max_input_time = ${MAX_INPUT_TIME}

; Error handling
error_reporting = ${ERROR_REPORTING}

; Timezone
date.timezone = ${TZ_VALUE}
EOF

# Generate session/display runtime config (loaded last)
cat > /usr/local/etc/php/conf.d/99-runtime.ini <<EOF
; Auto-generated at container startup
; Environment: ${ENVIRONMENT}, SSL: ${SSL}

; Error display (Off in production, On in development)
display_errors = ${DISPLAY_ERRORS}

; Session security
session.cookie_secure = ${SESSION_SECURE}
EOF

echo -e "${GREEN}  PHP: memory=${MEMORY_LIMIT}, upload=${UPLOAD_MAX}, exec_time=${MAX_EXEC_TIME}s${NC}"
echo -e "${GREEN}  Runtime PHP configs generated${NC}"

echo ""
echo -e "${GREEN}Base initialization complete for ${CONTAINER_ROLE}${NC}"
echo ""
