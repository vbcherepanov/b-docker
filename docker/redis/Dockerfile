FROM redis:alpine

ARG TZ
ENV TZ=${TZ:-UTC}

# Установка зависимостей и настройка таймзоны
RUN apk add --no-cache bash tzdata && \
    ln -snf /usr/share/zoneinfo/${TZ:-UTC} /etc/localtime && \
    echo ${TZ:-UTC} > /etc/timezone

COPY /docker/common/redis/init.sh /usr/init.sh
COPY /config/redis/redis.conf /usr/local/etc/redis/redis.conf
RUN chmod 755 /usr/init.sh

HEALTHCHECK --interval=30s --timeout=5s --retries=3 \
  CMD sh -c "redis-cli ping | grep -q PONG"

CMD ["/usr/init.sh"]