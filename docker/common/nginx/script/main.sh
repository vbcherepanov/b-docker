#!/bin/sh

. /usr/local/bin/script/func/main.sh
CONF_FILE="$CONF_DIR/$DOMAIN.conf"
APP_DIR="/home/$UGN/app/$DOMAIN"

# Compute canonical host for templates
CANONICAL_HOST="${CANONICAL_HOST:-non-www}"
if [ "$CANONICAL_HOST" = "www" ]; then
    CANONICAL_NAME="www.$DOMAIN"
elif [ "$CANONICAL_HOST" = "non-www" ]; then
    CANONICAL_NAME="$DOMAIN"
else
    CANONICAL_NAME="$DOMAIN"
fi
export CANONICAL_HOST CANONICAL_NAME

envsubst '${DOMAIN} ${UGN}' < "$TEMPLATE_DIR/default_conf.tmpl" > "$CONF_DIR/default.conf"

# Skip generation if per-site config exists in sites-enabled (takes priority)
if [ -f "/etc/nginx/sites-enabled/${DOMAIN}.conf" ]; then
    echo "[main] Per-site config found for $DOMAIN, skipping template generation"
elif [ ! -f "$CONF_FILE" ]; then
    echo "[main] Config not found, creating: $CONF_FILE"
    envsubst < "$TEMPLATE_DIR/site.conf.tmpl" > "$CONF_FILE"
else
    echo "[main] Config already exists: $CONF_FILE"
fi

# Создание директории сайта, если её нет
if [ ! -d "$APP_DIR" ]; then
    echo "📁 Создаём директорию: $APP_DIR"
    mkdir -p "$APP_DIR"
else
    echo "✅ Директория уже существует: $APP_DIR"
fi
if [ "$MAIL_CONFIG" = "1" ]; then
  if [ ! -f "$CONF_DIR/mailhog_$DOMAIN.conf" ]; then
     echo "📄 Файл конфигурации не найден, создаём: $CONF_DIR/mailhog_$DOMAIN.conf"
     envsubst < "$TEMPLATE_DIR/mail.conf.tmpl" > "$CONF_DIR/mailhog_$DOMAIN.conf"
  else
      echo "✅ Файл конфигурации уже существует: $CONF_DIR/mailhog_$DOMAIN.conf"
  fi
fi && \
if [ "$RABBIT_CONFIG" = "1" ]; then \
  if [ ! -f "$CONF_DIR/rabbitmq_$DOMAIN.conf" ]; then
       echo "📄 Файл конфигурации не найден, создаём: $CONF_DIR/rabbitmq_$DOMAIN.conf"
       envsubst < "$TEMPLATE_DIR/rabbit.conf.tmpl" > "$CONF_DIR/rabbitmq_$DOMAIN.conf"
    else
        echo "✅ Файл конфигурации уже существует: $CONF_DIR/rabbitmq_$DOMAIN.conf"
    fi
fi
echo "🔄 Перезагрузка Nginx..."
reload_nginx