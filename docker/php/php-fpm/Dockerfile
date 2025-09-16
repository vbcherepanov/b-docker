ARG PHP_VERSION=8.3
FROM my/php-base-fpm:${PHP_VERSION}

ARG ENVIRONMENT=production
ARG DOMAIN
ARG EMAIL
ARG SSL=0
ARG TZ
ARG UGN=deploy

ENV ENVIRONMENT=${ENVIRONMENT}
ENV DOMAIN=${DOMAIN}
ENV EMAIL=${EMAIL}
ENV SSL=${SSL}
ENV TZ=${TZ:-UTC}
ENV UGN=${UGN}

SHELL ["/bin/sh", "-eux", "-o", "pipefail", "-c"]

USER root
RUN if [ "$SSL" != "0" ]; then \
      SSL=1; \
    fi
## Копирование конфигов PHP и PHP-FPM
COPY /docker/common/php/php.ini.template /usr/local/etc/php/php.ini.template
RUN envsubst < /usr/local/etc/php/php.ini.template > /usr/local/etc/php/php.ini
COPY /docker/common/php/conf.d /usr/local/etc/php/conf.d
COPY /docker/common/php/php-fpm.d /usr/local/etc/php-fpm.d
COPY /docker/common/php/entrypoint.sh /usr/local/bin/docker-php-entrypoint
COPY /docker/common/php/add_site.sh /usr/local/bin/add_site.sh
RUN chmod +x /usr/local/bin/docker-php-entrypoint
RUN chmod +x /usr/local/bin/add_site.sh
#
# Очистка xdebug и mailhog в production
RUN if [ "$ENVIRONMENT" = "prod" ]; then \
      pecl uninstall -r xdebug || true && \
      docker-php-ext-disable xdebug || true && \
      rm -f /usr/local/etc/php/conf.d/*xdebug.ini \
            /usr/local/etc/php/conf.d/mailhog.ini; \
    else \
      rm -f /usr/local/etc/php/conf.d/msmtp.ini; \
    fi
EXPOSE 9000
RUN mkdir -p "/home/${UGN}/app" "/home/${UGN}/tmp" && \
    chown -R "${UGN}:${UGN}" "/home/${UGN}/app" "/home/${UGN}/tmp" && \
    chmod -R 755 "/home/${UGN}/app" "/home/${UGN}/tmp"

WORKDIR /home/${UGN}/app
USER ${UGN}
ENTRYPOINT ["/usr/local/bin/docker-php-entrypoint"]
CMD ["php-fpm"]
HEALTHCHECK --interval=300s --timeout=3s --start-period=1s \
  CMD REDIRECT_STATUS=true SCRIPT_NAME=/ping SCRIPT_FILENAME=/ping REQUEST_METHOD=GET \
      cgi-fcgi -bind -connect 127.0.0.1:9000 || exit 1