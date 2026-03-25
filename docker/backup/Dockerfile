# Backup container — uses the SAME database image as the main DB
# This guarantees 100% client/server compatibility (no MariaDB client vs MySQL 8.4 issues)
ARG MYSQL_IMAGE=mysql:8.4
FROM ${MYSQL_IMAGE}

ARG TZ=UTC

# Install cron and utilities
# mysql:8.4 = Oracle Linux 9 (microdnf)
# mariadb:* = Ubuntu (apt-get)
RUN set -eux; \
    if command -v microdnf >/dev/null 2>&1; then \
        microdnf install -y cronie tar gzip findutils && microdnf clean all; \
    elif command -v apt-get >/dev/null 2>&1; then \
        apt-get update && apt-get install -y --no-install-recommends cron tar gzip findutils && rm -rf /var/lib/apt/lists/*; \
    fi

# Set timezone
RUN ln -snf /usr/share/zoneinfo/${TZ} /etc/localtime && echo ${TZ} > /etc/timezone

# Create directories
RUN mkdir -p /backups/database /backups/files /scripts /var/log

# Copy scripts
COPY config/backup/backup.sh /scripts/backup.sh
COPY config/backup/cleanup.sh /scripts/cleanup.sh
COPY docker/backup/docker-entrypoint.sh /docker-entrypoint.sh

# Set permissions
RUN chmod +x /scripts/*.sh /docker-entrypoint.sh

ENTRYPOINT ["/docker-entrypoint.sh"]
CMD ["cron"]
