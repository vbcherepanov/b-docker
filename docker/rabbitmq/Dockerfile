FROM rabbitmq:4.1-management-alpine

ARG TZ
ENV TZ=${TZ:-UTC}

# Настройка таймзоны
RUN apk add --no-cache tzdata && \
    ln -snf /usr/share/zoneinfo/${TZ:-UTC} /etc/localtime && \
    echo ${TZ:-UTC} > /etc/timezone

# Установка нужных директорий с правами
RUN mkdir -p /var/log/rabbitmq && \
    chown -R rabbitmq:rabbitmq /var/log/rabbitmq

# Открытие портов для RabbitMQ
EXPOSE 5672 15672

# Устанавливаем healthcheck
HEALTHCHECK --interval=300s --timeout=5s --retries=3 \
  CMD rabbitmq-diagnostics -q check_running || exit 1