#!/bin/bash
set -e

# Source environment (cron doesn't pass container ENV)
if [ -f /etc/environment.backup ]; then
    set -a
    source /etc/environment.backup
    set +a
fi

BACKUP_DIR="${BACKUP_DIR:-/backups}"
RETENTION_DAYS="${BACKUP_RETENTION_DAYS:-7}"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

log "Starting cleanup (retention: $RETENTION_DAYS days)"

# Cleanup database backups
if [ -d "$BACKUP_DIR/database" ]; then
    removed=$(find "$BACKUP_DIR/database" -type f -name "*.sql.gz" -mtime +$RETENTION_DAYS -delete -print 2>/dev/null | wc -l)
    remaining=$(find "$BACKUP_DIR/database" -type f -name "*.sql.gz" 2>/dev/null | wc -l)
    log "Database: removed $removed, remaining $remaining"
fi

# Cleanup file backups
if [ -d "$BACKUP_DIR/files" ]; then
    removed=$(find "$BACKUP_DIR/files" -type f -name "*.tar.gz" -mtime +$RETENTION_DAYS -delete -print 2>/dev/null | wc -l)
    remaining=$(find "$BACKUP_DIR/files" -type f -name "*.tar.gz" 2>/dev/null | wc -l)
    log "Files: removed $removed, remaining $remaining"
fi

log "Cleanup completed"
