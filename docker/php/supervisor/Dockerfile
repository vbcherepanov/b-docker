ARG PHP_VERSION=8.3
FROM my/php-base-cli:${PHP_VERSION}

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

SHELL ["/bin/sh", "-eux", "-o", "pipefail", "-c"]
USER root
# Установка supervisor и полезных утилит
RUN apk add --no-cache bash curl supervisor

RUN if [ "$SSL" != "0" ]; then \
      SSL=1; \
    fi
# Каталог для supervisor
RUN mkdir -p /var/run/supervisor && \
    chown -R "${UGN}:${UGN}" /var/run/supervisor

RUN mkdir -p "/home/${UGN}/app" "/home/${UGN}/tmp" "/home/${UGN}/run" && \
    chown -v -R "${UGN}:${UGN}" "/home/${UGN}/app" "/home/${UGN}/tmp" && \
    chmod -v -R 755 "/home/${UGN}/app" "/home/${UGN}/tmp"
# Конфиги
COPY /docker/common/php/php.ini.template /usr/local/etc/php/php.ini.template
RUN envsubst < /usr/local/etc/php/php.ini.template > /usr/local/etc/php/php.ini
COPY /docker/common/php/conf.d /usr/local/etc/php/conf.d
COPY /docker/common/php/supervisor/supervisord.conf /etc/supervisord.conf
COPY /config/supervisor/conf /etc/supervisor/conf.d
COPY /docker/common/php/entrypoint.sh /usr/local/bin/docker-php-entrypoint
RUN chmod +x /usr/local/bin/docker-php-entrypoint

# Очистка xdebug и mailhog в продакшн
RUN if [ "$ENVIRONMENT" = "prod" ]; then \
      pecl uninstall -r xdebug || true && \
      docker-php-ext-disable xdebug || true && \
      rm -f /usr/local/etc/php/conf.d/*xdebug.ini \
            /usr/local/etc/php/conf.d/mailhog.ini; \
    else \
      rm -f /usr/local/etc/php/conf.d/msmtp.ini; \
    fi

# Рабочая директория и пользователь
WORKDIR /home/$UGN/app

ENTRYPOINT ["/usr/local/bin/docker-php-entrypoint"]
CMD ["supervisord", "-c", "/etc/supervisord.conf"]

HEALTHCHECK CMD [ "sh", "-c", "ps -o pid,comm | grep -q '^ *1 supervisord$'" ]