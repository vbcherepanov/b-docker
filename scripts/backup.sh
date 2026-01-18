#!/bin/bash
# ============================================================================
# BITRIX DOCKER - BACKUP & RESTORE SCRIPT v2.0
# Easy-to-use backup and restore utility
# Usage: ./backup.sh [command] [options]
# ============================================================================

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Load environment
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$SCRIPT_DIR/.env" ]; then
    # Safe env loading (skip problematic lines)
    while IFS='=' read -r key value; do
        # Skip comments, empty lines, and problematic variables
        [[ "$key" =~ ^[[:space:]]*# ]] && continue
        [[ -z "$key" ]] && continue
        key=$(echo "$key" | xargs 2>/dev/null) || continue
        [[ -z "$value" ]] && continue
        [[ "$key" == "DOLLAR" ]] && continue
        [[ "$key" == "UID" || "$key" == "EUID" || "$key" == "GID" || "$key" == "PPID" ]] && continue
        export "$key=$value" 2>/dev/null || true
    done < "$SCRIPT_DIR/.env"
fi

# Configuration
BACKUP_DIR="${SCRIPT_DIR}/backups"
WWW_DIR="${SCRIPT_DIR}/www"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
DB_HOST="${DB_HOST:-mysql}"
DB_NAME="${DB_NAME:-bitrix}"
DB_USERNAME="${DB_USERNAME:-bitrix}"
BACKUP_RETENTION_DAYS="${BACKUP_RETENTION_DAYS:-7}"

# Ensure backup directories exist
mkdir -p "$BACKUP_DIR"/{database,files,logs}

# Logging
log() {
    local level="$1"
    local message="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    case "$level" in
        "INFO")  echo -e "${BLUE}ℹ${NC} [$timestamp] $message" ;;
        "OK")    echo -e "${GREEN}✓${NC} [$timestamp] $message" ;;
        "WARN")  echo -e "${YELLOW}⚠${NC} [$timestamp] $message" ;;
        "ERROR") echo -e "${RED}✗${NC} [$timestamp] $message" ;;
    esac

    echo "[$timestamp] [$level] $message" >> "$BACKUP_DIR/logs/backup.log"
}

# Show help
show_help() {
    cat << 'EOF'
╔════════════════════════════════════════════════════════════╗
║         BITRIX DOCKER - BACKUP & RESTORE v2.0              ║
╚════════════════════════════════════════════════════════════╝

USAGE:
    ./backup.sh <command> [options]

COMMANDS:
    db              Backup database
    files           Backup site files
    full            Full backup (database + files)
    restore-db      Restore database from backup
    restore-files   Restore files from backup
    list            List all backups
    cleanup         Remove old backups
    status          Show backup status and disk usage

EXAMPLES:
    ./backup.sh db                           # Backup all databases
    ./backup.sh files                        # Backup all site files
    ./backup.sh full                         # Full backup
    ./backup.sh restore-db backup.sql.gz     # Restore database
    ./backup.sh restore-files backup.tar.gz  # Restore files
    ./backup.sh list                         # Show all backups
    ./backup.sh cleanup                      # Remove old backups

OPTIONS:
    --site=example.com    Backup specific site only
    --compress=fast|best  Compression level (default: fast)
    --quiet               Minimal output
    --help                Show this help

EOF
}

# Progress bar
show_progress() {
    local current=$1
    local total=$2
    local width=50
    local percent=$((current * 100 / total))
    local filled=$((width * current / total))
    local empty=$((width - filled))

    printf "\r["
    printf "%${filled}s" | tr ' ' '='
    printf "%${empty}s" | tr ' ' '-'
    printf "] %3d%%" $percent
}

# Get database password safely
get_db_password() {
    if [ -z "${DB_PASSWORD:-}" ]; then
        log "ERROR" "DB_PASSWORD not set in .env"
        exit 1
    fi
    echo "$DB_PASSWORD"
}

# Check if MySQL container is running
check_mysql() {
    if ! docker ps --format '{{.Names}}' | grep -q "mysql"; then
        log "ERROR" "MySQL container is not running"
        log "INFO" "Start containers first: make local"
        exit 1
    fi
}

# Backup database
backup_database() {
    local site="${1:-all}"
    local compress="${2:-fast}"

    check_mysql

    local backup_file
    if [ "$site" = "all" ]; then
        backup_file="$BACKUP_DIR/database/all_databases_${TIMESTAMP}.sql.gz"
        log "INFO" "Starting full database backup..."
    else
        backup_file="$BACKUP_DIR/database/${site}_${TIMESTAMP}.sql.gz"
        log "INFO" "Starting database backup for: $site"
    fi

    local gzip_level="-1"
    [ "$compress" = "best" ] && gzip_level="-9"

    local db_pass
    db_pass=$(get_db_password)

    if [ "$site" = "all" ]; then
        if docker exec -e MYSQL_PWD="$db_pass" mysql mysqldump \
            -u "$DB_USERNAME" \
            --single-transaction \
            --routines \
            --triggers \
            --events \
            --quick \
            --lock-tables=false \
            --all-databases 2>/dev/null | gzip $gzip_level > "$backup_file"; then

            local size=$(du -h "$backup_file" | cut -f1)
            log "OK" "Database backup completed: $backup_file ($size)"
        else
            log "ERROR" "Database backup failed"
            rm -f "$backup_file"
            return 1
        fi
    else
        local db_name="${site//./_}"
        if docker exec -e MYSQL_PWD="$db_pass" mysql mysqldump \
            -u "$DB_USERNAME" \
            --single-transaction \
            --routines \
            --triggers \
            --events \
            --quick \
            --lock-tables=false \
            "$db_name" 2>/dev/null | gzip $gzip_level > "$backup_file"; then

            local size=$(du -h "$backup_file" | cut -f1)
            log "OK" "Database backup completed: $backup_file ($size)"
        else
            log "ERROR" "Database backup failed for: $site"
            rm -f "$backup_file"
            return 1
        fi
    fi
}

# Backup files
backup_files() {
    local site="${1:-all}"
    local compress="${2:-fast}"

    local backup_file
    local source_dir

    if [ "$site" = "all" ]; then
        backup_file="$BACKUP_DIR/files/all_sites_${TIMESTAMP}.tar.gz"
        source_dir="$WWW_DIR"
        log "INFO" "Starting backup of all site files..."
    else
        backup_file="$BACKUP_DIR/files/${site}_${TIMESTAMP}.tar.gz"
        source_dir="$WWW_DIR/$site"
        log "INFO" "Starting backup of files for: $site"
    fi

    if [ ! -d "$source_dir" ]; then
        log "ERROR" "Source directory not found: $source_dir"
        return 1
    fi

    local gzip_level=""
    [ "$compress" = "best" ] && gzip_level="--gzip"

    # Calculate total size for progress
    log "INFO" "Calculating size..."
    local total_size=$(du -sb "$source_dir" 2>/dev/null | cut -f1)

    if tar -czf "$backup_file" \
        -C "$(dirname "$source_dir")" \
        --exclude='*.log' \
        --exclude='cache' \
        --exclude='tmp' \
        --exclude='bitrix/cache' \
        --exclude='bitrix/tmp' \
        --exclude='bitrix/managed_cache' \
        --exclude='bitrix/stack_cache' \
        --exclude='upload/resize_cache' \
        "$(basename "$source_dir")" 2>/dev/null; then

        local size=$(du -h "$backup_file" | cut -f1)
        log "OK" "Files backup completed: $backup_file ($size)"
    else
        log "ERROR" "Files backup failed"
        rm -f "$backup_file"
        return 1
    fi
}

# Full backup
backup_full() {
    local site="${1:-all}"
    local compress="${2:-fast}"

    echo ""
    echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}  FULL BACKUP - $site${NC}"
    echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"
    echo ""

    backup_database "$site" "$compress"
    echo ""
    backup_files "$site" "$compress"

    echo ""
    echo -e "${GREEN}════════════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}  BACKUP COMPLETED!${NC}"
    echo -e "${GREEN}════════════════════════════════════════════════════════════${NC}"

    # Cleanup old backups
    cleanup_backups
}

# Restore database
restore_database() {
    local backup_file="$1"
    local db_name="${2:-$DB_NAME}"

    if [ ! -f "$backup_file" ]; then
        # Try to find in backup directory
        if [ -f "$BACKUP_DIR/database/$backup_file" ]; then
            backup_file="$BACKUP_DIR/database/$backup_file"
        else
            log "ERROR" "Backup file not found: $backup_file"
            return 1
        fi
    fi

    check_mysql

    log "WARN" "This will OVERWRITE database: $db_name"
    echo -n "Continue? [y/N]: "
    read -r confirm
    if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
        log "INFO" "Restore cancelled"
        return 0
    fi

    log "INFO" "Restoring database from: $backup_file"

    local db_pass
    db_pass=$(get_db_password)

    if [[ "$backup_file" == *.gz ]]; then
        if zcat "$backup_file" | docker exec -i -e MYSQL_PWD="$db_pass" mysql mysql -u "$DB_USERNAME" "$db_name"; then
            log "OK" "Database restored successfully"
        else
            log "ERROR" "Database restore failed"
            return 1
        fi
    else
        if docker exec -i -e MYSQL_PWD="$db_pass" mysql mysql -u "$DB_USERNAME" "$db_name" < "$backup_file"; then
            log "OK" "Database restored successfully"
        else
            log "ERROR" "Database restore failed"
            return 1
        fi
    fi
}

# Restore files
restore_files() {
    local backup_file="$1"
    local site="${2:-}"

    if [ ! -f "$backup_file" ]; then
        # Try to find in backup directory
        if [ -f "$BACKUP_DIR/files/$backup_file" ]; then
            backup_file="$BACKUP_DIR/files/$backup_file"
        else
            log "ERROR" "Backup file not found: $backup_file"
            return 1
        fi
    fi

    local restore_dir
    if [ -z "$site" ]; then
        restore_dir="$WWW_DIR"
        log "WARN" "This will restore files to: $restore_dir"
    else
        restore_dir="$WWW_DIR/$site"
        log "WARN" "This will restore files to: $restore_dir"
    fi

    echo -n "Continue? [y/N]: "
    read -r confirm
    if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
        log "INFO" "Restore cancelled"
        return 0
    fi

    log "INFO" "Restoring files from: $backup_file"

    mkdir -p "$restore_dir"

    if tar -xzf "$backup_file" -C "$restore_dir"; then
        log "OK" "Files restored successfully to: $restore_dir"
    else
        log "ERROR" "Files restore failed"
        return 1
    fi
}

# List backups
list_backups() {
    echo ""
    echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}  AVAILABLE BACKUPS${NC}"
    echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"
    echo ""

    echo -e "${CYAN}📊 Database Backups:${NC}"
    if ls -1 "$BACKUP_DIR/database"/*.sql.gz 2>/dev/null; then
        ls -lh "$BACKUP_DIR/database"/*.sql.gz 2>/dev/null | awk '{print "  " $9 " (" $5 ")"}'
    else
        echo "  No database backups found"
    fi

    echo ""
    echo -e "${CYAN}📁 File Backups:${NC}"
    if ls -1 "$BACKUP_DIR/files"/*.tar.gz 2>/dev/null; then
        ls -lh "$BACKUP_DIR/files"/*.tar.gz 2>/dev/null | awk '{print "  " $9 " (" $5 ")"}'
    else
        echo "  No file backups found"
    fi

    echo ""
    echo -e "${CYAN}💾 Total Backup Size:${NC}"
    du -sh "$BACKUP_DIR" 2>/dev/null | awk '{print "  " $1}'
    echo ""
}

# Cleanup old backups
cleanup_backups() {
    log "INFO" "Cleaning up backups older than $BACKUP_RETENTION_DAYS days..."

    local db_count=$(find "$BACKUP_DIR/database" -name "*.sql.gz" -mtime +$BACKUP_RETENTION_DAYS -delete -print 2>/dev/null | wc -l)
    local files_count=$(find "$BACKUP_DIR/files" -name "*.tar.gz" -mtime +$BACKUP_RETENTION_DAYS -delete -print 2>/dev/null | wc -l)

    log "OK" "Cleanup done: removed $db_count DB backups, $files_count file backups"
}

# Show backup status
show_status() {
    echo ""
    echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}  BACKUP STATUS${NC}"
    echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"
    echo ""

    echo -e "${CYAN}Configuration:${NC}"
    echo "  Backup Directory:    $BACKUP_DIR"
    echo "  Retention Days:      $BACKUP_RETENTION_DAYS"
    echo "  Database Host:       $DB_HOST"
    echo "  Database Name:       $DB_NAME"
    echo ""

    echo -e "${CYAN}Backup Counts:${NC}"
    local db_count=$(ls -1 "$BACKUP_DIR/database"/*.sql.gz 2>/dev/null | wc -l)
    local files_count=$(ls -1 "$BACKUP_DIR/files"/*.tar.gz 2>/dev/null | wc -l)
    echo "  Database Backups:    $db_count"
    echo "  File Backups:        $files_count"
    echo ""

    echo -e "${CYAN}Latest Backups:${NC}"
    echo "  DB:    $(ls -1t "$BACKUP_DIR/database"/*.sql.gz 2>/dev/null | head -1 || echo 'None')"
    echo "  Files: $(ls -1t "$BACKUP_DIR/files"/*.tar.gz 2>/dev/null | head -1 || echo 'None')"
    echo ""

    echo -e "${CYAN}Disk Usage:${NC}"
    du -sh "$BACKUP_DIR"/* 2>/dev/null | awk '{print "  " $2 ": " $1}'
    echo ""
}

# Parse arguments
SITE="all"
COMPRESS="fast"
QUIET=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --site=*)
            SITE="${1#*=}"
            shift
            ;;
        --compress=*)
            COMPRESS="${1#*=}"
            shift
            ;;
        --quiet)
            QUIET=true
            shift
            ;;
        --help|-h)
            show_help
            exit 0
            ;;
        *)
            break
            ;;
    esac
done

# Main command handler
case "${1:-}" in
    "db"|"database")
        backup_database "$SITE" "$COMPRESS"
        ;;
    "files")
        backup_files "$SITE" "$COMPRESS"
        ;;
    "full")
        backup_full "$SITE" "$COMPRESS"
        ;;
    "restore-db"|"restore-database")
        if [ -z "${2:-}" ]; then
            log "ERROR" "Please specify backup file: ./backup.sh restore-db <file.sql.gz>"
            exit 1
        fi
        restore_database "$2" "${3:-}"
        ;;
    "restore-files")
        if [ -z "${2:-}" ]; then
            log "ERROR" "Please specify backup file: ./backup.sh restore-files <file.tar.gz>"
            exit 1
        fi
        restore_files "$2" "${3:-}"
        ;;
    "list")
        list_backups
        ;;
    "cleanup")
        cleanup_backups
        ;;
    "status")
        show_status
        ;;
    "help"|"--help"|"-h"|"")
        show_help
        ;;
    *)
        log "ERROR" "Unknown command: $1"
        echo ""
        show_help
        exit 1
        ;;
esac
