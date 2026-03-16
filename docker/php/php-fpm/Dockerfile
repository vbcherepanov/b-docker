# ============================================================================
# PHP-FPM CONTAINER (SPLIT ARCHITECTURE)
# Handles HTTP request processing via FastCGI
# Part of split architecture: php-fpm / php-cli / cron / supervisor
# ============================================================================

ARG PHP_VERSION=8.3
FROM my/php-base-fpm:${PHP_VERSION}

# ============================================================================
# BUILD ARGUMENTS
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
# PHP-FPM arguments
ARG PHP_FPM_PM=dynamic
ARG PHP_FPM_MAX_CHILDREN=50
ARG PHP_FPM_START_SERVERS=5
ARG PHP_FPM_MIN_SPARE_SERVERS=5
ARG PHP_FPM_MAX_SPARE_SERVERS=35
# PHP arguments
ARG PHP_MEMORY_LIMIT=256M
ARG PHP_UPLOAD_MAX_FILESIZE=64M
ARG PHP_POST_MAX_SIZE=64M
# Push server key is passed via docker-compose environment at runtime only

# ============================================================================
# ENVIRONMENT VARIABLES
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
    PHP_FPM_PM=${PHP_FPM_PM} \
    PHP_FPM_MAX_CHILDREN=${PHP_FPM_MAX_CHILDREN} \
    PHP_FPM_START_SERVERS=${PHP_FPM_START_SERVERS} \
    PHP_FPM_MIN_SPARE_SERVERS=${PHP_FPM_MIN_SPARE_SERVERS} \
    PHP_FPM_MAX_SPARE_SERVERS=${PHP_FPM_MAX_SPARE_SERVERS} \
    PHP_MEMORY_LIMIT=${PHP_MEMORY_LIMIT} \
    PHP_UPLOAD_MAX_FILESIZE=${PHP_UPLOAD_MAX_FILESIZE} \
    PHP_POST_MAX_SIZE=${PHP_POST_MAX_SIZE}

# Safe shell
SHELL ["/bin/sh", "-eux", "-o", "pipefail", "-c"]

USER root

# ============================================================================
# INSTALL ADDITIONAL PACKAGES
# ============================================================================
RUN apk add --no-cache \
    logrotate \
    net-tools \
    iputils \
    bind-tools \
    && rm -rf /tmp/* /var/cache/apk/*

# ============================================================================
# CREATE DIRECTORY STRUCTURE
# System directories (logs, PHP sessions, msmtp)
# NOTE: upload, local, bitrix/cache are created inside domain folders
#       at container startup in entrypoint (multisite support)
# ============================================================================
RUN mkdir -p \
    "/home/${UGN}/app" \
    "/home/${UGN}/tmp" \
    "/home/${UGN}/run" \
    "/home/${UGN}/.composer" \
    "/var/log/php" \
    "/var/log/php-fpm" \
    "/var/log/bitrix" \
    "/var/log/msmtp" \
    "/var/lib/msmtp/sites" \
    "/etc/bitrix-sites" \
    "/var/lib/php/sessions"

# ============================================================================
# SET PERMISSIONS
# ============================================================================
RUN chown -R "${UGN}:${UGN}" \
    "/home/${UGN}" \
    "/var/log/php" \
    "/var/log/php-fpm" \
    "/var/log/bitrix" \
    "/var/log/msmtp" \
    "/var/lib/msmtp/sites" \
    "/var/lib/php/sessions" \
    && chmod -R 755 "/home/${UGN}/app" \
    && chmod -R 770 "/var/lib/php/sessions" \
    && chmod -R 755 "/home/${UGN}/tmp"

# ============================================================================
# COPY CONFIGURATION FILES
# ============================================================================

# PHP configuration
COPY /docker/common/php/php.ini.template /usr/local/etc/php/php.ini.template
RUN envsubst < /usr/local/etc/php/php.ini.template > /usr/local/etc/php/php.ini

# PHP conf.d
COPY /docker/common/php/conf.d /usr/local/etc/php/conf.d

# PHP-FPM configuration
COPY /docker/common/php/php-fpm.d /usr/local/etc/php-fpm.d

# Logrotate
COPY /config/logrotate/bitrix-logs.conf /etc/logrotate.d/bitrix

# Base entrypoint (shared)
COPY /docker/common/php/entrypoint-base.sh /usr/local/bin/entrypoint-base

# FPM-specific entrypoint and scripts
COPY /docker/php/php-fpm/entrypoint.sh /usr/local/bin/docker-entrypoint
COPY /docker/common/php/scripts /usr/local/bin/scripts
RUN chmod +x /usr/local/bin/entrypoint-base /usr/local/bin/docker-entrypoint && \
    (chmod +x /usr/local/bin/scripts/* 2>/dev/null || true)

# ============================================================================
# CLEANUP DEBUG TOOLS IN PRODUCTION
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
# WORKDIR AND EXPOSE
# ============================================================================
WORKDIR /home/${UGN}/app

EXPOSE 9000

# Healthcheck via cgi-fcgi ping on port 9000
HEALTHCHECK --interval=30s --timeout=3s --start-period=10s --retries=3 \
  CMD REDIRECT_STATUS=true SCRIPT_NAME=/ping SCRIPT_FILENAME=/ping REQUEST_METHOD=GET \
      cgi-fcgi -bind -connect 127.0.0.1:9000 || exit 1

ENTRYPOINT ["/usr/local/bin/docker-entrypoint"]

CMD ["php-fpm"]
