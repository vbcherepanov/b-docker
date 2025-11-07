# ============================================================================
# ЕДИНЫЙ BITRIX КОНТЕЙНЕР
# PHP-FPM + CLI + Cron + Supervisor
# Все процессы управляются Supervisor'ом
# ============================================================================

ARG PHP_VERSION=8.3
FROM my/php-base-fpm:${PHP_VERSION}

# ============================================================================
# АРГУМЕНТЫ СБОРКИ
# ============================================================================
ARG ENVIRONMENT=production
ARG DOMAIN
ARG EMAIL
ARG SSL=0
ARG TZ=UTC
ARG UID=1000
ARG GID=1000
ARG UGN=bitrix
ARG DEBUG=0

# ============================================================================
# ПЕРЕМЕННЫЕ ОКРУЖЕНИЯ
# ============================================================================
ENV ENVIRONMENT=${ENVIRONMENT} \
    DOMAIN=${DOMAIN} \
    EMAIL=${EMAIL} \
    SSL=${SSL} \
    TZ=${TZ} \
    UGN=${UGN} \
    UID=${UID} \
    GID=${GID} \
    DEBUG=${DEBUG} \
    PHP_FPM_PM=${PHP_FPM_PM:-dynamic} \
    PHP_FPM_MAX_CHILDREN=${PHP_FPM_MAX_CHILDREN:-50} \
    PHP_FPM_START_SERVERS=${PHP_FPM_START_SERVERS:-5} \
    PHP_FPM_MIN_SPARE_SERVERS=${PHP_FPM_MIN_SPARE_SERVERS:-5} \
    PHP_FPM_MAX_SPARE_SERVERS=${PHP_FPM_MAX_SPARE_SERVERS:-35} \
    PHP_MEMORY_LIMIT=${PHP_MEMORY_LIMIT:-256M} \
    PHP_UPLOAD_MAX_FILESIZE=${PHP_UPLOAD_MAX_FILESIZE:-64M} \
    PHP_POST_MAX_SIZE=${PHP_POST_MAX_SIZE:-64M}

# Безопасный shell
SHELL ["/bin/sh", "-eux", "-o", "pipefail", "-c"]

USER root

# ============================================================================
# УСТАНОВКА ДОПОЛНИТЕЛЬНЫХ ПАКЕТОВ
# ============================================================================
# Supervisor для управления процессами
# Cron для выполнения задач по расписанию
# CLI утилиты для работы
# ============================================================================
RUN apk add --no-cache \
    supervisor \
    busybox-suid \
    dcron \
    logrotate \
    wget \
    curl \
    nano \
    vim \
    htop \
    procps \
    net-tools \
    iputils \
    bind-tools \
    jq \
    && rm -rf /tmp/* /var/cache/apk/*

# ============================================================================
# СОЗДАНИЕ СТРУКТУРЫ ДИРЕКТОРИЙ
# ============================================================================
RUN mkdir -p \
    # Основные директории приложения
    "/home/${UGN}/app" \
    "/home/${UGN}/tmp" \
    "/home/${UGN}/run" \
    "/home/${UGN}/.composer" \
    # Директории Битрикса (будут монтироваться извне)
    "/home/${UGN}/app/upload" \
    "/home/${UGN}/app/local" \
    "/home/${UGN}/app/bitrix/cache" \
    "/home/${UGN}/app/bitrix/backup" \
    "/home/${UGN}/app/bitrix/modules" \
    # Директории логов
    "/var/log/php" \
    "/var/log/php-fpm" \
    "/var/log/cron" \
    "/var/log/supervisor" \
    "/var/log/bitrix" \
    # Supervisor
    "/var/run/supervisor" \
    "/etc/supervisor/conf.d" \
    # Cron
    "/etc/crontabs" \
    && touch "/etc/crontabs/${UGN}"

# ============================================================================
# НАСТРОЙКА ПРАВ ДОСТУПА
# ============================================================================
# Битрикс требует специфичных прав на upload и cache директории
# ============================================================================
RUN chown -R "${UGN}:${UGN}" \
    "/home/${UGN}" \
    "/var/log/php" \
    "/var/log/php-fpm" \
    "/var/log/cron" \
    "/var/log/supervisor" \
    "/var/log/bitrix" \
    "/var/run/supervisor" \
    "/etc/crontabs/${UGN}" \
    && chmod 600 "/etc/crontabs/${UGN}" \
    && chmod -R 755 "/home/${UGN}/app" \
    && chmod -R 777 "/home/${UGN}/app/upload" "/home/${UGN}/app/bitrix/cache" \
    && chmod -R 755 "/home/${UGN}/tmp"

# ============================================================================
# КОПИРОВАНИЕ КОНФИГУРАЦИОННЫХ ФАЙЛОВ
# ============================================================================

# PHP конфигурация
COPY /docker/common/php/php.ini.template /usr/local/etc/php/php.ini.template
RUN envsubst < /usr/local/etc/php/php.ini.template > /usr/local/etc/php/php.ini
COPY /docker/common/php/conf.d /usr/local/etc/php/conf.d

# PHP-FPM конфигурация
COPY /docker/common/php/php-fpm.d /usr/local/etc/php-fpm.d

# Supervisor конфигурация
COPY /docker/php/bitrix/supervisord.conf /etc/supervisord.conf
COPY /config/supervisor/conf /etc/supervisor/conf.d
COPY /config/logrotate/bitrix-logs.conf /etc/logrotate.d/bitrix

# Entrypoint и вспомогательные скрипты
COPY /docker/php/bitrix/docker-entrypoint.sh /usr/local/bin/docker-entrypoint
COPY /docker/php/bitrix/healthcheck.sh /usr/local/bin/healthcheck
RUN chmod +x /usr/local/bin/docker-entrypoint /usr/local/bin/healthcheck

# ============================================================================
# ОЧИСТКА ОТЛАДОЧНЫХ ИНСТРУМЕНТОВ В ПРОДАКШН
# ============================================================================
RUN if [ "$ENVIRONMENT" = "prod" ] || [ "$ENVIRONMENT" = "production" ]; then \
      echo "==> Production mode: removing debug tools..."; \
      pecl uninstall -r xdebug || true; \
      docker-php-ext-disable xdebug || true; \
      rm -f /usr/local/etc/php/conf.d/*xdebug.ini \
            /usr/local/etc/php/conf.d/mailhog.ini \
            /usr/bin/mhsendmail; \
    else \
      echo "==> Development mode: keeping debug tools..."; \
      rm -f /usr/local/etc/php/conf.d/msmtp.ini; \
    fi

# ============================================================================
# БЕЗОПАСНОСТЬ: РАБОТА ОТ NON-ROOT ПОЛЬЗОВАТЕЛЯ
# ============================================================================
WORKDIR /home/${UGN}/app

# Expose порты
EXPOSE 9000

# Healthcheck для мониторинга состояния контейнера
HEALTHCHECK --interval=30s --timeout=10s --start-period=40s --retries=3 \
  CMD /usr/local/bin/healthcheck || exit 1

# Entrypoint
ENTRYPOINT ["/usr/local/bin/docker-entrypoint"]

# По умолчанию запускаем Supervisor, который управляет всеми процессами
CMD ["supervisord", "-c", "/etc/supervisord.conf", "-n"]
