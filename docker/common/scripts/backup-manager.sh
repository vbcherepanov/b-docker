#!/bin/bash
# ============================================================================
# BACKUP MANAGER FOR BITRIX DOCKER MULTISITE
# Per-site backups with individual DB credentials
# ============================================================================

set -euo pipefail

# Global settings
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

# Directories
BACKUP_DIR="$PROJECT_ROOT/backups"
WWW_DIR="$PROJECT_ROOT/www"
SITES_CONFIG_DIR="$PROJECT_ROOT/config/sites"
LOG_FILE="$BACKUP_DIR/backup.log"

# Default DB settings (for all-db backup or legacy)
DB_HOST="${DB_HOST:-mysql}"
DB_ROOT_PASSWORD="${DB_ROOT_PASSWORD:-}"
BACKUP_RETENTION_DAYS="${BACKUP_RETENTION_DAYS:-7}"
DOMAIN="${DOMAIN:-bitrix.local}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Logging
log() {
    local level="$1"
    local message="$2"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    case "$level" in
        "INFO")  echo -e "${BLUE}ℹ${NC} [$timestamp] $message" ;;
        "OK")    echo -e "${GREEN}✓${NC} [$timestamp] $message" ;;
        "WARN")  echo -e "${YELLOW}⚠${NC} [$timestamp] $message" ;;
        "ERROR") echo -e "${RED}✗${NC} [$timestamp] $message" ;;
    esac

    echo "[$timestamp] [$level] $message" >> "$LOG_FILE" 2>/dev/null || true
}

# Initialize backup directories
init_backup_dirs() {
    mkdir -p "$BACKUP_DIR/database" "$BACKUP_DIR/files" "$BACKUP_DIR/full"
    touch "$LOG_FILE" 2>/dev/null || true
}

# Get list of sites
get_sites_list() {
    local sites=()
    if [ -d "$WWW_DIR" ]; then
        for dir in "$WWW_DIR"/*/; do
            if [ -d "$dir" ]; then
                local site
                site=$(basename "$dir")
                if [[ "$site" == _* ]]; then continue; fi
                if [[ "$site" == .* ]]; then continue; fi
                sites+=("$site")
            fi
        done
    fi
    echo "${sites[@]}"
}

# Get site DB credentials from site.env
get_site_db_credentials() {
    local site="$1"
    local site_env="$SITES_CONFIG_DIR/$site/site.env"

    if [ -f "$site_env" ]; then
        # shellcheck disable=SC1090
        source "$site_env"
        echo "$DB_NAME|$DB_USER|$DB_PASSWORD"
    else
        # Fallback to domain-based naming
        local db_name="${site//./_}"
        echo "$db_name||"
    fi
}

# Show help
show_help() {
    cat << 'EOF'
╔════════════════════════════════════════════════════════════╗
║  BACKUP MANAGER FOR BITRIX DOCKER MULTISITE                ║
╚════════════════════════════════════════════════════════════╝

ИСПОЛЬЗОВАНИЕ:
    backup-manager.sh <command> [options]

КОМАНДЫ БЭКАПА:
    database [SITE]           Бэкап базы данных
    files [SITE]              Бэкап файлов сайта
    full [SITE]               Полный бэкап (БД + файлы)

    Если SITE не указан - бэкапятся ВСЕ сайты

КОМАНДЫ ВОССТАНОВЛЕНИЯ:
    restore database <FILE> [SITE]    Восстановить БД
    restore files <FILE> [SITE]       Восстановить файлы
    restore full <PREFIX> [SITE]      Восстановить БД и файлы

УПРАВЛЕНИЕ:
    list [database|files|all]   Список бэкапов
    sites                       Список сайтов
    cleanup                     Очистка старых бэкапов

ПРИМЕРЫ:
    backup-manager.sh database shop.local      # Бэкап БД shop.local
    backup-manager.sh files shop.local         # Бэкап файлов shop.local
    backup-manager.sh full                     # Полный бэкап ВСЕХ сайтов
    backup-manager.sh full shop.local          # Полный бэкап shop.local

    backup-manager.sh restore database backups/database/shop.local_20260118.sql.gz shop.local
    backup-manager.sh restore files backups/files/shop.local_20260118.tar.gz shop.local

    backup-manager.sh list                     # Все бэкапы
    backup-manager.sh sites                    # Список сайтов с БД info

СТРУКТУРА БЭКАПОВ:
    backups/
    ├── database/
    │   ├── shop.local_20260118_120000.sql.gz
    │   └── all_databases_20260118_120000.sql.gz
    ├── files/
    │   ├── shop.local_20260118_120000.tar.gz
    │   └── all_sites_20260118_120000.tar.gz
    └── full/
        └── shop.local_20260118_120000/
            ├── database.sql.gz
            └── files.tar.gz

EOF
}

# List available sites with DB info
list_sites() {
    echo ""
    echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}  ДОСТУПНЫЕ САЙТЫ ДЛЯ БЭКАПА${NC}"
    echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"
    echo ""

    printf "  %-25s %-20s %-15s\n" "САЙТ" "БАЗА ДАННЫХ" "РАЗМЕР"
    printf "  %-25s %-20s %-15s\n" "----" "-----------" "------"

    for site in $(get_sites_list); do
        local site_dir="$WWW_DIR/$site"
        local size="N/A"
        local db_name="N/A"

        if [ -d "$site_dir" ]; then
            size=$(du -sh "$site_dir" 2>/dev/null | cut -f1)
        fi

        local site_env="$SITES_CONFIG_DIR/$site/site.env"
        if [ -f "$site_env" ]; then
            db_name=$(grep '^DB_NAME=' "$site_env" | cut -d'=' -f2)
        else
            db_name="${site//./_}"
        fi

        printf "  %-25s %-20s %-15s\n" "$site" "$db_name" "$size"
    done

    echo ""
}

# Backup database for a specific site
backup_database_site() {
    local site="$1"
    local timestamp
    timestamp=$(date +%Y%m%d_%H%M%S)

    # Get site DB credentials
    local creds
    creds=$(get_site_db_credentials "$site")
    local db_name db_user db_password
    db_name=$(echo "$creds" | cut -d'|' -f1)
    db_user=$(echo "$creds" | cut -d'|' -f2)
    db_password=$(echo "$creds" | cut -d'|' -f3)

    local backup_file="$BACKUP_DIR/database/${site}_${timestamp}.sql.gz"

    log "INFO" "Бэкап БД сайта: $site (база: $db_name)"

    # Use site-specific credentials if available, otherwise root
    local mysql_user mysql_pass
    if [ -n "$db_user" ] && [ -n "$db_password" ]; then
        mysql_user="$db_user"
        mysql_pass="$db_password"
    else
        mysql_user="root"
        mysql_pass="$DB_ROOT_PASSWORD"
    fi

    if docker exec -e MYSQL_PWD="$mysql_pass" "${DOMAIN}_mysql" mysqldump \
        -u "$mysql_user" \
        --single-transaction \
        --routines \
        --triggers \
        --quick \
        --lock-tables=false \
        "$db_name" 2>/dev/null | gzip > "$backup_file"; then

        local size
        size=$(du -h "$backup_file" | cut -f1)
        log "OK" "Бэкап БД создан: $backup_file ($size)"
        echo "$backup_file"
    else
        log "ERROR" "Ошибка создания бэкапа БД для $site"
        rm -f "$backup_file"
        return 1
    fi
}

# Backup all databases
backup_database_all() {
    local timestamp
    timestamp=$(date +%Y%m%d_%H%M%S)
    local backup_file="$BACKUP_DIR/database/all_databases_${timestamp}.sql.gz"

    log "INFO" "Бэкап ВСЕХ баз данных..."

    if docker exec -e MYSQL_PWD="$DB_ROOT_PASSWORD" "${DOMAIN}_mysql" mysqldump \
        -u root \
        --single-transaction \
        --routines \
        --triggers \
        --events \
        --quick \
        --lock-tables=false \
        --all-databases 2>/dev/null | gzip > "$backup_file"; then

        local size
        size=$(du -h "$backup_file" | cut -f1)
        log "OK" "Бэкап всех БД создан: $backup_file ($size)"
        echo "$backup_file"
    else
        log "ERROR" "Ошибка создания бэкапа всех БД"
        rm -f "$backup_file"
        return 1
    fi
}

# Main database backup function
backup_database() {
    local site="${1:-}"

    init_backup_dirs

    if [ -z "$site" ] || [ "$site" = "all" ]; then
        # Backup each site's database individually
        log "INFO" "Бэкап баз данных всех сайтов..."
        for s in $(get_sites_list); do
            backup_database_site "$s" || true
        done
    else
        backup_database_site "$site"
    fi
}

# Backup files for a specific site
backup_files_site() {
    local site="$1"
    local timestamp
    timestamp=$(date +%Y%m%d_%H%M%S)
    local site_dir="$WWW_DIR/$site"
    local backup_file="$BACKUP_DIR/files/${site}_${timestamp}.tar.gz"

    if [ ! -d "$site_dir" ]; then
        log "ERROR" "Директория сайта не найдена: $site_dir"
        return 1
    fi

    log "INFO" "Бэкап файлов сайта: $site"

    if tar -czf "$backup_file" -C "$WWW_DIR" \
        --exclude='*.log' \
        --exclude='bitrix/cache' \
        --exclude='bitrix/tmp' \
        --exclude='bitrix/managed_cache' \
        --exclude='bitrix/stack_cache' \
        --exclude='upload/resize_cache' \
        "$site" 2>/dev/null; then

        local size
        size=$(du -h "$backup_file" | cut -f1)
        log "OK" "Бэкап файлов создан: $backup_file ($size)"
        echo "$backup_file"
    else
        log "ERROR" "Ошибка создания бэкапа файлов для $site"
        rm -f "$backup_file"
        return 1
    fi
}

# Backup all sites' files
backup_files_all() {
    local timestamp
    timestamp=$(date +%Y%m%d_%H%M%S)
    local backup_file="$BACKUP_DIR/files/all_sites_${timestamp}.tar.gz"

    log "INFO" "Бэкап файлов ВСЕХ сайтов..."

    if tar -czf "$backup_file" -C "$WWW_DIR" \
        --exclude='*.log' \
        --exclude='bitrix/cache' \
        --exclude='bitrix/tmp' \
        --exclude='bitrix/managed_cache' \
        --exclude='bitrix/stack_cache' \
        --exclude='upload/resize_cache' \
        . 2>/dev/null; then

        local size
        size=$(du -h "$backup_file" | cut -f1)
        log "OK" "Бэкап всех файлов создан: $backup_file ($size)"
        echo "$backup_file"
    else
        log "ERROR" "Ошибка создания бэкапа всех файлов"
        rm -f "$backup_file"
        return 1
    fi
}

# Main files backup function
backup_files() {
    local site="${1:-}"

    init_backup_dirs

    if [ -z "$site" ] || [ "$site" = "all" ]; then
        # Backup each site individually
        log "INFO" "Бэкап файлов всех сайтов..."
        for s in $(get_sites_list); do
            backup_files_site "$s" || true
        done
    else
        backup_files_site "$site"
    fi
}

# Full backup (database + files)
backup_full() {
    local site="${1:-}"
    local timestamp
    timestamp=$(date +%Y%m%d_%H%M%S)

    init_backup_dirs

    echo ""
    echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"
    if [ -z "$site" ] || [ "$site" = "all" ]; then
        echo -e "${BLUE}  ПОЛНЫЙ БЭКАП ВСЕХ САЙТОВ${NC}"
    else
        echo -e "${BLUE}  ПОЛНЫЙ БЭКАП: $site${NC}"
    fi
    echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"
    echo ""

    if [ -z "$site" ] || [ "$site" = "all" ]; then
        for s in $(get_sites_list); do
            log "INFO" "=== Бэкап сайта: $s ==="

            local full_dir="$BACKUP_DIR/full/${s}_${timestamp}"
            mkdir -p "$full_dir"

            # Database
            if backup_database_site "$s" > /dev/null 2>&1; then
                mv "$BACKUP_DIR/database/${s}_"*.sql.gz "$full_dir/database.sql.gz" 2>/dev/null || true
            fi

            # Files
            if backup_files_site "$s" > /dev/null 2>&1; then
                mv "$BACKUP_DIR/files/${s}_"*.tar.gz "$full_dir/files.tar.gz" 2>/dev/null || true
            fi

            log "OK" "Полный бэкап $s: $full_dir"
        done
    else
        local full_dir="$BACKUP_DIR/full/${site}_${timestamp}"
        mkdir -p "$full_dir"

        # Database
        log "INFO" "[1/2] Бэкап базы данных..."
        if backup_database_site "$site" > /dev/null 2>&1; then
            mv "$BACKUP_DIR/database/${site}_"*.sql.gz "$full_dir/database.sql.gz" 2>/dev/null || true
            log "OK" "БД сохранена"
        else
            log "WARN" "Ошибка бэкапа БД"
        fi

        # Files
        log "INFO" "[2/2] Бэкап файлов..."
        if backup_files_site "$site" > /dev/null 2>&1; then
            mv "$BACKUP_DIR/files/${site}_"*.tar.gz "$full_dir/files.tar.gz" 2>/dev/null || true
            log "OK" "Файлы сохранены"
        else
            log "WARN" "Ошибка бэкапа файлов"
        fi

        local size
        size=$(du -sh "$full_dir" | cut -f1)
        echo ""
        log "OK" "Полный бэкап создан: $full_dir ($size)"
    fi

    echo ""
}

# Restore database
restore_database() {
    local backup_file="$1"
    local site="${2:-}"

    if [ ! -f "$backup_file" ]; then
        log "ERROR" "Файл бэкапа не найден: $backup_file"
        return 1
    fi

    # Get DB name
    local db_name
    if [ -n "$site" ]; then
        local creds
        creds=$(get_site_db_credentials "$site")
        db_name=$(echo "$creds" | cut -d'|' -f1)
    else
        # Try to extract from filename
        db_name=$(basename "$backup_file" | sed 's/_[0-9]*_[0-9]*\.sql\.gz$//' | tr '.' '_')
    fi

    log "INFO" "Восстановление БД: $db_name из $backup_file"

    if [[ "$backup_file" == *.gz ]]; then
        if zcat "$backup_file" | docker exec -i -e MYSQL_PWD="$DB_ROOT_PASSWORD" "${DOMAIN}_mysql" mysql -u root "$db_name"; then
            log "OK" "База данных $db_name восстановлена"
        else
            log "ERROR" "Ошибка восстановления БД"
            return 1
        fi
    else
        if docker exec -i -e MYSQL_PWD="$DB_ROOT_PASSWORD" "${DOMAIN}_mysql" mysql -u root "$db_name" < "$backup_file"; then
            log "OK" "База данных $db_name восстановлена"
        else
            log "ERROR" "Ошибка восстановления БД"
            return 1
        fi
    fi
}

# Restore files
restore_files() {
    local backup_file="$1"
    local site="${2:-}"

    if [ ! -f "$backup_file" ]; then
        log "ERROR" "Файл бэкапа не найден: $backup_file"
        return 1
    fi

    local restore_dir
    if [ -n "$site" ]; then
        restore_dir="$WWW_DIR/$site"
        mkdir -p "$restore_dir"
    else
        restore_dir="$WWW_DIR"
    fi

    log "INFO" "Восстановление файлов в: $restore_dir"

    if tar -xzf "$backup_file" -C "$restore_dir"; then
        log "OK" "Файлы восстановлены в $restore_dir"
    else
        log "ERROR" "Ошибка восстановления файлов"
        return 1
    fi
}

# Restore full backup
restore_full() {
    local prefix="$1"
    local site="${2:-}"

    # Find backup directory
    local backup_dir
    if [ -d "$prefix" ]; then
        backup_dir="$prefix"
    elif [ -d "$BACKUP_DIR/full/$prefix" ]; then
        backup_dir="$BACKUP_DIR/full/$prefix"
    else
        log "ERROR" "Директория бэкапа не найдена: $prefix"
        return 1
    fi

    log "INFO" "Восстановление полного бэкапа из: $backup_dir"

    # Restore database
    if [ -f "$backup_dir/database.sql.gz" ]; then
        restore_database "$backup_dir/database.sql.gz" "$site"
    fi

    # Restore files
    if [ -f "$backup_dir/files.tar.gz" ]; then
        restore_files "$backup_dir/files.tar.gz" "$site"
    fi

    log "OK" "Полное восстановление завершено"
}

# List backups
list_backups() {
    local type="${1:-all}"

    init_backup_dirs

    echo ""
    echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}  СПИСОК БЭКАПОВ${NC}"
    echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"
    echo ""

    if [ "$type" = "database" ] || [ "$type" = "all" ]; then
        echo -e "${CYAN}📦 Бэкапы баз данных:${NC}"
        if ls "$BACKUP_DIR/database"/*.sql.gz 2>/dev/null | head -20; then
            :
        else
            echo "   (нет бэкапов)"
        fi
        echo ""
    fi

    if [ "$type" = "files" ] || [ "$type" = "all" ]; then
        echo -e "${CYAN}📁 Бэкапы файлов:${NC}"
        if ls "$BACKUP_DIR/files"/*.tar.gz 2>/dev/null | head -20; then
            :
        else
            echo "   (нет бэкапов)"
        fi
        echo ""
    fi

    if [ "$type" = "all" ]; then
        echo -e "${CYAN}📦 Полные бэкапы:${NC}"
        if ls -d "$BACKUP_DIR/full"/*/ 2>/dev/null | head -20; then
            :
        else
            echo "   (нет бэкапов)"
        fi
        echo ""
    fi
}

# Cleanup old backups
cleanup_old_backups() {
    init_backup_dirs

    log "INFO" "Очистка бэкапов старше $BACKUP_RETENTION_DAYS дней..."

    local db_count files_count full_count
    db_count=$(find "$BACKUP_DIR/database" -name "*.sql.gz" -mtime +"$BACKUP_RETENTION_DAYS" -delete -print 2>/dev/null | wc -l)
    files_count=$(find "$BACKUP_DIR/files" -name "*.tar.gz" -mtime +"$BACKUP_RETENTION_DAYS" -delete -print 2>/dev/null | wc -l)
    full_count=$(find "$BACKUP_DIR/full" -maxdepth 1 -type d -mtime +"$BACKUP_RETENTION_DAYS" -exec rm -rf {} \; -print 2>/dev/null | wc -l)

    log "OK" "Удалено: $db_count БД, $files_count файлов, $full_count полных бэкапов"
}

# Main command handler
case "${1:-}" in
    "database"|"db")
        backup_database "${2:-}"
        ;;
    "files")
        backup_files "${2:-}"
        ;;
    "full")
        backup_full "${2:-}"
        ;;
    "restore")
        case "${2:-}" in
            "database"|"db")
                restore_database "${3:-}" "${4:-}"
                ;;
            "files")
                restore_files "${3:-}" "${4:-}"
                ;;
            "full")
                restore_full "${3:-}" "${4:-}"
                ;;
            *)
                log "ERROR" "Укажите тип: database, files или full"
                exit 1
                ;;
        esac
        ;;
    "list")
        list_backups "${2:-all}"
        ;;
    "sites")
        list_sites
        ;;
    "cleanup")
        cleanup_old_backups
        ;;
    "help"|"--help"|"-h"|"")
        show_help
        ;;
    *)
        log "ERROR" "Неизвестная команда: $1"
        show_help
        exit 1
        ;;
esac
