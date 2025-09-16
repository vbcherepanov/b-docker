#!/bin/sh

. /usr/local/bin/script/func/main.sh
RABBIT_CONFIG_PARAM="${1:-$RABBIT_CONFIG}"
DOMAIN="${2:-$DOMAIN}"
if [ "$RABBIT_CONFIG_PARAM" = "1" ]; then
    envsubst < "$TEMPLATE_DIR/rabbit.conf.tmpl" > "$CONF_DIR/rabbit_$DOMAIN.conf"
    reload_nginx
fi