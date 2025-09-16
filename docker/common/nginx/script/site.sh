#!/bin/sh

. /usr/local/bin/script/func/main.sh

DOMAIN_SITE="${1:-$DOMAIN}"
export DOMAIN="$DOMAIN_SITE"

CONF_FILE="$CONF_DIR/$DOMAIN_SITE.conf"
APP_DIR="/home/$UGN/app/$DOMAIN_SITE"

NEED_RELOAD=0

# Создание директории сайта, если её нет
if [ ! -d "$APP_DIR" ]; then
    echo "📁 Создаём директорию: $APP_DIR"
    mkdir -p "$APP_DIR"
else
    echo "✅ Директория уже существует: $APP_DIR"
fi

# Генерация конфига, если он ещё не создан
if [ ! -f "$CONF_FILE" ]; then
    echo "📝 Генерируем конфиг: $CONF_FILE"
    envsubst < "$TEMPLATE_DIR/site.conf.tmpl" > "$CONF_FILE"
    NEED_RELOAD=1
else
    echo "✅ Конфиг уже существует: $CONF_FILE"
fi

# Перезагрузка nginx, только если был создан новый конфиг
if [ "$NEED_RELOAD" -eq 1 ]; then
    echo "🔄 Перезагрузка Nginx..."
    reload_nginx
else
    echo "🚫 Перезагрузка Nginx не требуется"
fi