#!/bin/bash
# ============================================================================
# BITRIX DOCKER - АВТОМАТИЧЕСКАЯ ОПТИМИЗАЦИЯ v2.0
# Анализирует характеристики сервера и генерирует ВСЕ конфигурации
# Включает security fixes и performance optimizations
# ============================================================================

set -euo pipefail

# Цвета
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Переменные
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
DRY_RUN=false
FORCE=false
UPDATE_ENV=false
ENVIRONMENT=""
CPU_CORES=""
RAM_GB=""

# ============================================================================
# ФУНКЦИИ ВЫВОДА
# ============================================================================

log_header() { echo -e "\n${BLUE}=== $1 ===${NC}"; }
log_success() { echo -e "${GREEN}✓${NC} $1"; }
log_warning() { echo -e "${YELLOW}⚠${NC} $1"; }
log_error() { echo -e "${RED}✗${NC} $1"; }
log_info() { echo -e "${CYAN}ℹ${NC} $1"; }

# ============================================================================
# ПОМОЩЬ
# ============================================================================

show_help() {
    cat << EOF
${BLUE}BITRIX DOCKER - Автоматическая оптимизация v2.0${NC}

Анализирует характеристики сервера и создает оптимальные конфигурации
для MySQL, Nginx, Redis, PHP-FPM, Memcached.

${YELLOW}Использование:${NC}
    $0 [options]

${YELLOW}Опции:${NC}
    --cpu-cores N       Принудительно указать CPU ядра
    --ram-gb N          Принудительно указать RAM (GB)
    --environment ENV   Окружение: local, dev, prod (auto-detect из .env)
    --update-env        Обновить .env файл напрямую
    --force             Перезаписать существующие конфигурации
    --dry-run           Показать без выполнения
    -h, --help          Справка

${YELLOW}Примеры:${NC}
    $0                          # Авто-детект всего
    $0 --environment prod       # Для production
    $0 --update-env             # Обновить .env
    $0 --cpu-cores 8 --ram-gb 32 --force

${YELLOW}Генерируемые конфигурации:${NC}
    config/mysql/my.{env}.cnf               MySQL/MariaDB
    config/redis/redis.conf                 Redis (с security!)
    config/memcached/memcached.conf         Memcached
    docker/common/nginx/nginx.conf          Nginx
    docker/common/php/php-fpm.d/www.conf    PHP-FPM pool
    docker/common/php/conf.d/opcache.ini    OPcache
    .env                                    (если --update-env)

EOF
}

# ============================================================================
# ОПРЕДЕЛЕНИЕ ХАРАКТЕРИСТИК СЕРВЕРА
# ============================================================================

detect_cpu_cores() {
    [ -n "$CPU_CORES" ] && echo "$CPU_CORES" && return

    if command -v nproc >/dev/null 2>&1; then
        nproc
    elif [ -f /proc/cpuinfo ]; then
        grep -c "^processor" /proc/cpuinfo
    elif command -v sysctl >/dev/null 2>&1; then
        sysctl -n hw.ncpu 2>/dev/null || sysctl -n hw.logicalcpu 2>/dev/null || echo "4"
    else
        echo "4"
    fi
}

detect_ram_gb() {
    [ -n "$RAM_GB" ] && echo "$RAM_GB" && return

    if [ -f /proc/meminfo ]; then
        local ram_kb=$(grep "MemTotal:" /proc/meminfo | awk '{print $2}')
        echo $((ram_kb / 1024 / 1024))
    elif command -v sysctl >/dev/null 2>&1; then
        local ram_bytes=$(sysctl -n hw.memsize 2>/dev/null || echo "4294967296")
        echo $((ram_bytes / 1024 / 1024 / 1024))
    else
        echo "4"
    fi
}

detect_environment() {
    [ -n "$ENVIRONMENT" ] && echo "$ENVIRONMENT" && return

    if [ -f "$PROJECT_DIR/.env" ]; then
        grep -E "^ENVIRONMENT=" "$PROJECT_DIR/.env" 2>/dev/null | cut -d'=' -f2 || echo "local"
    else
        echo "local"
    fi
}

# ============================================================================
# ГЕНЕРАЦИЯ MySQL КОНФИГУРАЦИИ
# ============================================================================

generate_mysql_config() {
    local cpu=$1 ram=$2 env=$3
    local output="$PROJECT_DIR/config/mysql/my.${env}.cnf"

    # Detect DB type from MYSQL_IMAGE
    local mysql_image=""
    local db_type="mysql"
    if [ -f "$PROJECT_DIR/.env" ]; then
        mysql_image=$(grep -E "^MYSQL_IMAGE=" "$PROJECT_DIR/.env" 2>/dev/null | cut -d'=' -f2 || echo "")
    fi
    if echo "$mysql_image" | grep -qi "mariadb"; then
        db_type="mariadb"
    fi

    log_info "Генерация конфигурации для ${db_type} (${mysql_image:-default})..."

    # Расчёт параметров с защитой от низкой RAM
    local buffer_pool max_conn thread_cache table_cache
    local flush_commit io_capacity tmp_table slow_time

    # Определяем доступную RAM для MySQL (оставляем запас для ОС и других сервисов)
    # Формула: для prod используем 50-60% RAM, но не более чем RAM - 1GB (для ОС)
    local available_ram_mb=$((ram * 1024))
    local reserved_mb=1024  # 1GB резерв для ОС и других сервисов
    [ "$ram" -le 2 ] && reserved_mb=512  # Для маленьких серверов меньше резерва

    case "$env" in
        local)
            # Local: 25% RAM, минимум 128MB, максимум 1GB
            buffer_pool=$((available_ram_mb * 25 / 100))
            [ "$buffer_pool" -lt 128 ] && buffer_pool=128
            [ "$buffer_pool" -gt 1024 ] && buffer_pool=1024
            max_conn=100
            flush_commit=2
            io_capacity=1000
            tmp_table=32
            slow_time=2
            ;;
        dev)
            # Dev: 40% RAM, минимум 256MB, максимум 4GB
            buffer_pool=$((available_ram_mb * 40 / 100))
            [ "$buffer_pool" -lt 256 ] && buffer_pool=256
            [ "$buffer_pool" -gt 4096 ] && buffer_pool=4096
            max_conn=$((cpu * 25))
            [ "$max_conn" -lt 100 ] && max_conn=100
            [ "$max_conn" -gt 300 ] && max_conn=300
            flush_commit=2
            io_capacity=2000
            tmp_table=64
            slow_time=2
            ;;
        prod)
            # Prod: 50-60% RAM, но оставляем минимум reserved_mb для ОС
            local max_buffer=$((available_ram_mb - reserved_mb))
            buffer_pool=$((available_ram_mb * 55 / 100))
            [ "$buffer_pool" -gt "$max_buffer" ] && buffer_pool=$max_buffer
            [ "$buffer_pool" -lt 256 ] && buffer_pool=256
            max_conn=$((cpu * 40))
            [ "$max_conn" -lt 100 ] && max_conn=100
            [ "$max_conn" -gt 500 ] && max_conn=500
            flush_commit=2  # 2 для баланса производительности/надёжности (Bitrix рекомендация)
            io_capacity=2000
            tmp_table=$((buffer_pool / 20))  # ~5% от buffer_pool
            [ "$tmp_table" -lt 32 ] && tmp_table=32
            [ "$tmp_table" -gt 512 ] && tmp_table=512
            slow_time=3
            ;;
    esac

    thread_cache=$((cpu * 4))
    [ "$thread_cache" -lt 8 ] && thread_cache=8
    [ "$thread_cache" -gt 100 ] && thread_cache=100

    table_cache=$((max_conn * 2))
    [ "$table_cache" -lt 400 ] && table_cache=400
    [ "$table_cache" -gt 4000 ] && table_cache=4000

    local table_def_cache=$((table_cache / 2))
    [ "$table_def_cache" -lt 400 ] && table_def_cache=400  # MariaDB minimum

    # Redo log / log file size calculation (пропорционально buffer_pool)
    local log_size_mb=$((buffer_pool / 4))
    [ "$log_size_mb" -lt 64 ] && log_size_mb=64
    [ "$log_size_mb" -gt 2048 ] && log_size_mb=2048

    # Buffer pool instances (MySQL only, removed in MariaDB 10.11)
    local instances=$((buffer_pool / 1024))
    [ "$instances" -lt 1 ] && instances=1
    [ "$instances" -gt 64 ] && instances=64

    # Буферы пропорционально RAM
    local sort_buf="2M" join_buf="2M" read_buf="1M" read_rnd_buf="4M"
    if [ "$ram" -ge 8 ]; then
        sort_buf="4M"
        join_buf="4M"
        read_buf="2M"
        read_rnd_buf="8M"
    elif [ "$ram" -le 2 ]; then
        sort_buf="1M"
        join_buf="1M"
        read_buf="512K"
        read_rnd_buf="2M"
    fi

    # IO threads пропорционально CPU
    local io_threads=$((cpu > 4 ? 4 : cpu))
    [ "$io_threads" -lt 2 ] && io_threads=2

    [ "$DRY_RUN" = true ] && { log_warning "[DRY RUN] $output"; return; }

    mkdir -p "$(dirname "$output")"

    # InnoDB log/redo config differs between MySQL and MariaDB
    local innodb_log_config=""
    local innodb_pool_instances=""
    if [ "$db_type" = "mariadb" ]; then
        # MariaDB: innodb_log_file_size (in M), no innodb_buffer_pool_instances in 10.11+
        innodb_log_config="innodb_log_file_size = ${log_size_mb}M"
    else
        # MySQL 8.0+: innodb_redo_log_capacity (in bytes), innodb_buffer_pool_instances
        local redo_bytes=$((log_size_mb * 1024 * 1024))
        innodb_log_config="innodb_redo_log_capacity = ${redo_bytes}"
        innodb_pool_instances="innodb_buffer_pool_instances = ${instances}"
    fi

    # Предупреждения для маленьких серверов
    if [ "$ram" -le 2 ]; then
        log_warning "RAM <= 2GB: MySQL получит только ${buffer_pool}MB для buffer_pool"
    fi
    if [ "$buffer_pool" -lt 512 ]; then
        log_warning "buffer_pool < 512MB: производительность может быть низкой"
    fi

    cat > "$output" << EOF
# ============================================================================
# ${db_type^} Configuration - AUTO OPTIMIZED
# Image: ${mysql_image:-default} | Server: ${cpu} CPU, ${ram}GB RAM | Env: ${env}
# Buffer Pool: ${buffer_pool}MB | Max Connections: ${max_conn}
# Generated: $(date '+%Y-%m-%d %H:%M:%S')
# ============================================================================

[mysqld]
# Basic
bind-address = 0.0.0.0
port = 3306
datadir = /var/lib/mysql
socket = /var/run/mysqld/mysqld.sock
pid-file = /var/run/mysqld/mysqld.pid
skip-name-resolve = 1

# Timezone
default-time-zone = "+03:00"

# Character set
character-set-server = utf8mb4
collation-server = utf8mb4_unicode_ci
init-connect = "SET NAMES utf8mb4"

# InnoDB Engine
innodb_strict_mode = OFF
innodb_file_per_table = 1
innodb_buffer_pool_size = ${buffer_pool}M
${innodb_pool_instances:+${innodb_pool_instances}
}innodb_buffer_pool_dump_at_shutdown = 1
innodb_buffer_pool_load_at_startup = 1

# InnoDB flush method
# NOTE: O_DIRECT disabled by default for Docker compatibility
# Enable manually if your storage supports it (native Linux with ext4/xfs)
# innodb_flush_method = O_DIRECT

innodb_flush_log_at_trx_commit = ${flush_commit}
${innodb_log_config}
innodb_log_buffer_size = $([[ "$buffer_pool" -gt 1024 ]] && echo "64M" || echo "16M")
innodb_lock_wait_timeout = $([[ "$env" == "prod" ]] && echo 50 || echo 120)
innodb_io_capacity = ${io_capacity}
innodb_io_capacity_max = $((io_capacity * 2))
innodb_flush_neighbors = 0
innodb_read_io_threads = ${io_threads}
innodb_write_io_threads = ${io_threads}
innodb_temp_data_file_path = ibtmp1:12M:autoextend:max:$([[ "$buffer_pool" -gt 2048 ]] && echo "10G" || echo "2G")

# Connections & Threads
max_connections = ${max_conn}
thread_cache_size = ${thread_cache}
thread_stack = $([[ "$ram" -le 2 ]] && echo "256K" || echo "512K")
table_open_cache = ${table_cache}
table_definition_cache = ${table_def_cache}

# Buffers
sort_buffer_size = ${sort_buf}
join_buffer_size = ${join_buf}
read_buffer_size = ${read_buf}
read_rnd_buffer_size = ${read_rnd_buf}

# Temp tables
tmp_table_size = ${tmp_table}M
max_heap_table_size = ${tmp_table}M
max_allowed_packet = $([[ "$ram" -le 2 ]] && echo "64M" || echo "256M")

# MyISAM (legacy, but may be used)
key_buffer_size = $([[ "$ram" -le 2 ]] && echo "32M" || echo "128M")

# Bitrix specific
transaction-isolation = READ-COMMITTED
sql_mode = ""
skip-log-bin

# Security
local_infile = 0
max_connect_errors = 10000

# Logging - stderr for Docker (NO log files to avoid permission issues)
# All errors go to: docker logs <container>
general_log = 0
slow_query_log = $([[ "$env" == "prod" ]] && echo 0 || echo 1)
long_query_time = ${slow_time}

# Timeouts
interactive_timeout = $([[ "$env" == "prod" ]] && echo 7200 || echo 28800)
wait_timeout = $([[ "$env" == "prod" ]] && echo 7200 || echo 28800)
connect_timeout = 10

# Performance Schema (disabled for low RAM)
performance_schema = $([[ "$ram" -ge 4 ]] && echo "ON" || echo "OFF")

[mysql]
default-character-set = utf8mb4

[mysqldump]
quick
quote-names
max_allowed_packet = $([[ "$ram" -le 2 ]] && echo "64M" || echo "256M")
single-transaction

[client]
port = 3306
socket = /var/run/mysqld/mysqld.sock
default-character-set = utf8mb4
EOF

    log_success "${db_type^}: $output (buffer_pool=${buffer_pool}M, log=${log_size_mb}M, max_conn=${max_conn})"
}

# ============================================================================
# ГЕНЕРАЦИЯ Redis КОНФИГУРАЦИИ (Docker-compatible!)
# ============================================================================

generate_redis_config() {
    local cpu=$1 ram=$2 env=$3
    local output="$PROJECT_DIR/config/redis/redis.conf"

    log_info "Генерация Redis конфигурации..."

    # Memory calculation: scale with available RAM
    # Formula: 2-5% of total RAM depending on environment
    local maxmem_mb percent
    case "$env" in
        local)
            percent=2
            maxmem_mb=$((ram * 1024 * percent / 100))
            [ "$maxmem_mb" -lt 512 ] && maxmem_mb=512
            ;;
        dev)
            percent=3
            maxmem_mb=$((ram * 1024 * percent / 100))
            [ "$maxmem_mb" -lt 1024 ] && maxmem_mb=1024
            ;;
        prod)
            percent=5
            maxmem_mb=$((ram * 1024 * percent / 100))
            [ "$maxmem_mb" -lt 2048 ] && maxmem_mb=2048
            ;;
    esac

    # Format: use 'gb' for >= 1024mb, otherwise 'mb'
    local maxmem
    if [ "$maxmem_mb" -ge 1024 ]; then
        maxmem="$((maxmem_mb / 1024))gb"
    else
        maxmem="${maxmem_mb}mb"
    fi

    [ "$DRY_RUN" = true ] && { log_warning "[DRY RUN] $output"; return; }

    mkdir -p "$(dirname "$output")"

    cat > "$output" << EOF
# ============================================================================
# Redis Configuration - AUTO OPTIMIZED + SECURITY
# Server: ${cpu} CPU, ${ram}GB RAM | Environment: ${env}
# Generated: $(date '+%Y-%m-%d %H:%M:%S')
# ============================================================================

# NETWORK - Docker containers need 0.0.0.0
# Security is handled by Docker network isolation
bind 0.0.0.0
protected-mode no
port 6379

# Memory - ${maxmem} for ${ram}GB server (${percent}% of RAM)
maxmemory ${maxmem}
maxmemory-policy allkeys-lru
maxmemory-samples 5

# Performance - lazy operations
lazyfree-lazy-eviction yes
lazyfree-lazy-expire yes
lazyfree-lazy-server-del yes
replica-lazy-flush yes

# Network
timeout 0
tcp-keepalive 300
tcp-backlog 65535

# Persistence (disable for pure cache)
$([[ "$env" == "prod" ]] && echo "save 900 1
save 300 10
save 60 10000" || echo "save \"\"")

# AOF
appendonly $([[ "$env" == "prod" ]] && echo "yes" || echo "no")
appendfsync everysec

# Logging
loglevel notice
logfile ""

# Data structures
hash-max-ziplist-entries 512
hash-max-ziplist-value 64
list-max-ziplist-size -2
set-max-intset-entries 512
zset-max-ziplist-entries 128
zset-max-ziplist-value 64

# Active defrag
activedefrag yes
active-defrag-ignore-bytes 100mb
active-defrag-threshold-lower 10
active-defrag-threshold-upper 100

# Databases - 16 for per-site isolation
databases 16
EOF

    log_success "Redis: $output"
}

# ============================================================================
# ГЕНЕРАЦИЯ Nginx КОНФИГУРАЦИИ
# ============================================================================

generate_nginx_config() {
    local cpu=$1 ram=$2 env=$3
    local output="$PROJECT_DIR/docker/common/nginx/nginx.conf"

    log_info "Генерация Nginx конфигурации..."

    local workers=$cpu
    local connections=$([[ "$env" == "prod" ]] && echo 4096 || echo 2048)
    local keepalive=$([[ "$env" == "prod" ]] && echo 65 || echo 75)
    local gzip_level=$([[ "$env" == "prod" ]] && echo 4 || echo 5)

    [ "$DRY_RUN" = true ] && { log_warning "[DRY RUN] $output"; return; }

    mkdir -p "$(dirname "$output")"

    cat > "$output" << EOF
# ============================================================================
# Nginx Configuration - AUTO OPTIMIZED
# Server: ${cpu} CPU, ${ram}GB RAM | Environment: ${env}
# Generated: $(date '+%Y-%m-%d %H:%M:%S')
# ============================================================================

user bitrix;
worker_processes ${workers};
worker_rlimit_nofile 65535;
pid /var/run/nginx/nginx.pid;

events {
    worker_connections ${connections};
    multi_accept on;
    use epoll;
}

http {
    # Security
    server_tokens off;

    # Performance: File cache
    open_file_cache max=10000 inactive=60s;
    open_file_cache_valid 120s;
    open_file_cache_min_uses 2;
    open_file_cache_errors on;

    # Basic
    include /etc/nginx/mime.types;
    default_type application/octet-stream;
    sendfile on;
    tcp_nopush on;
    tcp_nodelay on;
    keepalive_timeout ${keepalive};
    keepalive_requests 1000;
    types_hash_max_size 2048;

    # Logging
    log_format main_json '{'
      '"msec":"\$msec",'
      '"status":"\$status",'
      '"request_time":"\$request_time",'
      '"request_uri":"\$request_uri",'
      '"request_method":"\$request_method",'
      '"server_name":"\$host",'
      '"remote_addr":"\$remote_addr",'
      '"upstream_cache_status":"\$upstream_cache_status"'
    '}';
    access_log /dev/stdout main_json;
    error_log /dev/stderr warn;

    # Gzip
    gzip on;
    gzip_http_version 1.0;
    gzip_comp_level ${gzip_level};
    gzip_min_length 1100;
    gzip_buffers 16 8k;
    gzip_proxied any;
    gzip_types
        text/plain text/css text/xml text/javascript
        application/javascript application/json application/xml
        application/rss+xml application/atom+xml
        font/truetype font/opentype application/vnd.ms-fontobject
        image/svg+xml image/x-icon;
    gzip_static on;
    gzip_vary on;
    gzip_disable "MSIE [1-6]\.";

    # Client
    client_max_body_size 1024M;
    client_body_buffer_size 128k;
    client_header_buffer_size 1k;
    large_client_header_buffers 4 16k;

    # FastCGI
    proxy_connect_timeout 60s;
    proxy_send_timeout 60s;
    proxy_read_timeout 60s;
    fastcgi_send_timeout 300s;
    fastcgi_read_timeout 300s;
    fastcgi_buffers 16 16k;
    fastcgi_buffer_size 32k;
    chunked_transfer_encoding on;

    include /etc/nginx/conf.d/*.conf;
}
EOF

    log_success "Nginx: $output"
}

# ============================================================================
# ГЕНЕРАЦИЯ PHP-FPM КОНФИГУРАЦИИ
# ============================================================================

generate_phpfpm_config() {
    local cpu=$1 ram=$2 env=$3
    local output="$PROJECT_DIR/docker/common/php/php-fpm.d/www.conf"

    log_info "Генерация PHP-FPM конфигурации..."

    local max_children start_servers min_spare max_spare
    local pm_mode max_requests

    case "$env" in
        local)
            max_children=$((cpu * 3))
            pm_mode="dynamic"
            max_requests=500    # Higher to reduce restart overhead (memory leaks rare in PHP 8.x)
            ;;
        dev)
            max_children=$((cpu * 4))
            pm_mode="dynamic"
            max_requests=500
            ;;
        prod)
            max_children=$((cpu * 8))
            [ "$max_children" -gt 100 ] && max_children=100
            pm_mode="static"
            max_requests=1000
            ;;
    esac

    start_servers=$((max_children / 4))
    [ "$start_servers" -lt 2 ] && start_servers=2
    min_spare=$((start_servers - 1))
    [ "$min_spare" -lt 1 ] && min_spare=1
    max_spare=$((max_children / 3))

    [ "$DRY_RUN" = true ] && { log_warning "[DRY RUN] $output"; return; }

    mkdir -p "$(dirname "$output")"

    cat > "$output" << EOF
; ============================================================================
; PHP-FPM Pool Configuration - AUTO OPTIMIZED
; Server: ${cpu} CPU, ${ram}GB RAM | Environment: ${env}
; Generated: $(date '+%Y-%m-%d %H:%M:%S')
; ============================================================================

[www]
user = bitrix
group = bitrix
listen = 9000
listen.owner = bitrix
listen.group = bitrix
listen.mode = 0660

; Process manager
pm = ${pm_mode}
pm.max_children = ${max_children}
pm.start_servers = ${start_servers}
pm.min_spare_servers = ${min_spare}
pm.max_spare_servers = ${max_spare}
pm.max_requests = ${max_requests}
pm.process_idle_timeout = 10s

; Status & Health
pm.status_path = /status
ping.path = /ping
ping.response = pong

; Logging
access.log = /var/log/php-fpm/access.log
slowlog = /var/log/php-fpm/slow.log
request_slowlog_timeout = 10s

; Timeouts
request_terminate_timeout = 300s

; Environment
clear_env = no
catch_workers_output = yes
decorate_workers_output = no
EOF

    log_success "PHP-FPM: $output"
}

# ============================================================================
# ГЕНЕРАЦИЯ OPcache КОНФИГУРАЦИИ
# ============================================================================

generate_opcache_config() {
    local cpu=$1 ram=$2 env=$3
    local output="$PROJECT_DIR/docker/common/php/conf.d/opcache.ini"

    log_info "Генерация OPcache конфигурации..."

    local mem=256 files=20000 validate=0
    [ "$ram" -gt 8 ] && mem=512
    [ "$env" == "local" ] && validate=1
    [ "$env" == "prod" ] && files=30000

    [ "$DRY_RUN" = true ] && { log_warning "[DRY RUN] $output"; return; }

    mkdir -p "$(dirname "$output")"

    cat > "$output" << EOF
; ============================================================================
; OPcache Configuration - AUTO OPTIMIZED
; Server: ${cpu} CPU, ${ram}GB RAM | Environment: ${env}
; Generated: $(date '+%Y-%m-%d %H:%M:%S')
; ============================================================================

opcache.enable=1
opcache.memory_consumption=${mem}
opcache.interned_strings_buffer=64
opcache.max_accelerated_files=${files}
opcache.max_wasted_percentage=5

; CRITICAL for performance
; Production: 0 (no file checks) | Development: 1
opcache.validate_timestamps=${validate}
opcache.revalidate_freq=0

opcache.save_comments=1
opcache.enable_cli=0
opcache.consistency_checks=0
opcache.force_restart_timeout=180
opcache.blacklist_filename=/etc/php.d/opcache*.blacklist
EOF

    log_success "OPcache: $output"
}

# ============================================================================
# ГЕНЕРАЦИЯ Memcached КОНФИГУРАЦИИ
# ============================================================================

generate_memcached_config() {
    local cpu=$1 ram=$2 env=$3
    local output="$PROJECT_DIR/config/memcached/memcached.conf"

    log_info "Генерация Memcached конфигурации..."

    local mem conn threads
    # Memory: ~1% of RAM, minimum 256-512mb
    case "$env" in
        local)
            mem=$((ram * 1024 / 100))  # 1% of RAM
            [ "$mem" -lt 256 ] && mem=256
            [ "$mem" -gt 512 ] && mem=512  # Cap at 512 for local
            conn=512
            threads=$cpu
            ;;
        dev)
            mem=$((ram * 1024 / 100))  # 1% of RAM
            [ "$mem" -lt 256 ] && mem=256
            [ "$mem" -gt 1024 ] && mem=1024  # Cap at 1GB for dev
            conn=1024
            threads=$cpu
            ;;
        prod)
            mem=$((ram * 1024 * 2 / 100))  # 2% of RAM
            [ "$mem" -lt 512 ] && mem=512
            conn=2048
            threads=$((cpu * 2))
            ;;
    esac

    [ "$DRY_RUN" = true ] && { log_warning "[DRY RUN] $output"; return; }

    mkdir -p "$(dirname "$output")"

    cat > "$output" << EOF
# ============================================================================
# Memcached Configuration - AUTO OPTIMIZED
# Server: ${cpu} CPU, ${ram}GB RAM | Environment: ${env}
# Generated: $(date '+%Y-%m-%d %H:%M:%S')
# ============================================================================

# Memory
-m ${mem}

# Connections
-c ${conn}

# Threads
-t ${threads}

# Max item size
-I 2m

# Listen
-l 0.0.0.0
-p 11211

# Verbose (off in prod)
$([[ "$env" != "prod" ]] && echo "-v" || echo "# -v")
EOF

    log_success "Memcached: $output"
}

# ============================================================================
# ОБНОВЛЕНИЕ .env
# ============================================================================

update_env_file() {
    local cpu=$1 ram=$2 env=$3
    local envfile="$PROJECT_DIR/.env"

    if [ ! -f "$envfile" ]; then
        log_warning ".env не найден, пропуск обновления"
        return
    fi

    log_info "Обновление .env..."

    # PHP-FPM параметры (согласованы с generate_phpfpm_config)
    local max_children
    case "$env" in
        local) max_children=$((cpu * 3)); [ "$max_children" -lt 5 ] && max_children=5 ;;
        dev)   max_children=$((cpu * 4)); [ "$max_children" -lt 8 ] && max_children=8 ;;
        prod)  max_children=$((cpu * 8)); [ "$max_children" -gt 100 ] && max_children=100 ;;
    esac

    local start_servers=$((max_children / 4))
    [ "$start_servers" -lt 2 ] && start_servers=2
    local min_spare=$((start_servers - 1))
    [ "$min_spare" -lt 1 ] && min_spare=1
    local max_spare=$((max_children / 3))
    [ "$max_spare" -lt 2 ] && max_spare=2

    # MySQL параметры (согласованы с generate_mysql_config)
    local available_ram_mb=$((ram * 1024))
    local reserved_mb=1024
    [ "$ram" -le 2 ] && reserved_mb=512

    local mysql_buffer
    case "$env" in
        local)
            mysql_buffer=$((available_ram_mb * 25 / 100))
            [ "$mysql_buffer" -lt 128 ] && mysql_buffer=128
            [ "$mysql_buffer" -gt 1024 ] && mysql_buffer=1024
            ;;
        dev)
            mysql_buffer=$((available_ram_mb * 40 / 100))
            [ "$mysql_buffer" -lt 256 ] && mysql_buffer=256
            [ "$mysql_buffer" -gt 4096 ] && mysql_buffer=4096
            ;;
        prod)
            local max_buffer=$((available_ram_mb - reserved_mb))
            mysql_buffer=$((available_ram_mb * 55 / 100))
            [ "$mysql_buffer" -gt "$max_buffer" ] && mysql_buffer=$max_buffer
            [ "$mysql_buffer" -lt 256 ] && mysql_buffer=256
            ;;
    esac
    mysql_buffer="${mysql_buffer}M"

    # MySQL memory limits для docker (должны быть больше buffer_pool)
    local mysql_mem_limit mysql_mem_reservation
    local buffer_val=${mysql_buffer%M}
    # Memory limit = buffer_pool + 30% overhead (для соединений, временных таблиц и т.д.)
    mysql_mem_limit=$((buffer_val * 130 / 100))
    mysql_mem_reservation=$((buffer_val * 110 / 100))
    # Минимум 512MB limit
    [ "$mysql_mem_limit" -lt 512 ] && mysql_mem_limit=512
    [ "$mysql_mem_reservation" -lt 256 ] && mysql_mem_reservation=256
    mysql_mem_limit="${mysql_mem_limit}M"
    mysql_mem_reservation="${mysql_mem_reservation}M"

    # Memcached (пропорционально RAM)
    local memcached_mem memcached_threads memcached_conn
    case "$env" in
        local)
            memcached_mem=$((ram * 1024 / 100))  # 1% RAM
            [ "$memcached_mem" -lt 64 ] && memcached_mem=64
            [ "$memcached_mem" -gt 256 ] && memcached_mem=256
            memcached_threads=$cpu
            memcached_conn=256
            ;;
        dev)
            memcached_mem=$((ram * 1024 / 100))  # 1% RAM
            [ "$memcached_mem" -lt 128 ] && memcached_mem=128
            [ "$memcached_mem" -gt 512 ] && memcached_mem=512
            memcached_threads=$cpu
            memcached_conn=512
            ;;
        prod)
            memcached_mem=$((ram * 1024 * 2 / 100))  # 2% RAM
            [ "$memcached_mem" -lt 256 ] && memcached_mem=256
            [ "$memcached_mem" -gt 2048 ] && memcached_mem=2048
            memcached_threads=$((cpu * 2))
            memcached_conn=1024
            ;;
    esac

    # Redis memory (2-5% RAM)
    local redis_mem
    case "$env" in
        local) redis_mem=$((ram * 1024 * 2 / 100)); [ "$redis_mem" -lt 128 ] && redis_mem=128; [ "$redis_mem" -gt 512 ] && redis_mem=512 ;;
        dev)   redis_mem=$((ram * 1024 * 3 / 100)); [ "$redis_mem" -lt 256 ] && redis_mem=256; [ "$redis_mem" -gt 1024 ] && redis_mem=1024 ;;
        prod)  redis_mem=$((ram * 1024 * 5 / 100)); [ "$redis_mem" -lt 512 ] && redis_mem=512 ;;
    esac
    redis_mem="${redis_mem}mb"

    [ "$DRY_RUN" = true ] && { log_warning "[DRY RUN] $envfile"; return; }

    # Backup
    cp "$envfile" "${envfile}.backup.$(date +%Y%m%d_%H%M%S)"

    # Update values (macOS compatible sed)
    update_env_var() {
        local var=$1 val=$2
        if grep -q "^${var}=" "$envfile"; then
            if [[ "$OSTYPE" == "darwin"* ]]; then
                sed -i '' "s|^${var}=.*|${var}=${val}|" "$envfile"
            else
                sed -i "s|^${var}=.*|${var}=${val}|" "$envfile"
            fi
        fi
    }

    # PHP-FPM
    update_env_var "PHP_FPM_MAX_CHILDREN" "$max_children"
    update_env_var "PHP_FPM_START_SERVERS" "$start_servers"
    update_env_var "PHP_FPM_MIN_SPARE_SERVERS" "$min_spare"
    update_env_var "PHP_FPM_MAX_SPARE_SERVERS" "$max_spare"

    # MySQL
    update_env_var "MYSQL_INNODB_BUFFER_POOL_SIZE" "$mysql_buffer"
    update_env_var "MYSQL_MEMORY_LIMIT" "$mysql_mem_limit"
    update_env_var "MYSQL_MEMORY_RESERVATION" "$mysql_mem_reservation"

    # Memcached
    update_env_var "MEMCACHED_MEMORY_LIMIT" "$memcached_mem"
    update_env_var "MEMCACHED_THREADS" "$memcached_threads"
    update_env_var "MEMCACHED_CONN_LIMIT" "$memcached_conn"

    # Redis
    update_env_var "REDIS_MAX_MEMORY" "$redis_mem"

    # Production: disable debug
    if [ "$env" = "prod" ]; then
        update_env_var "DEBUG" "0"
    fi

    log_success ".env обновлён:"
    log_info "  MySQL buffer_pool: $mysql_buffer (memory limit: $mysql_mem_limit)"
    log_info "  PHP-FPM: max_children=$max_children"
    log_info "  Memcached: ${memcached_mem}MB"
    log_info "  Redis: $redis_mem"
}

# ============================================================================
# ОТЧЁТ
# ============================================================================

print_report() {
    local cpu=$1 ram=$2 env=$3

    echo ""
    echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}  ОТЧЁТ ПО ОПТИМИЗАЦИИ${NC}"
    echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"
    echo ""
    echo -e "  ${CYAN}Сервер:${NC}     ${GREEN}${cpu}${NC} CPU cores, ${GREEN}${ram}GB${NC} RAM"
    local env_upper
    env_upper=$(echo "$env" | tr 'a-z' 'A-Z')
    echo -e "  ${CYAN}Окружение:${NC}  ${GREEN}${env_upper}${NC}"
    echo ""

    # Расчитанные значения для отображения
    local mysql_buffer memcached_mem redis_mem php_children
    local available_ram_mb=$((ram * 1024))
    case "$env" in
        local)
            mysql_buffer=$((available_ram_mb * 25 / 100))
            [ "$mysql_buffer" -lt 128 ] && mysql_buffer=128
            [ "$mysql_buffer" -gt 1024 ] && mysql_buffer=1024
            memcached_mem=$((ram * 1024 / 100))
            [ "$memcached_mem" -lt 64 ] && memcached_mem=64
            redis_mem=$((ram * 1024 * 2 / 100))
            [ "$redis_mem" -lt 128 ] && redis_mem=128
            php_children=$((cpu * 3))
            ;;
        dev)
            mysql_buffer=$((available_ram_mb * 40 / 100))
            [ "$mysql_buffer" -lt 256 ] && mysql_buffer=256
            memcached_mem=$((ram * 1024 / 100))
            [ "$memcached_mem" -lt 128 ] && memcached_mem=128
            redis_mem=$((ram * 1024 * 3 / 100))
            [ "$redis_mem" -lt 256 ] && redis_mem=256
            php_children=$((cpu * 4))
            ;;
        prod)
            local reserved_mb=1024
            [ "$ram" -le 2 ] && reserved_mb=512
            local max_buffer=$((available_ram_mb - reserved_mb))
            mysql_buffer=$((available_ram_mb * 55 / 100))
            [ "$mysql_buffer" -gt "$max_buffer" ] && mysql_buffer=$max_buffer
            [ "$mysql_buffer" -lt 256 ] && mysql_buffer=256
            memcached_mem=$((ram * 1024 * 2 / 100))
            [ "$memcached_mem" -lt 256 ] && memcached_mem=256
            redis_mem=$((ram * 1024 * 5 / 100))
            [ "$redis_mem" -lt 512 ] && redis_mem=512
            php_children=$((cpu * 8))
            [ "$php_children" -gt 100 ] && php_children=100
            ;;
    esac

    echo -e "  ${CYAN}Расчитанные параметры:${NC}"
    echo -e "    MySQL buffer_pool:  ${GREEN}${mysql_buffer}MB${NC}"
    echo -e "    Redis maxmemory:    ${GREEN}${redis_mem}MB${NC}"
    echo -e "    Memcached memory:   ${GREEN}${memcached_mem}MB${NC}"
    echo -e "    PHP-FPM children:   ${GREEN}${php_children}${NC}"
    echo ""

    echo -e "  ${CYAN}Сгенерированные конфиги:${NC}"
    echo -e "    ${GREEN}✓${NC} config/mysql/my.${env}.cnf"
    echo -e "    ${GREEN}✓${NC} config/redis/redis.conf"
    echo -e "    ${GREEN}✓${NC} config/memcached/memcached.conf"
    echo -e "    ${GREEN}✓${NC} docker/common/nginx/nginx.conf"
    echo -e "    ${GREEN}✓${NC} docker/common/php/php-fpm.d/www.conf"
    echo -e "    ${GREEN}✓${NC} docker/common/php/conf.d/opcache.ini"
    [ "$UPDATE_ENV" = true ] && echo -e "    ${GREEN}✓${NC} .env (обновлён)"
    echo ""

    # Предупреждения для маленьких серверов
    local warnings=0
    if [ "$ram" -lt 2 ]; then
        log_error "RAM < 2GB: КРИТИЧЕСКИ МАЛО! Битрикс может работать нестабильно"
        warnings=$((warnings + 1))
    elif [ "$ram" -lt 4 ]; then
        log_warning "RAM < 4GB: минимальные настройки, рекомендуется 4GB+"
        warnings=$((warnings + 1))
    fi

    if [ "$cpu" -lt 2 ]; then
        log_warning "CPU < 2: рекомендуется минимум 2 ядра"
        warnings=$((warnings + 1))
    fi

    if [ "$mysql_buffer" -lt 512 ]; then
        log_warning "MySQL buffer_pool < 512MB: производительность БД будет низкой"
        warnings=$((warnings + 1))
    fi

    # Рекомендации по типу образа для маленьких серверов
    if [ "$ram" -le 4 ] && [ "$env" = "prod" ]; then
        echo ""
        log_info "Рекомендация для сервера с ${ram}GB RAM:"
        echo -e "    Используйте MariaDB вместо MySQL (меньше потребление RAM):"
        echo -e "    ${YELLOW}MYSQL_IMAGE=mariadb:10.11${NC} в .env"
    fi

    [ "$warnings" -gt 0 ] && echo ""

    echo -e "  ${CYAN}Следующие шаги:${NC}"
    echo -e "    1. Проверьте конфиги: ${YELLOW}git diff${NC}"
    echo -e "    2. Пересоберите:      ${YELLOW}docker compose build --no-cache${NC}"
    echo -e "    3. Перезапустите:     ${YELLOW}docker compose down && docker compose up -d${NC}"
    echo ""

    if [ "$warnings" -gt 0 ]; then
        echo -e "${YELLOW}  ⚠️  Обнаружено $warnings предупреждений - проверьте настройки${NC}"
    else
        echo -e "${GREEN}  ✅ Оптимизация завершена успешно!${NC}"
    fi
    echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"
}

# ============================================================================
# MAIN
# ============================================================================

main() {
    echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}  BITRIX DOCKER - АВТОМАТИЧЕСКАЯ ОПТИМИЗАЦИЯ v2.0${NC}"
    echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"

    # Парсинг аргументов
    while [[ $# -gt 0 ]]; do
        case $1 in
            --cpu-cores)    CPU_CORES="$2"; shift 2 ;;
            --ram-gb)       RAM_GB="$2"; shift 2 ;;
            --environment)  ENVIRONMENT="$2"; shift 2 ;;
            --update-env)   UPDATE_ENV=true; shift ;;
            --force)        FORCE=true; shift ;;
            --dry-run)      DRY_RUN=true; shift ;;
            -h|--help)      show_help; exit 0 ;;
            *)              log_error "Неизвестный параметр: $1"; exit 1 ;;
        esac
    done

    # Детект характеристик
    local cpu=$(detect_cpu_cores)
    local ram=$(detect_ram_gb)
    local env=$(detect_environment)

    # Валидация окружения
    if [[ ! "$env" =~ ^(local|dev|prod)$ ]]; then
        log_error "Неверное окружение: $env (допустимо: local, dev, prod)"
        exit 1
    fi

    log_header "ХАРАКТЕРИСТИКИ СЕРВЕРА"
    log_success "CPU: $cpu ядер"
    log_success "RAM: ${ram}GB"
    log_success "Environment: $env"

    log_header "ГЕНЕРАЦИЯ КОНФИГУРАЦИЙ"

    # Генерация всех конфигов
    generate_mysql_config "$cpu" "$ram" "$env"
    generate_redis_config "$cpu" "$ram" "$env"
    generate_nginx_config "$cpu" "$ram" "$env"
    generate_phpfpm_config "$cpu" "$ram" "$env"
    generate_opcache_config "$cpu" "$ram" "$env"
    generate_memcached_config "$cpu" "$ram" "$env"

    [ "$UPDATE_ENV" = true ] && update_env_file "$cpu" "$ram" "$env"

    # Отчёт
    print_report "$cpu" "$ram" "$env"
}

main "$@"
