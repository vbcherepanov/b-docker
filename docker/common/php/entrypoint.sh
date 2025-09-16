#!/bin/sh
set -euo pipefail

HOST_DOMAIN="host.docker.internal"

echo "Waiting for ${HOST_DOMAIN} to get IP address..."
sleep 2

# (необязательно) можно получить IP хоста
IP_ADDRESS="$(getent hosts "${HOST_DOMAIN}" | awk '{print $1}' || true)"

# Добавляем домен -> nginx (если контейнер 'nginx' резолвится)
if NGINX_IP="$(getent hosts nginx | awk '{print $1}' || true)"; then
  if [ -n "${NGINX_IP}" ] && [ -n "${DOMAIN:-}" ]; then
    if ! grep -qE "[[:space:]]${DOMAIN}(\$|[[:space:]])" /etc/hosts; then
      echo "Adding ${DOMAIN} to /etc/hosts with IP address ${NGINX_IP}"
      printf "%s %s\n" "${NGINX_IP}" "${DOMAIN}" >> /etc/hosts
    else
      echo "${DOMAIN} already present in /etc/hosts"
    fi
  else
    echo "DOMAIN is empty or nginx IP not found; skipping /etc/hosts update"
  fi
else
  echo "Could not resolve container 'nginx'; skipping /etc/hosts update"
fi

# /home/$UGN/tmp
UGN="${UGN:-bitrix}"
TMP_DIR="/home/${UGN}/tmp"
if [ -d "${TMP_DIR}" ]; then
  echo "Directory ${TMP_DIR} exists, setting permissions..."
else
  echo "Directory ${TMP_DIR} does not exist, creating..."
  mkdir -p "${TMP_DIR}"
fi
chown -R "${UGN}:${UGN}" "${TMP_DIR}"

# sanity-check потоков
if [ ! -e /dev/stderr ] || [ ! -e /dev/stdout ]; then
  echo "Warning: /dev/stdout or /dev/stderr missing; allocating TTY is recommended (tty: true)" 1>&2
fi

echo "Switching to ${UGN}..."

# Команда по умолчанию — php-fpm -F (foreground)
if [ "$#" -eq 0 ]; then
  if command -v crond >/dev/null 2>&1; then
    set -- crond -f -l 8 -L /dev/stdout -c /etc/crontabs
  elif command -v php-fpm >/dev/null 2>&1; then
    set -- php-fpm -F
  else
    set -- php
  fi
fi
# ВАЖНО: финальный exec под bitrix — сохранит stdout/stderr процесса Docker
exec "$@"