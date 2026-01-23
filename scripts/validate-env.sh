#!/bin/bash
# ============================================================
# Environment Validation Script for b-docker
# Checks for security issues in .env configuration
# Run: chmod +x validate-env.sh && ./validate-env.sh
# ============================================================

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

ENV_FILE="${1:-.env}"
ERRORS=0
WARNINGS=0

echo "========================================"
echo "  Environment Validation: $ENV_FILE"
echo "========================================"
echo ""

if [ ! -f "$ENV_FILE" ]; then
    echo -e "${RED}[ERROR]${NC} File not found: $ENV_FILE"
    exit 1
fi

# Load env file (handle special chars like DOLLAR=$)
set +u  # Allow unset variables during source
set +e  # Don't exit on export errors
while IFS='=' read -r key value; do
    # Skip comments and empty lines
    [[ "$key" =~ ^[[:space:]]*# ]] && continue
    [[ -z "$key" ]] && continue
    # Remove leading/trailing whitespace
    key=$(echo "$key" | xargs)
    # Skip if no value
    [[ -z "$value" ]] && continue
    # Skip readonly variables (UID, EUID, etc.)
    [[ "$key" == "UID" || "$key" == "EUID" || "$key" == "GID" || "$key" == "PPID" ]] && continue
    # Export variable (handle special chars)
    export "$key=$value" 2>/dev/null || true
done < "$ENV_FILE"
set -e
set -u

# Function to check for weak/placeholder passwords
check_password() {
    local name="$1"
    local value="$2"
    local weak_patterns=(
        "123"
        "password"
        "admin"
        "root"
        "test"
        "bitrix"
        "changeme"
        "CHANGE_ME"
        "example"
        "secret"
        "qwerty"
    )

    if [ -z "$value" ]; then
        echo -e "${RED}[CRITICAL]${NC} $name is empty!"
        ERRORS=$((ERRORS + 1))
        return
    fi

    if [ ${#value} -lt 16 ]; then
        echo -e "${YELLOW}[WARNING]${NC} $name is less than 16 characters (${#value} chars)"
        WARNINGS=$((WARNINGS + 1))
    fi

    for pattern in "${weak_patterns[@]}"; do
        if [[ "$value" == *"$pattern"* ]]; then
            echo -e "${RED}[CRITICAL]${NC} $name contains weak pattern '$pattern'"
            ERRORS=$((ERRORS + 1))
            return
        fi
    done

    echo -e "${GREEN}[OK]${NC} $name - looks secure (${#value} chars)"
}

# Function to check environment setting
check_env() {
    local name="$1"
    local expected="$2"
    local actual="$3"
    local severity="${4:-WARNING}"

    if [ "$actual" == "$expected" ]; then
        echo -e "${GREEN}[OK]${NC} $name = $actual"
    else
        if [ "$severity" == "CRITICAL" ]; then
            echo -e "${RED}[CRITICAL]${NC} $name should be '$expected', got '$actual'"
            ERRORS=$((ERRORS + 1))
        else
            echo -e "${YELLOW}[WARNING]${NC} $name = $actual (recommended: $expected)"
            WARNINGS=$((WARNINGS + 1))
        fi
    fi
}

echo "=== Password Security Checks ==="
echo ""

check_password "DB_PASSWORD" "${DB_PASSWORD:-}"
check_password "DB_ROOT_PASSWORD" "${DB_ROOT_PASSWORD:-}"
check_password "REDIS_PASSWORD" "${REDIS_PASSWORD:-}"
check_password "RABBITMQ_DEFAULT_PASS" "${RABBITMQ_DEFAULT_PASS:-}"
check_password "MONITORING_PASSWORD" "${MONITORING_PASSWORD:-}"
check_password "PUSH_SECURITY_KEY" "${PUSH_SECURITY_KEY:-}"
check_password "PORTAINER_AGENT_SECRET" "${PORTAINER_AGENT_SECRET:-}"

echo ""
echo "=== Environment Settings ==="
echo ""

# Check ENVIRONMENT setting
ENV="${ENVIRONMENT:-local}"
if [ "$ENV" == "prod" ] || [ "$ENV" == "production" ]; then
    echo -e "${BLUE}[INFO]${NC} Production environment detected"

    check_env "DEBUG" "0" "${DEBUG:-1}" "CRITICAL"
    check_env "SSL" "free" "${SSL:-0}" "WARNING"

    # Check if ports are exposed (shouldn't be in production)
    if [ -n "${DB_PORT:-}" ]; then
        echo -e "${YELLOW}[WARNING]${NC} DB_PORT is set ($DB_PORT) - MySQL port will be exposed"
        WARNINGS=$((WARNINGS + 1))
    fi

    if [ -n "${REDIS_PORT:-}" ]; then
        echo -e "${YELLOW}[WARNING]${NC} REDIS_PORT is set ($REDIS_PORT) - Redis port will be exposed"
        WARNINGS=$((WARNINGS + 1))
    fi
else
    echo -e "${BLUE}[INFO]${NC} Non-production environment: $ENV"
    check_env "DEBUG" "1" "${DEBUG:-0}"
fi

# Check RABBIT_COOKIE format (alphanumeric, 20+ chars)
if [ -n "${RABBIT_COOKIE:-}" ]; then
    if [ ${#RABBIT_COOKIE} -lt 20 ]; then
        echo -e "${YELLOW}[WARNING]${NC} RABBIT_COOKIE is short (${#RABBIT_COOKIE} chars, recommended: 20+)"
        WARNINGS=$((WARNINGS + 1))
    else
        echo -e "${GREEN}[OK]${NC} RABBIT_COOKIE looks good (${#RABBIT_COOKIE} chars)"
    fi
fi

# Check Let's Encrypt email
if [ "${SSL:-0}" == "free" ]; then
    if [ -z "${LETSENCRYPT_EMAIL:-}" ] || [[ "${LETSENCRYPT_EMAIL}" == *"example"* ]]; then
        echo -e "${RED}[CRITICAL]${NC} LETSENCRYPT_EMAIL must be set for SSL=free"
        ERRORS=$((ERRORS + 1))
    else
        echo -e "${GREEN}[OK]${NC} LETSENCRYPT_EMAIL is set"
    fi
fi

echo ""
echo "========================================"
echo "  Validation Summary"
echo "========================================"
echo ""
echo -e "Errors:   ${RED}$ERRORS${NC}"
echo -e "Warnings: ${YELLOW}$WARNINGS${NC}"
echo ""

if [ $ERRORS -gt 0 ]; then
    echo -e "${RED}FAILED${NC} - Fix critical errors before deployment!"
    echo ""
    echo "Generate secure passwords with:"
    echo "  ./generate-secrets.sh"
    exit 1
elif [ $WARNINGS -gt 0 ]; then
    echo -e "${YELLOW}PASSED WITH WARNINGS${NC} - Review warnings above"
    exit 0
else
    echo -e "${GREEN}PASSED${NC} - Environment looks secure!"
    exit 0
fi