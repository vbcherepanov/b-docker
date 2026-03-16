FROM redis:alpine

ARG TZ
ENV TZ=${TZ:-UTC}

# Install dependencies and configure timezone
RUN apk add --no-cache bash tzdata && \
    ln -snf /usr/share/zoneinfo/${TZ:-UTC} /etc/localtime && \
    echo ${TZ:-UTC} > /etc/timezone

# Create socket directory with proper permissions
# This dir is shared with PHP container via named volume
RUN mkdir -p /var/run/redis && \
    chown redis:redis /var/run/redis && \
    chmod 755 /var/run/redis

COPY /docker/common/redis/init.sh /usr/init.sh
COPY /config/redis/redis.conf /usr/local/etc/redis/redis.conf
RUN chmod 755 /usr/init.sh

HEALTHCHECK --interval=30s --timeout=5s --retries=3 \
  CMD sh -c "redis-cli ping | grep -q PONG"

CMD ["/usr/init.sh"]
