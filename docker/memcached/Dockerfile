FROM memcached:alpine

ARG MEMCACHED_CONN_LIMIT=1024
ARG MEMCACHED_MEMORY_LIMIT=64
ARG MEMCACHED_THREADS=4
ARG TZ

ENV TZ=${TZ:-UTC}
ENV MEMCACHED_CONN_LIMIT=${MEMCACHED_CONN_LIMIT}
ENV MEMCACHED_MEMORY_LIMIT=${MEMCACHED_MEMORY_LIMIT}
ENV MEMCACHED_THREADS=${MEMCACHED_THREADS}

# Настройка таймзоны
RUN apk add --no-cache tzdata && \
    ln -snf /usr/share/zoneinfo/${TZ:-UTC} /etc/localtime && \
    echo ${TZ:-UTC} > /etc/timezone

COPY /config/memcached/memcached.conf /etc/memcached.conf
EXPOSE 11211

HEALTHCHECK --interval=30s --timeout=5s --start-period=5s --retries=3 \
  CMD echo stats | nc -w 2 127.0.0.1 11211 | grep -q "STAT pid"

CMD memcached -m ${MEMCACHED_MEMORY_LIMIT} \
              -c ${MEMCACHED_CONN_LIMIT} \
              -p 11211 \
              -l 0.0.0.0 \
              -t ${MEMCACHED_THREADS}