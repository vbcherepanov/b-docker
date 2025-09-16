#!/bin/bash

set -euo pipefail

# Настройки из переменных окружения
DB_HOST=${DB_HOST:-mysql}
DB_NAME=${DB_NAME:-bitrix}
DB_USERNAME=${DB_USERNAME:-bitrix}
DB_PASSWORD=${DB_PASSWORD:-bitrix123}
DB_ROOT_PASSWORD=${DB_ROOT_PASSWORD:-root123}
BACKUP_RETENTION_DAYS=${BACKUP_RETENTION_DAYS:-7}
ENVIRONMENT=${ENVIRONMENT:-local}
UGN=${UGN:-bitrix}

# Директории
BACKUP_DIR="./backups"
WWW_DIR="./www"
LOG_FILE="$BACKUP_DIR/backup.log"

# Функция логирования
log() {
    local message="$1"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] $message" | tee -a "$LOG_FILE"
}

# Функция показа помощи
show_help() {
    cat << EOF
Управление бэкапами Bitrix Docker Environment

Использование:
    $0 database [site]              - Бэкап базы данных
    $0 files [site]                 - Бэкап файлов сайта
    $0 full [site]                  - Полный бэкап (база + файлы)
    $0 cleanup                      - Очистка старых бэкапов
    $0 restore database <file>      - Восстановление базы данных
    $0 restore files <file> [site]  - Восстановление файлов
    $0 list [type]                  - Список бэкапов

Примеры:
    $0 database                     - Бэкап всех БД
    $0 database example.com         - Бэкап БД конкретного сайта
    $0 files example.com            - Бэкап файлов сайта example.com
    $0 restore database backup.sql  - Восстановить БД из файла
    $0 list database               - Показать бэкапы БД

Переменные окружения:
    DB_HOST, DB_NAME, DB_USERNAME, DB_PASSWORD
    BACKUP_RETENTION_DAYS (по умолчанию: 7)
EOF
}

# Создание директорий для бэкапов
init_backup_dirs() {
    mkdir -p "$BACKUP_DIR/database" "$BACKUP_DIR/files" "$BACKUP_DIR/logs"
    touch "$LOG_FILE"
}

# Функция получения списка сайтов
get_sites_list() {
    if [ -d "$WWW_DIR" ]; then
        find "$WWW_DIR" -maxdepth 1 -type d ! -name "." | sed 's|./www/||' | sort
    fi
}

# Функция бэкапа базы данных
backup_database() {
    local site="${1:-all}"
    local timestamp=$(date +%Y%m%d_%H%M%S)

    init_backup_dirs

    if [ "$site" = "all" ]; then
        # Бэкап всех баз данных
        local backup_file="$BACKUP_DIR/database/all_databases_${timestamp}.sql.gz"
        log "Начинаем полный бэкап всех баз данных"

        if docker exec mysql mysqldump -u "$DB_USERNAME" -p"$DB_PASSWORD" \
            --single-transaction \
            --routines \
            --triggers \
            --events \
            --quick \
            --lock-tables=false \
            --all-databases | gzip > "$backup_file"; then

            log "Полный бэкап баз данных завершен: $backup_file"
            log "Размер: $(du -h "$backup_file" | cut -f1)"
        else
            log "ОШИБКА: Не удалось создать полный бэкап баз данных"
            return 1
        fi
    else
        # Бэкап конкретной базы
        local db_name="${site//./_}"  # Заменяем точки на подчеркивания для имени БД
        local backup_file="$BACKUP_DIR/database/${site}_${timestamp}.sql.gz"

        log "Начинаем бэкап базы данных для сайта: $site (БД: $db_name)"

        if docker exec mysql mysqldump -u "$DB_USERNAME" -p"$DB_PASSWORD" \
            --single-transaction \
            --routines \
            --triggers \
            --events \
            --quick \
            --lock-tables=false \
            "$db_name" | gzip > "$backup_file"; then

            log "Бэкап базы данных $site завершен: $backup_file"
            log "Размер: $(du -h "$backup_file" | cut -f1)"
        else
            log "ОШИБКА: Не удалось создать бэкап базы данных для $site"
            return 1
        fi
    fi
}

# Функция бэкапа файлов
backup_files() {
    local site="${1:-all}"
    local timestamp=$(date +%Y%m%d_%H%M%S)

    init_backup_dirs

    if [ "$site" = "all" ]; then
        # Бэкап всех сайтов
        local backup_file="$BACKUP_DIR/files/all_sites_${timestamp}.tar.gz"
        log "Начинаем бэкап файлов всех сайтов"

        if [ -d "$WWW_DIR" ]; then
            if tar -czf "$backup_file" -C "$WWW_DIR" \
                --exclude='*.log' \
                --exclude='cache' \
                --exclude='tmp' \
                --exclude='bitrix/cache' \
                --exclude='bitrix/tmp' \
                --exclude='bitrix/managed_cache' \
                --exclude='bitrix/stack_cache' \
                --exclude='upload/resize_cache' \
                .; then

                log "Бэкап файлов всех сайтов завершен: $backup_file"
                log "Размер: $(du -h "$backup_file" | cut -f1)"
            else
                log "ОШИБКА: Не удалось создать бэкап файлов всех сайтов"
                return 1
            fi
        else
            log "ОШИБКА: Директория $WWW_DIR не найдена"
            return 1
        fi
    else
        # Бэкап конкретного сайта
        local site_dir="$WWW_DIR/$site"
        local backup_file="$BACKUP_DIR/files/${site}_${timestamp}.tar.gz"

        log "Начинаем бэкап файлов сайта: $site"

        if [ -d "$site_dir" ]; then
            if tar -czf "$backup_file" -C "$site_dir" \
                --exclude='*.log' \
                --exclude='cache' \
                --exclude='tmp' \
                --exclude='bitrix/cache' \
                --exclude='bitrix/tmp' \
                --exclude='bitrix/managed_cache' \
                --exclude='bitrix/stack_cache' \
                --exclude='upload/resize_cache' \
                .; then

                log "Бэкап файлов сайта $site завершен: $backup_file"
                log "Размер: $(du -h "$backup_file" | cut -f1)"
            else
                log "ОШИБКА: Не удалось создать бэкап файлов сайта $site"
                return 1
            fi
        else
            log "ОШИБКА: Директория сайта $site_dir не найдена"
            return 1
        fi
    fi
}

# Функция полного бэкапа
backup_full() {
    local site="${1:-all}"

    log "Начинаем полный бэкап для: $site"

    if backup_database "$site" && backup_files "$site"; then
        log "Полный бэкап для $site успешно завершен"
        cleanup_old_backups
    else
        log "ОШИБКА: Полный бэкап для $site завершился с ошибкой"
        return 1
    fi
}

# Функция восстановления базы данных
restore_database() {
    local backup_file="$1"
    local db_name="${2:-$DB_NAME}"

    if [ ! -f "$backup_file" ]; then
        log "ОШИБКА: Файл бэкапа не найден: $backup_file"
        return 1
    fi

    log "Начинаем восстановление базы данных из: $backup_file"

    # Проверяем, сжатый ли файл
    if [[ "$backup_file" == *.gz ]]; then
        if zcat "$backup_file" | docker exec -i mysql mysql -u "$DB_USERNAME" -p"$DB_PASSWORD" "$db_name"; then
            log "База данных успешно восстановлена"
        else
            log "ОШИБКА: Не удалось восстановить базу данных"
            return 1
        fi
    else
        if docker exec -i mysql mysql -u "$DB_USERNAME" -p"$DB_PASSWORD" "$db_name" < "$backup_file"; then
            log "База данных успешно восстановлена"
        else
            log "ОШИБКА: Не удалось восстановить базу данных"
            return 1
        fi
    fi
}

# Функция восстановления файлов
restore_files() {
    local backup_file="$1"
    local site="${2:-}"

    if [ ! -f "$backup_file" ]; then
        log "ОШИБКА: Файл бэкапа не найден: $backup_file"
        return 1
    fi

    if [ -z "$site" ]; then
        # Восстановление в корень www
        local restore_dir="$WWW_DIR"
        log "Начинаем восстановление файлов всех сайтов из: $backup_file"
    else
        # Восстановление конкретного сайта
        local restore_dir="$WWW_DIR/$site"
        log "Начинаем восстановление файлов сайта $site из: $backup_file"
        mkdir -p "$restore_dir"
    fi

    if tar -xzf "$backup_file" -C "$restore_dir"; then
        log "Файлы успешно восстановлены в: $restore_dir"
    else
        log "ОШИБКА: Не удалось восстановить файлы"
        return 1
    fi
}

# Функция очистки старых бэкапов
cleanup_old_backups() {
    init_backup_dirs
    log "Начинаем очистку бэкапов старше $BACKUP_RETENTION_DAYS дней"

    # Очистка бэкапов базы данных
    local db_count=$(find "$BACKUP_DIR/database" -name "*.sql.gz" -mtime +$BACKUP_RETENTION_DAYS -delete -print | wc -l)

    # Очистка бэкапов файлов
    local files_count=$(find "$BACKUP_DIR/files" -name "*.tar.gz" -mtime +$BACKUP_RETENTION_DAYS -delete -print | wc -l)

    log "Очистка завершена: удалено $db_count бэкапов БД и $files_count бэкапов файлов"
}

# Функция вывода списка бэкапов
list_backups() {
    local type="${1:-all}"

    init_backup_dirs

    case "$type" in
        "database"|"db")
            log "Бэкапы баз данных:"
            ls -lah "$BACKUP_DIR/database"/*.sql.gz 2>/dev/null || echo "Бэкапы БД не найдены"
            ;;
        "files")
            log "Бэкапы файлов:"
            ls -lah "$BACKUP_DIR/files"/*.tar.gz 2>/dev/null || echo "Бэкапы файлов не найдены"
            ;;
        "all")
            log "Все бэкапы:"
            echo "=== Базы данных ==="
            ls -lah "$BACKUP_DIR/database"/*.sql.gz 2>/dev/null || echo "Бэкапы БД не найдены"
            echo "=== Файлы ==="
            ls -lah "$BACKUP_DIR/files"/*.tar.gz 2>/dev/null || echo "Бэкапы файлов не найдены"
            ;;
        *)
            log "ОШИБКА: Неизвестный тип бэкапа: $type"
            return 1
            ;;
    esac
}

# Основная логика
case "${1:-}" in
    "database"|"db")
        backup_database "${2:-all}"
        ;;
    "files")
        backup_files "${2:-all}"
        ;;
    "full")
        backup_full "${2:-all}"
        ;;
    "cleanup")
        cleanup_old_backups
        ;;
    "restore")
        case "${2:-}" in
            "database"|"db")
                restore_database "${3:-}" "${4:-}"
                ;;
            "files")
                restore_files "${3:-}" "${4:-}"
                ;;
            *)
                log "ОШИБКА: Укажите тип восстановления (database или files)"
                exit 1
                ;;
        esac
        ;;
    "list")
        list_backups "${2:-all}"
        ;;
    "help"|"--help"|"-h")
        show_help
        ;;
    *)
        log "ОШИБКА: Неизвестная команда"
        echo
        show_help
        exit 1
        ;;
esac