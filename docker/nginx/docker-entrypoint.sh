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
