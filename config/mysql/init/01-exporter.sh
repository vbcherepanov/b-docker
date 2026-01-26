#!/bin/bash
# ============================================================================
# Create MySQL Exporter user for Prometheus monitoring
# This script runs on database initialization
# ============================================================================

set -e

# Wait for MySQL to be ready
until mysqladmin ping -h"localhost" --silent; do
    echo "Waiting for MySQL..."
    sleep 2
done

# Create exporter user with password from environment
# MYSQL_EXPORTER_PASSWORD is set in .env
EXPORTER_PASSWORD="${MYSQL_EXPORTER_PASSWORD:-exporter_password}"

mysql -u root -p"${MYSQL_ROOT_PASSWORD}" <<-EOSQL
    -- Drop old user if exists (with wrong password)
    DROP USER IF EXISTS 'exporter'@'%';
    DROP USER IF EXISTS 'exporter'@'localhost';
    DROP USER IF EXISTS 'exporter'@'172.%';

    -- Create exporter user for Prometheus MySQL Exporter
    CREATE USER 'exporter'@'%' IDENTIFIED BY '${EXPORTER_PASSWORD}';

    -- Grant required permissions for mysqld_exporter
    GRANT PROCESS, REPLICATION CLIENT, SELECT ON *.* TO 'exporter'@'%';

    FLUSH PRIVILEGES;

    SELECT 'Exporter user created successfully' AS status;
EOSQL

echo "MySQL exporter user configured."
