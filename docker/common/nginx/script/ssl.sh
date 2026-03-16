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

        # Skip template generation if per-site config exists in sites-enabled
        if [ -f "/etc/nginx/sites-enabled/${DOMAIN}.conf" ]; then
            echo "[ssl] Per-site config found for $DOMAIN, skipping template generation"
        else
            cert_paths=$(get_cert_paths "$DOMAIN" "$EMAIL")
            if [ $? -eq 0 ]; then
                CERT_PATH=$(echo "$cert_paths" | tail -1 | awk '{print $1}')
                KEY_PATH=$(echo "$cert_paths" | tail -1 | awk '{print $2}')

                # Compute canonical host settings for template
                CANONICAL_HOST="${CANONICAL_HOST:-non-www}"
                if [ "$CANONICAL_HOST" = "www" ]; then
                    CANONICAL_NAME="www.$DOMAIN"
                    REDIRECT_NAME="$DOMAIN"
                elif [ "$CANONICAL_HOST" = "non-www" ]; then
                    CANONICAL_NAME="$DOMAIN"
                    REDIRECT_NAME="www.$DOMAIN"
                else
                    # "both" - no redirect
                    CANONICAL_NAME="$DOMAIN www.$DOMAIN"
                    REDIRECT_NAME=""
                fi

                export CERT_PATH KEY_PATH CANONICAL_HOST CANONICAL_NAME REDIRECT_NAME
                envsubst < "$TEMPLATE_DIR/ssl_site.conf.tmpl" > "$CONF_DIR/ssl_$DOMAIN.conf"

                # Append redirect server block if needed
                if [ -n "$REDIRECT_NAME" ]; then
                    cat >> "$CONF_DIR/ssl_$DOMAIN.conf" << REDIRECT_EOF
# Redirect non-canonical HTTPS to canonical
server {
    listen 443 ssl http2;
    server_name ${REDIRECT_NAME};

    ssl_certificate ${CERT_PATH};
    ssl_certificate_key ${KEY_PATH};

    return 301 https://${CANONICAL_NAME}\$request_uri;
}
REDIRECT_EOF
                fi

                # Remove placeholder from template output
                sed -i 's/# REDIRECT_BLOCK_PLACEHOLDER//' "$CONF_DIR/ssl_$DOMAIN.conf"

                # Remove HTTP-only config (replaced by SSL config with HTTP redirect)
                if [ -f "$CONF_DIR/$DOMAIN.conf" ]; then
                    echo "[ssl] Removing HTTP-only config: $DOMAIN.conf (replaced by SSL config)"
                    rm -f "$CONF_DIR/$DOMAIN.conf"
                fi

                CERT_GENERATED=1
                echo "[ssl] Created nginx config: ssl_$DOMAIN.conf (canonical: $CANONICAL_NAME)"
            fi
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

        # Always setup cron for automatic renewal when SSL=free
        # Cron must run regardless of CERT_GENERATED — certificates may already
        # exist on the volume from a previous run and still need renewal checks
        echo "[ssl] Setting up daily certificate check (cron)..."

        # Create renewal script
        cat > /usr/local/bin/ssl-renew.sh << 'EOFSCRIPT'
#!/bin/sh
. /usr/local/bin/script/func/main.sh
check_and_renew_all >> /var/log/letsencrypt/renewal.log 2>&1
EOFSCRIPT
        chmod +x /usr/local/bin/ssl-renew.sh

        # Add cron job - check daily at 3:00 AM (avoid duplicates on restart)
        grep -q 'ssl-renew.sh' /etc/crontabs/root 2>/dev/null || \
            echo "0 3 * * * /usr/local/bin/ssl-renew.sh" >> /etc/crontabs/root

        # Ensure log directory exists
        mkdir -p /var/log/letsencrypt

        echo "[ssl] Starting crond for certificate renewal..."
        crond

        # Reload nginx if any new configs were generated
        if [ "$CERT_GENERATED" -eq 1 ]; then
            echo "[ssl] Reloading nginx with new SSL configs..."
            reload_nginx
        fi

    # =========================================================================
    # SSL=self - Self-signed or custom certificates from volume
    # =========================================================================
    elif [ "$SSL" = "self" ]; then
        echo "[ssl] Mode: Self-signed/custom certificates"
        echo "[ssl] Looking for certificates in: $SSL_PATH/$DOMAIN/"

        # Skip template generation if per-site config exists in sites-enabled
        if [ -f "/etc/nginx/sites-enabled/${DOMAIN}.conf" ]; then
            echo "[ssl] Per-site config found for $DOMAIN, skipping template generation"
        elif [ -f "$SSL_PATH/$DOMAIN/$SSL_KEY" ] && [ -f "$SSL_PATH/$DOMAIN/$SSL_PRIV_KEY" ]; then
            CERT_PATH="$SSL_PATH/$DOMAIN/$SSL_KEY"
            KEY_PATH="$SSL_PATH/$DOMAIN/$SSL_PRIV_KEY"

            # Compute canonical host settings for template
            CANONICAL_HOST="${CANONICAL_HOST:-non-www}"
            if [ "$CANONICAL_HOST" = "www" ]; then
                CANONICAL_NAME="www.$DOMAIN"
                REDIRECT_NAME="$DOMAIN"
            elif [ "$CANONICAL_HOST" = "non-www" ]; then
                CANONICAL_NAME="$DOMAIN"
                REDIRECT_NAME="www.$DOMAIN"
            else
                CANONICAL_NAME="$DOMAIN www.$DOMAIN"
                REDIRECT_NAME=""
            fi

            export CERT_PATH KEY_PATH CANONICAL_HOST CANONICAL_NAME REDIRECT_NAME
            envsubst < "$TEMPLATE_DIR/ssl_site.conf.tmpl" > "$CONF_DIR/ssl_$DOMAIN.conf"

            # Append redirect server block if needed
            if [ -n "$REDIRECT_NAME" ]; then
                cat >> "$CONF_DIR/ssl_$DOMAIN.conf" << REDIRECT_EOF
# Redirect non-canonical HTTPS to canonical
server {
    listen 443 ssl http2;
    server_name ${REDIRECT_NAME};

    ssl_certificate ${CERT_PATH};
    ssl_certificate_key ${KEY_PATH};

    return 301 https://${CANONICAL_NAME}\$request_uri;
}
REDIRECT_EOF
            fi

            # Remove placeholder from template output
            sed -i 's/# REDIRECT_BLOCK_PLACEHOLDER//' "$CONF_DIR/ssl_$DOMAIN.conf"

            # Remove HTTP-only config (replaced by SSL config with HTTP redirect)
            if [ -f "$CONF_DIR/$DOMAIN.conf" ]; then
                echo "[ssl] Removing HTTP-only config: $DOMAIN.conf (replaced by SSL config)"
                rm -f "$CONF_DIR/$DOMAIN.conf"
            fi

            echo "[ssl] Loaded custom certificates for $DOMAIN (canonical: $CANONICAL_NAME)"
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
