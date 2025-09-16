FROM nginx:stable-alpine3.17-slim

# --- ARG и ENV переменные ---
ARG ENVIRONMENT=prod
ARG SSL=self
ARG DOMAIN
ARG EMAIL
ARG TZ
ARG UID
ARG GID
ARG UGN
ARG MAIL_CONFIG=1
ARG RABBIT_CONFIG=1
ARG DOLLAR

ENV DOLLAR=${DOLLAR}
ENV TZ=${TZ:-UTC}
ENV ENVIRONMENT=${ENVIRONMENT}
ENV SSL=${SSL}
ENV DOMAIN=${DOMAIN}
ENV EMAIL=${EMAIL}
ENV MAIL_CONFIG=${MAIL_CONFIG}
ENV RABBIT_CONFIG=${RABBIT_CONFIG}
ENV UGN=${UGN}
ENV UID=${UID}
ENV GID=${GID}

# --- Установка envsubst ---
RUN apk add --no-cache gettext bash curl openssl nss tzdata

# --- Настройка таймзоны ---
RUN ln -snf /usr/share/zoneinfo/${TZ:-UTC} /etc/localtime && echo ${TZ:-UTC} > /etc/timezone

# --- Создание пользователя ---
RUN addgroup -g $GID $UGN || true && \
    adduser -D -u $UID -G $UGN $UGN || true

# Создание директорий с правами
RUN mkdir -p /home/$UGN/app /home/$UGN/tmp /var/cache/nginx /var/run/nginx /var/template /var/cache/nginx/client_temp && \
    chown -R $UID:$GID /home/$UGN /var/cache/nginx /var/run/nginx /var/template /var/cache/nginx && \
    chmod -R 755 /home/$UGN /var/cache/nginx && \
    chmod -R 700 /var/cache/nginx
# --- Копирование конфигов и скриптов ---
COPY --chown=$UID:$GID /docker/common/nginx/templates /var/template
COPY --chown=$UID:$GID /config/nginx/ssl /etc/letsencrypt/live
COPY --chown=$UID:$GID /docker/common/nginx/snippets /etc/nginx/snippets
COPY --chown=$UID:$GID /docker/common/nginx/nginx-unprivileged.conf /etc/nginx/nginx.conf
COPY --chown=$UID:$GID /docker/common/nginx/script/ /usr/local/bin/script/

RUN envsubst '${DOMAIN} ${UGN}' < /var/template/default_conf.tmpl > /etc/nginx/conf.d/default.conf
RUN envsubst < /var/template/site.conf.tmpl > /etc/nginx/conf.d/$DOMAIN.conf
# Копирование конфигов для Mailhog и RabbitMQ, если включены
RUN if [ "$MAIL_CONFIG" = "1" ]; then \
        envsubst < /var/template/mail.conf.tmpl > /etc/nginx/conf.d/mailhog_$DOMAIN.conf; \
    fi && \
    if [ "$RABBIT_CONFIG" = "1" ]; then \
        envsubst < /var/template/rabbit.conf.tmpl > /etc/nginx/conf.d/rabbitmq_$DOMAIN.conf; \
    fi

# --- Разрешения на скрипты ---
RUN chmod +x /usr/local/bin/script/*

# --- Установка нужных пакетов ---
RUN \
    if [ "$ENVIRONMENT" = "prod" ] || [ "$ENVIRONMENT" = "dev" ]; then \
        if [ "$SSL" = "free" ]; then \
            apk add --no-cache certbot certbot-nginx cronie && \
            mkdir -p /var/run/crond && \
            touch /var/run/crond/crond.pid && \
            chmod 755 /var/run/crond; \
        fi; \
    fi

# --- Создание директорий для nginx под непривилегированным пользователем ---
RUN mkdir -p /var/cache/nginx/client_temp \
             /var/cache/nginx/proxy_temp \
             /var/cache/nginx/fastcgi_temp \
             /var/cache/nginx/uwsgi_temp \
             /var/cache/nginx/scgi_temp \
             /var/log/nginx \
             /var/run/nginx && \
    chown -R $UID:$GID /var/cache/nginx /var/log/nginx /var/run/nginx && \
    chmod -R 755 /var/cache/nginx /var/log/nginx /var/run/nginx

# --- Обновление конфига nginx для работы под непривилегированным пользователем ---
RUN sed -i '/^user/d' /etc/nginx/nginx.conf && \
    sed -i 's/listen 80;/listen 8080;/' /etc/nginx/conf.d/default.conf && \
    sed -i 's/listen 443;/listen 8443;/' /etc/nginx/conf.d/default.conf && \
    sed -i 's/\/var\/run\/nginx.pid/\/var\/run\/nginx\/nginx.pid/' /etc/nginx/nginx.conf

# --- Открытые порты (изменены для непривилегированного пользователя) ---
EXPOSE 8080 8443

# --- Рабочая директория и пользователь ---
RUN chown -R $UID:$GID /home/$UGN
WORKDIR /home/$UGN/app
USER $UGN

# --- Healthcheck ---
HEALTHCHECK --interval=300s --timeout=5s --retries=3 \
    CMD curl -f http://localhost:8080/health || exit 1

# --- Старт nginx ---
CMD ["nginx", "-g", "daemon off;"]