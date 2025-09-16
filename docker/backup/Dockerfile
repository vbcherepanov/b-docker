FROM alpine:latest

# Установка необходимых пакетов
RUN apk add --no-cache \
    bash \
    curl \
    mysql-client \
    tar \
    gzip \
    rsync \
    dcron \
    tzdata

# Создание пользователя для бэкапов
RUN addgroup -S backup && adduser -S backup -G backup

# Создание директорий
RUN mkdir -p /backups /scripts /etc/backup

# Копирование скриптов
COPY config/backup/backup.sh /scripts/backup.sh
COPY config/backup/cleanup.sh /scripts/cleanup.sh
COPY config/backup/crontab /etc/crontabs/backup

# Установка прав
RUN chmod +x /scripts/*.sh
RUN chown -R backup:backup /backups /scripts

# Установка временной зоны
ARG TZ
ENV TZ=${TZ:-UTC}
RUN ln -snf /usr/share/zoneinfo/${TZ:-UTC} /etc/localtime && echo ${TZ:-UTC} > /etc/timezone

# Запуск cron демона
CMD ["crond", "-f", "-d", "8"]