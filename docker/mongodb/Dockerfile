FROM mongo:4.4-focal

ARG TZ
ENV TZ=${TZ:-UTC}

# Настройка таймзоны
RUN ln -snf /usr/share/zoneinfo/${TZ:-UTC} /etc/localtime && \
    echo ${TZ:-UTC} > /etc/timezone

# Создание логов и установка прав
RUN mkdir -p /var/log/mongodb && \
    touch /var/log/mongodb/mongod.log && \
    chown -R mongodb:mongodb /var/log/mongodb && \
    chmod -R 755 /var/log/mongodb


COPY /config/mongodb/mongod.conf /etc/mongod.conf
# Healthcheck с использованием встроенного клиента
HEALTHCHECK --interval=30s --timeout=10s --retries=3 \
    CMD mongo --eval "db.adminCommand('ping')" || exit 1

# Используем оригинальный entrypoint
# Переопределяем только CMD
CMD ["mongod", "--config", "/etc/mongod.conf"]