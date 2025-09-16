#!/bin/sh
TEMPLATE_DIR="/var/template"
CONF_DIR="/etc/nginx/conf.d"
SSL_PATH="/etc/letsencrypt/live"
SSL_KEY="fullchain.pem"
SSL_PRIV_KEY="privkey.pem"

export DOLLAR='S';
reload_nginx() {
    echo "Reloading Nginx..."
    if nginx -t; then
        echo "Nginx configuration is valid. Reloading Nginx..."
        nginx -s reload
    else
        echo "Nginx configuration is invalid. Exiting."
        exit 1
    fi
}
start_nginx() {
  echo "Starting Nginx..."
  echo "Checking Nginx configuration..."
  if nginx -t; then
    echo "Nginx configuration is valid. Starting Nginx..."
    nginx -g 'daemon off;'
    echo "nginx started"
  else
    echo "Nginx configuration is invalid. Exiting."
    exit 1
  fi
}
get_cert_paths() {
    local domain="$1"
    local email="$2"
    # Выполнение команды certbot
    output=$(certbot certonly --nginx --non-interactive --agree-tos --email "$email" -d "$domain" 2>&1)
    echo "$output"
    # Извлечение путей к сертификату и ключу
    cert_path=$(echo "$output" | grep "Certificate is saved at:" | cut -d ' ' -f 7)
    key_path=$(echo "$output" | grep "Key is saved at:" | cut -d ' ' -f 7)
    # Проверка на успешное выполнение
    if echo "$output" | grep -q "Successfully received certificate"; then
        echo "Certificate path: $cert_path"
        echo "Key path: $key_path"
        echo "$cert_path" "$key_path"  # Возвращаем пути в качестве результата
    else
        echo "Error generating certificate!"
        echo "$output"  # Выводим сообщение об ошибке
        return 1  # Возвращаем ошибку
    fi
}