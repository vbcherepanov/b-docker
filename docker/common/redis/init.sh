#!/bin/sh
set -eux
echo "Configuring system for Redis..."
# Безопасно отключаем Transparent HugePages (если доступно)
[ -f /sys/kernel/mm/transparent_hugepage/enabled ] && echo never > /sys/kernel/mm/transparent_hugepage/enabled || true
[ -f /sys/kernel/mm/transparent_hugepage/defrag ] && echo never > /sys/kernel/mm/transparent_hugepage/defrag || true
# Настройка системных параметров (если разрешено)
sysctl -w net.core.somaxconn=512 || true
sysctl -w vm.overcommit_memory=1 || true
echo "Starting Redis..."
exec redis-server