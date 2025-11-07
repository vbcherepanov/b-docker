#!/bin/bash
# ============================================================================
# DOCKER ENTRYPOINT FOR BITRIX CONTAINER
# Инициализация контейнера перед запуском Supervisor
# ============================================================================

set -e

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}============================================================================${NC}"
echo -e "${BLUE}BITRIX DOCKER CONTAINER INITIALIZATION${NC}"
echo -e "${BLUE}============================================================================${NC}"

# ============================================================================
# ИНФОРМАЦИЯ ОБ ОКРУЖЕНИИ
# ============================================================================
echo -e "${GREEN}Environment: ${ENVIRONMENT}${NC}"
echo -e "${GREEN}Domain: ${DOMAIN}${NC}"
echo -e "${GREEN}PHP Version: $(php -v | head -n 1)${NC}"
echo -e "${GREEN}User: ${UGN} (UID:${UID}, GID:${GID})${NC}"
echo -e "${GREEN}Timezone: ${TZ}${NC}"
echo ""

# ============================================================================
# ПРОВЕРКА И СОЗДАНИЕ НЕОБХОДИМЫХ ДИРЕКТОРИЙ
# ============================================================================
echo -e "${YELLOW}[1/7] Checking directories...${NC}"

REQUIRED_DIRS=(
    "/home/${UGN}/app"
    "/home/${UGN}/app/upload"
    "/home/${UGN}/app/local"
    "/home/${UGN}/app/bitrix/cache"
    "/home/${UGN}/tmp"
    "/var/log/php"
    "/var/log/php-fpm"
    "/var/log/cron"
    "/var/log/supervisor"
    "/var/log/bitrix"
)

for dir in "${REQUIRED_DIRS[@]}"; do
    if [ ! -d "$dir" ]; then
        echo -e "  ${YELLOW}Creating directory: $dir${NC}"
        mkdir -p "$dir"
    fi
done

echo -e "${GREEN}  ✓ Directories checked${NC}"

# ============================================================================
# НАСТРОЙКА ПРАВ ДОСТУПА
# ============================================================================
echo -e "${YELLOW}[2/7] Setting up permissions...${NC}"

# Битрикс требует специфичные права на некоторые директории
if [ -d "/home/${UGN}/app/upload" ]; then
    chmod -R 777 "/home/${UGN}/app/upload" 2>/dev/null || true
fi

if [ -d "/home/${UGN}/app/bitrix/cache" ]; then
    chmod -R 777 "/home/${UGN}/app/bitrix/cache" 2>/dev/null || true
fi

if [ -d "/home/${UGN}/app/bitrix/managed_cache" ]; then
    chmod -R 777 "/home/${UGN}/app/bitrix/managed_cache" 2>/dev/null || true
fi

# Логи должны быть доступны для записи
chown -R "${UGN}:${UGN}" \
    "/var/log/php" \
    "/var/log/php-fpm" \
    "/var/log/bitrix" \
    2>/dev/null || true

# Supervisor логи
chown -R "${UGN}:${UGN}" "/var/log/supervisor" 2>/dev/null || true

echo -e "${GREEN}  ✓ Permissions configured${NC}"

# ============================================================================
# НАСТРОЙКА PHP-FPM
# ============================================================================
echo -e "${YELLOW}[3/7] Configuring PHP-FPM...${NC}"

# Проверяем наличие конфигурации PHP-FPM
if [ ! -f "/usr/local/etc/php-fpm.d/www.conf" ]; then
    echo -e "${RED}  ✗ PHP-FPM configuration not found!${NC}"
    exit 1
fi

# Динамическая настройка PHP-FPM pool в зависимости от окружения
if [ "${ENVIRONMENT}" = "prod" ] || [ "${ENVIRONMENT}" = "production" ]; then
    # Production: более консервативные настройки
    export PHP_FPM_PM="ondemand"
    export PHP_FPM_MAX_CHILDREN="${PHP_FPM_MAX_CHILDREN:-50}"
else
    # Development: более отзывчивые настройки
    export PHP_FPM_PM="dynamic"
    export PHP_FPM_MAX_CHILDREN="${PHP_FPM_MAX_CHILDREN:-20}"
fi

echo -e "${GREEN}  ✓ PHP-FPM configured (pm=${PHP_FPM_PM})${NC}"

# ============================================================================
# НАСТРОЙКА CRON
# ============================================================================
echo -e "${YELLOW}[4/7] Configuring cron...${NC}"

# Проверяем наличие crontab файла
if [ -f "/etc/crontabs/${UGN}" ]; then
    # Устанавливаем правильные права
    chmod 600 "/etc/crontabs/${UGN}"
    chown "${UGN}:${UGN}" "/etc/crontabs/${UGN}"

    # Проверяем содержимое
    if [ -s "/etc/crontabs/${UGN}" ]; then
        echo -e "${GREEN}  ✓ Crontab configured for user ${UGN}${NC}"
        echo -e "${BLUE}  Crontab contents:${NC}"
        cat "/etc/crontabs/${UGN}" | grep -v "^#" | grep -v "^$" | sed 's/^/    /'
    else
        echo -e "${YELLOW}  ⚠ Crontab file is empty${NC}"
    fi
else
    echo -e "${YELLOW}  ⚠ Crontab file not found, creating empty...${NC}"
    touch "/etc/crontabs/${UGN}"
    chmod 600 "/etc/crontabs/${UGN}"
    chown "${UGN}:${UGN}" "/etc/crontabs/${UGN}"
fi

echo -e "${GREEN}  ✓ Cron configured${NC}"

# ============================================================================
# ПРОВЕРКА ПОДКЛЮЧЕНИЯ К БАЗЕ ДАННЫХ
# ============================================================================
echo -e "${YELLOW}[5/7] Checking database connection...${NC}"

DB_HOST="${DB_HOST:-mysql}"
DB_PORT="${DB_PORT:-3306}"
MAX_TRIES=30
COUNT=0

# Ждем доступности MySQL
while [ $COUNT -lt $MAX_TRIES ]; do
    if nc -z "${DB_HOST}" "${DB_PORT}" 2>/dev/null; then
        echo -e "${GREEN}  ✓ Database is available at ${DB_HOST}:${DB_PORT}${NC}"
        break
    fi

    COUNT=$((COUNT + 1))
    if [ $COUNT -eq $MAX_TRIES ]; then
        echo -e "${RED}  ✗ Database is not available after ${MAX_TRIES} attempts${NC}"
        echo -e "${YELLOW}  ⚠ Continuing anyway...${NC}"
    else
        echo -e "${YELLOW}  ⏳ Waiting for database... (${COUNT}/${MAX_TRIES})${NC}"
        sleep 2
    fi
done

# ============================================================================
# ПРОВЕРКА ПОДКЛЮЧЕНИЯ К REDIS
# ============================================================================
echo -e "${YELLOW}[6/7] Checking Redis connection...${NC}"

REDIS_HOST="${REDIS_HOST:-redis}"
REDIS_PORT="${REDIS_PORT:-6379}"
MAX_TRIES=15
COUNT=0

# Ждем доступности Redis
while [ $COUNT -lt $MAX_TRIES ]; do
    if nc -z "${REDIS_HOST}" "${REDIS_PORT}" 2>/dev/null; then
        echo -e "${GREEN}  ✓ Redis is available at ${REDIS_HOST}:${REDIS_PORT}${NC}"
        break
    fi

    COUNT=$((COUNT + 1))
    if [ $COUNT -eq $MAX_TRIES ]; then
        echo -e "${YELLOW}  ⚠ Redis is not available after ${MAX_TRIES} attempts${NC}"
        echo -e "${YELLOW}  ⚠ Continuing anyway...${NC}"
        break
    else
        echo -e "${YELLOW}  ⏳ Waiting for Redis... (${COUNT}/${MAX_TRIES})${NC}"
        sleep 1
    fi
done

# ============================================================================
# COMPOSER (только для dev/local окружения)
# ============================================================================
echo -e "${YELLOW}[7/7] Checking Composer...${NC}"

if [ "${ENVIRONMENT}" != "prod" ] && [ "${ENVIRONMENT}" != "production" ]; then
    if [ -f "/home/${UGN}/app/composer.json" ]; then
        echo -e "${BLUE}  Composer dependencies found${NC}"
        # Не устанавливаем автоматически, оставляем на усмотрение разработчика
        # cd "/home/${UGN}/app" && composer install --no-interaction --prefer-dist
    fi
fi

echo -e "${GREEN}  ✓ Composer checked${NC}"

# ============================================================================
# ЗАПУСК ПЕРЕДАННОЙ КОМАНДЫ
# ============================================================================
echo ""
echo -e "${BLUE}============================================================================${NC}"
echo -e "${GREEN}✓ Initialization complete!${NC}"
echo -e "${BLUE}============================================================================${NC}"
echo -e "${YELLOW}Starting: $@${NC}"
echo ""

# Запускаем команду переданную в CMD
exec "$@"
