#!/bin/bash
set -e

# =============================================================================
# Backup container entrypoint
# - Dumps environment for cron jobs (cron doesn't inherit container ENV)
# - Generates crontab dynamically from ENV variables
# - Tests database connection at startup
# - Starts cron daemon
# =============================================================================

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ENTRYPOINT: $1"
}

# -----------------------------------------------------------
# 1. Save environment for cron (cron doesn't pass container ENV)
# -----------------------------------------------------------
env | grep -E '^(DB_|BACKUP_|TZ|HOME|PATH)' > /etc/environment.backup
chmod 600 /etc/environment.backup
log "Environment saved to /etc/environment.backup"

# -----------------------------------------------------------
# 2. Generate crontab from ENV variables
# -----------------------------------------------------------
SCHEDULE_DB="${BACKUP_SCHEDULE_DB:-0 2 * * *}"
SCHEDULE_FILES="${BACKUP_SCHEDULE_FILES:-0 3 * * *}"

cat > /etc/cron.d/backup <<EOF
SHELL=/bin/bash

# Database backup
${SCHEDULE_DB} root /scripts/backup.sh database >> /var/log/backup.log 2>&1

# Files backup
${SCHEDULE_FILES} root /scripts/backup.sh files >> /var/log/backup.log 2>&1

# Cleanup old backups (Sunday 4:00)
0 4 * * 0 root /scripts/backup.sh cleanup >> /var/log/backup.log 2>&1
EOF

chmod 0644 /etc/cron.d/backup
log "Crontab generated: DB=[${SCHEDULE_DB}] FILES=[${SCHEDULE_FILES}]"

# -----------------------------------------------------------
# 3. Detect database tools
# -----------------------------------------------------------
if command -v mysqldump >/dev/null 2>&1; then
    DUMP_CMD="mysqldump"
elif command -v mariadb-dump >/dev/null 2>&1; then
    DUMP_CMD="mariadb-dump"
else
    log "ERROR: No dump tool found (mysqldump/mariadb-dump)"
    exit 1
fi

DUMP_VERSION=$($DUMP_CMD --version 2>&1 | head -1)
log "Dump tool: $DUMP_CMD ($DUMP_VERSION)"

# -----------------------------------------------------------
# 4. Test database connection
# -----------------------------------------------------------
log "Testing connection to ${DB_HOST:-mysql}/${DB_NAME:-bitrix}..."

MYSQL_CMD="mysql"
command -v mariadb >/dev/null 2>&1 && MYSQL_CMD="mariadb"

export MYSQL_PWD="${DB_PASSWORD:-}"

if $MYSQL_CMD -h "${DB_HOST:-mysql}" -u "${DB_USERNAME:-bitrix}" \
    -e "SELECT 1" "${DB_NAME:-bitrix}" >/dev/null 2>&1; then
    TABLE_COUNT=$($MYSQL_CMD -h "${DB_HOST:-mysql}" -u "${DB_USERNAME:-bitrix}" -N -e \
        "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='${DB_NAME:-bitrix}'" 2>/dev/null)
    log "Database OK — ${TABLE_COUNT} tables in ${DB_NAME:-bitrix}"

    if [ "${TABLE_COUNT:-0}" -eq 0 ]; then
        log "WARNING: Database has 0 tables — backups will be empty!"
    fi
else
    log "WARNING: Cannot connect to database. Backups may fail!"
    log "Check DB_HOST, DB_USERNAME, DB_PASSWORD, DB_NAME variables"
fi
unset MYSQL_PWD

# -----------------------------------------------------------
# 5. Start cron or execute command
# -----------------------------------------------------------
if [ "$1" = "cron" ]; then
    log "Starting cron daemon..."
    touch /var/log/backup.log

    if command -v crond >/dev/null 2>&1; then
        exec crond -n   # Oracle Linux (cronie) / Alpine
    else
        exec cron -f    # Debian / Ubuntu
    fi
else
    exec "$@"
fi
