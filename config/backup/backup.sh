#!/bin/bash

# =============================================================================
# Bitrix Docker Backup Script
# Auto-detects mysqldump vs mariadb-dump
# Sources environment from /etc/environment.backup (cron-safe)
# =============================================================================

# Source environment (cron doesn't pass container ENV)
if [ -f /etc/environment.backup ]; then
    set -a
    source /etc/environment.backup
    set +a
fi

# Settings
DB_HOST="${DB_HOST:-mysql}"
DB_NAME="${DB_NAME:-bitrix}"
DB_USERNAME="${DB_USERNAME:-bitrix}"
BACKUP_RETENTION_DAYS="${BACKUP_RETENTION_DAYS:-7}"

if [ -z "${DB_PASSWORD:-}" ]; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') - ERROR: DB_PASSWORD not set"
    exit 1
fi

# Directories
BACKUP_DIR="/backups"
APP_DIR="/home/bitrix/app"
LOG_FILE="/var/log/backup.log"

# Detect dump tool
if command -v mysqldump >/dev/null 2>&1; then
    DUMP_CMD="mysqldump"
elif command -v mariadb-dump >/dev/null 2>&1; then
    DUMP_CMD="mariadb-dump"
else
    echo "$(date '+%Y-%m-%d %H:%M:%S') - ERROR: No dump tool found"
    exit 1
fi

# Detect mysql client
MYSQL_CMD="mysql"
command -v mariadb >/dev/null 2>&1 && MYSQL_CMD="mariadb"

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

mkdir -p "$BACKUP_DIR/database" "$BACKUP_DIR/files"

# ---------------------------------------------------------------------------
backup_database() {
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local backup_file="$BACKUP_DIR/database/db_backup_${timestamp}.sql.gz"

    log "Starting database backup: $DB_NAME (using $DUMP_CMD)"

    # Pre-flight: verify connection and check table count
    export MYSQL_PWD="$DB_PASSWORD"

    local table_count
    table_count=$($MYSQL_CMD -h "$DB_HOST" -u "$DB_USERNAME" -N -e \
        "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='$DB_NAME'" 2>/dev/null)

    if [ -z "$table_count" ] || [ "$table_count" -eq 0 ]; then
        unset MYSQL_PWD
        log "ERROR: Database $DB_NAME has 0 tables — aborting (refusing to create empty backup)"
        return 1
    fi

    log "Database has $table_count tables"

    # Run dump
    if $DUMP_CMD -h "$DB_HOST" -u "$DB_USERNAME" \
        --single-transaction \
        --routines \
        --triggers \
        --events \
        --quick \
        --lock-tables=false \
        "$DB_NAME" 2>>"$LOG_FILE" | gzip > "$backup_file"; then
        unset MYSQL_PWD

        # Verify backup is not suspiciously small (< 1KB = likely empty)
        local size_bytes
        size_bytes=$(stat -c%s "$backup_file" 2>/dev/null || stat -f%z "$backup_file" 2>/dev/null || echo 0)

        if [ "$size_bytes" -lt 1024 ]; then
            log "ERROR: Backup file too small (${size_bytes} bytes) — likely empty dump"
            rm -f "$backup_file"
            return 1
        fi

        local size
        size=$(du -h "$backup_file" | cut -f1)
        log "Database backup complete: $backup_file ($size, $table_count tables)"
    else
        unset MYSQL_PWD
        log "ERROR: $DUMP_CMD failed"
        rm -f "$backup_file"
        return 1
    fi
}

# ---------------------------------------------------------------------------
backup_files() {
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local backup_file="$BACKUP_DIR/files/files_backup_${timestamp}.tar.gz"

    log "Starting files backup: $APP_DIR"

    if [ ! -d "$APP_DIR" ]; then
        log "ERROR: Directory $APP_DIR not found"
        return 1
    fi

    if tar -czf "$backup_file" -C "$APP_DIR" \
        --exclude='*.log' \
        --exclude='cache/*' \
        --exclude='tmp/*' \
        --exclude='bitrix/cache/*' \
        --exclude='bitrix/tmp/*' \
        --exclude='bitrix/managed_cache/*' \
        --exclude='bitrix/stack_cache/*' \
        --exclude='upload/resize_cache/*' \
        . 2>>"$LOG_FILE"; then

        if [ -s "$backup_file" ]; then
            local size
            size=$(du -h "$backup_file" | cut -f1)
            log "Files backup complete: $backup_file ($size)"
        else
            log "ERROR: Files backup is empty"
            rm -f "$backup_file"
            return 1
        fi
    else
        log "ERROR: tar failed"
        rm -f "$backup_file"
        return 1
    fi
}

# ---------------------------------------------------------------------------
cleanup_old_backups() {
    log "Cleaning backups older than $BACKUP_RETENTION_DAYS days"

    local db_removed
    db_removed=$(find "$BACKUP_DIR/database" -name "*.sql.gz" -mtime +$BACKUP_RETENTION_DAYS -delete -print 2>/dev/null | wc -l)

    local files_removed
    files_removed=$(find "$BACKUP_DIR/files" -name "*.tar.gz" -mtime +$BACKUP_RETENTION_DAYS -delete -print 2>/dev/null | wc -l)

    log "Cleanup done: removed $db_removed db + $files_removed file backups"
}

# ---------------------------------------------------------------------------
main() {
    case "${1:-}" in
        database)
            backup_database
            ;;
        files)
            backup_files
            ;;
        cleanup)
            cleanup_old_backups
            ;;
        full)
            backup_database
            backup_files
            cleanup_old_backups
            ;;
        *)
            echo "Usage: $0 {database|files|cleanup|full}"
            exit 1
            ;;
    esac
}

main "$@"
