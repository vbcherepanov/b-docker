FROM nginx:alpine

# Установка зависимостей для безопасного nginx
RUN apk add --no-cache \
    curl \
    wget \
    tzdata \
    openssl

# Создание директорий для логов безопасности
RUN mkdir -p /var/log/nginx-security \
             /etc/nginx/security

# Копирование конфигураций
COPY docker/modsecurity/nginx.conf /etc/nginx/nginx.conf

# Создание пользователя nginx (если не существует)
RUN addgroup -g 101 -S nginx 2>/dev/null || true && \
    adduser -S -D -H -u 101 -h /var/cache/nginx -s /sbin/nologin -G nginx -g nginx nginx 2>/dev/null || true

# Права доступа
RUN chown -R nginx:nginx /var/log/nginx-security

EXPOSE 80 443

STOPSIGNAL SIGTERM

CMD ["nginx", "-g", "daemon off;"]