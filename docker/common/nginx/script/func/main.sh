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
        # Check if nginx is running (PID file exists and process is alive)
        if [ -f /var/run/nginx.pid ] && kill -0 $(cat /var/run/nginx.pid) 2>/dev/null; then
            nginx -s reload
            echo "[nginx] Configuration reloaded successfully"
        else
            echo "[nginx] Nginx not running yet, skip reload (configs will be loaded on start)"
        fi
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

# Check if certificate will expire within given seconds
# Usage: cert_expires_within "example.com" 432000
# Returns: 0 if will expire, 1 if still valid
cert_expires_within() {
    local domain="$1"
    local seconds="${2:-432000}"  # Default 5 days
    local cert_file="$SSL_PATH/$domain/$SSL_KEY"

    if [ ! -f "$cert_file" ]; then
        return 0  # No cert = needs renewal
    fi

    # openssl -checkend returns 0 if cert expires within <seconds>, 1 if still valid
    if openssl x509 -checkend "$seconds" -noout -in "$cert_file" 2>/dev/null; then
        return 1  # Still valid
    else
        return 0  # Will expire
    fi
}

# Get approximate days left (for logging purposes)
# Uses checkend to estimate days remaining
# Usage: get_cert_days_left "example.com"
# Returns: approximate number of days
get_cert_days_left() {
    local domain="$1"
    local cert_file="$SSL_PATH/$domain/$SSL_KEY"

    if [ ! -f "$cert_file" ]; then
        echo "0"
        return 1
    fi

    # Check at various intervals to estimate days left
    local days=0
    for d in 1 5 10 30 60 90; do
        local seconds=$((d * 86400))
        # Redirect both stdout and stderr to /dev/null
        if openssl x509 -checkend "$seconds" -noout -in "$cert_file" >/dev/null 2>&1; then
            days=$d
        else
            break
        fi
    done

    echo "$days"
}

# Check if certificate needs renewal (≤5 days left or doesn't exist)
# Usage: needs_renewal "example.com"
# Returns: 0 if needs renewal, 1 if OK
needs_renewal() {
    local domain="$1"
    local threshold_seconds=$((RENEWAL_THRESHOLD_DAYS * 86400))

    if ! cert_exists "$domain"; then
        echo "[ssl] Certificate for $domain does not exist"
        return 0
    fi

    if cert_expires_within "$domain" "$threshold_seconds"; then
        echo "[ssl] Certificate for $domain expires within $RENEWAL_THRESHOLD_DAYS days"
        return 0
    fi

    local days_approx
    days_approx=$(get_cert_days_left "$domain")
    echo "[ssl] Certificate for $domain is valid for ~$days_approx+ days"
    return 1
}

# Request new certificate from Let's Encrypt
# Usage: request_cert "example.com" "admin@example.com"
# Returns: 0 on success, 1 on failure
request_cert() {
    local domain="$1"
    local email="$2"

    echo "[ssl] Requesting certificate for $domain..." >&2

    local output
    output=$(certbot certonly --nginx --non-interactive --agree-tos \
        --email "$email" -d "$domain" 2>&1)
    local result=$?

    echo "$output" >&2

    if [ $result -eq 0 ] && echo "$output" | grep -q "Successfully received certificate\|Certificate not yet due for renewal"; then
        echo "[ssl] Certificate for $domain obtained successfully" >&2
        return 0
    else
        echo "[ssl] ERROR: Failed to obtain certificate for $domain" >&2
        return 1
    fi
}

# Renew existing certificate
# Usage: renew_cert "example.com"
# Returns: 0 on success, 1 on failure
renew_cert() {
    local domain="$1"

    echo "[ssl] Renewing certificate for $domain..." >&2

    local output
    output=$(certbot renew --cert-name "$domain" --nginx --non-interactive 2>&1)
    local result=$?

    echo "$output" >&2

    if [ $result -eq 0 ]; then
        echo "[ssl] Certificate for $domain renewed successfully" >&2
        return 0
    else
        echo "[ssl] ERROR: Failed to renew certificate for $domain" >&2
        return 1
    fi
}

# Smart function: create or renew certificate as needed
# Usage: ensure_cert "example.com" "admin@example.com"
# Returns: 0 on success (or no action needed), 1 on failure
# Note: All logging goes to stderr so stdout can be used for return values
ensure_cert() {
    local domain="$1"
    local email="$2"
    local threshold_seconds=$((RENEWAL_THRESHOLD_DAYS * 86400))

    echo "[ssl] ========================================" >&2
    echo "[ssl] Checking certificate for $domain" >&2
    echo "[ssl] ========================================" >&2

    if ! cert_exists "$domain"; then
        echo "[ssl] Certificate does not exist, requesting new one..." >&2
        request_cert "$domain" "$email"
        return $?
    fi

    # Check if expired (0 seconds threshold)
    if cert_expires_within "$domain" 0; then
        echo "[ssl] Certificate EXPIRED! Requesting new one..." >&2
        request_cert "$domain" "$email"
        return $?
    fi

    # Check if needs renewal (within threshold)
    if cert_expires_within "$domain" "$threshold_seconds"; then
        local days_approx
        days_approx=$(get_cert_days_left "$domain")
        echo "[ssl] Certificate expires within $RENEWAL_THRESHOLD_DAYS days (~$days_approx days left), renewing..." >&2
        renew_cert "$domain"
        return $?
    fi

    local days_approx
    days_approx=$(get_cert_days_left "$domain")
    echo "[ssl] Certificate is valid for ~$days_approx+ days, no action needed" >&2
    return 0
}

# Get certificate paths for nginx config
# Usage: get_cert_paths "example.com" "admin@example.com"
# Returns: "cert_path key_path" on stdout, logs to stderr
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
        echo "$cert_path $key_path"  # Only this goes to stdout
        return 0
    else
        echo "[ssl] ERROR: Certificate files not found after ensure_cert" >&2
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
