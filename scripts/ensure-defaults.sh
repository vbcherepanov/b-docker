#!/bin/bash
# ============================================================================
# Ensure default configs exist before docker build
# Copies .default files if optimized versions don't exist yet.
# Run: ./scripts/ensure-defaults.sh
# Called automatically by: make build, make first-run, make first-run-prod
# ============================================================================

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

# List of configs: source_default -> target
declare -A CONFIGS=(
    ["docker/common/nginx/nginx.conf.default"]="docker/common/nginx/nginx.conf"
    ["docker/common/php/php-fpm.d/www.conf.default"]="docker/common/php/php-fpm.d/www.conf"
    ["config/redis/redis.conf.default"]="config/redis/redis.conf"
    ["config/memcached/memcached.conf.default"]="config/memcached/memcached.conf"
)

echo -e "${YELLOW}[defaults] Checking required configs...${NC}"

COPIED=0
for default_file in "${!CONFIGS[@]}"; do
    target_file="${CONFIGS[$default_file]}"
    target_path="$PROJECT_DIR/$target_file"
    default_path="$PROJECT_DIR/$default_file"

    if [ ! -f "$target_path" ]; then
        if [ -f "$default_path" ]; then
            mkdir -p "$(dirname "$target_path")"
            cp "$default_path" "$target_path"
            echo -e "  ${GREEN}✓${NC} Created $target_file (from default)"
            COPIED=$((COPIED + 1))
        else
            echo -e "  ${YELLOW}⚠${NC} Missing both $target_file and $default_file"
        fi
    fi
done

# MySQL config: special handling (env-specific filename)
ENV_NAME="${ENVIRONMENT:-local}"
MYSQL_TARGET="$PROJECT_DIR/config/mysql/my.${ENV_NAME}.cnf"
MYSQL_DEFAULT="$PROJECT_DIR/config/mysql/my.default.cnf"

if [ ! -f "$MYSQL_TARGET" ]; then
    if [ -f "$MYSQL_DEFAULT" ]; then
        cp "$MYSQL_DEFAULT" "$MYSQL_TARGET"
        echo -e "  ${GREEN}✓${NC} Created config/mysql/my.${ENV_NAME}.cnf (from default)"
        COPIED=$((COPIED + 1))
    fi
fi

if [ $COPIED -eq 0 ]; then
    echo -e "  ${GREEN}✓${NC} All configs already exist"
else
    echo -e "${GREEN}[defaults] Created $COPIED config(s) from defaults${NC}"
fi
