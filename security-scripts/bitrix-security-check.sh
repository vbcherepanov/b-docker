#!/bin/bash
# ============================================================================
# BITRIX SECURITY CHECK
# Проверка безопасности специфичных настроек Bitrix CMS
# ============================================================================

REPORT_FILE="${REPORT_FILE:-/reports/bitrix-security.txt}"
APP_DIR="/app"

# Цвета
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Функции для отчета
report_header() {
    echo "============================================================================" >> "$REPORT_FILE"
    echo "$1" >> "$REPORT_FILE"
    echo "============================================================================" >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"
}

report_section() {
    echo "" >> "$REPORT_FILE"
    echo "▶ $1" >> "$REPORT_FILE"
    echo "----------------------------------------" >> "$REPORT_FILE"
}

report_ok() {
    echo "✓ $1" >> "$REPORT_FILE"
}

report_warning() {
    echo "⚠ WARNING: $1" >> "$REPORT_FILE"
}

report_error() {
    echo "✗ ERROR: $1" >> "$REPORT_FILE"
}

report_info() {
    echo "ℹ $1" >> "$REPORT_FILE"
}

# Начало отчета
echo "" > "$REPORT_FILE"
report_header "BITRIX CMS SECURITY CHECK REPORT"
report_info "Дата: $(date)"
report_info "Проверка: $APP_DIR"

# ============================================================================
# 1. ПРОВЕРКА ПРАВ ДОСТУПА К ФАЙЛАМ
# ============================================================================
report_section "1. Проверка прав доступа к критичным файлам"

# .settings.php должен быть 600 или 640
if [ -f "$APP_DIR/bitrix/.settings.php" ]; then
    PERMS=$(stat -c "%a" "$APP_DIR/bitrix/.settings.php" 2>/dev/null || stat -f "%Lp" "$APP_DIR/bitrix/.settings.php" 2>/dev/null)
    if [ "$PERMS" = "600" ] || [ "$PERMS" = "640" ]; then
        report_ok ".settings.php права: $PERMS (безопасно)"
    else
        report_warning ".settings.php права: $PERMS (рекомендуется 600 или 640)"
    fi
else
    report_info ".settings.php не найден"
fi

# dbconn.php должен быть 600 или 640
if [ -f "$APP_DIR/bitrix/php_interface/dbconn.php" ]; then
    PERMS=$(stat -c "%a" "$APP_DIR/bitrix/php_interface/dbconn.php" 2>/dev/null || stat -f "%Lp" "$APP_DIR/bitrix/php_interface/dbconn.php" 2>/dev/null)
    if [ "$PERMS" = "600" ] || [ "$PERMS" = "640" ]; then
        report_ok "dbconn.php права: $PERMS (безопасно)"
    else
        report_warning "dbconn.php права: $PERMS (рекомендуется 600 или 640)"
    fi
else
    report_info "dbconn.php не найден"
fi

# Проверка upload директории
if [ -d "$APP_DIR/upload" ]; then
    # Проверяем наличие PHP файлов в upload
    PHP_COUNT=$(find "$APP_DIR/upload" -name "*.php" 2>/dev/null | wc -l)
    if [ "$PHP_COUNT" -gt 0 ]; then
        report_error "Найдено $PHP_COUNT PHP файлов в /upload (потенциальная уязвимость!)"
        find "$APP_DIR/upload" -name "*.php" 2>/dev/null | head -10 >> "$REPORT_FILE"
    else
        report_ok "PHP файлы в /upload не найдены"
    fi
fi

# ============================================================================
# 2. ПРОВЕРКА .SETTINGS.PHP
# ============================================================================
report_section "2. Проверка настроек безопасности в .settings.php"

if [ -f "$APP_DIR/bitrix/.settings.php" ]; then
    # Проверка debug mode
    if grep -q "'debug' => true" "$APP_DIR/bitrix/.settings.php" 2>/dev/null; then
        report_warning "Debug mode включен (не рекомендуется для production)"
    else
        report_ok "Debug mode выключен"
    fi

    # Проверка utf_mode
    if grep -q "'utf_mode' => true" "$APP_DIR/bitrix/.settings.php" 2>/dev/null; then
        report_ok "UTF-8 mode включен"
    else
        report_info "UTF-8 mode не включен"
    fi

    # Проверка composer
    if grep -q "'composer' => true" "$APP_DIR/bitrix/.settings.php" 2>/dev/null; then
        report_ok "Composer autoload включен"
    fi
fi

# ============================================================================
# 3. ПРОВЕРКА АДМИНИСТРАТИВНОЙ ЧАСТИ
# ============================================================================
report_section "3. Защита административной части"

# Проверка .htpasswd для /bitrix/admin
if [ -f "$APP_DIR/bitrix/admin/.htpasswd" ]; then
    report_ok "HTTP Basic Auth настроен для /bitrix/admin"
elif [ -f "$APP_DIR/.htpasswd" ]; then
    report_ok "HTTP Basic Auth файл найден в корне"
else
    report_warning "HTTP Basic Auth не настроен для /bitrix/admin (рекомендуется)"
fi

# Проверка IP ограничений
if [ -f "$APP_DIR/bitrix/admin/.htaccess" ]; then
    if grep -q "Require ip" "$APP_DIR/bitrix/admin/.htaccess" 2>/dev/null; then
        report_ok "IP ограничения настроены для /bitrix/admin"
    else
        report_info "IP ограничения не настроены для /bitrix/admin"
    fi
fi

# ============================================================================
# 4. ПРОВЕРКА COMPOSER ЗАВИСИМОСТЕЙ
# ============================================================================
report_section "4. Проверка Composer зависимостей"

if [ -f "$APP_DIR/composer.lock" ]; then
    report_ok "composer.lock найден"

    # Проверка устаревших пакетов (если composer доступен)
    if command -v composer >/dev/null 2>&1; then
        cd "$APP_DIR" && composer outdated --direct 2>/dev/null >> "$REPORT_FILE" || true
    else
        report_info "Composer не установлен, пропускаем проверку устаревших пакетов"
    fi
else
    report_info "composer.lock не найден"
fi

# ============================================================================
# 5. ПРОВЕРКА ИЗВЕСТНЫХ УЯЗВИМЫХ ФАЙЛОВ
# ============================================================================
report_section "5. Поиск известных уязвимых файлов"

VULNERABLE_FILES=(
    "bitrix/admin/restore.php"
    "bitrix/modules/main/admin/restore.php"
    "upload/.htaccess.~1~"
    "upload/index.php"
    ".git/config"
    ".svn/entries"
    "phpinfo.php"
    "info.php"
    "test.php"
)

FOUND=0
for file in "${VULNERABLE_FILES[@]}"; do
    if [ -f "$APP_DIR/$file" ]; then
        report_warning "Найден потенциально опасный файл: $file"
        FOUND=$((FOUND + 1))
    fi
done

if [ $FOUND -eq 0 ]; then
    report_ok "Известные уязвимые файлы не найдены"
fi

# ============================================================================
# 6. ПРОВЕРКА РЕЗЕРВНЫХ КОПИЙ
# ============================================================================
report_section "6. Поиск незащищенных резервных копий"

BACKUP_PATTERNS="*.sql *.sql.gz *.zip *.tar.gz *.bak *.backup *.old"
BACKUP_COUNT=0

for pattern in $BACKUP_PATTERNS; do
    COUNT=$(find "$APP_DIR" -maxdepth 3 -name "$pattern" 2>/dev/null | wc -l)
    BACKUP_COUNT=$((BACKUP_COUNT + COUNT))
done

if [ $BACKUP_COUNT -gt 0 ]; then
    report_warning "Найдено $BACKUP_COUNT файлов резервных копий в веб-директории"
    find "$APP_DIR" -maxdepth 3 -name "*.sql*" -o -name "*.zip" -o -name "*.tar.gz" -o -name "*.bak" 2>/dev/null | head -10 >> "$REPORT_FILE"
else
    report_ok "Резервные копии в веб-директории не найдены"
fi

# ============================================================================
# 7. ПРОВЕРКА ВРЕМЕННЫХ ФАЙЛОВ
# ============================================================================
report_section "7. Поиск временных и отладочных файлов"

TEMP_PATTERNS="*.tmp *.log *.cache *~"
TEMP_COUNT=0

for pattern in $TEMP_PATTERNS; do
    COUNT=$(find "$APP_DIR" -maxdepth 2 -name "$pattern" 2>/dev/null | wc -l)
    TEMP_COUNT=$((TEMP_COUNT + COUNT))
done

if [ $TEMP_COUNT -gt 10 ]; then
    report_warning "Найдено $TEMP_COUNT временных файлов (рекомендуется очистка)"
else
    report_ok "Количество временных файлов в норме: $TEMP_COUNT"
fi

# ============================================================================
# 8. РАЗМЕР UPLOAD ДИРЕКТОРИИ
# ============================================================================
report_section "8. Проверка размера upload директории"

if [ -d "$APP_DIR/upload" ]; then
    UPLOAD_SIZE=$(du -sh "$APP_DIR/upload" 2>/dev/null | cut -f1)
    FILE_COUNT=$(find "$APP_DIR/upload" -type f 2>/dev/null | wc -l)
    report_info "Размер upload: $UPLOAD_SIZE"
    report_info "Количество файлов: $FILE_COUNT"

    # Проверка на подозрительно большие файлы
    LARGE_FILES=$(find "$APP_DIR/upload" -type f -size +100M 2>/dev/null | wc -l)
    if [ "$LARGE_FILES" -gt 0 ]; then
        report_warning "Найдено $LARGE_FILES файлов >100MB в upload"
    fi
fi

# ============================================================================
# ИТОГИ
# ============================================================================
report_section "ИТОГИ ПРОВЕРКИ"

WARNINGS=$(grep -c "⚠ WARNING" "$REPORT_FILE" 2>/dev/null || echo "0")
ERRORS=$(grep -c "✗ ERROR" "$REPORT_FILE" 2>/dev/null || echo "0")
WARNINGS=$(echo "$WARNINGS" | tr -d ' \n\r')
ERRORS=$(echo "$ERRORS" | tr -d ' \n\r')

echo "" >> "$REPORT_FILE"
echo "Найдено ошибок: $ERRORS" >> "$REPORT_FILE"
echo "Найдено предупреждений: $WARNINGS" >> "$REPORT_FILE"
echo "" >> "$REPORT_FILE"

if [ "$ERRORS" -gt 0 ]; then
    echo "❌ СТАТУС: ТРЕБУЕТСЯ ВНИМАНИЕ (найдены критичные проблемы)" >> "$REPORT_FILE"
    exit 1
elif [ "$WARNINGS" -gt 5 ]; then
    echo "⚠️  СТАТУС: ТРЕБУЮТСЯ УЛУЧШЕНИЯ (много предупреждений)" >> "$REPORT_FILE"
    exit 0
else
    echo "✅ СТАТУС: ХОРОШО (минимальные замечания)" >> "$REPORT_FILE"
    exit 0
fi
