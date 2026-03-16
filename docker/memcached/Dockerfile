FROM memcached:alpine

# Production-proven defaults matching BITRIX-DOCKER reference
ARG MEMCACHED_CONN_LIMIT=1024
ARG MEMCACHED_MEMORY_LIMIT=1024
ARG MEMCACHED_THREADS=8
ARG MEMCACHED_MAX_ITEM_SIZE=2m
ARG TZ

ENV TZ=${TZ:-UTC}
ENV MEMCACHED_CONN_LIMIT=${MEMCACHED_CONN_LIMIT}
ENV MEMCACHED_MEMORY_LIMIT=${MEMCACHED_MEMORY_LIMIT}
ENV MEMCACHED_THREADS=${MEMCACHED_THREADS}
ENV MEMCACHED_MAX_ITEM_SIZE=${MEMCACHED_MAX_ITEM_SIZE}

USER root

# Install timezone and healthcheck utilities
RUN apk add --no-cache tzdata netcat-openbsd && \
    ln -snf /usr/share/zoneinfo/${TZ:-UTC} /etc/localtime && \
    echo ${TZ:-UTC} > /etc/timezone

COPY /config/memcached/memcached.conf /etc/memcached.conf
EXPOSE 11211

HEALTHCHECK --interval=30s --timeout=5s --start-period=5s --retries=3 \
  CMD echo stats | nc -w 2 127.0.0.1 11211 | grep -q "STAT pid"

CMD memcached -u root \
              -m ${MEMCACHED_MEMORY_LIMIT} \
              -c ${MEMCACHED_CONN_LIMIT} \
              -p 11211 \
              -l 0.0.0.0 \
              -t ${MEMCACHED_THREADS} \
              -I ${MEMCACHED_MAX_ITEM_SIZE} \
              -o modern