#!/bin/sh

HOST_DOMAIN="host.docker.internal"
DOMAIN_SITE="${1:-$DOMAIN}"
# Ждем, пока контейнер будет готов
echo "Waiting for $HOST_DOMAIN to get IP address..."
sleep 10
# Получаем IP адрес контейнера
IP_ADDRESS=$(getent hosts "$HOST_DOMAIN" | awk '{ print $1 }')
NGINX_IP=$(getent hosts nginx | awk '{ print $1 }')
if [ -n "$NGINX_IP" ]; then
    echo "Adding $DOMAIN_SITE to /etc/hosts with IP address $NGINX_IP"
    echo "$NGINX_IP $DOMAIN_SITE" >> /etc/hosts
else
    echo "Could not find IP address for $1"
fi