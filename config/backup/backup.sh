#!/bin/bash

# Настройки из переменных окружения
DB_HOST=${DB_HOST:-mysql}
DB_NAME=${DB_NAME:-bitrix}
DB_USERNAME=${DB_USERNAME:-bitrix}
DB_PASSWORD=${DB_PASSWORD:-bitrix123}
DB_ROOT_PASSWORD=${DB_ROOT_PASSWORD:-root123}
BACKUP_RETENTION_DAYS=${BACKUP_RETENTION_DAYS:-7}

# Директории
BACKUP_DIR="/backups"
APP_DIR="/home/bitrix/app"
LOG_FILE="/var/log/backup.log"

# Функция логирования
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

# Создание директорий для бэкапов
mkdir -p "$BACKUP_DIR/database" "$BACKUP_DIR/files"

# Функция бэкапа базы данных
backup_database() {
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local backup_file="$BACKUP_DIR/database/db_backup_${timestamp}.sql.gz"

    log "Начинаем бэкап базы данных: $DB_NAME"

    if mysqldump -h "$DB_HOST" -u "$DB_USERNAME" -p"$DB_PASSWORD" \
        --single-transaction \
        --routines \
        --triggers \
        --events \
        --quick \
        --lock-tables=false \
        "$DB_NAME" | gzip > "$backup_file"; then

        log "Бэкап базы данных завершен: $backup_file"

        # Проверка размера файла
        if [ -s "$backup_file" ]; then
            local size=$(du -h "$backup_file" | cut -f1)
            log "Размер бэкапа базы данных: $size"
        else
            log "ОШИБКА: Файл бэкапа базы данных пустой"
            return 1
        fi
    else
        log "ОШИБКА: Не удалось создать бэкап базы данных"
        return 1
    fi
}

# Функция бэкапа файлов
backup_files() {
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local backup_file="$BACKUP_DIR/files/files_backup_${timestamp}.tar.gz"

    log "Начинаем бэкап файлов из: $APP_DIR"

    if [ -d "$APP_DIR" ]; then
        if tar -czf "$backup_file" -C "$APP_DIR" \
            --exclude='*.log' \
            --exclude='cache/*' \
            --exclude='tmp/*' \
            --exclude='bitrix/cache/*' \
            --exclude='bitrix/tmp/*' \
            --exclude='bitrix/managed_cache/*' \
            --exclude='bitrix/stack_cache/*' \
            --exclude='upload/resize_cache/*' \
            .; then

            log "Бэкап файлов завершен: $backup_file"

            # Проверка размера файла
            if [ -s "$backup_file" ]; then
                local size=$(du -h "$backup_file" | cut -f1)
                log "Размер бэкапа файлов: $size"
            else
                log "ОШИБКА: Файл бэкапа файлов пустой"
                return 1
            fi
        else
            log "ОШИБКА: Не удалось создать бэкап файлов"
            return 1
        fi
    else
        log "ОШИБКА: Директория $APP_DIR не найдена"
        return 1
    fi
}

# Функция очистки старых бэкапов
cleanup_old_backups() {
    log "Начинаем очистку бэкапов старше $BACKUP_RETENTION_DAYS дней"

    # Очистка бэкапов базы данных
    find "$BACKUP_DIR/database" -name "*.sql.gz" -mtime +$BACKUP_RETENTION_DAYS -delete

    # Очистка бэкапов файлов
    find "$BACKUP_DIR/files" -name "*.tar.gz" -mtime +$BACKUP_RETENTION_DAYS -delete

    log "Очистка старых бэкапов завершена"
}

# Функция отправки уведомлений (опционально)
send_notification() {
    local message="$1"
    local status="$2"

    # Здесь можно добавить отправку уведомлений через webhook, email и т.д.
    # Например, через curl к webhook Discord, Slack или Telegram

    log "Уведомление: $message (статус: $status)"
}

# Основная функция
main() {
    local action="$1"

    case "$action" in
        "database")
            backup_database
            if [ $? -eq 0 ]; then
                send_notification "Бэкап базы данных успешно завершен" "success"
            else
                send_notification "Ошибка при создании бэкапа базы данных" "error"
            fi
            ;;
        "files")
            backup_files
            if [ $? -eq 0 ]; then
                send_notification "Бэкап файлов успешно завершен" "success"
            else
                send_notification "Ошибка при создании бэкапа файлов" "error"
            fi
            ;;
        "cleanup")
            cleanup_old_backups
            ;;
        "full")
            backup_database
            backup_files
            cleanup_old_backups
            ;;
        *)
            echo "Использование: $0 {database|files|cleanup|full}"
            exit 1
            ;;
    esac
}

# Запуск
main "$@"