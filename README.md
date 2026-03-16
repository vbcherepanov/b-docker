# B-Docker -- Production-Ready Docker для 1С-Битрикс

Полнофункциональное Docker-окружение для запуска проектов на 1С-Битрикс с поддержкой мультисайтов, мониторинга, безопасности и автоматических бэкапов.

## Содержание

- [Возможности](#возможности)
- [Быстрый старт](#быстрый-старт)
- [Архитектура](#архитектура)
- [Управление сайтами](#управление-сайтами-мультисайт)
- [Мониторинг](#мониторинг)
- [Безопасность](#безопасность)
- [Бэкапы](#бэкапы)
- [SSL-сертификаты](#ssl-сертификаты)
- [Почта](#почта)
- [Push Server](#push-server)
- [Конфигурация](#конфигурация-env)
- [Команды Makefile](#команды-makefile)
- [Структура проекта](#структура-проекта)
- [Авто-оптимизация](#авто-оптимизация)
- [Xdebug](#xdebug)
- [Troubleshooting](#troubleshooting)
- [FAQ](#faq)

---

## Возможности

- **Мультисайт** -- изоляция каждого сайта (отдельная БД, SMTP, конфиги)
- **PHP 7.4 / 8.3 / 8.4** -- двухуровневая сборка образов (базовый + сервисный)
- **Nginx** с CORS, security headers, rate limiting
- **MySQL / MariaDB / Percona** -- автоматический выбор по объёму RAM
- **Redis** -- сессии, кэширование, AOF-персистенция, Unix Socket (~30% прирост)
- **Memcached** -- дополнительное кэширование
- **RabbitMQ** -- очереди сообщений (опционально)
- **Push Server** -- real-time уведомления Битрикс (push-pub + push-sub)
- **Мониторинг** -- Grafana + Prometheus + Loki + Promtail
- **7 экспортёров** -- nginx, php-fpm, redis, mysql, memcached, rabbitmq, node
- **Безопасность** -- Fail2ban (7 jail'ов), ModSecurity WAF, security hardening контейнеров
- **Бэкапы** -- per-site (БД + файлы), расписание через cron, ротация
- **SSL** -- самоподписанные сертификаты и Let's Encrypt
- **Авто-оптимизация** -- автоматическая настройка под ресурсы сервера (RAM/CPU)
- **Split-архитектура** -- опциональное разделение на 4 PHP-контейнера
- **OPcache JIT + APCu** -- максимальная производительность PHP
- **MailHog** -- перехват почты в окружении разработки
- **Systemd** -- автозапуск контейнеров после перезагрузки сервера
- **Portainer Agent** -- опциональное удалённое управление

---

## Быстрый старт

### Требования

| Софт                 | Минимальная версия | Проверка                   |
|----------------------|--------------------|----------------------------|
| **Docker**           | 24+                | `docker --version`         |
| **Docker Compose**   | v2                 | `docker compose version`   |
| **Git**              | 2.0+               | `git --version`            |
| **Make**             | 3.0+               | `make --version`           |

### Рекомендуемые ресурсы сервера

| Ресурс  | Минимум | Рекомендуется | Production |
|---------|---------|---------------|------------|
| **CPU** | 2 ядра  | 4 ядра        | 8+ ядер    |
| **RAM** | 4 ГБ    | 8 ГБ          | 16+ ГБ     |
| **Диск**| 20 ГБ   | 50 ГБ         | 100+ ГБ SSD|

### Установка

```bash
# 1. Клонировать репозиторий
git clone <repo-url> && cd b-docker

# 2. Полная подготовка окружения (генерация паролей, оптимизация, валидация)
make setup

# 3. Полная инициализация с нуля (setup + build + запуск)
make first-run
```

После завершения `first-run` доступны:

| Сервис   | URL                           |
|----------|-------------------------------|
| Сайт     | `http://bitrix.local`         |
| MailHog  | `http://bitrix.local:8025`    |
| Grafana  | `http://grafana.bitrix.local` |

> Не забудьте добавить домен в `/etc/hosts`:
> ```
> 127.0.0.1 bitrix.local www.bitrix.local grafana.bitrix.local
> ```

### Окружения

```bash
make local          # Разработка (+ MailHog, Xdebug, Push, Monitoring)
make dev            # Тестовый сервер (+ Push, Monitoring)
make prod           # Production (+ Backup, RabbitMQ, Monitoring, Push)
```

Управление:

```bash
make local-down     # Остановить
make local-restart  # Перезапустить
make local-logs     # Логи всех контейнеров
make local-ps       # Статус контейнеров
```

### Production: первый запуск

```bash
make first-run-prod        # Полная инициализация для production
sudo make install-service  # Автозапуск через systemd
```

---

## Архитектура

### Unified mode (по умолчанию)

Один контейнер `bitrix` с Supervisor, управляющий PHP-FPM + Cron + фоновыми воркерами.

```
                    ┌─────────────────┐
                    │     nginx       │
                    │  (80 / 443)     │
                    └────────┬────────┘
                             │ FastCGI
                    ┌────────▼────────┐
                    │     bitrix      │
                    │  PHP-FPM + Cron │
                    │  + Supervisor   │
                    └───┬────┬────┬───┘
                        │    │    │
               ┌────────▼┐ ┌▼────▼────┐
               │  MySQL  │ │  Redis   │
               └─────────┘ └──────────┘
                        │
                  ┌─────▼──────┐
                  │ Memcached  │
                  └────────────┘
```

### Split mode (опционально)

4 отдельных контейнера для максимальной изоляции и масштабируемости:

| Контейнер    | Назначение                                     |
|--------------|------------------------------------------------|
| `php-fpm`    | Обработка HTTP-запросов через FastCGI           |
| `php-cli`    | CLI-операции, composer, миграции                |
| `cron`       | Периодические задачи (агенты Битрикс, crontab) |
| `supervisor` | Фоновые воркеры (очереди, long-running)         |

```bash
# Переключение на split mode:
# 1. В .env установите: PHP_FPM_HOST=php-fpm
# 2. Запустите:

make split-local        # Разработка в split mode
make split-prod         # Production в split mode
make split-down         # Остановить
make split-ps           # Статус
make split-logs         # Логи
```

### Двухуровневые PHP-образы

Сборка разделена на два уровня для ускорения:

1. **Базовые образы** (`my/php-base-fpm:8.3`, `my/php-base-cli:8.3`) -- все PHP-расширения, собираются редко
2. **Сервисные образы** -- наследуют базовые, добавляют конфиги, собираются быстро

```bash
make build-base         # Собрать оба базовых образа
make build-base-cli     # Только CLI
make build-base-fpm     # Только FPM
```

### PHP-расширения

bcmath, bz2, exif, gettext, gmp, intl, mysqli, opcache, pdo_mysql, pcntl, sockets, sysvmsg, sysvsem, sysvshm, xsl, zip, curl, gd, ldap, imagick, amqp, apcu, zstd, msgpack, mongodb, redis, rdkafka, ssh2, yaml, igbinary, memcached, memcache, lz4

Условные: **xdebug** (при `DEBUG=1`), **mhsendmail** (при `ENVIRONMENT=local|dev`)

---

## Управление сайтами (мультисайт)

### Добавление сайта

```bash
make site-add SITE=shop.local                 # Базовое добавление
make site-add SITE=shop.local SSL=yes         # + самоподписанный SSL
make site-add SITE=prod.com SSL=letsencrypt   # + Let's Encrypt
make site-add SITE=api.local PHP=8.4          # + конкретная версия PHP
```

Автоматически создаётся:
- Директория `www/shop.local/www/` (document root)
- Nginx-конфиг `config/nginx/sites/shop.local.conf`
- Per-site конфиги `config/sites/shop.local/` (site.env, msmtp.conf, database-init.sql)
- База данных и пользователь MySQL
- Перезагрузка nginx

### Другие операции

```bash
make site-list                                # Список всех сайтов
make site-remove SITE=old.local               # Полное удаление (файлы + БД + конфиги)
make site-ssl SITE=shop.local                 # Самоподписанный SSL
make site-ssl-le SITE=prod.com                # Let's Encrypt сертификат
make site-reload                              # Перезагрузить nginx
make site-clone FROM=source.com TO=target.com # Клонировать сайт
```

### База данных

```bash
make db-init SITE=shop.local      # Создать БД для сайта
make db-init-all                  # Создать БД для всех сайтов
make db-list-sites                # Список per-site баз данных
```

### Структура файлов мультисайта

```
www/
└── shop.local/
    └── www/                  <-- Document root
        ├── index.php
        ├── bitrix/
        └── upload/

config/sites/
└── shop.local/
    ├── site.env              <-- DB credentials (DB_NAME, DB_USER, DB_PASSWORD)
    ├── msmtp.conf            <-- Per-site SMTP настройки
    └── database-init.sql     <-- SQL для создания БД и пользователя
```

> После добавления сайта добавьте запись в `/etc/hosts`:
> ```
> 127.0.0.1 shop.local www.shop.local
> ```

---

## Мониторинг

Стек мониторинга включается автоматически при запуске `make local`, `make dev` или `make prod`.

### Компоненты

| Компонент          | Назначение                          | Доступ                            |
|--------------------|-------------------------------------|-----------------------------------|
| **Grafana**        | Дашборды и визуализация             | `http://grafana.{DOMAIN}`         |
| **Prometheus**     | Сбор и хранение метрик              | `http://prometheus.{DOMAIN}`      |
| **Loki**           | Агрегация логов                     | Внутренний (порт 3100)            |
| **Promtail**       | Сбор логов из контейнеров           | Внутренний                        |
| **Node Exporter**  | Метрики хоста (CPU, RAM, диск)      | Внутренний (порт 9100)            |

### Экспортёры

| Экспортёр              | Метрики                                  |
|------------------------|------------------------------------------|
| `nginx-exporter`       | Запросы, соединения, статусы             |
| `php-fpm-exporter`     | Воркеры, очередь, медленные запросы      |
| `redis-exporter`       | Память, ключи, hit/miss ratio            |
| `mysql-exporter`       | InnoDB, соединения, запросы, репликация   |
| `memcached-exporter`   | Hit/miss, память, evictions              |
| `rabbitmq-exporter`    | Очереди, сообщения, потребители          |
| `node-exporter`        | CPU, RAM, диск, сеть хоста               |

### Готовые дашборды Grafana

- Security Dashboard
- Nginx Security Dashboard
- PHP Errors Dashboard

### Управление

```bash
make monitoring-up          # Включить мониторинг
make monitoring-down        # Выключить мониторинг
make logs-grafana           # Логи Grafana
```

---

## Безопасность

### Fail2ban -- 7 jail'ов

| Jail               | Защита от                          |
|--------------------|------------------------------------|
| `nginx-req-limit`  | Превышение rate limit              |
| `nginx-403`        | Массовые 403 (сканирование)        |
| `nginx-404`        | Массовые 404 (поиск уязвимостей)   |
| `nginx-botsearch`  | Сканирование ботами                |
| `nginx-brute`      | Brute force атаки                  |
| `nginx-sqli`       | SQL Injection попытки              |
| `nginx-xss`        | XSS атаки                         |

### Команды безопасности

```bash
make security-up              # Запуск Fail2ban
make security-up-full         # Fail2ban + ModSecurity WAF
make security-down            # Остановить
make security-restart         # Перезапустить
make security-status          # Статус

# Управление Fail2ban
make fail2ban-status          # Статус
make fail2ban-jails           # Список jail'ов
make fail2ban-banned          # Заблокированные IP
make fail2ban-unban IP=1.2.3.4  # Разблокировать IP
make fail2ban-ban IP=1.2.3.4    # Заблокировать IP

# Статистика
make security-attacks         # Последние атаки
make security-stats           # Статистика (403, 404, 429, баны)
make security-test            # Проверка конфигурации
```

### Hardening контейнеров

Все контейнеры защищены по рекомендациям Bitrix official:

- `no-new-privileges: true` -- запрет повышения привилегий
- `cap_drop: ALL` -- сброс всех Linux capabilities
- Минимальные `cap_add` для каждого сервиса
- `tmpfs` с `noexec,nodev,nosuid` для `/tmp` и `/var/tmp`
- JSON logging с ротацией (10MB x 3 файла на контейнер)
- Health checks для всех сервисов

---

## Бэкапы

### Per-site бэкапы

```bash
# Информация
make backup-sites                              # Список сайтов для бэкапа
make backup-list                               # Все бэкапы
make backup-list-db                            # Только БД
make backup-list-files                         # Только файлы

# Создание
make backup-db                                 # БД всех сайтов
make backup-db SITE=shop.local                 # БД одного сайта
make backup-files                              # Файлы всех сайтов
make backup-files SITE=shop.local              # Файлы одного сайта
make backup-full                               # Полный бэкап всех сайтов
make backup-full SITE=shop.local               # Полный бэкап одного сайта

# Восстановление
make backup-restore-db FILE=backups/database/shop_local_20260118.sql.gz
make backup-restore-db FILE=backup.sql.gz SITE=shop.local
make backup-restore-files FILE=backups/files/shop_local_20260118.tar.gz
make backup-restore-full DIR=backups/full/shop_local_20260118_120000

# Очистка
make backup-cleanup                            # Удалить старые бэкапы
```

### Автоматическое расписание (production)

| Задача        | Расписание          | Переменная               |
|---------------|---------------------|--------------------------|
| Бэкап БД      | Ежедневно в 02:00   | `BACKUP_SCHEDULE_DB`     |
| Бэкап файлов  | Ежедневно в 03:00   | `BACKUP_SCHEDULE_FILES`  |
| Retention      | 7 дней              | `BACKUP_RETENTION_DAYS`  |

### Структура бэкапов

```
backups/
├── database/
│   ├── shop_local_20260118_120000.sql.gz
│   └── blog_local_20260118_120000.sql.gz
├── files/
│   ├── shop_local_20260118_120000.tar.gz
│   └── blog_local_20260118_120000.tar.gz
└── full/
    └── shop_local_20260118_120000/
        ├── database.sql.gz
        ├── files.tar.gz
        └── manifest.txt
```

---

## SSL-сертификаты

### Режимы SSL (переменная `SSL` в `.env`)

| Значение | Описание                                              |
|----------|-------------------------------------------------------|
| `0`      | Без SSL (только HTTP)                                 |
| `self`   | Свои сертификаты (положить в `config/nginx/ssl/`)     |
| `free`   | Let's Encrypt (автогенерация и автопродление)         |

### Самоподписанный сертификат

```bash
make site-ssl SITE=shop.local
# Или при добавлении сайта:
make site-add SITE=shop.local SSL=yes
```

### Let's Encrypt

```bash
make site-ssl-le SITE=prod.com
# Или при добавлении сайта:
make site-add SITE=prod.com SSL=letsencrypt
```

---

## Почта

### Разработка -- MailHog

В окружениях `local` и `dev` автоматически запускается MailHog:

- **SMTP**: порт `1025`
- **Web UI**: `http://{DOMAIN}:8025`

Все исходящие письма перехватываются и доступны через web-интерфейс.

### Production -- MSMTP

Каждый сайт может иметь собственную SMTP-конфигурацию:

```
config/sites/shop.local/msmtp.conf
```

Пример настройки для продакшн:

```
account shop_local
host smtp.your-provider.com
port 587
from noreply@shop.local
auth on
user your-smtp-user
password your-smtp-password
tls on
```

Шаблон: `config/sites/_template/msmtp.conf.template`

---

## Push Server

Real-time уведомления Битрикс: чат, живая лента, мгновенные уведомления.

Используется официальный образ `quay.io/bitrix24/push:3.2-v1-alpine`.

| Сервис      | Назначение                              | Порт  |
|-------------|------------------------------------------|-------|
| `push-sub`  | Подписки клиентов (WebSocket)            | 8010  |
| `push-pub`  | Публикация событий (PHP -> Push Server)  | 9010  |

Настройка в `.env`:

```env
PUSH_SECURITY_KEY=<секретный ключ>   # openssl rand -hex 32
PUSH_PUB_PORT=9010
PUSH_SUB_PORT=8010
```

Push Server включается автоматически во всех окружениях (`make local`, `make dev`, `make prod`).

---

## Конфигурация (.env)

### Основные настройки

| Переменная               | Описание                            | По умолчанию         |
|--------------------------|-------------------------------------|----------------------|
| `COMPOSE_PROJECT_NAME`   | Имя проекта Docker Compose          | `bitrix`             |
| `ENVIRONMENT`            | Окружение: `local`, `dev`, `prod`   | `local`              |
| `DOMAIN`                 | Основной домен сайта                | `bitrix.local`       |
| `TZ`                     | Временная зона                      | `Europe/Moscow`      |
| `DEBUG`                  | Режим отладки (1 = Xdebug)         | `1`                  |
| `UID` / `GID`            | ID пользователя/группы              | `1000`               |

### PHP

| Переменная                  | Описание                     | По умолчанию |
|-----------------------------|------------------------------|--------------|
| `PHP_VERSION`               | Версия PHP: 7.4, 8.3, 8.4   | `8.3`        |
| `PHP_MEMORY_LIMIT`          | Лимит памяти                 | `512M`       |
| `PHP_UPLOAD_MAX_FILESIZE`   | Макс. размер загрузки        | `1024M`      |
| `PHP_POST_MAX_SIZE`         | Макс. размер POST            | `1024M`      |
| `PHP_MAX_EXECUTION_TIME`    | Макс. время выполнения (с)   | `300`        |
| `PHP_FPM_PM`               | Режим FPM                    | `dynamic`    |
| `PHP_FPM_MAX_CHILDREN`      | Макс. воркеров FPM           | `12`         |
| `PHP_OPCACHE_ENABLE`        | OPcache (0=off, 1=on)        | `0` (local)  |
| `PHP_OPCACHE_MEMORY`        | Память OPcache (MB)          | `256`        |
| `PHP_OPCACHE_MAX_FILES`     | Макс. файлов в кэше          | `100000`     |

### База данных

| Переменная                       | Описание                          | По умолчанию      |
|----------------------------------|-----------------------------------|--------------------|
| `MYSQL_IMAGE`                    | Образ БД                          | `mariadb:10.11`   |
| `DB_NAME`                        | Имя базы данных                   | `bitrix`          |
| `DB_USERNAME`                    | Пользователь БД                   | `bitrix`          |
| `DB_PASSWORD`                    | Пароль                            | генерируется      |
| `DB_ROOT_PASSWORD`               | Root-пароль                       | генерируется      |
| `MYSQL_INNODB_BUFFER_POOL_SIZE`  | Размер buffer pool                | `1G`              |
| `MYSQL_MAX_CONNECTIONS`          | Макс. подключений                 | `50`              |
| `MYSQL_MEMORY_LIMIT`            | Лимит памяти контейнера           | `2G`              |

**Рекомендации по выбору `MYSQL_IMAGE`:**

| RAM сервера | Образ                                                  |
|-------------|--------------------------------------------------------|
| < 4 ГБ     | `mariadb:10.11` (по умолчанию, низкое потребление)      |
| 4-16 ГБ    | `quay.io/bitrix24/percona-server:8.0.44-v1-rhel` (Bitrix official) |
| > 16 ГБ    | `quay.io/bitrix24/percona-server:8.4.7-v1-rhel`        |

### Redis и Memcached

| Переменная               | Описание               | По умолчанию |
|--------------------------|------------------------|--------------|
| `REDIS_MAX_MEMORY`       | Лимит памяти Redis     | `128mb`      |
| `REDIS_PASSWORD`         | Пароль Redis           | генерируется |
| `MEMCACHED_MEMORY_LIMIT` | Лимит памяти (MB)      | `1024`       |
| `MEMCACHED_THREADS`      | Потоков Memcached       | `8`          |
| `MEMCACHED_CONN_LIMIT`   | Лимит соединений       | `1024`       |

### RabbitMQ

| Переменная               | Описание               | По умолчанию |
|--------------------------|------------------------|--------------|
| `RABBITMQ_DEFAULT_USER`  | Логин                  | `admin`      |
| `RABBITMQ_DEFAULT_PASS`  | Пароль                 | генерируется |
| `RABBIT_PORT`            | AMQP порт              | `5672`       |
| `RABBIT_UI_PORT`         | Management UI порт     | `15672`      |

### Мониторинг

| Переменная                | Описание                      | По умолчанию |
|---------------------------|-------------------------------|--------------|
| `ENABLE_GRAFANA`          | Включить Grafana              | `1`          |
| `ENABLE_PROMETHEUS`       | Включить Prometheus           | `1`          |
| `ENABLE_LOKI`             | Включить Loki                 | `1`          |
| `GRAFANA_ADMIN_PASSWORD`  | Пароль админа Grafana         | `admin`      |
| `MONITORING_USER`         | Basic Auth для субдоменов     | `admin`      |
| `MONITORING_PASSWORD`     | Пароль Basic Auth             | генерируется |

### Субдомены для сервисов

| Переменная              | Описание                 | По умолчанию   |
|-------------------------|--------------------------|----------------|
| `GRAFANA_CONFIG`        | Включить субдомен (0/1)  | `0`            |
| `GRAFANA_SUBDOMAIN`     | Имя субдомена            | `grafana`      |
| `PROMETHEUS_CONFIG`     | Включить субдомен (0/1)  | `0`            |
| `PROMETHEUS_SUBDOMAIN`  | Имя субдомена            | `prometheus`   |
| `MAIL_CONFIG`           | Включить субдомен (0/1)  | `0`            |
| `RABBIT_CONFIG`         | Включить субдомен (0/1)  | `0`            |

### Бэкапы

| Переменная               | Описание                    | По умолчанию    |
|--------------------------|------------------------------|-----------------|
| `BACKUP_SCHEDULE_DB`     | Cron-расписание бэкапа БД   | `0 2 * * *`     |
| `BACKUP_SCHEDULE_FILES`  | Cron-расписание файлов       | `0 3 * * *`     |
| `BACKUP_RETENTION_DAYS`  | Хранить бэкапы (дней)        | `7`             |
| `BACKUP_PATH`            | Путь хранения                | `./backups`     |

### Docker Compose Profiles

| Профиль      | Что включает                             |
|--------------|------------------------------------------|
| `local`      | MailHog, Xdebug                          |
| `dev`        | Dev-окружение                            |
| `prod`       | Production-оптимизации                   |
| `monitoring` | Grafana, Prometheus, Loki, экспортёры    |
| `push`       | Push Server (pub + sub)                  |
| `backup`     | Контейнер бэкапов                        |
| `rabbitmq`   | RabbitMQ + exporter                      |
| `security`   | Fail2ban, ModSecurity                    |
| `split`      | Раздельные PHP-контейнеры                |
| `full`       | Все сервисы сразу                        |

---

## Команды Makefile

### Быстрый старт

| Команда               | Описание                                                  |
|-----------------------|-----------------------------------------------------------|
| `make setup`          | Подготовка (генерация секретов + оптимизация + валидация) |
| `make first-run`      | Полная инициализация с нуля (local)                       |
| `make first-run-prod` | Полная инициализация для production                       |
| `make quick-start`    | Быстрый запуск без полной настройки                       |
| `make optimize`       | Пересоздать конфиги под текущий сервер                    |
| `make validate`       | Валидация .env файла                                      |

### Управление контейнерами

| Команда              | Описание                |
|----------------------|-------------------------|
| `make local`         | Запуск для разработки   |
| `make dev`           | Запуск для dev-сервера  |
| `make prod`          | Запуск для production   |
| `make local-down`    | Остановить              |
| `make local-restart` | Перезапустить           |
| `make local-logs`    | Логи                    |
| `make local-ps`      | Статус контейнеров      |

> Аналогичные команды доступны с префиксами `dev-` и `prod-`.

### Сайты

| Команда                                  | Описание                     |
|------------------------------------------|------------------------------|
| `make site-add SITE=example.com`         | Добавить сайт                |
| `make site-remove SITE=example.com`      | Удалить сайт (включая БД)    |
| `make site-list`                         | Список сайтов                |
| `make site-ssl SITE=example.com`         | Self-signed SSL              |
| `make site-ssl-le SITE=example.com`      | Let's Encrypt SSL            |
| `make site-clone FROM=a.com TO=b.com`    | Клонировать сайт             |
| `make site-reload`                       | Перезагрузить nginx          |
| `make db-init SITE=example.com`          | Создать БД для сайта         |
| `make db-init-all`                       | Создать БД для всех сайтов   |
| `make db-list-sites`                     | Список per-site БД           |

### Бэкапы

| Команда                                         | Описание                  |
|--------------------------------------------------|---------------------------|
| `make backup-full [SITE=...]`                    | Полный бэкап              |
| `make backup-db [SITE=...]`                      | Бэкап БД                 |
| `make backup-files [SITE=...]`                   | Бэкап файлов             |
| `make backup-list`                               | Список бэкапов            |
| `make backup-restore-db FILE=... [SITE=...]`     | Восстановить БД           |
| `make backup-restore-files FILE=... [SITE=...]`  | Восстановить файлы        |
| `make backup-restore-full DIR=... [SITE=...]`    | Восстановить полный       |
| `make backup-cleanup`                            | Очистка старых бэкапов     |
| `make backup-sites`                              | Список сайтов для бэкапа   |

### Безопасность

| Команда                            | Описание                       |
|------------------------------------|--------------------------------|
| `make security-up`                 | Запуск Fail2ban                |
| `make security-up-full`            | Fail2ban + ModSecurity         |
| `make security-down`               | Остановить                     |
| `make security-stats`              | Статистика                     |
| `make fail2ban-status`             | Статус Fail2ban                |
| `make fail2ban-jails`              | Список jail'ов                 |
| `make fail2ban-banned`             | Заблокированные IP             |
| `make fail2ban-unban IP=x.x.x.x`  | Разблокировать IP              |
| `make fail2ban-ban IP=x.x.x.x`    | Заблокировать IP               |

### Логи

| Команда                                 | Описание                           |
|-----------------------------------------|------------------------------------|
| `make logs-status`                      | Размер и статус логов              |
| `make logs-rotate`                      | Ротация больших логов              |
| `make logs-cleanup [RETENTION_DAYS=N]`  | Удалить старые логи                |
| `make logs-maintain`                    | Ротация + очистка                  |
| `make logs-setup-cron`                  | Автоматическая ротация через cron  |
| `make logs-clear-all`                   | Удалить ВСЕ логи                   |
| `make logs-nginx`                       | Логи nginx                         |
| `make logs-php`                         | Логи PHP-FPM                       |
| `make logs-mysql`                       | Логи MySQL                         |

### Docker и диск

| Команда                        | Описание                                  |
|--------------------------------|-------------------------------------------|
| `make docker-status`           | Использование диска Docker                |
| `make docker-clean`            | Мягкая очистка (безопасно)                |
| `make docker-clean-full`       | Полная очистка                            |
| `make docker-clean-aggressive` | Максимальная очистка (+ build cache)      |
| `make docker-clean-cron`       | Еженедельная автоочистка через cron       |
| `make disk-usage`              | Использование диска хоста + Docker        |

### Сборка образов

| Команда               | Описание                                 |
|------------------------|------------------------------------------|
| `make build-base`      | Собрать базовые PHP-образы (CLI + FPM)   |
| `make build-base-cli`  | Только CLI                               |
| `make build-base-fpm`  | Только FPM                               |

### Split mode

| Команда                  | Описание                              |
|--------------------------|---------------------------------------|
| `make split-local`       | Split mode для разработки             |
| `make split-prod`        | Split mode для production             |
| `make split-down`        | Остановить                            |
| `make split-ps`          | Статус                                |
| `make split-logs`        | Логи                                  |
| `make split-rebuild-php` | Пересобрать только PHP-контейнеры     |
| `make bash-fpm`          | Shell в php-fpm                       |
| `make bash-cli`          | Shell в php-cli                       |
| `make bash-cron`         | Shell в cron                          |
| `make bash-supervisor`   | Shell в supervisor                    |

### Systemd

| Команда                  | Описание                           |
|--------------------------|-------------------------------------|
| `make install-service`   | Установить автозапуск (sudo)       |
| `make uninstall-service` | Удалить автозапуск                 |
| `make service-status`    | Статус сервиса                     |
| `make service-logs`      | Логи systemd                       |

### Диагностика

| Команда                    | Описание                                    |
|----------------------------|----------------------------------------------|
| `make mysql-diag`          | Диагностика MySQL (логи, конфиги, ресурсы)   |
| `make mysql-reset`         | Пересоздать MySQL с нуля (удалит данные!)     |
| `make auto-config`         | Автоконфигурация под ресурсы сервера          |
| `make auto-config-preview` | Предварительный просмотр конфигурации         |
| `make auto-config-manual CPU_CORES=8 RAM_GB=16` | Ручной ввод параметров  |

### Доступ к контейнерам

```bash
make bash_cli_local        # PHP CLI (local)
make bash_local_nginx      # Nginx (local)
make bash_cli              # PHP CLI
make bash_nginx            # Nginx
```

### Nginx

```bash
make check_local_nginx     # Проверить конфигурацию
make reload_local_nginx    # Перезагрузить
make check_nginx           # Проверить (prod)
make reload_nginx          # Перезагрузить (prod)
```

### Справка

```bash
make help                  # Все команды
make help-quick            # Шпаргалка
make help-sites            # Управление сайтами
make help-backup           # Бэкапы
make help-security         # Безопасность
make help-logs             # Логи
make help-docker           # Очистка Docker
make help-autoconfig       # Автоконфигурация
```

---

## Структура проекта

```
b-docker/
├── .env.example                        # Шаблон переменных окружения
├── Makefile                            # Все команды управления
├── docker-compose.bitrix.yml           # Единый compose-файл с профилями
│
├── docker/                             # Dockerfiles и файлы сборки
│   ├── nginx/Dockerfile
│   ├── mysql/Dockerfile
│   ├── redis/Dockerfile
│   ├── memcached/Dockerfile
│   ├── rabbitmq/Dockerfile
│   ├── mailhog/Dockerfile
│   ├── backup/Dockerfile
│   ├── fail2ban/
│   │   ├── Dockerfile
│   │   └── config/filter.d/           # 7 фильтров Fail2ban
│   ├── modsecurity/Dockerfile
│   ├── mongodb/Dockerfile
│   └── php/
│       ├── base/                       # Базовые PHP-образы
│       │   ├── cli/{7.4,8.3,8.4}/Dockerfile
│       │   └── fpm/{7.4,8.3,8.4}/Dockerfile
│       ├── bitrix/Dockerfile           # Unified контейнер
│       ├── php-fpm/Dockerfile          # Split: FPM
│       ├── php-cli/Dockerfile          # Split: CLI
│       ├── cron/Dockerfile             # Split: Cron
│       └── supervisor/Dockerfile       # Split: Supervisor
│
├── config/                             # Runtime-конфигурации
│   ├── cron/crontab                    # Cron-задачи
│   ├── mysql/
│   │   ├── my.{local,dev,prod}.cnf    # MySQL конфиги по окружению
│   │   └── init/                       # SQL-скрипты инициализации
│   ├── nginx/
│   │   ├── sites/                      # Per-site nginx конфиги
│   │   ├── ssl/                        # SSL сертификаты
│   │   └── conf/                       # Дополнительные nginx конфиги
│   ├── redis/redis.conf
│   ├── memcached/memcached.conf
│   ├── supervisor/conf/                # Supervisor-программы (воркеры)
│   ├── sites/                          # Per-site конфигурации
│   │   ├── _template/                  # Шаблоны для новых сайтов
│   │   └── {domain}/                   # Конфиг конкретного сайта
│   ├── grafana/
│   │   ├── provisioning/               # Источники данных
│   │   └── dashboards/                 # Готовые дашборды
│   ├── prometheus/
│   │   ├── prometheus.yml
│   │   └── rules/                      # Правила алертов
│   ├── loki/loki-config.yaml
│   ├── promtail/config.yml
│   ├── msmtp/                          # SMTP-конфигурация
│   ├── backup/                         # Конфиги бэкапов
│   ├── certbot/                        # Let's Encrypt скрипты
│   ├── logrotate/                      # Ротация логов
│   └── bitrix/                         # Пример .settings.php
│
├── scripts/                            # Скрипты автоматизации
│   ├── site.sh                         # Управление мультисайтами
│   ├── generate-secrets.sh             # Генерация паролей
│   ├── auto-optimize.sh                # Авто-оптимизация под сервер
│   ├── validate-env.sh                 # Валидация .env
│   ├── apply-security-fixes.sh         # Security hardening
│   ├── backup.sh                       # Скрипт бэкапов
│   ├── security-scan.sh                # Сканирование безопасности
│   ├── logs-rotate.sh                  # Ротация логов
│   ├── docker-cleanup.sh               # Очистка Docker
│   ├── install-service.sh              # Установка systemd сервиса
│   └── auto-setup-bitrix.sh            # Автоустановка Битрикс
│
├── www/                                # Код сайтов (gitignored)
│   └── {domain}/www/                   # Document root сайта
│
├── volume/                             # Персистентные данные (gitignored)
│   ├── logs/                           # Логи всех сервисов
│   │   ├── nginx/ php/ php-fpm/
│   │   ├── cron/ supervisor/
│   │   ├── mysql/ redis/ memcached/
│   │   ├── rabbitmq/ fail2ban/
│   │   ├── msmtp/ letsencrypt/ bitrix/
│   └── mysql/dump/                     # Дампы БД
│
├── backups/                            # Бэкапы (gitignored)
│   ├── database/ files/ full/
│
└── ssl/                                # SSL сертификаты
```

---

## Авто-оптимизация

Скрипт `auto-optimize.sh` автоматически настраивает параметры под ресурсы сервера:

| Параметр                         | Формула                           |
|----------------------------------|-----------------------------------|
| `PHP_FPM_MAX_CHILDREN`           | CPU_CORES * 3                     |
| `PHP_FPM_START_SERVERS`          | CPU_CORES * 0.75                  |
| `PHP_FPM_MIN_SPARE_SERVERS`      | MAX(CPU_CORES - 1, 2)            |
| `PHP_FPM_MAX_SPARE_SERVERS`      | CPU_CORES                         |
| `MYSQL_INNODB_BUFFER_POOL_SIZE`  | RAM * 0.5                         |
| `MYSQL_MAX_CONNECTIONS`          | CPU_CORES * 10                    |
| `MYSQL_IMAGE`                    | Выбор по объёму RAM               |
| `PHP_OPCACHE_MEMORY`            | 128 / 256 / 512 по объёму RAM     |

```bash
make optimize                                    # Пересоздать конфиги
make auto-config-preview                         # Предварительный просмотр
make auto-config-manual CPU_CORES=8 RAM_GB=16    # Ручной ввод параметров
```

---

## Xdebug

Активируется при `DEBUG=1` в `.env` (только окружения `local` и `dev`):

| Параметр     | Значение                |
|--------------|-------------------------|
| Порт         | 9003                    |
| Режим        | trigger                 |
| Host         | `host.docker.internal`  |
| IDE key      | `PHPSTORM`              |

---

## Troubleshooting

### MySQL не запускается

```bash
make mysql-diag       # Полная диагностика (ресурсы, логи, конфиги)
make mysql-reset      # Пересоздать с нуля (УДАЛИТ ДАННЫЕ!)
```

Частые причины:
- `innodb_buffer_pool_size` больше доступной RAM -- уменьшите в `.env`
- Для серверов с < 4 ГБ RAM используйте `MYSQL_IMAGE=mariadb:10.11`
- На macOS/ARM проблемы с `innodb-flush-method=O_DIRECT` -- отключен по умолчанию

### Контейнеры не видят друг друга

```bash
make docker-network-create   # Пересоздать сеть
```

### Nginx возвращает 502

PHP-FPM контейнер ещё не готов. Nginx запускается независимо и отдаёт 502 до готовности PHP-FPM. Подождите завершения health check (~40 секунд).

### OPcache не работает в разработке

По умолчанию `PHP_OPCACHE_ENABLE=0` для `local`. Это корректное поведение -- в разработке OPcache отключен для актуальности кода.

### Права доступа на файлы

Убедитесь что `UID` и `GID` в `.env` совпадают с вашим пользователем:

```bash
id -u    # Ваш UID
id -g    # Ваш GID
```

### Redis Unix Socket

Redis подключается через Unix Socket (shared volume `redis-socket`), что даёт прирост ~30% по сравнению с TCP. При проблемах можно переключиться на TCP через `REDIS_HOST=redis` в конфиге Битрикс.

### Логи занимают много места

```bash
make logs-status      # Проверить размер логов
make logs-maintain    # Ротация + очистка старых
make logs-setup-cron  # Настроить автоматическую ротацию
```

### Docker занимает много места

```bash
make docker-status          # Сколько занимает Docker
make docker-clean           # Безопасная очистка
make docker-clean-full      # Полная очистка
make docker-clean-cron      # Автоматическая еженедельная очистка
```

### Сайт не загружается после добавления

```bash
make check_local_nginx              # Проверить nginx конфигурацию
make reload_local_nginx             # Перезагрузить nginx
cat /etc/hosts | grep shop.local    # Проверить /etc/hosts
ls -la www/shop.local/www/          # Проверить файлы сайта
```

---

## FAQ

### Как сменить версию PHP?

```bash
# 1. Изменить в .env:
PHP_VERSION=8.4    # или 8.3, 7.4

# 2. Пересобрать и перезапустить:
make build-base
make local-restart
```

### Как переключиться на MariaDB / Percona?

```bash
# Изменить в .env:
MYSQL_IMAGE=mariadb:10.11
# или
MYSQL_IMAGE=quay.io/bitrix24/percona-server:8.0.44-v1-rhel

# Перезапустить:
make local-restart
```

### Где находятся логи?

| Расположение              | Описание                    |
|---------------------------|------------------------------|
| `./volume/logs/`          | Файловые логи (ротация)     |
| Grafana/Loki              | Централизованные логи        |
| `docker logs <container>` | Docker stdout/stderr         |

### Как добавить PHP-расширение?

1. Отредактируйте `docker/php/base/fpm/{version}/Dockerfile`
2. Пересоберите:

```bash
make build-base
make local-restart
```

### Как настроить SMTP для production?

Отредактируйте per-site конфиг:

```bash
# config/sites/shop.local/msmtp.conf
account shop_local
host smtp.your-provider.com
port 587
from noreply@shop.local
auth on
user your-smtp-user
password your-smtp-password
tls on
```

---

## Production Checklist

Перед деплоем на production:

- [ ] Все пароли изменены (выполнен `make setup`)
- [ ] `DEBUG=0` в `.env`
- [ ] `PHP_OPCACHE_ENABLE=1` в `.env`
- [ ] SSL настроен (`SSL=free` для Let's Encrypt)
- [ ] Бэкапы включены (профиль `backup`)
- [ ] Fail2ban запущен (`make security-up`)
- [ ] Systemd сервис установлен (`sudo make install-service`)
- [ ] Мониторинг работает (Grafana доступна)
- [ ] Протестирована процедура backup/restore
- [ ] Firewall настроен (только 80, 443, 22)
