#!/bin/sh
# =============================================================================
# Nginx Docker Entrypoint
# Handles SSL setup before starting nginx
# =============================================================================

set -e

echo "========================================"
echo "Nginx Container Starting"
echo "Environment: ${ENVIRONMENT:-local}"
echo "Domain: ${DOMAIN:-localhost}"
echo "SSL: ${SSL:-0}"
echo "========================================"

# Generate htpasswd for monitoring subdomains (grafana, prometheus, rabbit)
if [ -n "${MONITORING_USER}" ] && [ -n "${MONITORING_PASSWORD}" ]; then
    echo "Generating htpasswd for monitoring access..."
    HTPASSWD_FILE="/etc/nginx/conf.d/.htpasswd"
    # Generate password hash using openssl (htpasswd not available in alpine nginx)
    HASH=$(openssl passwd -apr1 "${MONITORING_PASSWORD}")
    echo "${MONITORING_USER}:${HASH}" > "${HTPASSWD_FILE}"
    chmod 644 "${HTPASSWD_FILE}"
    echo "htpasswd file created: ${HTPASSWD_FILE}"
else
    echo "Warning: MONITORING_USER or MONITORING_PASSWORD not set, htpasswd not created"
fi

# Replace PHP_FPM_HOST in nginx snippets (for split mode support)
PHP_FPM_HOST="${PHP_FPM_HOST:-bitrix}"
echo "PHP-FPM upstream: ${PHP_FPM_HOST}:9000"
if [ "$PHP_FPM_HOST" != "bitrix" ]; then
    echo "Updating nginx configs for PHP_FPM_HOST=${PHP_FPM_HOST}..."
    # Update all nginx config files that reference the PHP-FPM upstream
    for conf_file in /etc/nginx/snippets/*.conf /etc/nginx/conf.d/*.conf; do
        if [ -f "$conf_file" ] && grep -q 'bitrix:9000' "$conf_file"; then
            sed -i "s/bitrix:9000/${PHP_FPM_HOST}:9000/g" "$conf_file"
            echo "  Updated: $conf_file"
        fi
    done
fi

# Run SSL setup script
if [ -f /usr/local/bin/script/ssl.sh ]; then
    echo "Running SSL setup..."
    /usr/local/bin/script/ssl.sh
else
    echo "Warning: ssl.sh not found, skipping SSL setup"
fi

echo "========================================"
echo "Starting Nginx"
echo "========================================"

# Execute the main command (nginx)
exec "$@"
