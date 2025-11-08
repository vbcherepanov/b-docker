# MSMTP Configuration

Конфигурация отправки почты через SMTP для разных окружений.

## Структура

- `msmtprc` - основной конфигурационный файл (монтируется в `/etc/msmtp/msmtprc`)
- `msmtprc.example` - пример конфигурации

## Окружения

### Local (ENV=local)
Используется **MailHog** для перехвата почты.
- PHP использует: `/usr/bin/mhsendmail` (mailhog.ini)
- Web UI: http://localhost:8025
- SMTP: mailhog:1025
- Конфигурация: автоматическая через `docker/common/php/conf.d/mailhog.ini`

### Production (ENV=prod, ENV=production)
Используется **msmtp** для отправки через реальный SMTP.
- PHP использует: `/usr/bin/msmtp` (msmtp.ini)
- Конфигурация: `config/msmtp/msmtprc`

## Настройка для Production

1. Отредактируйте `config/msmtp/msmtprc`
2. Раскомментируйте нужный account (gmail, yandex, или создайте свой)
3. Заполните данные SMTP:
   ```
   account         production
   host            smtp.yourdomain.com
   port            587
   from            noreply@yourdomain.com
   user            smtp-user
   password        smtp-password
   auth            on
   tls             on
   ```
4. Установите account по умолчанию:
   ```
   account default : production
   ```
5. Перезапустите контейнер: `docker restart bitrix.local_bitrix`

## Тестирование

### Через PHP
```php
mail('test@example.com', 'Test Subject', 'Test message');
```

### Через msmtp напрямую
```bash
docker exec bitrix.local_bitrix sh -c 'echo "Subject: Test
To: test@example.com

Test message" | msmtp -C /etc/msmtp/msmtprc test@example.com'
```

### Проверка конфигурации
```bash
docker exec bitrix.local_bitrix msmtp -C /etc/msmtp/msmtprc --serverinfo
```

## Безопасность

⚠️ **Внимание**: `msmtprc` содержит пароли в открытом виде!

- Добавьте `config/msmtp/msmtprc` в `.gitignore` (уже добавлен)
- Используйте переменные окружения или Docker secrets для production
- Права доступа: 600 (только владелец может читать)

## Примеры конфигураций

### Gmail
```
account         gmail
host            smtp.gmail.com
port            587
from            noreply@yourdomain.com
user            your-email@gmail.com
password        your-app-password
auth            on
tls             on
tls_starttls    on
```

### Yandex
```
account         yandex
host            smtp.yandex.ru
port            465
from            noreply@yourdomain.com
user            your-email@yandex.ru
password        your-password
auth            on
tls             on
```
