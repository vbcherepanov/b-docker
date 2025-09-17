# --- Stage 1: Builder for templating SQL ---
FROM alpine:3.18 AS builder

ARG DB_USERNAME
ARG DB_PASSWORD
ARG DB_NAME
ARG DOMAIN
ARG TZ

ENV TZ=${TZ:-UTC}
ENV DB_USERNAME=${DB_USERNAME}
ENV DB_PASSWORD=${DB_PASSWORD}
ENV DB_NAME=${DB_NAME}
ENV DOMAIN=${DOMAIN}

RUN apk add --no-cache gettext pv

COPY /docker/common/mysql/templates/init.sql.tmpl /init.sql.tmpl

RUN envsubst < /init.sql.tmpl > /init.sql

# --- Stage 2: Final MySQL Container ---
FROM mysql:8.4.2

ARG DB_USERNAME
ARG DB_PASSWORD
ARG DB_NAME
ARG DOMAIN
ARG TZ

ENV TZ=${TZ:-UTC}
ENV DB_USERNAME=${DB_USERNAME}
ENV DB_PASSWORD=${DB_PASSWORD}
ENV DB_NAME=${DB_NAME}
ENV DOMAIN=${DOMAIN}

USER root

RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone
# Установка утилит для Oracle Linux
RUN microdnf update -y && \
    microdnf install -y expect && \
    microdnf clean all

COPY --from=builder /usr/bin/pv /usr/local/bin/pv
COPY --from=builder /lib/ld-musl-*.so* /lib/
COPY --from=builder /lib/libc.musl-*.so* /lib/
# Копирование скриптов
COPY /docker/common/mysql/script/ /script/
RUN chmod +x /script/*

# Копирование сгенерированного init.sql
COPY --from=builder /init.sql /docker-entrypoint-initdb.d/init.sql
COPY /config/mysql/init /docker-entrypoint-initdb.d/
COPY /config/mysql/my.conf /etc/mysql/conf.d/bitrix.cnf

EXPOSE 3306

HEALTHCHECK --interval=30s --timeout=20s --retries=10 \
  CMD mysqladmin ping -h 127.0.0.1 --silent || exit 1