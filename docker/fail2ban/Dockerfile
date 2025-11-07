FROM alpine:3.17

# Установка fail2ban и зависимостей
RUN apk add --no-cache \
    fail2ban \
    iptables \
    whois \
    tzdata \
    bash

# Создание директорий
RUN mkdir -p /var/log/fail2ban \
             /etc/fail2ban/jail.d \
             /etc/fail2ban/filter.d \
             /etc/fail2ban/action.d

# Копирование конфигураций
COPY docker/fail2ban/config/jail.local /etc/fail2ban/jail.local
COPY docker/fail2ban/config/filter.d/ /etc/fail2ban/filter.d/
COPY docker/fail2ban/config/action.d/ /etc/fail2ban/action.d/
COPY docker/fail2ban/entrypoint.sh /entrypoint.sh

# Права на выполнение
RUN chmod +x /entrypoint.sh

# Переменные окружения
ENV TZ=UTC

VOLUME ["/var/log/nginx"]

EXPOSE 22

ENTRYPOINT ["/entrypoint.sh"]
CMD ["fail2ban-server", "-f"]