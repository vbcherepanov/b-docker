FROM alpine:latest

# Установка необходимых пакетов
RUN apk add --no-cache \
    bash \
    curl \
    mysql-client \
    tar \
    gzip \
    rsync \
    tzdata

# Создание пользователя для бэкапов
RUN addgroup -g 1000 -S backup && adduser -u 1000 -S backup -G backup

# Создание директорий
RUN mkdir -p /backups /scripts /etc/backup /var/spool/cron/crontabs

# Копирование скриптов
COPY config/backup/backup.sh /scripts/backup.sh
COPY config/backup/cleanup.sh /scripts/cleanup.sh
COPY config/backup/crontab /var/spool/cron/crontabs/root

# Установка прав
RUN chmod +x /scripts/*.sh && \
    chown -R backup:backup /backups /scripts && \
    chmod 0600 /var/spool/cron/crontabs/root

# Установка временной зоны
ARG TZ
ENV TZ=${TZ:-UTC}
RUN ln -snf /usr/share/zoneinfo/${TZ:-UTC} /etc/localtime && echo ${TZ:-UTC} > /etc/timezone

# Запуск busybox crond (foreground, логи в stdout)
CMD ["crond", "-f", "-l", "2"]