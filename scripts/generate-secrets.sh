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

# Default/placeholder values that should be replaced
DEFAULTS_PATTERN="bitrix123|root123|admin123|changeme123|myagentsecret|CHANGE_ME|SWQOKODSQALRPCLNMEQG"

# Check if a value is a default/placeholder (should be replaced)
is_default_value() {
    local value="$1"
    [[ -z "$value" ]] && return 0  # empty = default
    echo "$value" | grep -qiE "$DEFAULTS_PATTERN" && return 0
    return 1
}

# Get current value from .env file
get_env_value() {
    local key="$1"
    local file="$2"
    grep "^${key}=" "$file" 2>/dev/null | head -1 | cut -d'=' -f2-
}

# Update only if current value is a default/placeholder
safe_update_env() {
    local key="$1"
    local new_value="$2"
    local file="$3"
    local current_value
    current_value=$(get_env_value "$key" "$file")

    if is_default_value "$current_value"; then
        if [[ "$OSTYPE" == "darwin"* ]]; then
            sed -i '' "s|^${key}=.*|${key}=${new_value}|" "$file"
        else
            sed -i "s|^${key}=.*|${key}=${new_value}|" "$file"
        fi
        echo -e "  ${GREEN}✓${NC} $key — updated"
    else
        echo -e "  ${BLUE}•${NC} $key — already set (kept)"
    fi
}

# Determine mode: --update-env = auto, otherwise interactive
AUTO_MODE="false"
if [[ "${1:-}" == "--update-env" ]]; then
    AUTO_MODE="true"
fi

UPDATE_ENV="false"
if [ "$AUTO_MODE" = "true" ]; then
    UPDATE_ENV="true"
else
    echo "========================================"
    read -p "Update .env file with these values? (y/N) " -n 1 -r
    echo ""
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        UPDATE_ENV="true"
    fi
fi

if [ "$UPDATE_ENV" = "true" ]; then
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

    echo ""
    echo -e "${BLUE}Updating .env (only default/placeholder values):${NC}"

    safe_update_env "DB_PASSWORD" "$DB_PASSWORD" "$ENV_FILE"
    safe_update_env "DB_ROOT_PASSWORD" "$DB_ROOT_PASSWORD" "$ENV_FILE"
    safe_update_env "REDIS_PASSWORD" "$REDIS_PASSWORD" "$ENV_FILE"
    safe_update_env "RABBIT_COOKIE" "$RABBIT_COOKIE" "$ENV_FILE"
    safe_update_env "RABBITMQ_DEFAULT_PASS" "$RABBITMQ_PASS" "$ENV_FILE"
    safe_update_env "MONITORING_PASSWORD" "$MONITORING_PASS" "$ENV_FILE"
    safe_update_env "PUSH_SECURITY_KEY" "$PUSH_KEY" "$ENV_FILE"
    safe_update_env "PORTAINER_AGENT_SECRET" "$PORTAINER_SECRET" "$ENV_FILE"

    echo ""
    echo -e "${GREEN}Done!${NC} Passwords updated where needed."
else
    echo ""
    echo "Copy the values above to your .env file manually"
fi