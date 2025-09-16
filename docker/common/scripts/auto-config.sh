#!/bin/bash

set -euo pipefail

# Функция логирования
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# Функция показа помощи
show_help() {
    cat << EOF
Автоматическая конфигурация Bitrix Docker Environment

Анализирует характеристики системы (CPU, RAM, диск) и создает
оптимальные конфигурационные файлы для всех сервисов.

Использование:
    $0 [options]

Опции:
    --cpu-cores N       - Принудительно указать количество ядер CPU
    --ram-gb N          - Принудительно указать объем RAM в GB
    --environment ENV   - Окружение (local/dev/prod), по умолчанию: local
    --force             - Перезаписать существующие конфигурации
    --dry-run           - Показать что будет сделано, но не выполнять
    -h, --help          - Показать эту справку

Примеры:
    $0                                    # Автодетект и генерация для local
    $0 --environment prod                 # Автодетект и генерация для prod
    $0 --cpu-cores 8 --ram-gb 16 --force # Принудительно для 8 CPU/16GB RAM
    $0 --dry-run                          # Предварительный просмотр

Генерируемые конфигурации:
    - config/mysql/my.conf               # MySQL/MariaDB
    - config/nginx/nginx.conf            # Nginx основной
    - config/redis/redis.conf            # Redis
    - config/memcached/memcached.conf    # Memcached
    - docker/common/php/php.ini.template # PHP-FPM
    - .env                               # Переменные окружения
EOF
}

# Получение характеристик системы
detect_system_specs() {
    local cpu_cores
    local ram_gb
    local disk_free_gb

    # Определение количества ядер CPU
    if command -v nproc >/dev/null 2>&1; then
        cpu_cores=$(nproc)
    elif [ -f /proc/cpuinfo ]; then
        cpu_cores=$(grep -c "^processor" /proc/cpuinfo)
    elif command -v sysctl >/dev/null 2>&1; then
        cpu_cores=$(sysctl -n hw.ncpu 2>/dev/null || echo "4")
    else
        cpu_cores=4
    fi

    # Определение объема RAM (в GB)
    if [ -f /proc/meminfo ]; then
        local ram_kb=$(grep "MemTotal:" /proc/meminfo | awk '{print $2}')
        ram_gb=$((ram_kb / 1024 / 1024))
    elif command -v sysctl >/dev/null 2>&1; then
        local ram_bytes=$(sysctl -n hw.memsize 2>/dev/null || echo "4294967296")
        ram_gb=$((ram_bytes / 1024 / 1024 / 1024))
    else
        ram_gb=4
    fi

    # Определение свободного места на диске (в GB)
    disk_free_gb=$(df . | tail -1 | awk '{print int($4/1024/1024)}')

    echo "$cpu_cores $ram_gb $disk_free_gb"
}

# Генерация конфигурации MySQL
generate_mysql_config() {
    local cpu_cores="$1"
    local ram_gb="$2"
    local environment="$3"
    local output_file="$4"

    # Расчет параметров на основе RAM
    local innodb_buffer_pool_size=$((ram_gb * 1024 * 60 / 100))  # 60% от RAM
    local max_connections=$((cpu_cores * 50))                    # 50 соединений на ядро
    local query_cache_size=$((ram_gb * 1024 * 5 / 100))         # 5% от RAM
    local key_buffer_size=$((ram_gb * 1024 * 10 / 100))         # 10% от RAM
    local sort_buffer_size=$((ram_gb > 8 ? 4 : 2))              # 2-4MB в зависимости от RAM
    local join_buffer_size=$((ram_gb > 8 ? 4 : 2))              # 2-4MB в зависимости от RAM

    # Корректировка для разных окружений
    case "$environment" in
        "local")
            innodb_buffer_pool_size=$((innodb_buffer_pool_size / 2))  # Меньше для локальной разработки
            max_connections=$((max_connections / 2))
            ;;
        "dev")
            innodb_buffer_pool_size=$((innodb_buffer_pool_size * 75 / 100))
            ;;
        "prod")
            # Используем полные значения
            ;;
    esac

    # Минимальные ограничения
    [ "$innodb_buffer_pool_size" -lt 128 ] && innodb_buffer_pool_size=128
    [ "$max_connections" -lt 50 ] && max_connections=50
    [ "$query_cache_size" -lt 16 ] && query_cache_size=16
    [ "$key_buffer_size" -lt 32 ] && key_buffer_size=32

    cat > "$output_file" << EOF
# Автоматически сгенерированная конфигурация MySQL
# Системные характеристики: ${cpu_cores} CPU cores, ${ram_gb}GB RAM
# Окружение: ${environment}
# Дата генерации: $(date)

[mysqld]
bind-address = 0.0.0.0
default-time-zone = "+00:00"

# InnoDB настройки
innodb_strict_mode = OFF
innodb_file_per_table = 1
innodb_flush_log_at_trx_commit = 2
innodb_flush_method = O_DIRECT
innodb_buffer_pool_size = ${innodb_buffer_pool_size}M
innodb_log_file_size = 256M
innodb_log_buffer_size = 16M
innodb_lock_wait_timeout = 120

# Общие настройки производительности
max_connections = ${max_connections}
query_cache_size = ${query_cache_size}M
query_cache_type = 1
key_buffer_size = ${key_buffer_size}M
sort_buffer_size = ${sort_buffer_size}M
join_buffer_size = ${join_buffer_size}M
read_buffer_size = 2M
read_rnd_buffer_size = 8M
thread_cache_size = $((cpu_cores * 2))
thread_stack = 256K
table_open_cache = $((max_connections * 2))

# Настройки для Bitrix
transaction-isolation = READ-COMMITTED
binlog_cache_size = 0
sql_mode = ""
skip-log-bin
general_log = 0

# Кодировка
character-set-server = utf8mb4
collation-server = utf8mb4_unicode_ci
init-connect = "SET NAMES utf8mb4"

# Лимиты
max_allowed_packet = 256M
tmp_table_size = 64M
max_heap_table_size = 64M

# Медленные запросы (только для dev/local)
EOF

    if [ "$environment" != "prod" ]; then
        cat >> "$output_file" << EOF
slow_query_log = 1
slow_query_log_file = /var/log/mysql/slow.log
long_query_time = 2
EOF
    fi
}

# Генерация конфигурации Nginx
generate_nginx_config() {
    local cpu_cores="$1"
    local ram_gb="$2"
    local environment="$3"
    local output_file="$4"

    local worker_processes="$cpu_cores"
    local worker_connections=$((ram_gb > 4 ? 2048 : 1024))
    local client_max_body_size=$((ram_gb > 8 ? 1024 : 512))

    cat > "$output_file" << EOF
# Автоматически сгенерированная конфигурация Nginx
# Системные характеристики: ${cpu_cores} CPU cores, ${ram_gb}GB RAM
# Окружение: ${environment}
# Дата генерации: $(date)

user nginx;
worker_processes ${worker_processes};
worker_rlimit_nofile 8192;

error_log /var/log/nginx/error.log warn;
pid /var/run/nginx.pid;

events {
    worker_connections ${worker_connections};
    use epoll;
    multi_accept on;
}

http {
    include /etc/nginx/mime.types;
    default_type application/octet-stream;

    # Логирование
    log_format main '\$remote_addr - \$remote_user [\$time_local] "\$request" '
                    '\$status \$body_bytes_sent "\$http_referer" '
                    '"\$http_user_agent" "\$http_x_forwarded_for"';

    access_log /var/log/nginx/access.log main;

    # Основные настройки
    sendfile on;
    tcp_nopush on;
    tcp_nodelay on;
    keepalive_timeout 65;
    types_hash_max_size 2048;
    server_tokens off;

    # Размеры буферов
    client_max_body_size ${client_max_body_size}M;
    client_body_buffer_size 128k;
    client_header_buffer_size 4k;
    large_client_header_buffers 4 16k;

    # Таймауты
    client_body_timeout 60s;
    client_header_timeout 60s;
    send_timeout 60s;

    # Gzip сжатие
    gzip on;
    gzip_vary on;
    gzip_proxied any;
    gzip_comp_level 6;
    gzip_types
        application/atom+xml
        application/javascript
        application/json
        application/rss+xml
        application/vnd.ms-fontobject
        application/x-font-ttf
        application/x-web-app-manifest+json
        application/xhtml+xml
        application/xml
        font/opentype
        image/svg+xml
        image/x-icon
        text/css
        text/javascript
        text/plain
        text/x-component;

    # SSL настройки
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-RSA-AES256-GCM-SHA512:DHE-RSA-AES256-GCM-SHA512:ECDHE-RSA-AES256-GCM-SHA384;
    ssl_prefer_server_ciphers off;
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 10m;

    # Безопасность
    add_header X-Frame-Options SAMEORIGIN;
    add_header X-Content-Type-Options nosniff;
    add_header X-XSS-Protection "1; mode=block";

    # Подключение конфигураций сайтов
    include /etc/nginx/conf.d/*.conf;
}
EOF
}

# Генерация конфигурации Redis
generate_redis_config() {
    local cpu_cores="$1"
    local ram_gb="$2"
    local environment="$3"
    local output_file="$4"

    local maxmemory=$((ram_gb * 1024 * 25 / 100))  # 25% от RAM для Redis
    local databases=16
    if [ "$environment" != "prod" ]; then
        databases=1
    fi

    # Минимум 128MB
    [ "$maxmemory" -lt 128 ] && maxmemory=128

    cat > "$output_file" << EOF
# Автоматически сгенерированная конфигурация Redis
# Системные характеристики: ${cpu_cores} CPU cores, ${ram_gb}GB RAM
# Окружение: ${environment}
# Дата генерации: $(date)

# Основные настройки
port 6379
bind 0.0.0.0
timeout 300
tcp-keepalive 60

# Память
maxmemory ${maxmemory}mb
maxmemory-policy allkeys-lru
databases ${databases}

# Персистентность
save 900 1
save 300 10
save 60 10000

# Логирование
loglevel notice
logfile ""

# Производительность
hash-max-ziplist-entries 512
hash-max-ziplist-value 64
list-max-ziplist-size -2
list-compress-depth 0
set-max-intset-entries 512
zset-max-ziplist-entries 128
zset-max-ziplist-value 64

# Сеть
tcp-backlog 511
EOF

    if [ "$environment" == "prod" ]; then
        cat >> "$output_file" << EOF

# Продакшн настройки
maxclients 10000
appendonly yes
appendfsync everysec
auto-aof-rewrite-percentage 100
auto-aof-rewrite-min-size 64mb
EOF
    fi
}

# Генерация конфигурации PHP
generate_php_config() {
    local cpu_cores="$1"
    local ram_gb="$2"
    local environment="$3"
    local output_file="$4"

    local memory_limit=$((ram_gb > 8 ? 512 : 256))
    local max_children=$((cpu_cores * 5))
    local max_requests=500
    if [ "$environment" = "prod" ]; then
        max_requests=1000
    fi
    local upload_max_filesize=$((ram_gb > 4 ? 1024 : 512))

    # Корректировка для окружения
    case "$environment" in
        "local")
            max_children=$((max_children / 2))
            ;;
        "dev")
            max_children=$((max_children * 75 / 100))
            ;;
    esac

    cat > "$output_file" << EOF
; Автоматически сгенерированная конфигурация PHP
; Системные характеристики: ${cpu_cores} CPU cores, ${ram_gb}GB RAM
; Окружение: ${environment}
; Дата генерации: $(date)

[PHP]
; Основные настройки
memory_limit = ${memory_limit}M
max_execution_time = 300
max_input_time = 300
post_max_size = ${upload_max_filesize}M
upload_max_filesize = ${upload_max_filesize}M
max_file_uploads = 20

; Обработка ошибок
display_errors = \${DISPLAY_ERRORS}
log_errors = On
error_log = /var/log/php/error.log

; Сессии
session.save_handler = files
session.save_path = "/var/lib/php/sessions"
session.gc_maxlifetime = 3600
session.cookie_lifetime = 0

; OPcache
opcache.enable = 1
opcache.memory_consumption = $((memory_limit / 2))
opcache.interned_strings_buffer = 16
opcache.max_accelerated_files = 10000
opcache.validate_timestamps = \${OPCACHE_VALIDATE}
opcache.revalidate_freq = 2
opcache.save_comments = 1

; Буферизация
output_buffering = 4096
zlib.output_compression = Off

; Безопасность
expose_php = Off
allow_url_fopen = On
allow_url_include = Off

; Временная зона
date.timezone = \${TZ}

; Bitrix специфичные настройки
mbstring.func_overload = 0
mbstring.internal_encoding = UTF-8

[PHP-FPM]
; FPM настройки процессов
pm = dynamic
pm.max_children = ${max_children}
pm.start_servers = $((max_children / 4))
pm.min_spare_servers = $((max_children / 4))
pm.max_spare_servers = $((max_children / 2))
pm.max_requests = ${max_requests}

; Логирование FPM
access.log = /var/log/php/fpm-access.log
slowlog = /var/log/php/fpm-slow.log
request_slowlog_timeout = 10s

; Мониторинг
pm.status_path = /status
ping.path = /ping
EOF
}

# Генерация переменных окружения
generate_env_variables() {
    local cpu_cores="$1"
    local ram_gb="$2"
    local environment="$3"
    local output_file="$4"

    # Порты в зависимости от окружения
    local http_port=80
    local https_port=443
    local db_port=3306

    if [ "$environment" == "local" ]; then
        db_port=3306
    fi

    cat > "$output_file" << EOF
# Автоматически сгенерированные переменные окружения
# Системные характеристики: ${cpu_cores} CPU cores, ${ram_gb}GB RAM
# Окружение: ${environment}
# Дата генерации: $(date)

# Системные характеристики (автодетект)
DETECTED_CPU_CORES=${cpu_cores}
DETECTED_RAM_GB=${ram_gb}

# Общие настройки
TZ=Europe/Moscow
ENVIRONMENT=${environment}
DEBUG=$([[ "$environment" == "local" ]] && echo "1" || echo "0")
UGN=bitrix
UID=1000
GID=1000

# PHP настройки (оптимизированы под систему)
PHP_VERSION=8.3
DISPLAY_ERRORS=$([[ "$environment" == "local" ]] && echo "On" || echo "Off")
OPCACHE_VALIDATE=$([[ "$environment" == "local" ]] && echo "1" || echo "0")

# Порты
HTTP_PORT=${http_port}
HTTPS_PORT=${https_port}
DB_PORT=${db_port}

# Рекомендуемые настройки контейнеров
MEMCACHED_MEMORY_LIMIT=$((ram_gb > 4 ? 512 : 256))
MEMCACHED_CONN_LIMIT=$((cpu_cores * 256))
MEMCACHED_THREADS=${cpu_cores}

# Backup настройки
BACKUP_RETENTION_DAYS=$([[ "$environment" == "prod" ]] && echo "30" || echo "7")
EOF
}

# Основная функция
main() {
    local cpu_cores=""
    local ram_gb=""
    local environment="local"
    local force=false
    local dry_run=false

    # Парсинг аргументов
    while [[ $# -gt 0 ]]; do
        case $1 in
            --cpu-cores)
                cpu_cores="$2"
                shift 2
                ;;
            --ram-gb)
                ram_gb="$2"
                shift 2
                ;;
            --environment)
                environment="$2"
                shift 2
                ;;
            --force)
                force=true
                shift
                ;;
            --dry-run)
                dry_run=true
                shift
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            *)
                echo "Неизвестный параметр: $1"
                show_help
                exit 1
                ;;
        esac
    done

    # Валидация окружения
    if [[ ! "$environment" =~ ^(local|dev|prod)$ ]]; then
        log "ОШИБКА: Неправильное окружение '$environment'. Доступны: local, dev, prod"
        exit 1
    fi

    # Автодетект или использование переданных параметров
    if [ -z "$cpu_cores" ] || [ -z "$ram_gb" ]; then
        log "Автоматическое определение характеристик системы..."
        local specs
        specs=$(detect_system_specs)
        local detected_cpu_cores detected_ram_gb detected_disk_gb
        read -r detected_cpu_cores detected_ram_gb detected_disk_gb <<< "$specs"

        cpu_cores="${cpu_cores:-$detected_cpu_cores}"
        ram_gb="${ram_gb:-$detected_ram_gb}"

        log "Обнаружено: $cpu_cores CPU cores, ${ram_gb}GB RAM, ${detected_disk_gb}GB свободного места"
    else
        log "Используются заданные характеристики: $cpu_cores CPU cores, ${ram_gb}GB RAM"
    fi

    # Создание директорий
    local config_dirs=(
        "config/mysql"
        "config/nginx"
        "config/redis"
        "config/memcached"
        "docker/common/php"
    )

    for dir in "${config_dirs[@]}"; do
        mkdir -p "$dir"
    done

    log "Генерация конфигураций для окружения: $environment"

    # Список файлов для генерации
    local configs=(
        "config/mysql/my.conf:mysql"
        "config/nginx/nginx.conf:nginx"
        "config/redis/redis.conf:redis"
        "docker/common/php/php.ini.template:php"
        ".env.${environment}:env"
    )

    # Генерация или вывод
    for config in "${configs[@]}"; do
        local file_path="${config%:*}"
        local config_type="${config#*:}"

        if [ "$dry_run" = true ]; then
            log "[DRY-RUN] Будет сгенерирован: $file_path ($config_type)"
            continue
        fi

        if [ -f "$file_path" ] && [ "$force" = false ]; then
            log "ПРОПУСК: $file_path уже существует (используйте --force для перезаписи)"
            continue
        fi

        log "Генерация: $file_path"

        case "$config_type" in
            "mysql")
                generate_mysql_config "$cpu_cores" "$ram_gb" "$environment" "$file_path"
                ;;
            "nginx")
                generate_nginx_config "$cpu_cores" "$ram_gb" "$environment" "$file_path"
                ;;
            "redis")
                generate_redis_config "$cpu_cores" "$ram_gb" "$environment" "$file_path"
                ;;
            "php")
                generate_php_config "$cpu_cores" "$ram_gb" "$environment" "$file_path"
                ;;
            "env")
                generate_env_variables "$cpu_cores" "$ram_gb" "$environment" "$file_path"
                ;;
        esac
    done

    if [ "$dry_run" = true ]; then
        log "Режим предварительного просмотра завершен. Запустите без --dry-run для генерации файлов."
    else
        log "Автоконфигурация завершена!"
        log ""
        log "Рекомендации:"
        log "1. Проверьте сгенерированные конфигурации"
        log "2. Скопируйте .env.${environment} в .env: cp .env.${environment} .env"
        log "3. Перезапустите контейнеры: make restart-${environment}"
        log ""
        log "Характеристики системы:"
        log "  CPU cores: $cpu_cores"
        log "  RAM: ${ram_gb}GB"
        log "  Окружение: $environment"
    fi
}

# Запуск
main "$@"