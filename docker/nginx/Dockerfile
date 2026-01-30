# =============================================================================
# NGINX - Web Server for Bitrix
# Supports: local, dev, production environments
# SSL modes: 0 (none), self (custom certs), free (Let's Encrypt)
# Features: Brotli compression (Bitrix official)
# =============================================================================
# Use nginx:mainline-alpine for brotli module support
FROM nginx:1.27-alpine

# --- Build Arguments ---
ARG ENVIRONMENT=local
ARG SSL=0
ARG DOMAIN=localhost
ARG EMAIL=admin@localhost
ARG TZ=UTC
ARG UID=1000
ARG GID=1000
ARG UGN=bitrix
ARG MAIL_CONFIG=0
ARG RABBIT_CONFIG=0
ARG GRAFANA_CONFIG=0
ARG PROMETHEUS_CONFIG=0
ARG MAIL_SUBDOMAIN=mail
ARG RABBIT_SUBDOMAIN=rabbit
ARG GRAFANA_SUBDOMAIN=grafana
ARG PROMETHEUS_SUBDOMAIN=prometheus

# --- Environment Variables ---
ENV TZ=${TZ}
ENV ENVIRONMENT=${ENVIRONMENT}
ENV SSL=${SSL}
ENV DOMAIN=${DOMAIN}
ENV EMAIL=${EMAIL}
ENV MAIL_CONFIG=${MAIL_CONFIG}
ENV RABBIT_CONFIG=${RABBIT_CONFIG}
ENV GRAFANA_CONFIG=${GRAFANA_CONFIG}
ENV PROMETHEUS_CONFIG=${PROMETHEUS_CONFIG}
ENV MAIL_SUBDOMAIN=${MAIL_SUBDOMAIN}
ENV RABBIT_SUBDOMAIN=${RABBIT_SUBDOMAIN}
ENV GRAFANA_SUBDOMAIN=${GRAFANA_SUBDOMAIN}
ENV PROMETHEUS_SUBDOMAIN=${PROMETHEUS_SUBDOMAIN}
ENV UGN=${UGN}
ENV UID=${UID}
ENV GID=${GID}
ENV DOLLAR='$'

# --- Install dependencies and Brotli module ---
# nginx-mod-http-brotli provides brotli compression (Bitrix official feature)
RUN apk add --no-cache \
    gettext \
    bash \
    curl \
    openssl \
    nss \
    tzdata \
    nginx-mod-http-brotli

# --- Timezone ---
RUN ln -snf /usr/share/zoneinfo/${TZ} /etc/localtime && echo ${TZ} > /etc/timezone

# --- Create user ---
RUN addgroup -g ${GID} ${UGN} 2>/dev/null || true && \
    adduser -D -u ${UID} -G ${UGN} ${UGN} 2>/dev/null || true

# --- Create directories ---
RUN mkdir -p \
    /home/${UGN}/app \
    /home/${UGN}/tmp \
    /var/cache/nginx/client_temp \
    /var/cache/nginx/proxy_temp \
    /var/cache/nginx/fastcgi_temp \
    /var/cache/nginx/uwsgi_temp \
    /var/cache/nginx/scgi_temp \
    /var/log/nginx \
    /var/run/nginx \
    /var/template \
    /etc/letsencrypt/live && \
    chown -R ${UID}:${GID} /home/${UGN} /var/cache/nginx /var/log/nginx /var/run/nginx /var/template && \
    chmod -R 755 /home/${UGN} /var/cache/nginx /var/log/nginx /var/run/nginx

# --- Copy templates and configs ---
COPY --chown=${UID}:${GID} docker/common/nginx/templates /var/template
COPY --chown=${UID}:${GID} docker/common/nginx/snippets /etc/nginx/snippets
COPY --chown=${UID}:${GID} docker/common/nginx/nginx.conf /etc/nginx/nginx.conf
COPY --chown=${UID}:${GID} docker/common/nginx/script/ /usr/local/bin/script/
COPY --chown=${UID}:${GID} docker/nginx/docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh

# --- Copy self-signed SSL certs if exists ---
COPY --chown=${UID}:${GID} config/nginx/ssl /etc/letsencrypt/live

# --- Generate nginx configs based on environment ---
RUN envsubst '${DOMAIN} ${UGN} ${DOLLAR}' < /var/template/default_conf.tmpl > /etc/nginx/conf.d/default.conf && \
    envsubst '${DOMAIN} ${UGN} ${DOLLAR}' < /var/template/site.conf.tmpl > /etc/nginx/conf.d/${DOMAIN}.conf

# --- Generate optional service configs ---
RUN if [ "${MAIL_CONFIG}" = "1" ]; then \
        envsubst '${DOMAIN} ${MAIL_SUBDOMAIN} ${DOLLAR}' < /var/template/mail.conf.tmpl > /etc/nginx/conf.d/${MAIL_SUBDOMAIN}.${DOMAIN}.conf; \
    fi && \
    if [ "${RABBIT_CONFIG}" = "1" ]; then \
        envsubst '${DOMAIN} ${RABBIT_SUBDOMAIN} ${DOLLAR}' < /var/template/rabbit.conf.tmpl > /etc/nginx/conf.d/${RABBIT_SUBDOMAIN}.${DOMAIN}.conf; \
    fi && \
    if [ "${GRAFANA_CONFIG}" = "1" ]; then \
        envsubst '${DOMAIN} ${GRAFANA_SUBDOMAIN} ${DOLLAR}' < /var/template/grafana.conf.tmpl > /etc/nginx/conf.d/${GRAFANA_SUBDOMAIN}.${DOMAIN}.conf; \
    fi && \
    if [ "${PROMETHEUS_CONFIG}" = "1" ]; then \
        envsubst '${DOMAIN} ${PROMETHEUS_SUBDOMAIN} ${DOLLAR}' < /var/template/prometheus.conf.tmpl > /etc/nginx/conf.d/${PROMETHEUS_SUBDOMAIN}.${DOMAIN}.conf; \
    fi

# --- Install certbot for Let's Encrypt (prod/dev with SSL=free only) ---
RUN if [ "${SSL}" = "free" ]; then \
        apk add --no-cache certbot certbot-nginx && \
        mkdir -p /var/run/crond && \
        touch /var/run/crond/crond.pid && \
        chmod 755 /var/run/crond; \
    fi

# --- Make scripts executable ---
RUN chmod +x /usr/local/bin/script/* /usr/local/bin/docker-entrypoint.sh

# --- Ports ---
EXPOSE 80 443

# --- Working directory ---
WORKDIR /home/${UGN}/app

# --- Healthcheck ---
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD curl -sf http://localhost:80/health || exit 1

# --- Entrypoint ---
ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
CMD ["nginx", "-g", "daemon off;"]
