#!/bin/bash
# ============================================================================
# HEALTHCHECK SCRIPT FOR BITRIX CONTAINER
# Проверка работоспособности всех критичных процессов
# ============================================================================

set -e

# Флаг общего состояния
HEALTHY=0

# ============================================================================
# 1. ПРОВЕРКА SUPERVISOR
# ============================================================================
if ! pgrep -x supervisord > /dev/null 2>&1; then
    echo "ERROR: Supervisord is not running"
    exit 1
fi

# ============================================================================
# 2. ПРОВЕРКА PHP-FPM
# ============================================================================
# Проверяем через cgi-fcgi (быстрее чем через supervisorctl)
if command -v cgi-fcgi >/dev/null 2>&1; then
    if ! REDIRECT_STATUS=true \
         SCRIPT_NAME=/ping \
         SCRIPT_FILENAME=/ping \
         REQUEST_METHOD=GET \
         cgi-fcgi -bind -connect 127.0.0.1:9000 >/dev/null 2>&1; then
        echo "ERROR: PHP-FPM is not responding"
        exit 1
    fi
else
    # Fallback: проверяем процесс
    if ! pgrep -x php-fpm > /dev/null 2>&1; then
        echo "ERROR: PHP-FPM process is not running"
        exit 1
    fi
fi

# ============================================================================
# 3. ПРОВЕРКА CRON
# ============================================================================
if ! pgrep -x crond > /dev/null 2>&1; then
    echo "WARNING: Crond is not running (non-critical)"
    # Не выходим с ошибкой, так как cron не критичен для работы сайта
fi

# ============================================================================
# 4. ПРОВЕРКА ЧЕРЕЗ SUPERVISOR STATUS
# ============================================================================
# Проверяем что все критичные процессы в состоянии RUNNING
if command -v supervisorctl >/dev/null 2>&1; then
    # Проверяем PHP-FPM через supervisor
    PHP_FPM_STATUS=$(supervisorctl -c /etc/supervisord.conf status php-fpm 2>/dev/null | awk '{print $2}' || echo "UNKNOWN")

    if [ "$PHP_FPM_STATUS" != "RUNNING" ]; then
        echo "ERROR: PHP-FPM supervisor status: $PHP_FPM_STATUS"
        exit 1
    fi
fi

# ============================================================================
# ВСЕ ПРОВЕРКИ ПРОЙДЕНЫ
# ============================================================================
echo "OK: All critical services are running"
exit 0
