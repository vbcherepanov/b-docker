#!/bin/sh
set -eux

echo "Configuring system for Redis..."

# Safely disable Transparent HugePages (if accessible)
[ -f /sys/kernel/mm/transparent_hugepage/enabled ] && echo never > /sys/kernel/mm/transparent_hugepage/enabled || true
[ -f /sys/kernel/mm/transparent_hugepage/defrag ] && echo never > /sys/kernel/mm/transparent_hugepage/defrag || true

# System tuning (if permitted)
sysctl -w net.core.somaxconn=512 || true
sysctl -w vm.overcommit_memory=1 || true

# Ensure socket directory exists with correct permissions
# This directory is a shared volume between redis and php containers
# GID 1000 = bitrix user in PHP container, allowing socket access via group
mkdir -p /var/run/redis
chown redis:1000 /var/run/redis
chmod 770 /var/run/redis

echo "Starting Redis with config..."
exec redis-server /usr/local/etc/redis/redis.conf
