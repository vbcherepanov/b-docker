#!/bin/sh
# =============================================================================
# SSL Certificate Management Script
# Called at nginx container startup
# =============================================================================

. /usr/local/bin/script/func/main.sh

echo "[ssl] ========================================"
echo "[ssl] SSL Setup Starting"
echo "[ssl] Environment: $ENVIRONMENT"
echo "[ssl] SSL Mode: $SSL"
echo "[ssl] Domain: $DOMAIN"
echo "[ssl] ========================================"

# Only process SSL in prod/dev environments
if [ "$ENVIRONMENT" = "prod" ] || [ "$ENVIRONMENT" = "dev" ]; then

    # =========================================================================
    # SSL=free - Let's Encrypt (automatic certificates)
    # =========================================================================
    if [ "$SSL" = "free" ]; then
        echo "[ssl] Mode: Let's Encrypt (free certificates)"
        CERT_GENERATED=0

        # Process main domain
        echo "[ssl] Processing main domain: $DOMAIN"
        cert_paths=$(get_cert_paths "$DOMAIN" "$EMAIL")
        if [ $? -eq 0 ]; then
            CERT_PATH=$(echo "$cert_paths" | tail -1 | awk '{print $1}')
            KEY_PATH=$(echo "$cert_paths" | tail -1 | awk '{print $2}')
            export CERT_PATH KEY_PATH
            envsubst < "$TEMPLATE_DIR/ssl_site.conf.tmpl" > "$CONF_DIR/ssl_$DOMAIN.conf"
            CERT_GENERATED=1
            echo "[ssl] Created nginx config: ssl_$DOMAIN.conf"
        fi

        sleep 2

        # Process mail subdomain if enabled
        if [ "$MAIL_CONFIG" = "1" ]; then
            SUBDOMAIN="${MAIL_SUBDOMAIN:-mail}"
            DOMAIN_STRING="$SUBDOMAIN.$DOMAIN"
            echo "[ssl] Processing subdomain: $DOMAIN_STRING"
            cert_paths=$(get_cert_paths "$DOMAIN_STRING" "$EMAIL")
            if [ $? -eq 0 ]; then
                CERT_PATH=$(echo "$cert_paths" | tail -1 | awk '{print $1}')
                KEY_PATH=$(echo "$cert_paths" | tail -1 | awk '{print $2}')
                export CERT_PATH KEY_PATH MAIL_SUBDOMAIN="$SUBDOMAIN"
                envsubst < "$TEMPLATE_DIR/ssl_mail.conf.tmpl" > "$CONF_DIR/ssl_$DOMAIN_STRING.conf"
                CERT_GENERATED=1
                echo "[ssl] Created nginx config: ssl_$DOMAIN_STRING.conf"
            fi
            sleep 2
        fi

        # Process rabbit subdomain if enabled
        if [ "$RABBIT_CONFIG" = "1" ]; then
            SUBDOMAIN="${RABBIT_SUBDOMAIN:-rabbit}"
            DOMAIN_STRING="$SUBDOMAIN.$DOMAIN"
            echo "[ssl] Processing subdomain: $DOMAIN_STRING"
            cert_paths=$(get_cert_paths "$DOMAIN_STRING" "$EMAIL")
            if [ $? -eq 0 ]; then
                CERT_PATH=$(echo "$cert_paths" | tail -1 | awk '{print $1}')
                KEY_PATH=$(echo "$cert_paths" | tail -1 | awk '{print $2}')
                export CERT_PATH KEY_PATH RABBIT_SUBDOMAIN="$SUBDOMAIN"
                envsubst < "$TEMPLATE_DIR/ssl_rabbit.conf.tmpl" > "$CONF_DIR/ssl_$DOMAIN_STRING.conf"
                CERT_GENERATED=1
                echo "[ssl] Created nginx config: ssl_$DOMAIN_STRING.conf"
            fi
            sleep 2
        fi

        # Process grafana subdomain if enabled
        if [ "$GRAFANA_CONFIG" = "1" ]; then
            SUBDOMAIN="${GRAFANA_SUBDOMAIN:-grafana}"
            DOMAIN_STRING="$SUBDOMAIN.$DOMAIN"
            echo "[ssl] Processing subdomain: $DOMAIN_STRING"
            cert_paths=$(get_cert_paths "$DOMAIN_STRING" "$EMAIL")
            if [ $? -eq 0 ]; then
                CERT_PATH=$(echo "$cert_paths" | tail -1 | awk '{print $1}')
                KEY_PATH=$(echo "$cert_paths" | tail -1 | awk '{print $2}')
                export CERT_PATH KEY_PATH GRAFANA_SUBDOMAIN="$SUBDOMAIN"
                envsubst < "$TEMPLATE_DIR/ssl_grafana.conf.tmpl" > "$CONF_DIR/ssl_$DOMAIN_STRING.conf"
                CERT_GENERATED=1
                echo "[ssl] Created nginx config: ssl_$DOMAIN_STRING.conf"
            fi
            sleep 2
        fi

        # Process prometheus subdomain if enabled
        if [ "$PROMETHEUS_CONFIG" = "1" ]; then
            SUBDOMAIN="${PROMETHEUS_SUBDOMAIN:-prometheus}"
            DOMAIN_STRING="$SUBDOMAIN.$DOMAIN"
            echo "[ssl] Processing subdomain: $DOMAIN_STRING"
            cert_paths=$(get_cert_paths "$DOMAIN_STRING" "$EMAIL")
            if [ $? -eq 0 ]; then
                CERT_PATH=$(echo "$cert_paths" | tail -1 | awk '{print $1}')
                KEY_PATH=$(echo "$cert_paths" | tail -1 | awk '{print $2}')
                export CERT_PATH KEY_PATH PROMETHEUS_SUBDOMAIN="$SUBDOMAIN"
                envsubst < "$TEMPLATE_DIR/ssl_prometheus.conf.tmpl" > "$CONF_DIR/ssl_$DOMAIN_STRING.conf"
                CERT_GENERATED=1
                echo "[ssl] Created nginx config: ssl_$DOMAIN_STRING.conf"
            fi
            sleep 2
        fi

        # Setup cron for automatic renewal if any certificate was created
        if [ "$CERT_GENERATED" -eq 1 ]; then
            echo "[ssl] Setting up daily certificate check (cron)..."

            # Create renewal script
            cat > /usr/local/bin/ssl-renew.sh << 'EOFSCRIPT'
#!/bin/sh
. /usr/local/bin/script/func/main.sh
check_and_renew_all >> /var/log/letsencrypt/renewal.log 2>&1
EOFSCRIPT
            chmod +x /usr/local/bin/ssl-renew.sh

            # Add cron job - check daily at 3:00 AM
            echo "0 3 * * * /usr/local/bin/ssl-renew.sh" >> /etc/crontabs/root

            # Ensure log directory exists
            mkdir -p /var/log/letsencrypt

            echo "[ssl] Starting crond..."
            crond

            echo "[ssl] Reloading nginx with new SSL configs..."
            reload_nginx
        fi

    # =========================================================================
    # SSL=self - Self-signed or custom certificates from volume
    # =========================================================================
    elif [ "$SSL" = "self" ]; then
        echo "[ssl] Mode: Self-signed/custom certificates"
        echo "[ssl] Looking for certificates in: $SSL_PATH/$DOMAIN/"

        if [ -f "$SSL_PATH/$DOMAIN/$SSL_KEY" ] && [ -f "$SSL_PATH/$DOMAIN/$SSL_PRIV_KEY" ]; then
            CERT_PATH="$SSL_PATH/$DOMAIN/$SSL_KEY"
            KEY_PATH="$SSL_PATH/$DOMAIN/$SSL_PRIV_KEY"
            export CERT_PATH KEY_PATH
            envsubst < "$TEMPLATE_DIR/ssl_site.conf.tmpl" > "$CONF_DIR/ssl_$DOMAIN.conf"
            echo "[ssl] Loaded custom certificates for $DOMAIN"
            reload_nginx
        else
            echo "[ssl] WARNING: Certificate files not found!"
            echo "[ssl] Expected: $SSL_PATH/$DOMAIN/$SSL_KEY"
            echo "[ssl] Expected: $SSL_PATH/$DOMAIN/$SSL_PRIV_KEY"
        fi

    # =========================================================================
    # SSL=0 or other - No SSL
    # =========================================================================
    else
        echo "[ssl] Mode: No SSL (HTTP only)"
        echo "[ssl] To enable SSL, set SSL=free or SSL=self in .env"
    fi

else
    echo "[ssl] Skipping SSL setup (ENVIRONMENT=$ENVIRONMENT)"
fi

echo "[ssl] ========================================"
echo "[ssl] SSL Setup Complete"
echo "[ssl] ========================================"
