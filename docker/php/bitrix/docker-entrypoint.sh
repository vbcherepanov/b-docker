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
echo -e "${YELLOW}[1/9] Checking directories...${NC}"

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
    "/var/lib/php/sessions"
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
echo -e "${YELLOW}[2/9] Setting up permissions...${NC}"

# Изменяем владельца файлов приложения для совместимости с macOS
if [ -d "/home/${UGN}/app" ]; then
    echo -e "${BLUE}  ⏳ Changing ownership of /home/${UGN}/app to ${UGN}...${NC}"
    chown -R "${UGN}:${UGN}" "/home/${UGN}/app" 2>/dev/null || true
    echo -e "${GREEN}  ✓ Ownership changed${NC}"
fi

# Битрикс требует специфичные права на некоторые директории
# ВАЖНО: 775 вместо 777 для безопасности
# Владелец bitrix имеет полный доступ, группа тоже, остальные только чтение+execute
if [ -d "/home/${UGN}/app/upload" ]; then
    chmod -R 775 "/home/${UGN}/app/upload" 2>/dev/null || true
fi

if [ -d "/home/${UGN}/app/bitrix/cache" ]; then
    chmod -R 775 "/home/${UGN}/app/bitrix/cache" 2>/dev/null || true
fi

if [ -d "/home/${UGN}/app/bitrix/managed_cache" ]; then
    chmod -R 775 "/home/${UGN}/app/bitrix/managed_cache" 2>/dev/null || true
fi

# Логи должны быть доступны для записи
chown -R "${UGN}:${UGN}" \
    "/var/log/php" \
    "/var/log/php-fpm" \
    "/var/log/bitrix" \
    2>/dev/null || true

# Supervisor логи
chown -R "${UGN}:${UGN}" "/var/log/supervisor" 2>/dev/null || true

# PHP Sessions - критично для работы Битрикс
# 770 - только владелец и группа имеют доступ (безопасность)
if [ -d "/var/lib/php/sessions" ]; then
    chown -R "${UGN}:${UGN}" "/var/lib/php/sessions" 2>/dev/null || true
    chmod 770 "/var/lib/php/sessions" 2>/dev/null || true
fi

echo -e "${GREEN}  ✓ Permissions configured${NC}"

# ============================================================================
# НАСТРОЙКА PHP-FPM
# ============================================================================
echo -e "${YELLOW}[3/9] Configuring PHP-FPM...${NC}"

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
# ВЕРСИОННЫЕ НАСТРОЙКИ PHP (совместимость 7.4, 8.3, 8.4)
# ============================================================================
echo -e "${YELLOW}[4/12] Configuring PHP version-specific settings...${NC}"

# Получаем версию PHP
PHP_VERSION=$(php -r "echo PHP_MAJOR_VERSION.'.'.PHP_MINOR_VERSION;")
echo -e "${BLUE}  PHP Version detected: ${PHP_VERSION}${NC}"

# Создаем версионный конфиг
VERSION_INI="/usr/local/etc/php/conf.d/00-version-compat.ini"

cat > "${VERSION_INI}" <<EOF
; =============================================================================
; PHP VERSION-SPECIFIC SETTINGS
; Auto-generated for PHP ${PHP_VERSION}
; =============================================================================
EOF

# PHP 7.4 и 8.0-8.3: включаем настройки которые deprecated в 8.4
case "${PHP_VERSION}" in
    7.4|8.0|8.1|8.2|8.3)
        cat >> "${VERSION_INI}" <<EOF

; mbstring internal encoding (deprecated in PHP 8.0+ but still works until 8.4)
mbstring.internal_encoding = UTF-8

; Session ID settings for enhanced security (deprecated in PHP 8.4)
session.sid_length = 48
session.sid_bits_per_character = 6
EOF
        echo -e "${GREEN}  ✓ Added legacy settings for PHP ${PHP_VERSION}${NC}"
        ;;
    8.4|8.5|9.*)
        cat >> "${VERSION_INI}" <<EOF

; PHP ${PHP_VERSION}: mbstring.internal_encoding, session.sid_length,
; session.sid_bits_per_character are deprecated/removed
; Using PHP defaults (UTF-8, secure session IDs)
EOF
        echo -e "${GREEN}  ✓ Using modern defaults for PHP ${PHP_VERSION}${NC}"
        ;;
    *)
        echo -e "${YELLOW}  ⚠ Unknown PHP version ${PHP_VERSION}, using safe defaults${NC}"
        ;;
esac

echo -e "${GREEN}  ✓ Version-specific settings configured${NC}"

# ============================================================================
# НАСТРОЙКА CRON
# ============================================================================
echo -e "${YELLOW}[5/12] Configuring cron...${NC}"

# NOTE: dcron in Alpine requires root crontab for reliable execution
# Crontab is mounted to /etc/crontabs/root via docker-compose
if [ -f "/etc/crontabs/root" ]; then
    # Устанавливаем правильные права для root crontab
    chmod 600 "/etc/crontabs/root"
    chown root:root "/etc/crontabs/root"

    # Проверяем содержимое
    if [ -s "/etc/crontabs/root" ]; then
        echo -e "${GREEN}  ✓ Root crontab configured${NC}"
        CRON_TASKS=$(cat "/etc/crontabs/root" | grep -v "^#" | grep -v "^$" | grep -v "run-parts" | wc -l)
        echo -e "${BLUE}  Active Bitrix tasks: ${CRON_TASKS}${NC}"
    else
        echo -e "${YELLOW}  ⚠ Crontab file is empty${NC}"
    fi
else
    echo -e "${YELLOW}  ⚠ Root crontab file not found${NC}"
fi

echo -e "${GREEN}  ✓ Cron configured${NC}"

# ============================================================================
# НАСТРОЙКА MSMTP (для отправки почты)
# ============================================================================
echo -e "${YELLOW}[6/12] Configuring msmtp...${NC}"

if [ -f "/etc/msmtprc" ]; then
    # msmtp требует чтобы конфиг с паролем принадлежал запускающему пользователю
    chown "${UGN}:${UGN}" /etc/msmtprc 2>/dev/null || true
    chmod 600 /etc/msmtprc 2>/dev/null || true
    echo -e "${GREEN}  ✓ msmtp configured for user ${UGN}${NC}"
else
    echo -e "${YELLOW}  ⚠ msmtprc not found, mail may not work${NC}"
fi

# ============================================================================
# ПРОВЕРКА ПОДКЛЮЧЕНИЯ К БАЗЕ ДАННЫХ
# ============================================================================
echo -e "${YELLOW}[7/12] Checking database connection...${NC}"

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
echo -e "${YELLOW}[8/12] Checking Redis connection...${NC}"

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
echo -e "${YELLOW}[9/12] Checking Composer...${NC}"

if [ "${ENVIRONMENT}" != "prod" ] && [ "${ENVIRONMENT}" != "production" ]; then
    if [ -f "/home/${UGN}/app/composer.json" ]; then
        echo -e "${BLUE}  Composer dependencies found${NC}"
        # Не устанавливаем автоматически, оставляем на усмотрение разработчика
        # cd "/home/${UGN}/app" && composer install --no-interaction --prefer-dist
    fi
fi

echo -e "${GREEN}  ✓ Composer checked${NC}"

# ============================================================================
# НАСТРОЙКА /etc/hosts ДЛЯ NGINX
# ============================================================================
echo -e "${YELLOW}[10/12] Configuring /etc/hosts for nginx access...${NC}"

# Небольшая задержка для инициализации Docker DNS
sleep 2

# Ждем доступности nginx контейнера
MAX_TRIES=30
COUNT=0
NGINX_IP=""

while [ $COUNT -lt $MAX_TRIES ]; do
    NGINX_IP=$(getent hosts nginx 2>/dev/null | awk '{ print $1 }')

    if [ -n "$NGINX_IP" ]; then
        echo -e "${GREEN}  ✓ Nginx container found at ${NGINX_IP}${NC}"
        break
    fi

    COUNT=$((COUNT + 1))
    if [ $COUNT -eq $MAX_TRIES ]; then
        echo -e "${YELLOW}  ⚠ Nginx container not found after ${MAX_TRIES} attempts (${COUNT} seconds)${NC}"
        echo -e "${YELLOW}  ⚠ Skipping /etc/hosts update${NC}"
        break
    else
        if [ $((COUNT % 5)) -eq 0 ]; then
            echo -e "${YELLOW}  ⏳ Waiting for nginx... (${COUNT}/${MAX_TRIES})${NC}"
        fi
        sleep 1
    fi
done

# Обновляем /etc/hosts если нашли nginx
if [ -n "$NGINX_IP" ]; then
    # Docker /etc/hosts is bind-mounted and can't use sed -i
    # Use grep to filter and write to temp file, then cat back
    grep -v 'bitrix\.local' /etc/hosts | grep -v "${DOMAIN}" | grep -v 'mailhog' > /tmp/hosts.tmp || true
    cat /tmp/hosts.tmp > /etc/hosts

    # Добавляем записи для локального доступа и основного домена
    echo "$NGINX_IP bitrix.local" >> /etc/hosts
    echo "$NGINX_IP ${DOMAIN}" >> /etc/hosts

    # Добавляем mailhog для корректной работы почты
    MAILHOG_IP=$(getent hosts mailhog 2>/dev/null | awk '{ print $1 }')
    if [ -n "$MAILHOG_IP" ]; then
        echo "$MAILHOG_IP mailhog" >> /etc/hosts
        echo -e "${GREEN}  ✓ Added mailhog IP ($MAILHOG_IP) to /etc/hosts${NC}"
    fi

    rm -f /tmp/hosts.tmp

    echo -e "${GREEN}  ✓ Added nginx IP ($NGINX_IP) to /etc/hosts as bitrix.local and ${DOMAIN}${NC}"
fi

# ============================================================================
# АВТОГЕНЕРАЦИЯ session.cookie_secure НА ОСНОВЕ SSL
# ============================================================================
echo -e "${YELLOW}[11/12] Configuring session.cookie_secure...${NC}"

SESSION_SECURE="Off"
if [ "$SSL" = "1" ] || [ "$SSL" = "2" ]; then
    SESSION_SECURE="On"
    echo -e "${GREEN}  ✓ SSL enabled (SSL=$SSL), setting session.cookie_secure=On${NC}"
else
    echo -e "${YELLOW}  ⚠ SSL disabled (SSL=$SSL), setting session.cookie_secure=Off${NC}"
fi

# Создаем конфиг файл с правильным значением
cat > /usr/local/etc/php/conf.d/99-session-security.ini <<EOF
; Auto-generated session security settings based on SSL=${SSL}
session.cookie_secure = ${SESSION_SECURE}
EOF

echo -e "${GREEN}  ✓ Session security configured: session.cookie_secure=${SESSION_SECURE}${NC}"

# ============================================================================
# ДОБАВЛЕНИЕ ВНУТРЕННЕГО SSL СЕРТИФИКАТА В ДОВЕРЕННЫЕ
# ============================================================================
echo -e "${YELLOW}[12/12] Adding internal SSL certificate to trusted CA...${NC}"

# Только если SSL включён
if [ "$SSL" = "0" ] || [ -z "$SSL" ]; then
    echo -e "${YELLOW}  ⚠ SSL disabled (SSL=$SSL), skipping certificate trust setup${NC}"
elif [ -n "$NGINX_IP" ]; then
    MAX_TRIES=30
    COUNT=0
    CERT_ADDED=false

    while [ $COUNT -lt $MAX_TRIES ]; do
        # Пытаемся получить сертификат от nginx
        NGINX_CERT=$(echo | timeout 5 openssl s_client -connect "${NGINX_IP}:443" -servername "${DOMAIN}" 2>/dev/null | openssl x509 2>/dev/null)

        if [ -n "$NGINX_CERT" ]; then
            # Добавляем сертификат в CA bundle PHP
            echo "$NGINX_CERT" >> /etc/ssl/cert.pem
            echo -e "${GREEN}  ✓ Internal nginx SSL certificate added to PHP CA bundle${NC}"
            CERT_ADDED=true
            break
        fi

        COUNT=$((COUNT + 1))
        if [ $COUNT -eq $MAX_TRIES ]; then
            echo -e "${YELLOW}  ⚠ Could not get nginx SSL certificate after ${MAX_TRIES} attempts${NC}"
        else
            if [ $((COUNT % 10)) -eq 0 ]; then
                echo -e "${YELLOW}  ⏳ Waiting for nginx SSL... (${COUNT}/${MAX_TRIES})${NC}"
            fi
            sleep 1
        fi
    done
else
    echo -e "${YELLOW}  ⚠ Nginx IP not found, skipping SSL certificate trust${NC}"
fi

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
