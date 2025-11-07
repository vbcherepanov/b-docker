#!/bin/bash

# Backup cleanup script
# Removes old backups based on retention policy

set -e

BACKUP_DIR=${BACKUP_DIR:-"/backups"}
RETENTION_DAYS=${BACKUP_RETENTION_DAYS:-7}

# Log function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# Cleanup function
cleanup_backups() {
    local backup_type=$1
    local retention_days=${2:-$RETENTION_DAYS}

    log "Starting cleanup for $backup_type backups (retention: $retention_days days)"

    if [ -d "$BACKUP_DIR/$backup_type" ]; then
        # Find and remove files older than retention period
        find "$BACKUP_DIR/$backup_type" -type f -mtime +$retention_days -name "*.tar.gz" -exec rm -f {} \;

        # Count remaining backups
        local count=$(find "$BACKUP_DIR/$backup_type" -type f -name "*.tar.gz" | wc -l)
        log "Cleanup completed. Remaining $backup_type backups: $count"
    else
        log "Backup directory $BACKUP_DIR/$backup_type does not exist"
    fi
}

# Main cleanup
log "Starting backup cleanup process"

# Cleanup database backups
cleanup_backups "database" $RETENTION_DAYS

# Cleanup file backups
cleanup_backups "files" $RETENTION_DAYS

# Cleanup logs older than 30 days
if [ -d "/var/log" ]; then
    find /var/log -type f -name "*.log" -mtime +30 -exec rm -f {} \;
    log "Old log files cleaned up"
fi

log "Backup cleanup process completed"