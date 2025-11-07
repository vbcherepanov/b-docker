#!/bin/bash

# MySQL initialization script

set -e

echo "MySQL init script started"

# Wait for MySQL to be ready
while ! mysqladmin ping -h"localhost" --silent; do
    echo "Waiting for MySQL to be ready..."
    sleep 2
done

echo "MySQL is ready"

# Run any additional initialization
if [ -f /docker-entrypoint-initdb.d/init.sql ]; then
    echo "Running custom initialization script..."
    mysql -u root -p"${MYSQL_ROOT_PASSWORD}" < /docker-entrypoint-initdb.d/init.sql
    echo "Custom initialization completed"
fi

echo "MySQL init script completed"