#!/bin/bash
# ============================================================
# Secure Secrets Generator for b-docker
# Generates cryptographically secure passwords and tokens
# Run: chmod +x generate-secrets.sh && ./generate-secrets.sh
# ============================================================

set -euo pipefail

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo "========================================"
echo "  Secure Secrets Generator"
echo "========================================"
echo ""

# Generate secure password (base64, 32 chars)
gen_password() {
    openssl rand -base64 32 | tr -d '/+=' | head -c 32
}

# Generate hex token (for cookies, etc)
gen_hex() {
    local length="${1:-32}"
    openssl rand -hex "$length"
}

# Generate uppercase cookie (for RabbitMQ)
gen_cookie() {
    openssl rand -hex 20 | tr '[:lower:]' '[:upper:]' | head -c 20
}

echo -e "${BLUE}Generating secure values...${NC}"
echo ""

DB_PASSWORD=$(gen_password)
DB_ROOT_PASSWORD=$(gen_password)
REDIS_PASSWORD=$(gen_password)
RABBITMQ_PASS=$(gen_password)
RABBIT_COOKIE=$(gen_cookie)
MONITORING_PASS=$(gen_password)
PUSH_KEY=$(gen_hex 32)
PORTAINER_SECRET=$(gen_hex 32)

echo "=== Generated Secrets ==="
echo ""
echo -e "${GREEN}# Database${NC}"
echo "DB_PASSWORD=$DB_PASSWORD"
echo "DB_ROOT_PASSWORD=$DB_ROOT_PASSWORD"
echo ""
echo -e "${GREEN}# Redis${NC}"
echo "REDIS_PASSWORD=$REDIS_PASSWORD"
echo ""
echo -e "${GREEN}# RabbitMQ${NC}"
echo "RABBIT_COOKIE=$RABBIT_COOKIE"
echo "RABBITMQ_DEFAULT_PASS=$RABBITMQ_PASS"
echo ""
echo -e "${GREEN}# Monitoring${NC}"
echo "MONITORING_PASSWORD=$MONITORING_PASS"
echo ""
echo -e "${GREEN}# Services${NC}"
echo "PUSH_SECURITY_KEY=$PUSH_KEY"
echo "PORTAINER_AGENT_SECRET=$PORTAINER_SECRET"
echo ""

# Ask to update .env
echo "========================================"
read -p "Update .env file with these values? (y/N) " -n 1 -r
echo ""

if [[ $REPLY =~ ^[Yy]$ ]]; then
    ENV_FILE=".env"

    if [ ! -f "$ENV_FILE" ]; then
        if [ -f ".env.example" ]; then
            cp .env.example "$ENV_FILE"
            echo -e "${BLUE}Created .env from .env.example${NC}"
        else
            echo -e "${YELLOW}No .env file found. Create manually.${NC}"
            exit 1
        fi
    fi

    # Backup existing .env
    cp "$ENV_FILE" "${ENV_FILE}.backup.$(date +%Y%m%d_%H%M%S)"
    echo -e "${BLUE}Backup created${NC}"

    # Update values using sed
    # macOS compatible sed
    if [[ "$OSTYPE" == "darwin"* ]]; then
        SED_INPLACE="sed -i ''"
    else
        SED_INPLACE="sed -i"
    fi

    $SED_INPLACE "s|^DB_PASSWORD=.*|DB_PASSWORD=$DB_PASSWORD|" "$ENV_FILE"
    $SED_INPLACE "s|^DB_ROOT_PASSWORD=.*|DB_ROOT_PASSWORD=$DB_ROOT_PASSWORD|" "$ENV_FILE"
    $SED_INPLACE "s|^REDIS_PASSWORD=.*|REDIS_PASSWORD=$REDIS_PASSWORD|" "$ENV_FILE"
    $SED_INPLACE "s|^RABBIT_COOKIE=.*|RABBIT_COOKIE=$RABBIT_COOKIE|" "$ENV_FILE"
    $SED_INPLACE "s|^RABBITMQ_DEFAULT_PASS=.*|RABBITMQ_DEFAULT_PASS=$RABBITMQ_PASS|" "$ENV_FILE"
    $SED_INPLACE "s|^MONITORING_PASSWORD=.*|MONITORING_PASSWORD=$MONITORING_PASS|" "$ENV_FILE"
    $SED_INPLACE "s|^PUSH_SECURITY_KEY=.*|PUSH_SECURITY_KEY=$PUSH_KEY|" "$ENV_FILE"
    $SED_INPLACE "s|^PORTAINER_AGENT_SECRET=.*|PORTAINER_AGENT_SECRET=$PORTAINER_SECRET|" "$ENV_FILE"

    echo ""
    echo -e "${GREEN}SUCCESS!${NC} .env updated with secure passwords"
    echo ""
    echo "Next steps:"
    echo "1. Validate: ./validate-env.sh"
    echo "2. Rebuild:  docker compose build --no-cache"
    echo "3. Restart:  docker compose down && docker compose up -d"
else
    echo ""
    echo "Copy the values above to your .env file manually"
fi