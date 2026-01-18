#!/bin/bash
# ============================================================================
# SENDMAIL WRAPPER FOR MULTISITE
# Determines the domain from current directory and uses per-site msmtp config
# Usage: sendmail-wrapper.sh -t -i (as drop-in replacement for sendmail)
# ============================================================================

# Configuration
SITES_CONFIG_DIR="${SITES_CONFIG_DIR:-/etc/bitrix-sites}"
DEFAULT_MSMTP_CONFIG="${DEFAULT_MSMTP_CONFIG:-/etc/msmtprc}"
LOG_FILE="${LOG_FILE:-/var/log/msmtp/sendmail-wrapper.log}"
APP_DIR="${APP_DIR:-/home/bitrix/app}"

# Ensure log directory exists
mkdir -p "$(dirname "$LOG_FILE")"

# Logging function
log() {
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] $*" >> "$LOG_FILE"
}

# Determine domain from current working directory
# Expected structure: /home/bitrix/app/{domain}/www/...
get_domain_from_cwd() {
    local cwd
    cwd=$(pwd)

    # Extract domain from path like /home/bitrix/app/shop.local/www/bitrix/...
    if [[ "$cwd" =~ ^${APP_DIR}/([^/]+)/ ]]; then
        echo "${BASH_REMATCH[1]}"
        return 0
    fi

    # Fallback: try to get from SCRIPT_FILENAME if set
    if [ -n "${SCRIPT_FILENAME:-}" ]; then
        if [[ "$SCRIPT_FILENAME" =~ ^${APP_DIR}/([^/]+)/ ]]; then
            echo "${BASH_REMATCH[1]}"
            return 0
        fi
    fi

    return 1
}

# Find msmtp config for domain
get_msmtp_config() {
    local domain="$1"
    local site_config="$SITES_CONFIG_DIR/$domain/msmtp.conf"

    if [ -f "$site_config" ]; then
        echo "$site_config"
    elif [ -f "$DEFAULT_MSMTP_CONFIG" ]; then
        echo "$DEFAULT_MSMTP_CONFIG"
    else
        return 1
    fi
}

# Main execution
main() {
    local domain=""
    local msmtp_config=""

    # Try to determine domain
    domain=$(get_domain_from_cwd) || domain=""

    if [ -n "$domain" ]; then
        log "Domain detected: $domain (from cwd: $(pwd))"
        msmtp_config=$(get_msmtp_config "$domain") || msmtp_config=""
    fi

    # Fallback to default config if no domain-specific found
    if [ -z "$msmtp_config" ]; then
        if [ -f "$DEFAULT_MSMTP_CONFIG" ]; then
            msmtp_config="$DEFAULT_MSMTP_CONFIG"
            log "Using default msmtp config: $msmtp_config"
        else
            log "ERROR: No msmtp config found!"
            echo "sendmail-wrapper: No msmtp config found" >&2
            exit 1
        fi
    else
        log "Using site-specific config: $msmtp_config"
    fi

    # Execute msmtp with the determined config
    # Pass all arguments through
    log "Executing: msmtp -C $msmtp_config $*"
    exec /usr/bin/msmtp -C "$msmtp_config" "$@"
}

# Run main with all script arguments
main "$@"
