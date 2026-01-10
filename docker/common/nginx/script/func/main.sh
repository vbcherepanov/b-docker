#!/bin/sh
# =============================================================================
# Nginx SSL Management Functions
# =============================================================================

TEMPLATE_DIR="/var/template"
CONF_DIR="/etc/nginx/conf.d"
SSL_PATH="/etc/letsencrypt/live"
SSL_KEY="fullchain.pem"
SSL_PRIV_KEY="privkey.pem"
RENEWAL_THRESHOLD_DAYS=5

export DOLLAR='$'

# =============================================================================
# Nginx Functions
# =============================================================================

reload_nginx() {
    echo "[nginx] Reloading configuration..."
    if nginx -t; then
        nginx -s reload
        echo "[nginx] Configuration reloaded successfully"
    else
        echo "[nginx] ERROR: Invalid configuration!"
        exit 1
    fi
}

start_nginx() {
    echo "[nginx] Starting..."
    if nginx -t; then
        nginx -g 'daemon off;'
    else
        echo "[nginx] ERROR: Invalid configuration!"
        exit 1
    fi
}

# =============================================================================
# SSL Certificate Functions
# =============================================================================

# Check if certificate exists for domain
# Usage: cert_exists "example.com"
# Returns: 0 if exists, 1 if not
cert_exists() {
    local domain="$1"
    local cert_file="$SSL_PATH/$domain/$SSL_KEY"

    if [ -f "$cert_file" ]; then
        return 0
    else
        return 1
    fi
}

# Get certificate expiry date in epoch seconds
# Usage: get_cert_expiry_epoch "example.com"
# Returns: epoch seconds or empty on error
get_cert_expiry_epoch() {
    local domain="$1"
    local cert_file="$SSL_PATH/$domain/$SSL_KEY"

    if [ ! -f "$cert_file" ]; then
        echo ""
        return 1
    fi

    # Get expiry date from certificate
    local expiry_date
    expiry_date=$(openssl x509 -enddate -noout -in "$cert_file" 2>/dev/null | cut -d= -f2)

    if [ -z "$expiry_date" ]; then
        echo ""
        return 1
    fi

    # Convert to epoch (works on Alpine/BusyBox)
    local expiry_epoch
    expiry_epoch=$(date -d "$expiry_date" +%s 2>/dev/null)

    echo "$expiry_epoch"
}

# Get days left until certificate expires
# Usage: get_cert_days_left "example.com"
# Returns: number of days (can be negative if expired)
get_cert_days_left() {
    local domain="$1"
    local expiry_epoch

    expiry_epoch=$(get_cert_expiry_epoch "$domain")

    if [ -z "$expiry_epoch" ]; then
        echo "-1"
        return 1
    fi

    local now_epoch
    now_epoch=$(date +%s)

    local seconds_left=$((expiry_epoch - now_epoch))
    local days_left=$((seconds_left / 86400))

    echo "$days_left"
}

# Check if certificate needs renewal (≤5 days left or doesn't exist)
# Usage: needs_renewal "example.com"
# Returns: 0 if needs renewal, 1 if OK
needs_renewal() {
    local domain="$1"

    if ! cert_exists "$domain"; then
        echo "[ssl] Certificate for $domain does not exist"
        return 0
    fi

    local days_left
    days_left=$(get_cert_days_left "$domain")

    if [ "$days_left" -le "$RENEWAL_THRESHOLD_DAYS" ]; then
        echo "[ssl] Certificate for $domain expires in $days_left days (threshold: $RENEWAL_THRESHOLD_DAYS)"
        return 0
    fi

    echo "[ssl] Certificate for $domain is valid for $days_left more days"
    return 1
}

# Request new certificate from Let's Encrypt
# Usage: request_cert "example.com" "admin@example.com"
# Returns: 0 on success, 1 on failure
request_cert() {
    local domain="$1"
    local email="$2"

    echo "[ssl] Requesting certificate for $domain..."

    local output
    output=$(certbot certonly --nginx --non-interactive --agree-tos \
        --email "$email" -d "$domain" 2>&1)
    local result=$?

    echo "$output"

    if [ $result -eq 0 ] && echo "$output" | grep -q "Successfully received certificate\|Certificate not yet due for renewal"; then
        echo "[ssl] Certificate for $domain obtained successfully"
        return 0
    else
        echo "[ssl] ERROR: Failed to obtain certificate for $domain"
        return 1
    fi
}

# Renew existing certificate
# Usage: renew_cert "example.com"
# Returns: 0 on success, 1 on failure
renew_cert() {
    local domain="$1"

    echo "[ssl] Renewing certificate for $domain..."

    local output
    output=$(certbot renew --cert-name "$domain" --nginx --non-interactive 2>&1)
    local result=$?

    echo "$output"

    if [ $result -eq 0 ]; then
        echo "[ssl] Certificate for $domain renewed successfully"
        return 0
    else
        echo "[ssl] ERROR: Failed to renew certificate for $domain"
        return 1
    fi
}

# Smart function: create or renew certificate as needed
# Usage: ensure_cert "example.com" "admin@example.com"
# Returns: 0 on success (or no action needed), 1 on failure
ensure_cert() {
    local domain="$1"
    local email="$2"

    echo "[ssl] ========================================"
    echo "[ssl] Checking certificate for $domain"
    echo "[ssl] ========================================"

    if ! cert_exists "$domain"; then
        echo "[ssl] Certificate does not exist, requesting new one..."
        request_cert "$domain" "$email"
        return $?
    fi

    local days_left
    days_left=$(get_cert_days_left "$domain")

    if [ "$days_left" -le 0 ]; then
        echo "[ssl] Certificate EXPIRED! Requesting new one..."
        request_cert "$domain" "$email"
        return $?
    elif [ "$days_left" -le "$RENEWAL_THRESHOLD_DAYS" ]; then
        echo "[ssl] Certificate expires in $days_left days, renewing..."
        renew_cert "$domain"
        return $?
    else
        echo "[ssl] Certificate is valid for $days_left days, no action needed"
        return 0
    fi
}

# Get certificate paths for nginx config
# Usage: get_cert_paths "example.com" "admin@example.com"
# Returns: "cert_path key_path" on success
get_cert_paths() {
    local domain="$1"
    local email="$2"

    # Ensure certificate exists and is valid
    if ! ensure_cert "$domain" "$email"; then
        return 1
    fi

    local cert_path="$SSL_PATH/$domain/$SSL_KEY"
    local key_path="$SSL_PATH/$domain/$SSL_PRIV_KEY"

    if [ -f "$cert_path" ] && [ -f "$key_path" ]; then
        echo "$cert_path $key_path"
        return 0
    else
        echo "[ssl] ERROR: Certificate files not found after ensure_cert"
        return 1
    fi
}

# Check and renew all certificates (for cron job)
# Usage: check_and_renew_all
check_and_renew_all() {
    echo "[ssl] ========================================"
    echo "[ssl] Daily certificate check: $(date)"
    echo "[ssl] ========================================"

    local renewed=0

    # Check main domain
    if [ -n "$DOMAIN" ]; then
        if needs_renewal "$DOMAIN"; then
            if ensure_cert "$DOMAIN" "$EMAIL"; then
                renewed=1
            fi
        fi
    fi

    # Check mail subdomain
    if [ "$MAIL_CONFIG" = "1" ] && [ -n "$DOMAIN" ]; then
        local mail_domain="mail.$DOMAIN"
        if needs_renewal "$mail_domain"; then
            if ensure_cert "$mail_domain" "$EMAIL"; then
                renewed=1
            fi
        fi
    fi

    # Check rabbit subdomain
    if [ "$RABBIT_CONFIG" = "1" ] && [ -n "$DOMAIN" ]; then
        local rabbit_domain="rabbit.$DOMAIN"
        if needs_renewal "$rabbit_domain"; then
            if ensure_cert "$rabbit_domain" "$EMAIL"; then
                renewed=1
            fi
        fi
    fi

    # Reload nginx if any certificate was renewed
    if [ "$renewed" -eq 1 ]; then
        echo "[ssl] Certificates renewed, reloading nginx..."
        reload_nginx
    fi

    echo "[ssl] Daily check completed"
}
