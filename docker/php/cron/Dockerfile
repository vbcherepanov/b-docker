ARG PHP_VERSION=8.3
FROM my/php-base-cli:${PHP_VERSION}

# Аргументы и переменные окружения
ARG ENVIRONMENT=production
ARG DOMAIN
ARG EMAIL
ARG SSL=0
ARG TZ
ARG UID=1000
ARG GID=1000
ARG UGN=deploy
ENV ENVIRONMENT=${ENVIRONMENT}
ENV DOMAIN=${DOMAIN}
ENV EMAIL=${EMAIL}
ENV SSL=${SSL}
ENV TZ=${TZ:-UTC}
ENV UGN=${UGN}

# SHELL с безопасными флагами
SHELL ["/bin/sh", "-eux", "-o", "pipefail", "-c"]

USER root
RUN if [ "$SSL" != "0" ]; then \
      SSL=1; \
    fi
# Установка cronie и утилит
RUN apk add --no-cache bash curl busybox-suid tzdata

# Подготовка директорий с правильными правами
RUN mkdir -p "/home/${UGN}/app" "/home/${UGN}/tmp" "/home/${UGN}/run" /etc/crontabs && \
    touch "/etc/crontabs/${UGN}" && \
    chmod 600 "/etc/crontabs/${UGN}" && \
    chown -v -R "${UGN}:${UGN}" "/home/${UGN}/app" "/home/${UGN}/tmp" "/home/${UGN}/run" "/etc/crontabs/${UGN}" && \
    chmod -v -R 755 "/home/${UGN}/app" "/home/${UGN}/tmp" "/home/${UGN}/run"

# Копирование конфигов и entrypoint
COPY /docker/common/php/php.ini.template /usr/local/etc/php/php.ini.template
RUN envsubst < /usr/local/etc/php/php.ini.template > /usr/local/etc/php/php.ini
COPY /docker/common/php/conf.d /usr/local/etc/php/conf.d
COPY /docker/common/php/entrypoint.sh /usr/local/bin/docker-php-entrypoint
RUN chmod +x /usr/local/bin/docker-php-entrypoint
# Очистка Xdebug и MailHog в продакшн
RUN if [ "$ENVIRONMENT" = "prod" ]; then \
      pecl uninstall -r xdebug || true && \
      docker-php-ext-disable xdebug || true && \
      rm -f /usr/local/etc/php/conf.d/*xdebug.ini \
            /usr/local/etc/php/conf.d/mailhog.ini; \
    else \
      rm -f /usr/local/etc/php/conf.d/msmtp.ini; \
    fi
WORKDIR /home/$UGN/app

#ENV UGN=root
ENTRYPOINT ["/usr/local/bin/docker-php-entrypoint"]
CMD ["crond","-f","-l","8","-L","/dev/stdout","-c","/etc/crontabs"]
# Healthcheck
HEALTHCHECK --interval=30s --timeout=5s --retries=3 \
   CMD pidof crond >/dev/null || exit 1
