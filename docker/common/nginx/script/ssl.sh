#!/bin/sh

. /usr/local/bin/script/func/main.sh

if [ "$ENVIRONMENT" = "prod" ] || [ "$ENVIRONMENT" = "dev" ]; then
    if [ "$SSL" = "2" ]; then
        CERT_GENERATED=0
        echo "start generate SSL cert"
        echo "Create SSL for $DOMAIN"
        cert_paths=$(get_cert_paths "$DOMAIN" "$EMAIL")
        if [ $? -eq 0 ]; then
            CERT_PATH=$(echo "$cert_paths" | awk '{print $1}')
            KEY_PATH=$(echo "$cert_paths" | awk '{print $2}')
            envsubst < "$TEMPLATE_DIR/ssl_site.conf.tmpl" > "$CONF_DIR/ssl_$DOMAIN.conf"
            CERT_GENERATED=1
        fi
        sleep 3
        if [ "$MAIL_CONFIG" = "1" ]; then
            DOMAIN_STRING="mail.$DOMAIN"
            echo "Create SSL for $DOMAIN_STRING"
            cert_paths=$(get_cert_paths "$DOMAIN_STRING" "$EMAIL")
            if [ $? -eq 0 ]; then
                CERT_PATH=$(echo "$cert_paths" | awk '{print $1}')
                KEY_PATH=$(echo "$cert_paths" | awk '{print $2}')
                envsubst < "$TEMPLATE_DIR/ssl_mail.conf.tmpl" > "$CONF_DIR/ssl_$DOMAIN_STRING.conf"
                CERT_GENERATED=1
            fi
        fi
        sleep 3
        if [ "$RABBIT_CONFIG" = "1" ]; then
            DOMAIN_STRING="rabbit.$DOMAIN"
            echo "Create SSL for $DOMAIN_STRING"
            cert_paths=$(get_cert_paths "$DOMAIN_STRING" "$EMAIL")
            if [ $? -eq 0 ]; then
                CERT_PATH=$(echo "$cert_paths" | awk '{print $1}')
                KEY_PATH=$(echo "$cert_paths" | awk '{print $2}')
                envsubst < "$TEMPLATE_DIR/ssl_rabbit.conf.tmpl" > "$CONF_DIR/ssl_$DOMAIN_STRING.conf"
                CERT_GENERATED=1
            fi
        fi
        sleep 3
        if [ "$CERT_GENERATED" -eq 1 ]; then
            echo "Setting up cron job for certbot renewal..."
            echo "0 0 * * * certbot renew --quiet --post-hook \"nginx -s reload\"" >> /etc/crontabs/nginx
            echo "Starting crond..."
            crond
            reload_nginx
        fi
    elif [ "$SSL" = "1" ]; then
        echo "Loading self-signed certificates from volume..."
    else
        echo "Using local certificates for $DOMAIN"
    fi
fi