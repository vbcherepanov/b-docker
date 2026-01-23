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

# System directories (NOT in www/)
SYSTEM_DIRS=(
    "/home/${UGN}/tmp"
    "/var/log/php"
    "/var/log/php-fpm"
    "/var/log/cron"
    "/var/log/supervisor"
    "/var/log/bitrix"
    "/var/lib/php/sessions"
)

for dir in "${SYSTEM_DIRS[@]}"; do
    if [ ! -d "$dir" ]; then
        echo -e "  ${YELLOW}Creating directory: $dir${NC}"
        mkdir -p "$dir"
    fi
done

# Multisite: create directories INSIDE each domain folder, NOT in root www/
# Structure: /home/bitrix/app/{domain}/www/bitrix/cache, /home/bitrix/app/{domain}/www/upload, etc.
APP_DIR="/home/${UGN}/app"
if [ -d "$APP_DIR" ]; then
    for domain_dir in "$APP_DIR"/*/; do
        if [ -d "$domain_dir" ]; then
            domain=$(basename "$domain_dir")
            site_www="$domain_dir/www"

            # Only process valid domain folders (those with www/ subdirectory)
            if [ -d "$site_www" ]; then
                echo -e "  ${BLUE}Checking site: $domain${NC}"

                # Create required Bitrix directories inside each site
                for subdir in "bitrix/cache" "bitrix/managed_cache" "upload" "local"; do
                    target="$site_www/$subdir"
                    if [ ! -d "$target" ]; then
                        echo -e "    ${YELLOW}Creating: $subdir${NC}"
                        mkdir -p "$target"
                    fi
                done
            fi
        fi
    done
fi

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

# Multisite: set permissions for each site's directories
# ВАЖНО: 775 вместо 777 для безопасности
# Владелец bitrix имеет полный доступ, группа тоже, остальные только чтение+execute
APP_DIR="/home/${UGN}/app"
if [ -d "$APP_DIR" ]; then
    for domain_dir in "$APP_DIR"/*/; do
        if [ -d "$domain_dir" ]; then
            site_www="$domain_dir/www"
            if [ -d "$site_www" ]; then
                # Set permissions for Bitrix writable directories
                for subdir in "upload" "bitrix/cache" "bitrix/managed_cache"; do
                    target="$site_www/$subdir"
                    if [ -d "$target" ]; then
                        chmod -R 775 "$target" 2>/dev/null || true
                    fi
                done
            fi
        fi
    done
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

# Версионные настройки PHP
case "${PHP_VERSION}" in
    7.4)
        # PHP 7.4: все legacy настройки
        cat >> "${VERSION_INI}" <<EOF

; mbstring internal encoding (required for PHP 7.4)
mbstring.internal_encoding = UTF-8

; Session ID settings for enhanced security
session.sid_length = 48
session.sid_bits_per_character = 6
EOF
        echo -e "${GREEN}  ✓ Added PHP 7.4 settings${NC}"
        ;;
    8.0|8.1|8.2|8.3)
        # PHP 8.0-8.3: mbstring deprecated, session.sid settings work
        cat >> "${VERSION_INI}" <<EOF

; mbstring.internal_encoding is deprecated in PHP 8.0+, UTF-8 is default
; Session ID settings for enhanced security (deprecated in PHP 8.4)
session.sid_length = 48
session.sid_bits_per_character = 6
EOF
        echo -e "${GREEN}  ✓ Added PHP ${PHP_VERSION} settings${NC}"
        ;;
    8.4|8.5|9.*)
        # PHP 8.4+: все эти настройки deprecated/removed
        cat >> "${VERSION_INI}" <<EOF

; PHP ${PHP_VERSION}: using modern defaults
; - mbstring uses UTF-8 by default
; - session IDs are generated securely by default
EOF
        echo -e "${GREEN}  ✓ Using modern defaults for PHP ${PHP_VERSION}${NC}"
        ;;
    *)
        echo -e "${YELLOW}  ⚠ Unknown PHP version ${PHP_VERSION}, using safe defaults${NC}"
        ;;
esac

echo -e "${GREEN}  ✓ Version-specific settings configured${NC}"

# ============================================================================
# НАСТРОЙКА CRON (base + per-site crontabs)
# ============================================================================
echo -e "${YELLOW}[5/12] Configuring cron...${NC}"

# NOTE: dcron in Alpine requires root crontab for reliable execution
# Base crontab is mounted read-only to /etc/crontabs/root.base
# Per-site crontabs are in /etc/bitrix-sites/{domain}/crontab
# We merge them into /etc/crontabs/root at startup

CRONTAB_BASE="/etc/crontabs/root.base"
CRONTAB_TARGET="/etc/crontabs/root"
SITES_CRONTAB_DIR="/etc/bitrix-sites"

if [ -f "$CRONTAB_BASE" ]; then
    # Start with base crontab
    cp "$CRONTAB_BASE" "$CRONTAB_TARGET"

    # Append per-site crontabs
    SITE_CRON_COUNT=0
    if [ -d "$SITES_CRONTAB_DIR" ]; then
        for site_crontab in "$SITES_CRONTAB_DIR"/*/crontab; do
            if [ -f "$site_crontab" ] && [ -s "$site_crontab" ]; then
                site_domain=$(basename "$(dirname "$site_crontab")")
                echo "" >> "$CRONTAB_TARGET"
                echo "# === PER-SITE CRON: $site_domain ===" >> "$CRONTAB_TARGET"
                cat "$site_crontab" >> "$CRONTAB_TARGET"
                SITE_CRON_COUNT=$((SITE_CRON_COUNT + 1))
                echo -e "${BLUE}  + Added crontab for: $site_domain${NC}"
            fi
        done
    fi

    # Set permissions
    chmod 600 "$CRONTAB_TARGET"
    chown root:root "$CRONTAB_TARGET"

    # Summary
    CRON_TASKS=$(grep -v "^#" "$CRONTAB_TARGET" | grep -v "^$" | grep -v "run-parts" | wc -l)
    echo -e "${GREEN}  ✓ Crontab merged (base + ${SITE_CRON_COUNT} site crontabs)${NC}"
    echo -e "${BLUE}  Active tasks: ${CRON_TASKS}${NC}"
else
    echo -e "${YELLOW}  ⚠ Base crontab not found at $CRONTAB_BASE${NC}"
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
# НАСТРОЙКА PUSH SERVER (автоматическая конфигурация из ENV)
# ============================================================================
echo -e "${YELLOW}[9/13] Configuring Push Server...${NC}"

if [ -n "${PUSH_SECURITY_KEY}" ]; then
    export APP_ROOT="/home/${UGN}/app"
    if [ -f "/home/${UGN}/app/bitrix/.settings.php" ]; then
        php /usr/local/bin/scripts/configure-push.php
        echo -e "${GREEN}  ✓ Push server configured${NC}"
    else
        echo -e "${YELLOW}  ⚠ Bitrix not installed, skipping push configuration${NC}"
    fi
else
    echo -e "${YELLOW}  ⚠ PUSH_SECURITY_KEY not set, skipping push configuration${NC}"
fi

# ============================================================================
# COMPOSER (только для dev/local окружения)
# ============================================================================
echo -e "${YELLOW}[10/13] Checking Composer...${NC}"

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
echo -e "${YELLOW}[11/13] Configuring /etc/hosts for nginx access...${NC}"

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
echo -e "${YELLOW}[12/13] Configuring session.cookie_secure...${NC}"

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
echo -e "${YELLOW}[13/13] Adding internal SSL certificate to trusted CA...${NC}"

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
