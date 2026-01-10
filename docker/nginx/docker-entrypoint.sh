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
