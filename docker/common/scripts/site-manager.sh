#!/bin/bash

set -euo pipefail

# Функция логирования
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# Функция показа помощи
show_help() {
    cat << EOF
Управление сайтами в Bitrix Docker Environment

Использование:
    $0 add <domain> [php_version]     - Добавить новый сайт
    $0 remove <domain>                - Удалить сайт
    $0 list                          - Показать список сайтов
    $0 ssl <domain> <action>         - Управление SSL сертификатами

Примеры:
    $0 add example.com 8.3           - Добавить сайт с PHP 8.3
    $0 add test.local                - Добавить сайт с PHP по умолчанию
    $0 remove old.local              - Удалить сайт
    $0 ssl example.com generate      - Создать SSL сертификат
    $0 ssl example.com remove        - Удалить SSL сертификат

Переменные окружения:
    ENVIRONMENT - окружение (local/dev/prod)
    UGN - пользователь (по умолчанию: bitrix)
    PHP_VERSION - версия PHP по умолчанию (7.4 или 8.3)
EOF
}

# Получение переменных окружения
ENVIRONMENT=${ENVIRONMENT:-local}
UGN=${UGN:-bitrix}
DEFAULT_PHP_VERSION=${PHP_VERSION:-8.3}

# Директории
WWW_DIR="./www"
CONFIG_DIR="./config/nginx/conf"
SSL_DIR="./config/ssl"

# Создание директорий если их нет
mkdir -p "$WWW_DIR" "$CONFIG_DIR" "$SSL_DIR"

# Функция получения списка сайтов
get_sites_list() {
    if [ -d "$WWW_DIR" ]; then
        find "$WWW_DIR" -maxdepth 1 -type d ! -name "." ! -name "www" | sed 's|./www/||' | sort
    fi
}

# Функция добавления сайта
add_site() {
    local domain="$1"
    local php_version="${2:-$DEFAULT_PHP_VERSION}"

    if [ -z "$domain" ]; then
        log "ОШИБКА: Не указан домен"
        exit 1
    fi

    # Проверка версии PHP
    if [[ "$php_version" != "7.4" && "$php_version" != "8.3" ]]; then
        log "ОШИБКА: Поддерживаются только версии PHP 7.4 и 8.3"
        exit 1
    fi

    local site_dir="$WWW_DIR/$domain"
    local nginx_conf="$CONFIG_DIR/${domain}.conf"

    # Проверка существования сайта
    if [ -d "$site_dir" ]; then
        log "ПРЕДУПРЕЖДЕНИЕ: Сайт $domain уже существует"
        return 0
    fi

    log "Создание сайта $domain с PHP $php_version"

    # Создание директории сайта
    mkdir -p "$site_dir/www"

    # Создание простого index.php
    cat > "$site_dir/www/index.php" << EOF
<?php
phpinfo();
echo "<h1>Сайт $domain работает!</h1>";
echo "<p>PHP версия: " . PHP_VERSION . "</p>";
echo "<p>Текущее время: " . date('Y-m-d H:i:s') . "</p>";
?>
EOF

    # Создание конфигурации Nginx
    cat > "$nginx_conf" << EOF
server {
    listen 8080;
    server_name $domain;
    root /home/\$UGN/app/$domain/www;
    index index.php index.html;

    # Логи
    access_log /var/log/nginx/${domain}_access.log;
    error_log /var/log/nginx/${domain}_error.log;

    # Основная обработка
    location / {
        try_files \$uri \$uri/ /index.php?\$args;
    }

    # Обработка PHP
    location ~ \.php\$ {
        include fastcgi_params;
        fastcgi_pass php${php_version//.}-fpm:9000;
        fastcgi_index index.php;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
    }

    # Безопасность
    location ~ /\. {
        deny all;
    }

    # Bitrix специфичные настройки
    location ~* ^.+\.(jpg|jpeg|gif|png|svg|js|css|mp3|ogg|mpe?g|avi|zip|gz|bz2?|rar|swf)\$ {
        expires 30d;
        add_header Cache-Control "public, immutable";
    }
}
EOF

    # Если SSL включен, создаем SSL конфигурацию
    if [ "${SSL:-0}" != "0" ]; then
        cat > "$CONFIG_DIR/ssl_${domain}.conf" << EOF
server {
    listen 8443 ssl http2;
    server_name $domain;
    root /home/\$UGN/app/$domain/www;
    index index.php index.html;

    # SSL сертификаты
    ssl_certificate /etc/ssl/certs/${domain}.crt;
    ssl_certificate_key /etc/ssl/private/${domain}.key;

    # SSL настройки
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-RSA-AES256-GCM-SHA512:DHE-RSA-AES256-GCM-SHA512:ECDHE-RSA-AES256-GCM-SHA384;
    ssl_prefer_server_ciphers off;

    # Остальные настройки как в HTTP версии
    include /etc/nginx/conf.d/${domain}.conf;
}
EOF
    fi

    log "Сайт $domain успешно создан"
    log "Директория: $site_dir"
    log "Конфигурация Nginx: $nginx_conf"
    log "Не забудьте перезапустить контейнеры: make restart-${ENVIRONMENT}"
}

# Функция удаления сайта
remove_site() {
    local domain="$1"

    if [ -z "$domain" ]; then
        log "ОШИБКА: Не указан домен"
        exit 1
    fi

    local site_dir="$WWW_DIR/$domain"
    local nginx_conf="$CONFIG_DIR/${domain}.conf"
    local ssl_conf="$CONFIG_DIR/ssl_${domain}.conf"

    if [ ! -d "$site_dir" ]; then
        log "ПРЕДУПРЕЖДЕНИЕ: Сайт $domain не найден"
        return 0
    fi

    read -p "Вы уверены, что хотите удалить сайт $domain? [y/N]: " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log "Отмена удаления"
        return 0
    fi

    log "Удаление сайта $domain"

    # Удаление директории сайта
    rm -rf "$site_dir"

    # Удаление конфигураций Nginx
    [ -f "$nginx_conf" ] && rm -f "$nginx_conf"
    [ -f "$ssl_conf" ] && rm -f "$ssl_conf"

    # Удаление SSL сертификатов
    [ -f "$SSL_DIR/${domain}.crt" ] && rm -f "$SSL_DIR/${domain}.crt"
    [ -f "$SSL_DIR/${domain}.key" ] && rm -f "$SSL_DIR/${domain}.key"

    log "Сайт $domain успешно удален"
    log "Не забудьте перезапустить контейнеры: make restart-${ENVIRONMENT}"
}

# Функция вывода списка сайтов
list_sites() {
    log "Список сайтов:"
    local sites=$(get_sites_list)

    if [ -z "$sites" ]; then
        log "Сайты не найдены"
        return 0
    fi

    echo "Domain | Directory | Nginx Config | SSL Config"
    echo "-------|-----------|--------------|------------"

    while IFS= read -r site; do
        local nginx_conf="$CONFIG_DIR/${site}.conf"
        local ssl_conf="$CONFIG_DIR/ssl_${site}.conf"
        local nginx_status="❌"
        local ssl_status="❌"

        [ -f "$nginx_conf" ] && nginx_status="✅"
        [ -f "$ssl_conf" ] && ssl_status="✅"

        printf "%-20s | %-20s | %-10s | %-10s\n" "$site" "$WWW_DIR/$site" "$nginx_status" "$ssl_status"
    done <<< "$sites"
}

# Функция управления SSL
manage_ssl() {
    local domain="$1"
    local action="$2"

    if [ -z "$domain" ] || [ -z "$action" ]; then
        log "ОШИБКА: Необходимо указать домен и действие"
        exit 1
    fi

    case "$action" in
        "generate")
            generate_ssl_cert "$domain"
            ;;
        "remove")
            remove_ssl_cert "$domain"
            ;;
        *)
            log "ОШИБКА: Неизвестное действие $action. Доступны: generate, remove"
            exit 1
            ;;
    esac
}

# Функция генерации самоподписанного SSL сертификата
generate_ssl_cert() {
    local domain="$1"
    local cert_file="$SSL_DIR/${domain}.crt"
    local key_file="$SSL_DIR/${domain}.key"

    log "Генерация самоподписанного SSL сертификата для $domain"

    openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
        -keyout "$key_file" \
        -out "$cert_file" \
        -subj "/C=RU/ST=Moscow/L=Moscow/O=BitrixDev/CN=$domain"

    chmod 600 "$key_file"
    chmod 644 "$cert_file"

    log "SSL сертификат создан:"
    log "  Сертификат: $cert_file"
    log "  Ключ: $key_file"
}

# Функция удаления SSL сертификата
remove_ssl_cert() {
    local domain="$1"
    local cert_file="$SSL_DIR/${domain}.crt"
    local key_file="$SSL_DIR/${domain}.key"

    log "Удаление SSL сертификата для $domain"

    [ -f "$cert_file" ] && rm -f "$cert_file"
    [ -f "$key_file" ] && rm -f "$key_file"

    log "SSL сертификат удален"
}

# Основная логика
case "${1:-}" in
    "add")
        add_site "${2:-}" "${3:-}"
        ;;
    "remove")
        remove_site "${2:-}"
        ;;
    "list")
        list_sites
        ;;
    "ssl")
        manage_ssl "${2:-}" "${3:-}"
        ;;
    "help"|"--help"|"-h")
        show_help
        ;;
    *)
        log "ОШИБКА: Неизвестная команда"
        echo
        show_help
        exit 1
        ;;
esac