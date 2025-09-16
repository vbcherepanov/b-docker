#!/bin/sh

. /usr/local/bin/script/func/main.sh
MAIL_CONFIG_PARAM="${1:-$MAIL_CONFIG}"
DOMAIN="${2:-$DOMAIN}"

if [ "$MAIL_CONFIG_PARAM" = "1" ]; then
    envsubst < "$TEMPLATE_DIR/mail.conf.tmpl" > "$CONF_DIR/mail_$DOMAIN.conf"
    reload_nginx
fi