# Custom Fail2ban Actions

Эта директория предназначена для пользовательских actions fail2ban.

## Доступные примеры

### 1. Telegram уведомления (`telegram-notify.conf.example`)

Отправляет уведомления в Telegram при бане/разбане IP.

**Настройка:**
```bash
# 1. Переименуйте файл
mv telegram-notify.conf.example telegram-notify.conf

# 2. Замените плейсхолдеры в файле:
#    <TELEGRAM_BOT_TOKEN> - токен бота от @BotFather
#    <TELEGRAM_CHAT_ID> - ID чата (узнать через @userinfobot)

# 3. Добавьте в jail.local:
action = %(action_mw)s
         telegram-notify[name=%(__name__)s]

# 4. Перезапустите fail2ban
docker restart bitrix.local_fail2ban
```

### 2. Slack уведомления (`slack-notify.conf.example`)

Отправляет уведомления в Slack канал.

**Настройка:**
```bash
# 1. Переименуйте файл
mv slack-notify.conf.example slack-notify.conf

# 2. Создайте Incoming Webhook в Slack
# 3. Замените <SLACK_WEBHOOK_URL> на ваш webhook URL

# 4. Добавьте в jail.local:
action = %(action_mw)s
         slack-notify[name=%(__name__)s]

# 5. Перезапустите fail2ban
docker restart bitrix.local_fail2ban
```

## Создание своих actions

Создайте файл `custom-action.conf`:

```ini
[Definition]

# Команда при бане
actionban = echo "Banned <ip> for <name>" >> /var/log/fail2ban/custom.log

# Команда при разбане
actionunban = echo "Unbanned <ip> from <name>" >> /var/log/fail2ban/custom.log

# Команда при старте fail2ban (опционально)
actionstart = echo "Fail2ban started for <name>" >> /var/log/fail2ban/custom.log

# Команда при остановке (опционально)
actionstop = echo "Fail2ban stopped for <name>" >> /var/log/fail2ban/custom.log

# Параметры
[Init]
name = default
```

### Доступные переменные

- `<ip>` - IP адрес нарушителя
- `<name>` - имя jail (nginx-403, nginx-sqli и т.д.)
- `<bantime>` - время бана в секундах
- `<failures>` - количество неудачных попыток
- `<time>` - время события

## Использование в jail.local

Одиночный action:
```ini
[nginx-sqli]
action = telegram-notify[name=%(__name__)s]
```

Несколько actions:
```ini
[nginx-sqli]
action = %(action_mw)s
         telegram-notify[name=%(__name__)s]
         slack-notify[name=%(__name__)s]
```

## Тестирование

Проверить action вручную:
```bash
# Войти в контейнер
docker exec -it bitrix.local_fail2ban sh

# Протестировать ban
fail2ban-client set nginx-sqli banip 1.2.3.4

# Проверить логи
tail -f /var/log/fail2ban/fail2ban.log
```

## Полезные ссылки

- [Fail2ban Actions Documentation](https://fail2ban.readthedocs.io/en/latest/config.html#actions)
- [Action Templates](https://github.com/fail2ban/fail2ban/tree/master/config/action.d)
