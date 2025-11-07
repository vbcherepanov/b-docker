#!/bin/bash

# Установка временной зоны
if [ ! -z "$TZ" ]; then
    ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone
fi

# Создание сокета для fail2ban
mkdir -p /var/run/fail2ban

# Инициализация iptables если нужно
if [ "$INIT_IPTABLES" = "true" ]; then
    # Проверяем доступность iptables
    if command -v iptables >/dev/null 2>&1; then
        # Создаем базовые цепочки если их нет
        iptables -L INPUT >/dev/null 2>&1 || iptables -N INPUT 2>/dev/null || true
        iptables -L FORWARD >/dev/null 2>&1 || iptables -N FORWARD 2>/dev/null || true
        iptables -L OUTPUT >/dev/null 2>&1 || iptables -N OUTPUT 2>/dev/null || true

        # Базовые правила безопасности
        iptables -I INPUT -i lo -j ACCEPT 2>/dev/null || true
        iptables -I INPUT -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT 2>/dev/null || true

        echo "iptables initialized"
    else
        echo "Warning: iptables not available, running in log-only mode"
    fi
fi

# Проверка наличия лог файлов
if [ ! -f /var/log/nginx/access.log ]; then
    echo "Warning: /var/log/nginx/access.log not found, creating empty file"
    touch /var/log/nginx/access.log
fi

if [ ! -f /var/log/nginx/error.log ]; then
    echo "Warning: /var/log/nginx/error.log not found, creating empty file"
    touch /var/log/nginx/error.log
fi

# Тестируем конфигурацию fail2ban
echo "Testing fail2ban configuration..."
fail2ban-client -t || exit 1

echo "Starting fail2ban..."
exec "$@"