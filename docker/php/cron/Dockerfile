# ============================================================================
# CRON CONTAINER (SPLIT ARCHITECTURE)
# Runs scheduled tasks for Bitrix agents and maintenance
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
# INSTALL CRON AND UTILITIES
# dcron requires busybox-suid for proper crontab execution
# ============================================================================
RUN apk add --no-cache \
    dcron \
    busybox-suid \
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
    "/var/log/cron" \
    "/var/log/bitrix" \
    "/etc/crontabs" \
    "/etc/bitrix-sites" \
    "/var/lib/php/sessions" \
    && touch "/etc/crontabs/${UGN}"

# ============================================================================
# SET PERMISSIONS
# ============================================================================
RUN chown -R "${UGN}:${UGN}" \
    "/home/${UGN}" \
    "/var/log/php" \
    "/var/log/cron" \
    "/var/log/bitrix" \
    "/etc/crontabs/${UGN}" \
    "/var/lib/php/sessions" \
    && chmod 600 "/etc/crontabs/${UGN}" \
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

# Base entrypoint (shared)
COPY /docker/common/php/entrypoint-base.sh /usr/local/bin/entrypoint-base

# Cron-specific entrypoint
COPY /docker/php/cron/entrypoint.sh /usr/local/bin/docker-entrypoint
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

# Healthcheck: verify crond process is running
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD pidof crond >/dev/null || exit 1

ENTRYPOINT ["/usr/local/bin/docker-entrypoint"]

# Run crond in foreground with log level 2 (notice), output to stdout
CMD ["crond", "-f", "-l", "2", "-L", "/dev/stdout"]
