#!/bin/bash
# ============================================================================
# COMPREHENSIVE BITRIX SECURITY AUDIT
# Полная комплексная проверка безопасности Bitrix CMS
# Внешнее + Внутреннее сканирование + Docker контейнеры
# ============================================================================

set -e

# Настройки
DOMAIN="${DOMAIN:-localhost}"
APP_DIR="${APP_DIR:-/app}"
REPORT_DIR="${REPORT_DIR:-/reports}"
CHECK_DOCKER="${CHECK_DOCKER:-false}"
REPORT_FILE="$REPORT_DIR/comprehensive-security-audit-$(date +%Y%m%d-%H%M%S).txt"
DETAILED_REPORT="$REPORT_DIR/detailed-security-report-$(date +%Y%m%d-%H%M%S).html"

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

# Счетчики
TOTAL_CHECKS=0
PASSED_CHECKS=0
WARNINGS=0
ERRORS=0
CRITICAL=0

# Парсинг аргументов
while [[ $# -gt 0 ]]; do
    case $1 in
        --docker)
            CHECK_DOCKER="true"
            shift
            ;;
        --domain)
            DOMAIN="$2"
            shift 2
            ;;
        --app-dir)
            APP_DIR="$2"
            shift 2
            ;;
        --help)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --docker          Включить проверку Docker контейнеров"
            echo "  --domain DOMAIN   Домен для проверки (по умолчанию: localhost)"
            echo "  --app-dir DIR     Директория приложения (по умолчанию: /app)"
            echo "  --help            Показать эту справку"
            echo ""
            echo "Переменные окружения:"
            echo "  DOMAIN            Домен для проверки"
            echo "  APP_DIR           Директория приложения"
            echo "  REPORT_DIR        Директория для отчетов (по умолчанию: /reports)"
            echo "  CHECK_DOCKER      Проверять Docker (true/false)"
            echo ""
            echo "Примеры:"
            echo "  $0 --docker --domain example.com"
            echo "  DOMAIN=example.com CHECK_DOCKER=true $0"
            exit 0
            ;;
        *)
            echo "Неизвестный параметр: $1"
            echo "Используйте --help для справки"
            exit 1
            ;;
    esac
done

# ============================================================================
# ФУНКЦИИ ОТЧЕТА
# ============================================================================

init_report() {
    mkdir -p "$REPORT_DIR"
    echo "" > "$REPORT_FILE"

    cat > "$REPORT_FILE" <<EOF
╔════════════════════════════════════════════════════════════════════════════╗
║                  COMPREHENSIVE BITRIX SECURITY AUDIT                       ║
╚════════════════════════════════════════════════════════════════════════════╝

Дата проверки: $(date '+%Y-%m-%d %H:%M:%S')
Проверяемый домен: $DOMAIN
Директория приложения: $APP_DIR
Отчет: $REPORT_FILE

════════════════════════════════════════════════════════════════════════════

EOF
}

section_header() {
    echo "" | tee -a "$REPORT_FILE"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" | tee -a "$REPORT_FILE"
    echo -e "${CYAN}$1${NC}" | tee -a "$REPORT_FILE"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" | tee -a "$REPORT_FILE"
    echo "" | tee -a "$REPORT_FILE"
}

check_ok() {
    TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
    PASSED_CHECKS=$((PASSED_CHECKS + 1))
    echo -e "${GREEN}✓${NC} $1" | tee -a "$REPORT_FILE"
}

check_info() {
    echo -e "${BLUE}ℹ${NC} $1" | tee -a "$REPORT_FILE"
}

check_warning() {
    TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
    WARNINGS=$((WARNINGS + 1))
    echo -e "${YELLOW}⚠${NC} WARNING: $1" | tee -a "$REPORT_FILE"
}

check_error() {
    TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
    ERRORS=$((ERRORS + 1))
    echo -e "${RED}✗${NC} ERROR: $1" | tee -a "$REPORT_FILE"
}

check_critical() {
    TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
    CRITICAL=$((CRITICAL + 1))
    echo -e "${RED}❌ CRITICAL:${NC} $1" | tee -a "$REPORT_FILE"
}

# ============================================================================
# 1. СКАНИРОВАНИЕ ОТКРЫТЫХ ПОРТОВ
# ============================================================================

scan_open_ports() {
    section_header "1. СКАНИРОВАНИЕ ОТКРЫТЫХ ПОРТОВ И СЕТЕВОЙ БЕЗОПАСНОСТИ"

    check_info "Сканирование портов на $DOMAIN..."

    # Порты которые должны быть открыты
    REQUIRED_PORTS="80 443"
    # Порты которые НЕ должны быть открыты извне
    DANGEROUS_PORTS="3306 5432 6379 11211 27017 9200 5601 8080 8888"

    for port in $REQUIRED_PORTS; do
        if command -v nc >/dev/null 2>&1; then
            if timeout 3 nc -zv $DOMAIN $port 2>&1 | grep -q succeeded; then
                check_ok "Порт $port открыт (HTTP/HTTPS)"
            else
                check_warning "Порт $port закрыт (может быть проблемой)"
            fi
        elif command -v telnet >/dev/null 2>&1; then
            if timeout 3 telnet $DOMAIN $port 2>&1 | grep -q Connected; then
                check_ok "Порт $port открыт"
            fi
        fi
    done

    check_info "Проверка опасных портов, которые не должны быть доступны извне..."
    for port in $DANGEROUS_PORTS; do
        if command -v nc >/dev/null 2>&1; then
            if timeout 2 nc -zv $DOMAIN $port 2>&1 | grep -q succeeded; then
                check_critical "Порт $port открыт извне! (БД/Кэш должны быть закрыты)"
            else
                check_ok "Порт $port закрыт (безопасно)"
            fi
        fi
    done

    # Проверка firewall
    if command -v firewall-cmd >/dev/null 2>&1; then
        if firewall-cmd --state 2>/dev/null | grep -q running; then
            check_ok "Firewall активен"
        else
            check_warning "Firewall не запущен"
        fi
    elif command -v ufw >/dev/null 2>&1; then
        if ufw status 2>/dev/null | grep -q active; then
            check_ok "UFW firewall активен"
        else
            check_warning "UFW firewall неактивен"
        fi
    fi
}

# ============================================================================
# 2. SSL/TLS СЕРТИФИКАТЫ И ШИФРОВАНИЕ
# ============================================================================

check_ssl_tls() {
    section_header "2. ПРОВЕРКА SSL/TLS СЕРТИФИКАТОВ И ШИФРОВАНИЯ"

    if command -v openssl >/dev/null 2>&1; then
        check_info "Проверка SSL сертификата для $DOMAIN..."

        # Проверка наличия SSL
        SSL_INFO=$(echo | timeout 5 openssl s_client -servername $DOMAIN -connect $DOMAIN:443 2>/dev/null)

        if [ $? -eq 0 ]; then
            check_ok "SSL/TLS соединение установлено"

            # Проверка срока действия
            EXPIRY=$(echo | timeout 5 openssl s_client -servername $DOMAIN -connect $DOMAIN:443 2>/dev/null | openssl x509 -noout -enddate 2>/dev/null | cut -d= -f2)
            if [ -n "$EXPIRY" ]; then
                check_info "Сертификат действителен до: $EXPIRY"

                # Проверка на истечение срока (< 30 дней)
                EXPIRY_EPOCH=$(date -d "$EXPIRY" +%s 2>/dev/null || date -j -f "%b %d %H:%M:%S %Y %Z" "$EXPIRY" +%s 2>/dev/null)
                NOW_EPOCH=$(date +%s)
                DAYS_LEFT=$(( ($EXPIRY_EPOCH - $NOW_EPOCH) / 86400 ))

                if [ $DAYS_LEFT -lt 0 ]; then
                    check_critical "SSL сертификат истек!"
                elif [ $DAYS_LEFT -lt 30 ]; then
                    check_warning "SSL сертификат истекает через $DAYS_LEFT дней"
                else
                    check_ok "SSL сертификат действителен еще $DAYS_LEFT дней"
                fi
            fi

            # Проверка TLS версии
            TLS_VERSION=$(echo | timeout 5 openssl s_client -servername $DOMAIN -connect $DOMAIN:443 2>/dev/null | grep "Protocol" | awk '{print $3}')
            if [ "$TLS_VERSION" = "TLSv1.3" ] || [ "$TLS_VERSION" = "TLSv1.2" ]; then
                check_ok "Используется безопасный протокол: $TLS_VERSION"
            else
                check_warning "Используется устаревший протокол: $TLS_VERSION"
            fi

            # Проверка слабых шифров
            if echo "$SSL_INFO" | grep -q "Cipher.*NULL\|Cipher.*EXPORT\|Cipher.*DES"; then
                check_critical "Обнаружены слабые шифры!"
            else
                check_ok "Слабые шифры не обнаружены"
            fi

        else
            check_error "Не удалось установить SSL соединение с $DOMAIN"
        fi

        # Проверка HTTPS редиректа
        HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://$DOMAIN 2>/dev/null || echo "000")
        if [ "$HTTP_CODE" = "301" ] || [ "$HTTP_CODE" = "302" ] || [ "$HTTP_CODE" = "307" ] || [ "$HTTP_CODE" = "308" ]; then
            check_ok "HTTP -> HTTPS редирект настроен (код: $HTTP_CODE)"
        else
            check_warning "HTTP -> HTTPS редирект не настроен или работает неправильно (код: $HTTP_CODE)"
        fi

    else
        check_warning "OpenSSL не установлен, пропускаем проверку SSL"
    fi
}

# ============================================================================
# 3. HTTP ЗАГОЛОВКИ БЕЗОПАСНОСТИ
# ============================================================================

check_security_headers() {
    section_header "3. ПРОВЕРКА HTTP ЗАГОЛОВКОВ БЕЗОПАСНОСТИ"

    if command -v curl >/dev/null 2>&1; then
        check_info "Получение заголовков с https://$DOMAIN..."

        HEADERS=$(curl -s -I -L https://$DOMAIN 2>/dev/null || curl -s -I http://$DOMAIN 2>/dev/null)

        # X-Frame-Options
        if echo "$HEADERS" | grep -qi "X-Frame-Options"; then
            XFRAME=$(echo "$HEADERS" | grep -i "X-Frame-Options" | cut -d: -f2 | tr -d ' \r')
            check_ok "X-Frame-Options установлен: $XFRAME"
        else
            check_warning "X-Frame-Options не установлен (защита от clickjacking)"
        fi

        # X-Content-Type-Options
        if echo "$HEADERS" | grep -qi "X-Content-Type-Options.*nosniff"; then
            check_ok "X-Content-Type-Options: nosniff установлен"
        else
            check_warning "X-Content-Type-Options: nosniff не установлен"
        fi

        # Strict-Transport-Security (HSTS)
        if echo "$HEADERS" | grep -qi "Strict-Transport-Security"; then
            HSTS=$(echo "$HEADERS" | grep -i "Strict-Transport-Security" | cut -d: -f2 | tr -d ' \r')
            check_ok "HSTS установлен: $HSTS"
        else
            check_warning "HSTS (Strict-Transport-Security) не установлен"
        fi

        # Content-Security-Policy
        if echo "$HEADERS" | grep -qi "Content-Security-Policy"; then
            check_ok "Content-Security-Policy установлен"
        else
            check_warning "Content-Security-Policy не установлен (защита от XSS)"
        fi

        # X-XSS-Protection
        if echo "$HEADERS" | grep -qi "X-XSS-Protection"; then
            check_ok "X-XSS-Protection установлен"
        else
            check_warning "X-XSS-Protection не установлен"
        fi

        # Referrer-Policy
        if echo "$HEADERS" | grep -qi "Referrer-Policy"; then
            check_ok "Referrer-Policy установлен"
        else
            check_info "Referrer-Policy не установлен (рекомендуется)"
        fi

        # Permissions-Policy
        if echo "$HEADERS" | grep -qi "Permissions-Policy"; then
            check_ok "Permissions-Policy установлен"
        else
            check_info "Permissions-Policy не установлен (рекомендуется)"
        fi

        # Проверка на утечку версии сервера
        if echo "$HEADERS" | grep -qi "Server:"; then
            SERVER=$(echo "$HEADERS" | grep -i "Server:" | cut -d: -f2 | tr -d ' \r')
            if echo "$SERVER" | grep -qiE "nginx/[0-9]|apache/[0-9]"; then
                check_warning "Версия веб-сервера раскрывается: $SERVER"
            else
                check_ok "Версия веб-сервера скрыта: $SERVER"
            fi
        fi

        # X-Powered-By
        if echo "$HEADERS" | grep -qi "X-Powered-By"; then
            POWERED=$(echo "$HEADERS" | grep -i "X-Powered-By" | cut -d: -f2 | tr -d ' \r')
            check_warning "X-Powered-By раскрывает технологию: $POWERED (рекомендуется отключить)"
        else
            check_ok "X-Powered-By скрыт"
        fi

    else
        check_warning "curl не установлен, пропускаем проверку заголовков"
    fi
}

# ============================================================================
# 4. СКАНИРОВАНИЕ ВЕБ-УЯЗВИМОСТЕЙ
# ============================================================================

scan_web_vulnerabilities() {
    section_header "4. СКАНИРОВАНИЕ ВЕБ-УЯЗВИМОСТЕЙ"

    check_info "Проверка доступности уязвимых файлов и директорий..."

    # Список опасных файлов/путей
    VULNERABLE_PATHS=(
        "phpinfo.php"
        "info.php"
        "test.php"
        ".git/config"
        ".git/HEAD"
        ".svn/entries"
        ".env"
        ".env.local"
        "composer.json"
        "composer.lock"
        "package.json"
        ".htaccess"
        "web.config"
        "config.php"
        "configuration.php"
        "backup.sql"
        "dump.sql"
        "database.sql"
        "bitrix/backup/"
        "bitrix/php_interface/dbconn.php"
        "upload/test.php"
        "readme.html"
        "license.txt"
    )

    EXPOSED_COUNT=0
    for path in "${VULNERABLE_PATHS[@]}"; do
        URL="https://$DOMAIN/$path"
        HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "$URL" 2>/dev/null || echo "000")

        if [ "$HTTP_CODE" = "200" ]; then
            check_critical "Доступен файл: /$path (код: $HTTP_CODE)"
            EXPOSED_COUNT=$((EXPOSED_COUNT + 1))
        fi
    done

    if [ $EXPOSED_COUNT -eq 0 ]; then
        check_ok "Уязвимые файлы не доступны извне"
    fi

    # Проверка directory listing
    check_info "Проверка directory listing..."
    LISTING_CODE=$(curl -s -o /dev/null -w "%{http_code}" "https://$DOMAIN/upload/" 2>/dev/null || echo "000")
    if [ "$LISTING_CODE" = "200" ]; then
        # Проверяем содержимое на наличие index of
        LISTING_CONTENT=$(curl -s "https://$DOMAIN/upload/" 2>/dev/null)
        if echo "$LISTING_CONTENT" | grep -qi "index of"; then
            check_critical "Directory listing включен для /upload/"
        else
            check_ok "Directory listing отключен"
        fi
    else
        check_ok "Directory listing отключен или директория защищена"
    fi

    # Проверка SQL injection (базовая)
    check_info "Базовая проверка на SQL injection..."
    SQLI_TEST=$(curl -s "https://$DOMAIN/?id=1'" 2>/dev/null || true)
    if echo "$SQLI_TEST" | grep -qiE "sql syntax|mysql error|warning.*mysql|postgresql|sqlite"; then
        check_critical "Возможна SQL injection уязвимость!"
    else
        check_ok "SQL ошибки не обнаружены в ответах"
    fi

    # Проверка XSS (базовая)
    check_info "Базовая проверка на XSS..."
    XSS_TEST=$(curl -s "https://$DOMAIN/?test=<script>alert(1)</script>" 2>/dev/null || true)
    if echo "$XSS_TEST" | grep -q "<script>alert(1)</script>"; then
        check_warning "Возможна XSS уязвимость (требуется детальная проверка)"
    else
        check_ok "Базовая XSS проверка пройдена"
    fi
}

# ============================================================================
# 5. ПРОВЕРКА PHP НАСТРОЕК БЕЗОПАСНОСТИ
# ============================================================================

check_php_security() {
    section_header "5. ПРОВЕРКА PHP НАСТРОЕК БЕЗОПАСНОСТИ"

    if command -v php >/dev/null 2>&1; then
        PHP_VERSION=$(php -v | head -1)
        check_info "PHP версия: $PHP_VERSION"

        # display_errors
        DISPLAY_ERRORS=$(php -r "echo ini_get('display_errors');")
        if [ "$DISPLAY_ERRORS" = "0" ] || [ "$DISPLAY_ERRORS" = "" ]; then
            check_ok "display_errors отключен"
        else
            check_warning "display_errors включен (не рекомендуется для production)"
        fi

        # expose_php
        EXPOSE_PHP=$(php -r "echo ini_get('expose_php');")
        if [ "$EXPOSE_PHP" = "0" ] || [ "$EXPOSE_PHP" = "" ]; then
            check_ok "expose_php отключен"
        else
            check_warning "expose_php включен (раскрывает версию PHP)"
        fi

        # allow_url_fopen
        URL_FOPEN=$(php -r "echo ini_get('allow_url_fopen');")
        if [ "$URL_FOPEN" = "0" ]; then
            check_ok "allow_url_fopen отключен (безопасно)"
        else
            check_info "allow_url_fopen включен (может быть опасно)"
        fi

        # allow_url_include
        URL_INCLUDE=$(php -r "echo ini_get('allow_url_include');")
        if [ "$URL_INCLUDE" = "0" ] || [ "$URL_INCLUDE" = "" ]; then
            check_ok "allow_url_include отключен"
        else
            check_critical "allow_url_include включен (критическая уязвимость!)"
        fi

        # disable_functions
        DISABLED=$(php -r "echo ini_get('disable_functions');")
        if [ -n "$DISABLED" ]; then
            check_ok "Опасные функции отключены: ${DISABLED:0:50}..."
        else
            check_warning "Опасные функции PHP не отключены"
        fi

        # open_basedir
        BASEDIR=$(php -r "echo ini_get('open_basedir');")
        if [ -n "$BASEDIR" ]; then
            check_ok "open_basedir настроен: $BASEDIR"
        else
            check_warning "open_basedir не настроен (рекомендуется для изоляции)"
        fi

        # session.cookie_httponly
        HTTPONLY=$(php -r "echo ini_get('session.cookie_httponly');")
        if [ "$HTTPONLY" = "1" ]; then
            check_ok "session.cookie_httponly включен"
        else
            check_warning "session.cookie_httponly выключен (уязвимость к XSS)"
        fi

        # session.cookie_secure
        COOKIE_SECURE=$(php -r "echo ini_get('session.cookie_secure');")
        if [ "$COOKIE_SECURE" = "1" ]; then
            check_ok "session.cookie_secure включен"
        else
            check_warning "session.cookie_secure выключен (только для HTTPS!)"
        fi

    else
        check_warning "PHP CLI не доступен, пропускаем проверку"
    fi
}

# ============================================================================
# 6. ПРОВЕРКА MYSQL/MARIADB БЕЗОПАСНОСТИ
# ============================================================================

check_database_security() {
    section_header "6. ПРОВЕРКА MYSQL/MARIADB БЕЗОПАСНОСТИ"

    if command -v mysql >/dev/null 2>&1; then
        # Проверка доступности MySQL без пароля (анонимный доступ)
        if mysql -u root -e "SELECT 1" 2>/dev/null >/dev/null; then
            check_critical "MySQL доступен без пароля для root!"
        else
            check_ok "MySQL требует аутентификацию"
        fi

        # Проверка удаленного доступа
        if netstat -tln 2>/dev/null | grep -q ":3306.*0.0.0.0" || ss -tln 2>/dev/null | grep -q ":3306.*0.0.0.0"; then
            check_warning "MySQL слушает на всех интерфейсах (0.0.0.0:3306)"
        else
            check_ok "MySQL слушает только на локальных интерфейсах"
        fi

    else
        check_info "MySQL CLI не доступен, пропускаем проверку"
    fi
}

# ============================================================================
# 7. ПРОВЕРКА NGINX/APACHE КОНФИГУРАЦИИ
# ============================================================================

check_webserver_config() {
    section_header "7. ПРОВЕРКА NGINX/APACHE КОНФИГУРАЦИИ"

    # Nginx
    if command -v nginx >/dev/null 2>&1; then
        NGINX_VERSION=$(nginx -v 2>&1 | head -1)
        check_info "Nginx: $NGINX_VERSION"

        # Проверка server_tokens
        if nginx -T 2>/dev/null | grep -q "server_tokens off"; then
            check_ok "server_tokens выключен"
        else
            check_warning "server_tokens не выключен (раскрывает версию nginx)"
        fi

        # Проверка client_max_body_size
        MAX_BODY=$(nginx -T 2>/dev/null | grep client_max_body_size | tail -1 | awk '{print $2}' | tr -d ';')
        if [ -n "$MAX_BODY" ]; then
            check_info "client_max_body_size: $MAX_BODY"
        fi

    fi

    # Apache
    if command -v apache2 >/dev/null 2>&1 || command -v httpd >/dev/null 2>&1; then
        APACHE_CMD=$(command -v apache2 || command -v httpd)
        APACHE_VERSION=$($APACHE_CMD -v 2>&1 | head -1)
        check_info "Apache: $APACHE_VERSION"

        # Проверка ServerTokens
        if $APACHE_CMD -M 2>/dev/null | grep -q mod_security; then
            check_ok "mod_security загружен"
        else
            check_info "mod_security не обнаружен"
        fi
    fi
}

# ============================================================================
# 8. ПРОВЕРКА BITRIX СПЕЦИФИЧНЫХ ФАЙЛОВ
# ============================================================================

check_bitrix_files() {
    section_header "8. ПРОВЕРКА BITRIX ФАЙЛОВ И ПРАВ ДОСТУПА"

    if [ ! -d "$APP_DIR" ]; then
        check_error "Директория $APP_DIR не найдена"
        return
    fi

    # .settings.php
    if [ -f "$APP_DIR/bitrix/.settings.php" ]; then
        PERMS=$(stat -c "%a" "$APP_DIR/bitrix/.settings.php" 2>/dev/null || stat -f "%Lp" "$APP_DIR/bitrix/.settings.php" 2>/dev/null)
        if [ "$PERMS" = "600" ] || [ "$PERMS" = "640" ]; then
            check_ok ".settings.php права: $PERMS"
        else
            check_warning ".settings.php права: $PERMS (рекомендуется 600)"
        fi

        # Проверка debug mode
        if grep -q "'debug' => true" "$APP_DIR/bitrix/.settings.php" 2>/dev/null; then
            check_warning "Debug mode включен в .settings.php"
        else
            check_ok "Debug mode выключен"
        fi
    fi

    # dbconn.php
    if [ -f "$APP_DIR/bitrix/php_interface/dbconn.php" ]; then
        PERMS=$(stat -c "%a" "$APP_DIR/bitrix/php_interface/dbconn.php" 2>/dev/null || stat -f "%Lp" "$APP_DIR/bitrix/php_interface/dbconn.php" 2>/dev/null)
        if [ "$PERMS" = "600" ] || [ "$PERMS" = "640" ]; then
            check_ok "dbconn.php права: $PERMS"
        else
            check_warning "dbconn.php права: $PERMS (рекомендуется 600)"
        fi
    fi

    # PHP в upload
    if [ -d "$APP_DIR/upload" ]; then
        PHP_COUNT=$(find "$APP_DIR/upload" -name "*.php" 2>/dev/null | wc -l)
        if [ "$PHP_COUNT" -gt 0 ]; then
            check_critical "Найдено $PHP_COUNT PHP файлов в /upload!"
        else
            check_ok "PHP файлы в /upload не найдены"
        fi
    fi

    # Резервные копии
    BACKUP_COUNT=$(find "$APP_DIR" -maxdepth 2 -type f \( -name "*.sql" -o -name "*.sql.gz" -o -name "*.bak" \) 2>/dev/null | wc -l)
    if [ "$BACKUP_COUNT" -gt 0 ]; then
        check_warning "Найдено $BACKUP_COUNT резервных копий в веб-директории"
    else
        check_ok "Резервные копии в веб-директории не найдены"
    fi

    # .git директория
    if [ -d "$APP_DIR/.git" ]; then
        check_warning ".git директория присутствует в веб-корне (может раскрывать исходники)"
    else
        check_ok ".git директория не найдена в веб-корне"
    fi
}

# ============================================================================
# 9. ПРОВЕРКА СИСТЕМНЫХ ОБНОВЛЕНИЙ
# ============================================================================

check_system_updates() {
    section_header "9. ПРОВЕРКА СИСТЕМНЫХ ОБНОВЛЕНИЙ"

    if command -v yum >/dev/null 2>&1; then
        check_info "Проверка обновлений (YUM)..."
        UPDATES=$(yum check-update 2>/dev/null | grep -v "^$" | grep -v "^Last metadata" | wc -l)
        if [ "$UPDATES" -gt 5 ]; then
            check_warning "Доступно $UPDATES обновлений пакетов"
        elif [ "$UPDATES" -gt 0 ]; then
            check_info "Доступно $UPDATES обновлений"
        else
            check_ok "Система обновлена"
        fi
    elif command -v apt >/dev/null 2>&1; then
        check_info "Проверка обновлений (APT)..."
        apt update -qq 2>/dev/null || true
        UPDATES=$(apt list --upgradable 2>/dev/null | grep -v "^Listing" | wc -l)
        if [ "$UPDATES" -gt 5 ]; then
            check_warning "Доступно $UPDATES обновлений пакетов"
        else
            check_info "Доступно $UPDATES обновлений"
        fi
    fi
}

# ============================================================================
# 10. ПРОВЕРКА DOCKER КОНТЕЙНЕРОВ
# ============================================================================

check_docker_security() {
    section_header "10. ПРОВЕРКА DOCKER КОНТЕЙНЕРОВ"

    if ! command -v docker >/dev/null 2>&1; then
        check_info "Docker не установлен, пропускаем проверку"
        return
    fi

    # Проверка что Docker запущен
    if ! docker info >/dev/null 2>&1; then
        check_warning "Docker daemon не запущен"
        return
    fi

    check_info "Проверка Docker окружения..."

    # Список запущенных контейнеров
    RUNNING_CONTAINERS=$(docker ps --format "{{.Names}}" 2>/dev/null | wc -l)
    if [ "$RUNNING_CONTAINERS" -eq 0 ]; then
        check_info "Нет запущенных контейнеров"
        return
    fi

    check_info "Найдено запущенных контейнеров: $RUNNING_CONTAINERS"

    # Проверка каждого контейнера
    docker ps --format "{{.Names}}" | while read -r container; do
        check_info "Проверка контейнера: $container"

        # 1. Проверка запуска от root
        CONTAINER_USER=$(docker inspect --format='{{.Config.User}}' "$container" 2>/dev/null || echo "")
        if [ -z "$CONTAINER_USER" ] || [ "$CONTAINER_USER" = "root" ] || [ "$CONTAINER_USER" = "0" ]; then
            check_warning "Контейнер $container запущен от root (рекомендуется non-root пользователь)"
        else
            check_ok "Контейнер $container запущен от пользователя: $CONTAINER_USER"
        fi

        # 2. Проверка privileged режима
        IS_PRIVILEGED=$(docker inspect --format='{{.HostConfig.Privileged}}' "$container" 2>/dev/null)
        if [ "$IS_PRIVILEGED" = "true" ]; then
            check_critical "Контейнер $container запущен в privileged режиме! (критическая уязвимость)"
        else
            check_ok "Контейнер $container не использует privileged режим"
        fi

        # 3. Проверка read-only файловой системы
        IS_READONLY=$(docker inspect --format='{{.HostConfig.ReadonlyRootfs}}' "$container" 2>/dev/null)
        if [ "$IS_READONLY" = "true" ]; then
            check_ok "Контейнер $container использует read-only файловую систему"
        else
            check_info "Контейнер $container не использует read-only FS (рекомендуется для production)"
        fi

        # 4. Проверка проброшенных портов
        PORTS=$(docker inspect --format='{{range $p, $conf := .NetworkSettings.Ports}}{{if $conf}}{{$p}} -> {{(index $conf 0).HostPort}} {{end}}{{end}}' "$container" 2>/dev/null)
        if [ -n "$PORTS" ]; then
            check_info "Контейнер $container пробрасывает порты: $PORTS"

            # Проверка на опасные порты
            if echo "$PORTS" | grep -qE "3306|5432|6379|11211|27017"; then
                check_warning "Контейнер $container пробрасывает опасные порты БД/кэша наружу!"
            fi
        fi

        # 5. Проверка capabilities
        CAPABILITIES=$(docker inspect --format='{{range .HostConfig.CapAdd}}{{.}} {{end}}' "$container" 2>/dev/null | tr -d '[]')
        if [ -n "$CAPABILITIES" ] && [ "$CAPABILITIES" != "<no value>" ]; then
            if echo "$CAPABILITIES" | grep -qi "SYS_ADMIN\|NET_ADMIN"; then
                check_warning "Контейнер $container имеет опасные capabilities: $CAPABILITIES"
            else
                check_info "Контейнер $container capabilities: $CAPABILITIES"
            fi
        fi

        # 6. Проверка монтированных томов
        VOLUMES=$(docker inspect --format='{{range .Mounts}}{{if eq .Type "bind"}}{{.Source}} {{end}}{{end}}' "$container" 2>/dev/null)
        if echo "$VOLUMES" | grep -q "/var/run/docker.sock"; then
            check_critical "Контейнер $container имеет доступ к Docker socket! (критическая уязвимость)"
        fi
        if echo "$VOLUMES" | grep -qE "/etc|/root|/home"; then
            check_warning "Контейнер $container монтирует системные директории: $VOLUMES"
        fi

        # 7. Проверка security options
        SECCOMP=$(docker inspect --format='{{range .HostConfig.SecurityOpt}}{{.}} {{end}}' "$container" 2>/dev/null)
        if echo "$SECCOMP" | grep -q "seccomp=unconfined"; then
            check_critical "Контейнер $container отключил seccomp! (критическая уязвимость)"
        elif echo "$SECCOMP" | grep -q "apparmor=unconfined"; then
            check_warning "Контейнер $container отключил AppArmor"
        fi

        # 8. Проверка health check
        HEALTH=$(docker inspect --format='{{.Config.Healthcheck}}' "$container" 2>/dev/null)
        if [ "$HEALTH" != "<no value>" ] && [ -n "$HEALTH" ]; then
            check_ok "Контейнер $container имеет healthcheck"
        else
            check_info "Контейнер $container не имеет healthcheck (рекомендуется настроить)"
        fi

        # 9. Проверка лимитов ресурсов
        MEM_LIMIT=$(docker inspect --format='{{.HostConfig.Memory}}' "$container" 2>/dev/null)
        CPU_LIMIT=$(docker inspect --format='{{.HostConfig.NanoCpus}}' "$container" 2>/dev/null)

        if [ "$MEM_LIMIT" = "0" ]; then
            check_warning "Контейнер $container не имеет лимита памяти (рекомендуется установить)"
        else
            MEM_MB=$((MEM_LIMIT / 1024 / 1024))
            check_ok "Контейнер $container лимит памяти: ${MEM_MB}MB"
        fi

        if [ "$CPU_LIMIT" = "0" ]; then
            check_info "Контейнер $container не имеет лимита CPU"
        fi

        # 10. Проверка образа на уязвимости (если установлен trivy)
        if command -v trivy >/dev/null 2>&1; then
            IMAGE=$(docker inspect --format='{{.Config.Image}}' "$container" 2>/dev/null)
            check_info "Сканирование образа $IMAGE с помощью Trivy..."
            VULNS=$(trivy image --severity HIGH,CRITICAL --quiet "$IMAGE" 2>/dev/null | grep -c "Total:" || echo "0")
            if [ "$VULNS" -gt 0 ]; then
                check_warning "Образ $IMAGE содержит уязвимости (запустите: trivy image $IMAGE)"
            fi
        fi

    done

    # Проверка Docker daemon настроек
    check_info "Проверка настроек Docker daemon..."

    # Проверка на запуск без TLS
    if docker info 2>/dev/null | grep -q "Server Version"; then
        check_ok "Docker daemon доступен"
    fi

    # Проверка userns-remap
    USERNS=$(docker info --format '{{.SecurityOptions}}' 2>/dev/null)
    if echo "$USERNS" | grep -q "userns"; then
        check_ok "User namespace remapping включен"
    else
        check_info "User namespace remapping не включен (рекомендуется для production)"
    fi

    # Проверка Content Trust
    if [ "$DOCKER_CONTENT_TRUST" = "1" ]; then
        check_ok "Docker Content Trust включен"
    else
        check_info "Docker Content Trust не включен (рекомендуется для production)"
    fi

    # Проверка неиспользуемых образов и контейнеров
    DANGLING_IMAGES=$(docker images -f "dangling=true" -q 2>/dev/null | wc -l)
    if [ "$DANGLING_IMAGES" -gt 10 ]; then
        check_warning "Найдено $DANGLING_IMAGES неиспользуемых образов (выполните: docker image prune)"
    elif [ "$DANGLING_IMAGES" -gt 0 ]; then
        check_info "Найдено $DANGLING_IMAGES неиспользуемых образов"
    else
        check_ok "Неиспользуемые образы отсутствуют"
    fi

    STOPPED_CONTAINERS=$(docker ps -a -f "status=exited" -q 2>/dev/null | wc -l)
    if [ "$STOPPED_CONTAINERS" -gt 5 ]; then
        check_warning "Найдено $STOPPED_CONTAINERS остановленных контейнеров (выполните: docker container prune)"
    fi

    # Проверка Docker Compose secrets (если используется)
    if command -v docker-compose >/dev/null 2>&1 || command -v docker compose >/dev/null 2>&1; then
        if [ -f "docker-compose.yml" ] || [ -f "docker-compose.yaml" ]; then
            check_info "Найден docker-compose.yml"

            # Проверка на hardcoded пароли
            if grep -qiE "password.*:|PASS.*:|secret.*:" docker-compose.y*ml 2>/dev/null; then
                check_warning "В docker-compose.yml возможно есть hardcoded пароли (используйте secrets/env файлы)"
            else
                check_ok "Hardcoded пароли в docker-compose.yml не обнаружены"
            fi
        fi
    fi
}

# ============================================================================
# 11. ИТОГОВЫЙ ОТЧЕТ
# ============================================================================

generate_summary() {
    section_header "11. ИТОГОВЫЙ ОТЧЕТ"

    SCORE=$(awk "BEGIN {printf \"%.1f\", ($PASSED_CHECKS / $TOTAL_CHECKS) * 100}")

    cat >> "$REPORT_FILE" <<EOF
Всего проверок выполнено: $TOTAL_CHECKS
✓ Пройдено успешно: $PASSED_CHECKS
⚠ Предупреждений: $WARNINGS
✗ Ошибок: $ERRORS
❌ Критических проблем: $CRITICAL

Общий балл безопасности: $SCORE%

════════════════════════════════════════════════════════════════════════════

EOF

    if [ $CRITICAL -gt 0 ]; then
        echo -e "${RED}❌ СТАТУС: КРИТИЧЕСКИЕ ПРОБЛЕМЫ ОБНАРУЖЕНЫ!${NC}" | tee -a "$REPORT_FILE"
        echo "Требуется немедленное исправление критических уязвимостей!" | tee -a "$REPORT_FILE"
    elif [ $ERRORS -gt 0 ]; then
        echo -e "${RED}✗ СТАТУС: ОБНАРУЖЕНЫ СЕРЬЕЗНЫЕ ПРОБЛЕМЫ${NC}" | tee -a "$REPORT_FILE"
        echo "Рекомендуется устранить ошибки в ближайшее время" | tee -a "$REPORT_FILE"
    elif [ $WARNINGS -gt 10 ]; then
        echo -e "${YELLOW}⚠ СТАТУС: ТРЕБУЮТСЯ УЛУЧШЕНИЯ${NC}" | tee -a "$REPORT_FILE"
        echo "Много предупреждений, рекомендуется усилить безопасность" | tee -a "$REPORT_FILE"
    elif [ $WARNINGS -gt 0 ]; then
        echo -e "${YELLOW}⚡ СТАТУС: ХОРОШО (есть рекомендации)${NC}" | tee -a "$REPORT_FILE"
        echo "Система в целом безопасна, но есть моменты для улучшения" | tee -a "$REPORT_FILE"
    else
        echo -e "${GREEN}✅ СТАТУС: ОТЛИЧНО!${NC}" | tee -a "$REPORT_FILE"
        echo "Безопасность на высоком уровне!" | tee -a "$REPORT_FILE"
    fi

    echo "" | tee -a "$REPORT_FILE"
    echo "Полный отчет сохранен в: $REPORT_FILE" | tee -a "$REPORT_FILE"
    echo "" | tee -a "$REPORT_FILE"
}

# ============================================================================
# MAIN
# ============================================================================

main() {
    echo -e "${PURPLE}╔════════════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${PURPLE}║         ЗАПУСК КОМПЛЕКСНОЙ ПРОВЕРКИ БЕЗОПАСНОСТИ BITRIX CMS                ║${NC}"
    echo -e "${PURPLE}╚════════════════════════════════════════════════════════════════════════════╝${NC}"
    echo ""

    init_report

    scan_open_ports
    check_ssl_tls
    check_security_headers
    scan_web_vulnerabilities
    check_php_security
    check_database_security
    check_webserver_config
    check_bitrix_files
    check_system_updates

    # Docker проверка (если включена)
    if [ "$CHECK_DOCKER" = "true" ]; then
        check_docker_security
    fi

    generate_summary

    echo ""
    echo -e "${CYAN}════════════════════════════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}Проверка завершена!${NC}"
    echo -e "Отчет: ${BLUE}$REPORT_FILE${NC}"
    echo -e "${CYAN}════════════════════════════════════════════════════════════════════════════${NC}"

    # Exit code based on severity
    if [ $CRITICAL -gt 0 ]; then
        exit 2
    elif [ $ERRORS -gt 0 ]; then
        exit 1
    else
        exit 0
    fi
}

main
