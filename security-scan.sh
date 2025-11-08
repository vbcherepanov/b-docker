#!/bin/bash
# ============================================================================
# BITRIX SECURITY SCANNER
# Комплексная проверка безопасности Bitrix CMS
# ============================================================================

set -e

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Директории
REPORTS_DIR="./security-reports"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

# Функции
print_header() {
    echo -e "${BLUE}============================================================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}============================================================================${NC}"
}

print_section() {
    echo -e "\n${CYAN}▶ $1${NC}\n"
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

# Проверка что контейнеры запущены
check_containers() {
    print_section "Проверка контейнеров Bitrix..."

    if ! docker ps | grep -q "bitrix.local_nginx"; then
        print_error "Nginx контейнер не запущен!"
        print_warning "Запустите: docker compose -f docker-compose.bitrix.yml --profile local up -d"
        exit 1
    fi

    if ! docker ps | grep -q "bitrix.local_bitrix"; then
        print_error "Bitrix контейнер не запущен!"
        print_warning "Запустите: docker compose -f docker-compose.bitrix.yml --profile local up -d"
        exit 1
    fi

    print_success "Все контейнеры запущены"
}

# Создание директории для отчетов
prepare_reports_dir() {
    mkdir -p "$REPORTS_DIR"
    print_success "Директория отчетов: $REPORTS_DIR"
}

# Быстрое сканирование (5-10 минут)
quick_scan() {
    print_header "БЫСТРОЕ СКАНИРОВАНИЕ БЕЗОПАСНОСТИ"

    prepare_reports_dir
    check_containers

    print_section "1/3 OWASP ZAP Baseline Scan"
    docker compose -f docker-compose.security.yml run --rm owasp-zap-baseline || print_warning "ZAP scan completed with warnings"
    print_success "ZAP baseline scan завершен"

    print_section "2/3 Nikto Web Server Scan"
    docker compose -f docker-compose.security.yml run --rm nikto || print_warning "Nikto scan completed with warnings"
    print_success "Nikto scan завершен"

    print_section "3/3 Bitrix Security Check"
    docker compose -f docker-compose.security.yml run --rm bitrix-security-check || print_warning "Bitrix check completed with warnings"
    print_success "Bitrix security check завершен"

    print_header "БЫСТРОЕ СКАНИРОВАНИЕ ЗАВЕРШЕНО"
    echo -e "${GREEN}Отчеты сохранены в: $REPORTS_DIR${NC}"
    echo -e "${YELLOW}Для просмотра отчетов откройте HTML файлы в браузере${NC}"
}

# Полное сканирование (30-60 минут)
full_scan() {
    print_header "ПОЛНОЕ СКАНИРОВАНИЕ БЕЗОПАСНОСТИ"

    prepare_reports_dir
    check_containers

    print_section "1/6 OWASP ZAP Full Scan (это займет 20-30 минут...)"
    docker compose -f docker-compose.security.yml run --rm owasp-zap-full || print_warning "ZAP full scan completed with warnings"
    print_success "ZAP full scan завершен"

    print_section "2/6 OWASP ZAP API Scan"
    docker compose -f docker-compose.security.yml run --rm owasp-zap-api || print_warning "ZAP API scan completed with warnings"
    print_success "ZAP API scan завершен"

    print_section "3/6 Nikto Web Server Scan"
    docker compose -f docker-compose.security.yml run --rm nikto || print_warning "Nikto scan completed with warnings"
    print_success "Nikto scan завершен"

    print_section "4/6 SSL/TLS Security Check"
    docker compose -f docker-compose.security.yml run --rm testssl || print_warning "TestSSL check completed with warnings"
    print_success "TestSSL check завершен"

    print_section "5/6 Docker Image Security Scan"
    docker compose -f docker-compose.security.yml run --rm trivy || print_warning "Trivy scan completed with warnings"
    print_success "Trivy scan завершен"

    print_section "6/6 Bitrix Security Check"
    docker compose -f docker-compose.security.yml run --rm bitrix-security-check || print_warning "Bitrix check completed with warnings"
    print_success "Bitrix security check завершен"

    print_header "ПОЛНОЕ СКАНИРОВАНИЕ ЗАВЕРШЕНО"
    echo -e "${GREEN}Отчеты сохранены в: $REPORTS_DIR${NC}"
    echo -e "${YELLOW}Для просмотра отчетов откройте HTML файлы в браузере${NC}"
}

# Генерация сводного отчета
generate_report() {
    print_header "ГЕНЕРАЦИЯ СВОДНОГО ОТЧЕТА"

    SUMMARY_FILE="$REPORTS_DIR/summary-$TIMESTAMP.html"

    cat > "$SUMMARY_FILE" << 'EOF'
<!DOCTYPE html>
<html lang="ru">
<head>
    <meta charset="UTF-8">
    <title>Bitrix Security Report</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; background: #f5f5f5; }
        .container { max-width: 1200px; margin: 0 auto; background: white; padding: 30px; border-radius: 8px; box-shadow: 0 2px 4px rgba(0,0,0,0.1); }
        h1 { color: #333; border-bottom: 3px solid #007bff; padding-bottom: 10px; }
        h2 { color: #555; margin-top: 30px; }
        .report-list { list-style: none; padding: 0; }
        .report-list li { padding: 15px; margin: 10px 0; background: #f9f9f9; border-left: 4px solid #007bff; }
        .report-list a { text-decoration: none; color: #007bff; font-weight: bold; }
        .info { background: #e7f3ff; padding: 15px; border-radius: 4px; margin: 20px 0; }
        .timestamp { color: #666; font-size: 0.9em; }
    </style>
</head>
<body>
    <div class="container">
        <h1>🔒 Bitrix Security Scan Report</h1>
        <p class="timestamp">Generated: DATE_PLACEHOLDER</p>

        <div class="info">
            <strong>ℹ️ О сканировании:</strong><br>
            Проведена комплексная проверка безопасности Bitrix CMS на уязвимости OWASP Top 10,
            конфигурацию сервера, SSL/TLS и Docker контейнеров.
        </div>

        <h2>📊 Отчеты сканирования</h2>
        <ul class="report-list" id="reports">
            <!-- Reports will be inserted here -->
        </ul>

        <h2>🛡️ Рекомендации</h2>
        <ul>
            <li>Проверьте все отчеты на наличие критических уязвимостей (High/Critical)</li>
            <li>Обновите все компоненты с известными CVE</li>
            <li>Настройте безопасные HTTP заголовки (CSP, HSTS, X-Frame-Options)</li>
            <li>Используйте сильные SSL/TLS конфигурации</li>
            <li>Регулярно обновляйте Bitrix CMS и все зависимости</li>
        </ul>
    </div>

    <script>
        // Find all HTML reports
        const reports = [
            { name: 'OWASP ZAP Baseline', file: 'zap-baseline-report.html', icon: '🔍' },
            { name: 'OWASP ZAP Full Scan', file: 'zap-full-report.html', icon: '🔬' },
            { name: 'OWASP ZAP API Scan', file: 'zap-api-report.html', icon: '🔌' },
            { name: 'Nikto Web Server', file: 'nikto-report.html', icon: '🌐' },
            { name: 'TestSSL.sh', file: 'testssl-report.html', icon: '🔐' },
            { name: 'Trivy Container Scan', file: 'trivy-report.json', icon: '🐳' },
            { name: 'Bitrix Security Check', file: 'bitrix-security.txt', icon: '⚙️' }
        ];

        const reportsList = document.getElementById('reports');
        reports.forEach(report => {
            const li = document.createElement('li');
            li.innerHTML = `${report.icon} <a href="${report.file}" target="_blank">${report.name}</a>`;
            reportsList.appendChild(li);
        });

        document.querySelector('.timestamp').innerHTML = 'Generated: ' + new Date().toLocaleString('ru-RU');
    </script>
</body>
</html>
EOF

    print_success "Сводный отчет создан: $SUMMARY_FILE"
    echo -e "${CYAN}Откройте в браузере: file://${PWD}/${SUMMARY_FILE}${NC}"
}

# Показать справку
show_help() {
    cat << EOF
${BLUE}============================================================================
BITRIX SECURITY SCANNER
============================================================================${NC}

${GREEN}Использование:${NC}
    $0 [команда]

${GREEN}Команды:${NC}
    ${CYAN}quick${NC}       Быстрое сканирование (5-10 минут)
                 - OWASP ZAP baseline
                 - Nikto scan
                 - Bitrix security check

    ${CYAN}full${NC}        Полное сканирование (30-60 минут)
                 - OWASP ZAP full scan
                 - OWASP ZAP API scan
                 - Nikto scan
                 - TestSSL.sh
                 - Trivy container scan
                 - Bitrix security check

    ${CYAN}report${NC}      Генерация сводного HTML отчета

    ${CYAN}help${NC}        Показать эту справку

${GREEN}Примеры:${NC}
    $0 quick        # Быстрое сканирование
    $0 full         # Полное сканирование
    $0 report       # Создать сводный отчет

${YELLOW}Результаты сохраняются в: ${REPORTS_DIR}${NC}

EOF
}

# Главная логика
case "${1:-}" in
    quick)
        quick_scan
        ;;
    full)
        full_scan
        ;;
    report)
        generate_report
        ;;
    help|--help|-h)
        show_help
        ;;
    *)
        show_help
        exit 1
        ;;
esac
