#!/bin/bash
# Deploy hook for Bitrix SSL certificate
# This script is called by certbot after successful certificate renewal

# Load environment variables
if [ -f /home/deploy/bitrix/.env ]; then
    source /home/deploy/bitrix/.env
fi

DOMAIN="${DOMAIN:-bitrix.local}"
SSL_DIR="/home/deploy/bitrix/ssl"
CONTAINER="${DOMAIN}_nginx"

# Copy certificates
cp -L /etc/letsencrypt/live/$DOMAIN/fullchain.pem $SSL_DIR/
cp -L /etc/letsencrypt/live/$DOMAIN/privkey.pem $SSL_DIR/

# Restart nginx container
docker restart $CONTAINER

echo "[$(date)] SSL certificate deployed for $DOMAIN" >> /var/log/certbot-deploy.log
