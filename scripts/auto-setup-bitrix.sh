#!/bin/bash
# ============================================================================
# BITRIX DOCKER - АВТОМАТИЧЕСКАЯ НАСТРОЙКА
# Анализирует характеристики сервера и генерирует оптимальные конфигурации
# ============================================================================

set -euo pipefail

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Переменные
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DRY_RUN=false
FORCE=false
ENVIRONMENT="local"
CPU_CORES=""
RAM_GB=""
DISK_GB=""

# ============================================================================
# ФУНКЦИИ ВЫВОДА
# ============================================================================

print_header() {
    echo -e "${BLUE}============================================================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}============================================================================${NC}"
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

print_info() {
    echo -e "${CYAN}ℹ $1${NC}"
}

# ============================================================================
# ПОМОЩЬ
# ============================================================================

show_help() {
    cat << EOF
${BLUE}BITRIX DOCKER - Автоматическая настройка${NC}

Анализирует характеристики сервера (CPU, RAM, Disk) и создает
оптимальные конфигурации для MySQL, Nginx, Redis, PHP.

${YELLOW}Использование:${NC}
    $0 [options]

${YELLOW}Опции:${NC}
    --cpu-cores N       Принудительно указать количество CPU ядер
    --ram-gb N          Принудительно указать объем RAM (GB)
    --disk-gb N         Принудительно указать объем диска (GB)
    --environment ENV   Окружение: local, dev, test, prod (по умолчанию: local)
    --force             Перезаписать существующие конфигурации
    --dry-run           Показать что будет сделано, без выполнения
    -h, --help          Показать эту справку

${YELLOW}Примеры:${NC}
    $0                                      # Авто-детект, окружение local
    $0 --environment prod                   # Авто-детект для production
    $0 --cpu-cores 8 --ram-gb 16            # Ручная настройка
    $0 --environment prod --force           # Перезапись конфигов для prod
    $0 --dry-run                            # Предпросмотр без изменений

${YELLOW}Генерируемые файлы:${NC}
    config/mysql/my.{environment}.cnf       MySQL конфигурация
    config/nginx/nginx.conf                 Nginx основной конфиг
    config/redis/redis.conf                 Redis конфигурация
    config/php/php.ini.optimized            PHP конфигурация
    .env.{environment}.optimized            Оптимизированные переменные

EOF
}

# ============================================================================
# ОПРЕДЕЛЕНИЕ ХАРАКТЕРИСТИК СЕРВЕРА
# ============================================================================

detect_cpu_cores() {
    local cores

    if [ -n "$CPU_CORES" ]; then
        echo "$CPU_CORES"
        return
    fi

    if command -v nproc >/dev/null 2>&1; then
        cores=$(nproc)
    elif [ -f /proc/cpuinfo ]; then
        cores=$(grep -c "^processor" /proc/cpuinfo)
    elif command -v sysctl >/dev/null 2>&1; then
        cores=$(sysctl -n hw.ncpu 2>/dev/null || sysctl -n hw.logicalcpu 2>/dev/null || echo "2")
    else
        cores=2
    fi

    echo "$cores"
}

detect_ram_gb() {
    local ram_gb

    if [ -n "$RAM_GB" ]; then
        echo "$RAM_GB"
        return
    fi

    if [ -f /proc/meminfo ]; then
        local ram_kb=$(grep "MemTotal:" /proc/meminfo | awk '{print $2}')
        ram_gb=$((ram_kb / 1024 / 1024))
    elif command -v sysctl >/dev/null 2>&1; then
        local ram_bytes=$(sysctl -n hw.memsize 2>/dev/null || echo "4294967296")
        ram_gb=$((ram_bytes / 1024 / 1024 / 1024))
    else
        ram_gb=4
    fi

    echo "$ram_gb"
}

detect_disk_gb() {
    local disk_gb

    if [ -n "$DISK_GB" ]; then
        echo "$DISK_GB"
        return
    fi

    disk_gb=$(df "$SCRIPT_DIR" | tail -1 | awk '{print int($4/1024/1024)}')

    echo "$disk_gb"
}

# ============================================================================
# ГЕНЕРАЦИЯ MYSQL КОНФИГУРАЦИИ
# ============================================================================

generate_mysql_config() {
    local cpu=$1
    local ram=$2
    local env=$3
    local output_file="$SCRIPT_DIR/config/mysql/my.${env}.optimized.cnf"

    print_info "Генерация MySQL конфигурации..."

    # Расчет параметров
    local innodb_buffer_pool_size
    local max_connections
    local innodb_buffer_pool_instances
    local innodb_io_capacity
    local tmp_table_size

    case "$env" in
        local)
            innodb_buffer_pool_size=$((ram * 512))  # 512MB для local
            max_connections=100
            innodb_buffer_pool_instances=1
            innodb_io_capacity=1000
            tmp_table_size=64
            ;;
        dev)
            innodb_buffer_pool_size=$((ram * 1024))  # 1GB для dev
            max_connections=150
            innodb_buffer_pool_instances=2
            innodb_io_capacity=1500
            tmp_table_size=128
            ;;
        test)
            innodb_buffer_pool_size=$((ram * 1536))  # 1.5GB для test
            max_connections=200
            innodb_buffer_pool_instances=4
            innodb_io_capacity=2000
            tmp_table_size=128
            ;;
        prod)
            innodb_buffer_pool_size=$((ram * 1024 * 60 / 100))  # 60% RAM для prod
            max_connections=$((cpu * 50))
            innodb_buffer_pool_instances=$((innodb_buffer_pool_size / 1024))
            [ "$innodb_buffer_pool_instances" -gt 64 ] && innodb_buffer_pool_instances=64
            [ "$innodb_buffer_pool_instances" -lt 1 ] && innodb_buffer_pool_instances=1
            innodb_io_capacity=2000
            tmp_table_size=128
            ;;
    esac

    local thread_cache_size=$((cpu * 4))
    local table_open_cache=$((max_connections * 2))
    local table_definition_cache=$((table_open_cache / 2))
    local redo_log_capacity=$((innodb_buffer_pool_size / 4))
    [ "$redo_log_capacity" -lt 512 ] && redo_log_capacity=512
    [ "$redo_log_capacity" -gt 2048 ] && redo_log_capacity=2048

    local redo_log_bytes=$((redo_log_capacity * 1024 * 1024))
    local innodb_io_capacity_max=$((innodb_io_capacity * 2))

    # Вычисляем значения для конфига
    local flush_log_at_commit=1
    [ "$env" = "local" ] && flush_log_at_commit=2

    local lock_wait_timeout=50
    [ "$env" != "prod" ] && lock_wait_timeout=120

    local slow_query_time=3
    [ "$env" = "local" ] && slow_query_time=2

    local sort_buffer="2M"
    [ "$ram" -gt 8 ] && sort_buffer="4M"

    local join_buffer="2M"
    [ "$ram" -gt 8 ] && join_buffer="4M"

    # Вычисляем все текстовые значения
    local env_upper=$(echo "$env" | tr '[:lower:]' '[:upper:]')
    local current_date=$(date '+%Y-%m-%d %H:%M:%S')

    # Генерация файла
    if [ "$DRY_RUN" = true ]; then
        print_warning "[DRY RUN] Создан бы файл: $output_file"
        return
    fi

    mkdir -p "$(dirname "$output_file")"

    cat > "$output_file" << EOF
# ============================================================================
# MYSQL CONFIGURATION FOR BITRIX - ${env_upper}
# Auto-generated by auto-setup-bitrix.sh
# Server: ${cpu} CPU cores, ${ram}GB RAM
# Date: ${current_date}
# ============================================================================

[mysqld]
# Основные настройки
bind-address = 0.0.0.0
port = 3306
skip-name-resolve = 1

# Кодировка
character-set-server = utf8mb4
collation-server = utf8mb4_unicode_ci
init-connect = "SET NAMES utf8mb4"

# InnoDB настройки
innodb_strict_mode = OFF
innodb_file_per_table = 1
innodb_buffer_pool_size = ${innodb_buffer_pool_size}M
innodb_buffer_pool_instances = ${innodb_buffer_pool_instances}
innodb_flush_method = O_DIRECT
innodb_flush_log_at_trx_commit = ${flush_log_at_commit}
innodb_redo_log_capacity = ${redo_log_bytes}
innodb_log_buffer_size = 64M
innodb_lock_wait_timeout = ${lock_wait_timeout}
innodb_io_capacity = ${innodb_io_capacity}
innodb_io_capacity_max = ${innodb_io_capacity_max}
innodb_flush_neighbors = 0

# Производительность
max_connections = ${max_connections}
thread_cache_size = ${thread_cache_size}
thread_stack = 512K
table_open_cache = ${table_open_cache}
table_definition_cache = ${table_definition_cache}

# Буферы
sort_buffer_size = ${sort_buffer}
join_buffer_size = ${join_buffer}
read_buffer_size = 2M
read_rnd_buffer_size = 8M

# Временные таблицы
tmp_table_size = ${tmp_table_size}M
max_heap_table_size = ${tmp_table_size}M
max_allowed_packet = 256M

# Bitrix специфичные
transaction-isolation = READ-COMMITTED
sql_mode = ""

# Логирование
log_error = /var/log/mysql/error.log
slow_query_log = 1
slow_query_log_file = /var/log/mysql/slow.log
long_query_time = ${slow_query_time}

[mysql]
default-character-set = utf8mb4

[mysqldump]
quick
quote-names
max_allowed_packet = 256M

[client]
default-character-set = utf8mb4
EOF

    print_success "MySQL конфигурация создана: $output_file"
}

# ============================================================================
# ГЕНЕРАЦИЯ NGINX КОНФИГУРАЦИИ
# ============================================================================

generate_nginx_config() {
    local cpu=$1
    local env=$2
    local output_file="$SCRIPT_DIR/config/nginx/nginx.${env}.optimized.conf"

    print_info "Генерация Nginx конфигурации..."

    local worker_processes=$cpu
    local worker_connections=2048
    [ "$env" = "prod" ] && worker_connections=4096

    local keepalive_timeout=75
    [ "$env" = "prod" ] && keepalive_timeout=65

    local gzip_level=4
    [ "$env" = "prod" ] && gzip_level=6

    local env_upper=$(echo "$env" | tr '[:lower:]' '[:upper:]')
    local current_date=$(date '+%Y-%m-%d %H:%M:%S')

    if [ "$DRY_RUN" = true ]; then
        print_warning "[DRY RUN] Создан бы файл: $output_file"
        return
    fi

    mkdir -p "$(dirname "$output_file")"

    cat > "$output_file" << EOF
# ============================================================================
# NGINX CONFIGURATION FOR BITRIX - ${env_upper}
# Auto-generated by auto-setup-bitrix.sh
# Server: ${cpu} CPU cores
# Date: ${current_date}
# ============================================================================

user nginx;
worker_processes ${worker_processes};
worker_rlimit_nofile 65535;
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

    # Производительность
    sendfile on;
    tcp_nopush on;
    tcp_nodelay on;
    keepalive_timeout ${keepalive_timeout};
    types_hash_max_size 2048;
    server_tokens off;

    # Gzip сжатие
    gzip on;
    gzip_vary on;
    gzip_proxied any;
    gzip_comp_level ${gzip_level};
    gzip_types text/plain text/css text/xml text/javascript
               application/json application/javascript application/xml+rss
               application/rss+xml font/truetype font/opentype
               application/vnd.ms-fontobject image/svg+xml;
    gzip_disable "msie6";

    # Буферы
    client_body_buffer_size 128k;
    client_max_body_size 256m;
    client_header_buffer_size 4k;
    large_client_header_buffers 4 16k;

    # FastCGI кэш для Битрикс
    fastcgi_cache_path /var/cache/nginx levels=1:2 keys_zone=BITRIX:100m
                        inactive=60m max_size=1g;
    fastcgi_cache_key "\$scheme\$request_method\$host\$request_uri";

    # Включаем виртуальные хосты
    include /etc/nginx/conf.d/*.conf;
}
EOF

    print_success "Nginx конфигурация создана: $output_file"
}

# ============================================================================
# ГЕНЕРАЦИЯ REDIS КОНФИГУРАЦИИ
# ============================================================================

generate_redis_config() {
    local ram=$1
    local env=$2
    local output_file="$SCRIPT_DIR/config/redis/redis.${env}.optimized.conf"

    print_info "Генерация Redis конфигурации..."

    local maxmemory
    case "$env" in
        local)
            maxmemory=256mb
            ;;
        dev)
            maxmemory=512mb
            ;;
        test)
            maxmemory=768mb
            ;;
        prod)
            maxmemory=$((ram * 1024 * 25 / 100))mb  # 25% RAM
            ;;
    esac

    local appendonly="no"
    [ "$env" = "prod" ] && appendonly="yes"

    local env_upper=$(echo "$env" | tr '[:lower:]' '[:upper:]')
    local current_date=$(date '+%Y-%m-%d %H:%M:%S')

    if [ "$DRY_RUN" = true ]; then
        print_warning "[DRY RUN] Создан бы файл: $output_file"
        return
    fi

    mkdir -p "$(dirname "$output_file")"

    cat > "$output_file" << EOF
# ============================================================================
# REDIS CONFIGURATION FOR BITRIX - ${env_upper}
# Auto-generated by auto-setup-bitrix.sh
# Server: ${ram}GB RAM
# Date: ${current_date}
# ============================================================================

# Bind на все интерфейсы (защита через пароль)
bind 0.0.0.0
port 6379
protected-mode yes

# Память
maxmemory ${maxmemory}
maxmemory-policy allkeys-lru
maxmemory-samples 5

# Персистентность
save 900 1
save 300 10
save 60 10000
stop-writes-on-bgsave-error yes
rdbcompression yes
rdbchecksum yes
dbfilename dump.rdb
dir /data

# AOF (для prod - включено)
appendonly ${appendonly}
appendfilename "appendonly.aof"
appendfsync everysec
no-appendfsync-on-rewrite no
auto-aof-rewrite-percentage 100
auto-aof-rewrite-min-size 64mb

# Логирование
loglevel notice
logfile /var/log/redis/redis.log

# Производительность
timeout 300
tcp-keepalive 300
tcp-backlog 511

# Databases
databases 16
EOF

    print_success "Redis конфигурация создана: $output_file"
}

# ============================================================================
# ГЕНЕРАЦИЯ .ENV С ОПТИМИЗИРОВАННЫМИ ПАРАМЕТРАМИ
# ============================================================================

generate_env_params() {
    local cpu=$1
    local ram=$2
    local env=$3
    local output_file="$SCRIPT_DIR/.env.${env}.optimized"

    print_info "Генерация оптимизированных параметров .env..."

    # PHP-FPM параметры
    local php_fpm_max_children
    local php_memory_limit

    case "$env" in
        local)
            php_fpm_max_children=$((cpu * 3))
            php_memory_limit="512M"
            ;;
        dev)
            php_fpm_max_children=$((cpu * 4))
            php_memory_limit="384M"
            ;;
        test|prod)
            php_fpm_max_children=$((cpu * 10))
            [ "$php_fpm_max_children" -gt 100 ] && php_fpm_max_children=100
            php_memory_limit="256M"
            ;;
    esac

    local php_fpm_start_servers=$((php_fpm_max_children / 5))
    [ "$php_fpm_start_servers" -lt 2 ] && php_fpm_start_servers=2

    local php_fpm_min_spare=$((php_fpm_start_servers - 1))
    [ "$php_fpm_min_spare" -lt 1 ] && php_fpm_min_spare=1

    local php_fpm_max_spare=$((php_fpm_max_children / 3))

    # Вычисляем остальные параметры
    local php_fpm_pm="dynamic"
    [ "$env" = "prod" ] && php_fpm_pm="ondemand"

    local mysql_buffer
    local mysql_connections
    if [ "$env" = "local" ]; then
        mysql_buffer="$((ram * 512))M"
        mysql_connections=100
    else
        mysql_buffer="$((ram * 1024 * 60 / 100))M"
        mysql_connections=$((cpu * 50))
    fi

    local redis_memory
    if [ "$env" = "local" ]; then
        redis_memory="256mb"
    else
        redis_memory="$((ram * 1024 * 25 / 100))mb"
    fi

    local memcached_memory
    if [ "$env" = "local" ]; then
        memcached_memory=128
    else
        memcached_memory=$((ram * 512))
    fi

    local opcache_enable
    if [ "$env" = "local" ]; then
        opcache_enable=0
    else
        opcache_enable=1
    fi

    local opcache_memory=256
    [ "$ram" -gt 8 ] && opcache_memory=512

    local opcache_files=20000
    [ "$env" = "prod" ] && opcache_files=30000

    local env_upper=$(echo "$env" | tr '[:lower:]' '[:upper:]')
    local current_date=$(date '+%Y-%m-%d %H:%M:%S')

    if [ "$DRY_RUN" = true ]; then
        print_warning "[DRY RUN] Создан бы файл: $output_file"
        return
    fi

    cat > "$output_file" << EOF
# ============================================================================
# OPTIMIZED ENVIRONMENT VARIABLES - ${env_upper}
# Auto-generated by auto-setup-bitrix.sh
# Server: ${cpu} CPU cores, ${ram}GB RAM
# Date: ${current_date}
# ============================================================================
# ВНИМАНИЕ: Добавьте эти параметры в ваш .env файл

# PHP-FPM оптимизация
PHP_FPM_PM=${php_fpm_pm}
PHP_FPM_MAX_CHILDREN=${php_fpm_max_children}
PHP_FPM_START_SERVERS=${php_fpm_start_servers}
PHP_FPM_MIN_SPARE_SERVERS=${php_fpm_min_spare}
PHP_FPM_MAX_SPARE_SERVERS=${php_fpm_max_spare}

# PHP лимиты
PHP_MEMORY_LIMIT=${php_memory_limit}
PHP_UPLOAD_MAX_FILESIZE=64M
PHP_POST_MAX_SIZE=64M

# MySQL оптимизация
MYSQL_INNODB_BUFFER_POOL_SIZE=${mysql_buffer}
MYSQL_MAX_CONNECTIONS=${mysql_connections}

# Redis оптимизация
REDIS_MAX_MEMORY=${redis_memory}

# Memcached оптимизация
MEMCACHED_MEMORY_LIMIT=${memcached_memory}
MEMCACHED_THREADS=${cpu}

# OPcache
PHP_OPCACHE_ENABLE=${opcache_enable}
PHP_OPCACHE_MEMORY=${opcache_memory}
PHP_OPCACHE_MAX_FILES=${opcache_files}
EOF

    print_success "Оптимизированные параметры созданы: $output_file"
    print_info "Добавьте эти параметры в ваш .env файл"
}

# ============================================================================
# СОЗДАНИЕ ОТЧЕТА
# ============================================================================

generate_report() {
    local cpu=$1
    local ram=$2
    local disk=$3
    local env=$4

    print_header "ОТЧЕТ ПО АВТОМАТИЧЕСКОЙ НАСТРОЙКЕ"

    echo -e "${CYAN}Характеристики сервера:${NC}"
    echo -e "  CPU:  ${GREEN}${cpu}${NC} ядер"
    echo -e "  RAM:  ${GREEN}${ram}GB${NC}"
    echo -e "  Disk: ${GREEN}${disk}GB${NC} свободно"
    echo ""

    local env_upper=$(echo "$env" | tr '[:lower:]' '[:upper:]')
    echo -e "${CYAN}Окружение:${NC} ${GREEN}${env_upper}${NC}"
    echo ""

    echo -e "${CYAN}Сгенерированные конфигурации:${NC}"
    echo -e "  ${GREEN}✓${NC} config/mysql/my.${env}.optimized.cnf"
    echo -e "  ${GREEN}✓${NC} config/nginx/nginx.${env}.optimized.conf"
    echo -e "  ${GREEN}✓${NC} config/redis/redis.${env}.optimized.conf"
    echo -e "  ${GREEN}✓${NC} .env.${env}.optimized"
    echo ""

    echo -e "${CYAN}Рекомендации:${NC}"

    if [ "$ram" -lt 4 ]; then
        print_warning "RAM < 4GB: рекомендуется минимум 4GB для нормальной работы Битрикс"
    fi

    if [ "$cpu" -lt 2 ]; then
        print_warning "CPU < 2: рекомендуется минимум 2 ядра"
    fi

    if [ "$disk" -lt 20 ]; then
        print_warning "Disk < 20GB: рекомендуется минимум 20GB свободного места"
    fi

    if [ "$env" = "prod" ]; then
        echo ""
        print_info "Для production:"
        echo -e "  ${YELLOW}1.${NC} Проверьте и скопируйте созданные конфигурации"
        echo -e "  ${YELLOW}2.${NC} Добавьте параметры из .env.${env}.optimized в .env"
        echo -e "  ${YELLOW}3.${NC} Перезапустите контейнеры: docker compose restart"
        echo -e "  ${YELLOW}4.${NC} Мониторьте производительность в Grafana"
    fi

    echo ""
    print_success "Автоматическая настройка завершена!"
}

# ============================================================================
# MAIN
# ============================================================================

main() {
    print_header "BITRIX DOCKER - АВТОМАТИЧЕСКАЯ НАСТРОЙКА"

    # Парсинг аргументов
    while [[ $# -gt 0 ]]; do
        case $1 in
            --cpu-cores)
                CPU_CORES="$2"
                shift 2
                ;;
            --ram-gb)
                RAM_GB="$2"
                shift 2
                ;;
            --disk-gb)
                DISK_GB="$2"
                shift 2
                ;;
            --environment)
                ENVIRONMENT="$2"
                shift 2
                ;;
            --force)
                FORCE=true
                shift
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            *)
                print_error "Неизвестный параметр: $1"
                show_help
                exit 1
                ;;
        esac
    done

    # Проверка окружения
    if [[ ! "$ENVIRONMENT" =~ ^(local|dev|test|prod)$ ]]; then
        print_error "Неверное окружение: $ENVIRONMENT (допустимо: local, dev, test, prod)"
        exit 1
    fi

    # Определение характеристик
    print_info "Определение характеристик сервера..."

    local cpu=$(detect_cpu_cores)
    local ram=$(detect_ram_gb)
    local disk=$(detect_disk_gb)

    print_success "CPU: $cpu ядер, RAM: ${ram}GB, Disk: ${disk}GB свободно"
    echo ""

    # Генерация конфигураций
    generate_mysql_config "$cpu" "$ram" "$ENVIRONMENT"
    generate_nginx_config "$cpu" "$ENVIRONMENT"
    generate_redis_config "$ram" "$ENVIRONMENT"
    generate_env_params "$cpu" "$ram" "$ENVIRONMENT"

    echo ""

    # Отчет
    generate_report "$cpu" "$ram" "$disk" "$ENVIRONMENT"
}

# Запуск
main "$@"
