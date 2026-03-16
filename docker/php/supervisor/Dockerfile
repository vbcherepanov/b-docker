# ============================================================================
# SUPERVISOR CONTAINER (SPLIT ARCHITECTURE)
# Runs background workers (Bitrix agents, mail queue, push server, etc.)
# Part of split architecture: php-fpm / php-cli / cron / supervisor
# ============================================================================

ARG PHP_VERSION=8.3
FROM my/php-base-cli:${PHP_VERSION}

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
# PHP arguments
ARG PHP_MEMORY_LIMIT=256M
ARG PHP_UPLOAD_MAX_FILESIZE=64M
ARG PHP_POST_MAX_SIZE=64M

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
    PHP_MEMORY_LIMIT=${PHP_MEMORY_LIMIT} \
    PHP_UPLOAD_MAX_FILESIZE=${PHP_UPLOAD_MAX_FILESIZE} \
    PHP_POST_MAX_SIZE=${PHP_POST_MAX_SIZE}

# Safe shell
SHELL ["/bin/sh", "-eux", "-o", "pipefail", "-c"]

USER root

# ============================================================================
# INSTALL SUPERVISOR AND UTILITIES
# ============================================================================
RUN apk add --no-cache \
    supervisor \
    curl \
    && rm -rf /tmp/* /var/cache/apk/*

# ============================================================================
# CREATE DIRECTORY STRUCTURE
# ============================================================================
RUN mkdir -p \
    "/home/${UGN}/app" \
    "/home/${UGN}/tmp" \
    "/home/${UGN}/run" \
    "/var/log/php" \
    "/var/log/supervisor" \
    "/var/log/bitrix" \
    "/var/run/supervisor" \
    "/etc/supervisor/conf.d" \
    "/etc/bitrix-sites" \
    "/var/lib/php/sessions"

# ============================================================================
# SET PERMISSIONS
# ============================================================================
RUN chown -R "${UGN}:${UGN}" \
    "/home/${UGN}" \
    "/var/log/php" \
    "/var/log/supervisor" \
    "/var/log/bitrix" \
    "/var/run/supervisor" \
    "/var/lib/php/sessions" \
    && chmod -R 755 "/home/${UGN}/app" \
    && chmod -R 770 "/var/lib/php/sessions" \
    && chmod -R 755 "/home/${UGN}/tmp" \
    && chmod -R 755 "/var/log/supervisor"

# ============================================================================
# COPY CONFIGURATION FILES
# ============================================================================

# PHP configuration
COPY /docker/common/php/php.ini.template /usr/local/etc/php/php.ini.template
RUN envsubst < /usr/local/etc/php/php.ini.template > /usr/local/etc/php/php.ini

# PHP conf.d
COPY /docker/common/php/conf.d /usr/local/etc/php/conf.d

# Supervisor configuration (reuse from common)
COPY /docker/common/php/supervisor/supervisord.conf /etc/supervisord.conf
COPY /config/supervisor/conf /etc/supervisor/conf.d

# Base entrypoint (shared)
COPY /docker/common/php/entrypoint-base.sh /usr/local/bin/entrypoint-base

# Supervisor-specific entrypoint
COPY /docker/php/supervisor/entrypoint.sh /usr/local/bin/docker-entrypoint
RUN chmod +x /usr/local/bin/entrypoint-base /usr/local/bin/docker-entrypoint

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
# WORKDIR
# ============================================================================
WORKDIR /home/${UGN}/app

# Healthcheck: verify supervisord process is running
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD ps -o pid,comm | grep -q supervisord || exit 1

ENTRYPOINT ["/usr/local/bin/docker-entrypoint"]

CMD ["supervisord", "-c", "/etc/supervisord.conf"]
