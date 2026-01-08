#!/bin/bash
# Initialize Let's Encrypt SSL certificate for Bitrix
# Usage: ./init-ssl.sh [email] [domain]

set -e

# Load environment variables
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$(dirname "$SCRIPT_DIR")")"

if [ -f "$PROJECT_DIR/.env" ]; then
    source "$PROJECT_DIR/.env"
fi

EMAIL="${1:-${ADMIN_EMAIL:-admin@example.com}}"
DOMAIN="${2:-${DOMAIN:-bitrix.local}}"
SSL_DIR="$PROJECT_DIR/ssl"

echo "=== Bitrix SSL Certificate Setup ==="
echo "Domain: $DOMAIN"
echo "Email: $EMAIL"
echo "SSL Dir: $SSL_DIR"
echo ""

# Check if certbot is installed
if ! command -v certbot &> /dev/null; then
    echo "Installing certbot..."
    apt-get update && apt-get install -y certbot
fi

# Stop nginx to free port 80
echo "Stopping nginx container..."
docker stop ${DOMAIN}_nginx 2>/dev/null || true

# Get certificate
echo "Obtaining SSL certificate..."
certbot certonly --standalone \
    -d "$DOMAIN" \
    --non-interactive \
    --agree-tos \
    --email "$EMAIL"

# Copy certificates to project
echo "Copying certificates..."
cp -L /etc/letsencrypt/live/$DOMAIN/fullchain.pem $SSL_DIR/
cp -L /etc/letsencrypt/live/$DOMAIN/privkey.pem $SSL_DIR/

# Install deploy hook
echo "Installing renewal hook..."
mkdir -p /etc/letsencrypt/renewal-hooks/deploy
cp "$SCRIPT_DIR/renewal-hooks/deploy/bitrix-ssl.sh" /etc/letsencrypt/renewal-hooks/deploy/
chmod +x /etc/letsencrypt/renewal-hooks/deploy/bitrix-ssl.sh

# Start nginx
echo "Starting nginx container..."
docker start ${DOMAIN}_nginx

echo ""
echo "=== SSL Setup Complete ==="
echo "Certificate: /etc/letsencrypt/live/$DOMAIN/"
echo "Auto-renewal: enabled (certbot.timer)"
echo ""
echo "Test renewal with: certbot renew --dry-run"
