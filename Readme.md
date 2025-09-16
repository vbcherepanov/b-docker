# Bitrix Docker Environment

**bitrix-docker** - современное Docker окружение для запуска проектов на 1C-Bitrix с полным стеком мониторинга, автоматическими бэкапами и централизованным управлением.

## 🔧 Исправленные проблемы

### Критические ошибки в Dockerfile:
1. **Логическая ошибка в условиях** - исправлено `||` на правильную логику для отключения xdebug в продакшн
2. **Неправильный пакетный менеджер** - заменен `microdnf` на `apt-get` для MySQL образа
3. **Опечатки в переменных** - исправлена `DOLLAD` на `DOLLAR`

### Оптимизация Makefile:
1. **Удалены дублирующие команды** - очищен от конфликтующих целей
2. **Добавлены новые команды** для работы с единым compose файлом
3. **Исправлены зависимости** между командами

### Новый единый docker-compose:
- **Профили для окружений**: local, dev, prod, monitoring, backup, portainer
- **Все сервисы во всех профилях** - MySQL, Redis, Memcached, MailHog доступны везде
- **Умное управление функциями** - Xdebug отключается через переменную ENVIRONMENT
- **Гибкие зависимости** - правильные depends_on для всех окружений

## 📊 Централизованное логирование

**Все логи автоматически собираются в Promtail → Loki → Grafana:**

- **Docker контейнеры** - логи всех контейнеров через Docker Socket
- **Nginx** - access/error логи с парсингом HTTP статусов
- **PHP-FPM** - логи ошибок и работы процессов
- **MySQL** - логи ошибок БД
- **Redis** - логи операций кеширования
- **Cron/Supervisor** - логи фоновых задач

**Доступ к логам:**
- Grafana UI: `http://localhost:3000` (admin/admin)
- Prometheus: `http://localhost:9090`
- Loki: `http://localhost:3100`

## ⚙️ Автоматическая конфигурация

Система автоматически определяет:
- **CPU**: количество ядер → настройки worker_processes, max_children
- **RAM**: объем памяти → innodb_buffer_pool_size, memory_limit, Redis maxmemory
- **Окружение**: local/dev/prod → включение/отключение debug-сервисов

### Формулы оптимизации:

#### MySQL:
- `innodb_buffer_pool_size = 60% от RAM`
- `max_connections = 50 соединений на CPU ядро`
- `query_cache_size = 5% от RAM`

#### PHP-FPM:
- `max_children = CPU ядра × 5`
- `memory_limit = 256MB (≤8GB RAM) / 512MB (>8GB RAM)`

#### Redis:
- `maxmemory = 25% от RAM`

#### Nginx:
- `worker_processes = количество CPU ядер`
- `worker_connections = 1024 (≤4GB RAM) / 2048 (>4GB RAM)`

## 📊 Профили и окружения

### 🧪 Локальная разработка (`local`)
**Команды**: `make *-local`
**Включает**:
- Все основные сервисы PHP
- MySQL, Redis, Memcached
- MailHog для тестирования почты
- Xdebug включен
- Все логи в volume/logs/

### 🏭 Продакшн (`prod`)
**Команды**: `make *-prod`
**Включает**:
- Все основные сервисы PHP
- MySQL, Redis, Memcached (локальные или внешние)
- MailHog доступен
- Xdebug выключен (через переменную ENVIRONMENT)
- Оптимизированные конфиги

### 📈 Мониторинг (`monitoring`)
**Команды**: `make *-monitoring`
**Дополнительно**:
- Grafana (порт 3000)
- Prometheus (порт 9090)
- Loki для логов
- Promtail для сбора логов
- Node Exporter для метрик системы

### 💾 Бэкапы (`backup`)
**Команды**: `make backup-*`
**Функции**:
- Автоматические бэкапы БД и файлов
- Настраиваемое расписание через cron
- Ротация старых бэкапов
- Восстановление из архивов

### 🎛️ Управление (`portainer`)
**Команды**: `make portainer-*`
**Возможности**:
- Portainer Agent для централизованного управления
- Веб-интерфейс управления контейнерами
- Мониторинг ресурсов

## Основные возможности

- **PHP 7.4 и 8.3** - поддержка двух версий PHP
- **Единый docker-compose.yml** - с профилями для всех окружений
- **Централизованное логирование** - Promtail → Loki → Grafana
- **Автоматическая оптимизация** - конфиги под железо с формулами
- **Автоматические бэкапы** - база данных и файлы с настраиваемым расписанием
- **SSL сертификаты** - поддержка self-signed, собственных и Let's Encrypt сертификатов
- **Portainer Agent** - для централизованного управления контейнерами
- **Безопасность** - все конфигурации вынесены во внешние файлы
- **Окружения** - отдельные настройки для local/dev/prod

## Технологический стек

- **Web-сервер**: Nginx
- **PHP**: PHP-FPM + PHP-CLI + Cron + Supervisor
- **База данных**: MySQL (доступна во всех профилях)
- **Кэширование**: Redis + Memcached (доступны во всех профилях)
- **Очереди**: RabbitMQ (опциональный профиль)
- **Почта**: Mailhog (доступен во всех профилях)
- **Мониторинг**: Grafana, Prometheus, Loki, Promtail, Node Exporter
- **Управление**: Portainer Agent
- **Бэкапы**: Автоматическая система бэкапов

## 🚀 Быстрый старт

### 1. Настройка окружения

```bash
# Локальная разработка
cp .env.local.example .env
# или для продакшн
cp .env.prod.example .env

# Отредактируйте переменные под ваши нужды
nano .env
```

### 2. Автоматическая конфигурация

```bash
# Автоопределение железа + генерация конфигов
make auto-config

# Принудительная перезапись (если уже есть конфиги)
make auto-config-force

# Для продакшн
make auto-config-prod

# Предварительный просмотр
make auto-config-preview
```

### 3. Запуск проекта

```bash
# Локальная разработка (все сервисы)
make init-local

# Продакшн (все сервисы, оптимизированные конфиги)
make init-prod

# С мониторингом (все сервисы + Grafana, Prometheus, Loki)
make init-monitoring

# Альтернативные команды через docker compose:
# Только основные сервисы
docker compose up -d

# Основные + мониторинг
docker compose --profile monitoring up -d

# Основные + бэкапы
docker compose --profile backup up -d

# Все профили сразу
docker compose --profile monitoring --profile backup --profile portainer up -d
```

## Переменные окружения

### Общие настройки

| Переменная | Описание | Значения |
|------------|----------|----------|
| `TZ` | Временная зона | Europe/Moscow<br>**Важно**: Если переменная пустая или не задана, используется UTC (+00:00) |
| `ENVIRONMENT` | Окружение | local/dev/prod |
| `DEBUG` | Режим отладки | 0/1 |
| `DOMAIN` | Доменное имя | example.com |
| `EMAIL` | Email администратора | admin@example.com |
| `SSL` | Тип SSL сертификата | 0 - без SSL<br>1 - собственные сертификаты<br>2 - Let's Encrypt |
| `UGN` | Имя пользователя | bitrix |
| `UID/GID` | ID пользователя/группы | 1000 |

### Порты

| Переменная | Описание | Значение по умолчанию |
|------------|----------|----------------------|
| `HTTP_PORT` | HTTP порт | 80 |
| `HTTPS_PORT` | HTTPS порт | 443 |
| `DB_PORT` | MySQL порт (локально) | 3306 |
| `REDIS_PORT` | Redis порт (локально) | 6379 |
| `RABBIT_PORT` | RabbitMQ AMQP порт | 5672 |
| `RABBIT_UI_PORT` | RabbitMQ UI порт | 15672 |
| `GRAFANA_PORT` | Grafana порт | 3000 |
| `PROMETHEUS_PORT` | Prometheus порт | 9090 |
| `PORTAINER_PORT` | Portainer Agent порт | 9443 |

### PHP настройки

| Переменная | Описание | Значения |
|------------|----------|----------|
| `PHP_VERSION` | Версия PHP | 7.4 или 8.3 |
| `BITRIX_VM_VER` | Версия Bitrix VM | 7.5.2 |

### База данных

| Переменная | Описание |
|------------|----------|
| `DB_HOST` | Хост БД (mysql для локального контейнера или внешний сервер) |
| `DB_NAME` | Имя базы данных |
| `DB_USERNAME` | Пользователь БД |
| `DB_PASSWORD` | Пароль БД |
| `DB_ROOT_PASSWORD` | Root пароль MySQL |
| `REDIS_HOST` | Хост Redis (redis для локального или внешний сервер) |
| `MEMCACHED_HOST` | Хост Memcached (memcached для локального или внешний) |

### Настройки бэкапов

| Переменная | Описание | Пример |
|------------|----------|---------|
| `BACKUP_SCHEDULE_DB` | Расписание бэкапа БД | 0 2 * * * |
| `BACKUP_SCHEDULE_FILES` | Расписание бэкапа файлов | 0 3 * * * |
| `BACKUP_RETENTION_DAYS` | Количество дней хранения | 7 |
| `BACKUP_PATH` | Путь для бэкапов | ./backups |

## 🔧 Команды управления

### Основные команды:
```bash
# Инициализация и запуск
make init-local              # Полная инициализация для локальной разработки
make init-prod               # Полная инициализация для продакшн
make up-local                # Запуск локальной среды
make up-prod                 # Запуск продакшн среды
make restart-local           # Перезапуск локальной среды
make down-local              # Остановка локальной среды

# Автоконфигурация
make auto-config             # Автоматическая конфигурация
make auto-config-force       # Принудительная автоконфигурация
make auto-config-prod        # Автоконфигурация для продакшн
make auto-config-preview     # Предварительный просмотр

# Ручная конфигурация
make auto-config-manual CPU_CORES=8 RAM_GB=16
```

### Управление сайтами:
```bash
make site-add DOMAIN=example.com         # Добавить новый сайт
make site-remove DOMAIN=example.com      # Удалить сайт
make site-list                           # Список всех сайтов
make bitrix-site DOMAIN=mysite.local     # Создать Bitrix сайт
make site-clone FROM=old.com TO=new.com  # Клонировать сайт
```

### SSL сертификаты:
```bash
make ssl-generate DOMAIN=example.com     # Создать SSL сертификат
make ssl-remove DOMAIN=example.com       # Удалить SSL сертификат
```

### Бэкапы:
```bash
make backup-db                           # Бэкап базы данных
make backup-files                        # Бэкап файлов
make backup-full                         # Полный бэкап
make backup-list                         # Список бэкапов
make backup-restore-db FILE=backup.sql.gz
make backup-restore-files FILE=backup.tar.gz
```

### Мониторинг и логи:
```bash
make logs-nginx-local                    # Логи Nginx
make logs-php-local                      # Логи PHP-FPM
make status-local                        # Статус контейнеров
```

### Переключение окружений:
```bash
make set-local                           # Переключиться на local
make set-dev                             # Переключиться на dev
make set-prod                            # Переключиться на prod
```

### Помощь:
```bash
make help                                # Основная справка
make help-sites                          # Справка по управлению сайтами
make help-backup                         # Справка по бэкапам
make help-autoconfig                     # Справка по автоконфигурации
```

## 📁 Структура проекта

```
b-docker/
├── docker-compose.yml                  # Единый compose файл
├── Makefile                            # Команды управления
├── .env.local.example                  # Пример для локальной разработки
├── .env.prod.example                   # Пример для продакшн
├── docker/                            # Dockerfile'ы сервисов
│   ├── nginx/                         # Nginx + PHP-FPM
│   ├── php/                           # PHP контейнеры
│   ├── mysql/                         # MySQL
│   ├── redis/                         # Redis
│   ├── memcached/                     # Memcached
│   ├── mailhog/                       # MailHog (dev)
│   └── backup/                        # Система бэкапов
├── config/                            # Конфигурационные файлы
│   ├── nginx/                         # Настройки Nginx
│   ├── php/                           # Настройки PHP
│   ├── mysql/                         # Настройки MySQL
│   ├── redis/                         # Настройки Redis
│   └── grafana/                       # Настройки мониторинга
├── scripts/                           # Утилиты
│   ├── auto-config.sh                 # Автоконфигурация
│   ├── site-manager.sh                # Управление сайтами
│   └── backup-manager.sh              # Управление бэкапами
└── www/                               # Код проектов
    └── [домен]/                       # Папка сайта
```

## 🔍 Диагностика

### Проверка конфигурации:
```bash
# Валидация docker-compose
docker compose -f docker-compose.yml config

# Проверка Nginx конфигурации
make check-nginx-local

# Тест PHP
make bash-cli-local
php -v
```

### Логи и отладка:
```bash
# Все логи в ./volume/logs/
ls -la volume/logs/

# Логи конкретного сервиса
make logs-nginx-local
make logs-php-local

# Статус всех контейнеров
make status-local
```

## 🚨 Безопасность

### Продакшн рекомендации:
1. **Смените все пароли** в `.env` файле
2. **Отключите debug режимы** (`DEBUG=0`)
3. **Рассмотрите внешние сервисы** для БД и Redis (опционально)
4. **Настройте файрвол** для открытых портов
5. **Включите SSL** (`SSL=2` для Let's Encrypt)
6. **Ротируйте логи** и настройте мониторинг

### Переменные окружения для продакшн:
```bash
ENVIRONMENT=prod
DEBUG=0
# Для локальных сервисов:
DB_HOST=mysql
REDIS_HOST=redis
# Или для внешних сервисов:
# DB_HOST=external-mysql.server.com
# REDIS_HOST=external-redis.server.com
GRAFANA_ADMIN_PASSWORD=strong_password
PORTAINER_AGENT_SECRET=strong_secret
```

## SSL Сертификаты

Поддерживается три режима работы с SSL:

### SSL=0 - Без SSL
- HTTP доступ по порту 80
- Подходит для локальной разработки

### SSL=1 - Собственные сертификаты
- Поместите сертификаты в директорию `./ssl/`
- Файлы: `domain.crt` и `domain.key`
- HTTPS доступ по порту 443

### SSL=2 - Let's Encrypt
- Автоматическое получение бесплатных сертификатов
- Требует настройки DNS на ваш сервер
- Автоматическое обновление сертификатов

## Мониторинг

### Grafana
- **URL**: http://localhost:3000
- **Логин**: admin
- **Пароль**: admin (изменить в продакшн!)

### Prometheus
- **URL**: http://localhost:9090
- Сбор метрик со всех сервисов

### Доступные дашборды
- Системные метрики сервера
- Метрики Docker контейнеров
- Метрики Nginx
- Метрики MySQL
- Метрики Redis
- Метрики RabbitMQ
- Логи приложений

## Бэкапы

### Автоматические бэкапы
Система автоматически создает бэкапы согласно расписанию:
- База данных: ежедневно в 2:00
- Файлы: ежедневно в 3:00
- Очистка старых бэкапов: еженедельно в воскресенье в 4:00
- Полный бэкап: еженедельно в субботу в 1:00

### Структура бэкапов
```
./backups/
├── database/
│   ├── db_backup_20240915_020000.sql.gz
│   └── ...
└── files/
    ├── files_backup_20240915_030000.tar.gz
    └── ...
```

### Ручные бэкапы
Можно создавать бэкапы вручную с помощью команд make (см. выше).

## Portainer Agent

Для централизованного управления контейнерами установите Portainer на центральный сервер и подключите агенты:

1. Запустите агент: `make portainer-up` или `make portainer-up-prod`
2. В Portainer добавьте новый endpoint типа "Agent"
3. Укажите IP сервера и порт из `PORTAINER_PORT`
4. Используйте секрет из `PORTAINER_AGENT_SECRET`

## Сетевой доступ

### Локальная разработка
1. Установите в `.env` переменную `DOMAIN=bitrix.local`
2. Добавьте в файл hosts:
   - **Windows**: `C:\Windows\System32\drivers\etc\hosts`
   - **macOS/Linux**: `/etc/hosts`
   - Строка: `127.0.0.1 bitrix.local`

### Удаленный доступ
- HTTP: `http://YOUR_SERVER_IP:HTTP_PORT`
- HTTPS: `https://YOUR_SERVER_IP:HTTPS_PORT`

## Безопасность

### Обязательные изменения для продакшн:
1. Смените все пароли в `.env.prod`
2. Установите `DEBUG=0`
3. Настройте SSL сертификаты (`SSL=2` для Let's Encrypt)
4. Ограничьте доступ к портам мониторинга через firewall
5. Настройте backup на внешнее хранилище
6. Используйте внешние MySQL и Redis сервера

### Рекомендации:
- Регулярно обновляйте Docker образы
- Мониторьте логи безопасности
- Используйте сильные пароли
- Настройте автоматические обновления системы

## Настройка временной зоны

Все контейнеры автоматически настраивают временную зону в соответствии с переменной `TZ` из файла `.env`:

- **Если TZ установлена** (например, `TZ=Europe/Moscow`): используется указанная зона
- **Если TZ пустая или не задана**: автоматически используется UTC (+00:00)
- **MySQL**: временная зона базы данных устанавливается в UTC (+00:00) для обеспечения консистентности
- **Контейнеры**: все системные часы контейнеров синхронизируются с указанной временной зоной

## Работа с мультисайтами

Система поддерживает размещение нескольких сайтов в одном Docker окружении. Каждый сайт имеет свою директорию в `./www/` и может использовать разные версии PHP.

### Примеры использования

#### Создание нескольких сайтов
```bash
# Создание основного сайта
make site-add DOMAIN=main-site.com PHP_VERSION=8.3

# Создание тестового сайта
make site-add DOMAIN=test.local PHP_VERSION=7.4

# Создание Bitrix сайта
make bitrix-site DOMAIN=shop.local PHP_VERSION=8.3

# Просмотр всех сайтов
make site-list
```

#### Работа с бэкапами для конкретных сайтов
```bash
# Бэкап конкретного сайта
make backup-full SITE=main-site.com

# Бэкап только файлов
make backup-files SITE=test.local

# Бэкап только базы данных
make backup-db SITE=shop.local

# Восстановление сайта
make backup-restore-files FILE=test_local_20240101_120000.tar.gz SITE=test.local
```

#### Управление SSL сертификатами
```bash
# Создание SSL для всех сайтов
make ssl-generate DOMAIN=main-site.com
make ssl-generate DOMAIN=test.local
make ssl-generate DOMAIN=shop.local

# Клонирование готового сайта
make site-clone FROM=main-site.com TO=staging.main-site.com
```

### Структура проекта с мультисайтами
```
./www/
├── main-site.com/
│   └── www/
│       ├── index.php
│       └── bitrix/
├── test.local/
│   └── www/
│       └── index.php
└── shop.local/
    └── www/
        ├── index.php
        ├── bitrix/
        └── upload/

./config/nginx/conf/
├── main-site.com.conf
├── test.local.conf
├── shop.local.conf
├── ssl_main-site.com.conf
├── ssl_test.local.conf
└── ssl_shop.local.conf

./ssl/
├── main-site.com.crt
├── main-site.com.key
├── test.local.crt
├── test.local.key
├── shop.local.crt
└── shop.local.key
```

### Автоматическая конфигурация системы

Docker окружение поддерживает автоматическую генерацию оптимальных конфигураций на основе характеристик вашего сервера:

```bash
# Автоматическая конфигурация с детектом железа
make auto-config                     # Для текущего окружения
make auto-config-force               # С принудительной перезаписью
make auto-config-prod                # Для продакшн окружения

# Предварительный просмотр
make auto-config-preview             # Посмотреть что будет сгенерировано

# Ручное указание параметров
make auto-config-manual CPU_CORES=8 RAM_GB=16
```

#### Что автоматически настраивается:

- **MySQL**: buffer pool, connections, cache размеры
- **Nginx**: worker processes, connections, client limits
- **Redis**: memory limits, databases, persistence
- **PHP-FPM**: process manager, memory limits, opcache
- **Переменные окружения**: оптимальные значения для контейнеров

#### Пример автодетекта:
```
Обнаружено: 12 CPU cores, 64GB RAM
- MySQL buffer pool: 19.6GB (60% RAM)
- Nginx workers: 12 (по количеству ядер)
- PHP-FPM children: 60 (5 на ядро)
- Redis memory: 16GB (25% RAM)
```

### Быстрые команды помощи
```bash
make help           # Показать основные команды
make help-sites     # Показать команды управления сайтами
make help-backup    # Показать команды управления бэкапами
make help-autoconfig # Показать команды автоконфигурации
```

## Устранение неполадок

### Проверка статуса
```bash
make status-local          # Локально
make status                # Продакшн
```

### Просмотр логов
```bash
make logs-nginx-local      # Логи Nginx
make logs-php-local        # Логи PHP
```

### Перезапуск сервисов
```bash
make restart-local         # Локально
make restart               # Продакшн
```

### Очистка системы
```bash
make clean-all             # Полная очистка Docker
```

## Требования к системе

### Минимальные:
- Docker 20.10+
- Docker Compose 2.0+
- 4GB RAM
- 20GB свободного места

### Рекомендуемые:
- 8GB+ RAM
- SSD диск
- 100GB+ свободного места
- Регулярные бэкапы

## 🤝 Поддержка

Для получения помощи:
- Используйте `make help` для списка команд
- Проверьте логи: `make logs-nginx-local` или `make logs-php-local`
- Запустите диагностику: `make status-local`

---

**Создано с ❤️ для эффективной разработки на Bitrix**