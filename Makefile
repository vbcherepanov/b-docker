#!make
ifneq ("$(wildcard .env)","")
  include .env
  export
endif

DOCKER_COMPOSE = docker compose
DOCKER_COMPOSE_LOCAL = docker compose --profile local --profile dev
DOCKER_COMPOSE_PROD = docker compose --profile monitoring --profile backup
UID ?= $(shell id -u)
GID ?= $(shell id -g)
UGN ?=bitrix
NETWORK_NAME ?=nginx_webnet

.PHONY: reload-cron up init down build docker-build docker-up docker-down-clear test init composer-install cli cron-agent tests-run init-system create-unit-test create_dump monitoring-up monitoring-down portainer-up portainer-down backup-db backup-files backup-full set-local set-dev set-prod ssl-generate logs-nginx logs-php status clean-volumes clean-images clean-all disk-usage

# === НОВЫЕ КОМАНДЫ ЕДИНОГО DOCKER-COMPOSE ===

# Локальная разработка (с MySQL, Redis, MailHog)
up-local: build-base docker-local-build docker-local-up nginx_local_start
init-local: docker-down-clear-local docker-network-create build-base docker-local-build docker-local-up nginx_local_start
restart-local: docker-down-local docker-network-create build-base docker-local-build docker-local-up nginx_local_start
down-local: docker-local-down-clear

# Продакшн (без локальных сервисов)
up-prod: build-base docker-prod-build docker-prod-up nginx_start
init-prod: docker-down-clear-prod docker-network-create build-base docker-prod-build docker-prod-up nginx_start
restart-prod: docker-down-prod docker-network-create build-base docker-prod-build docker-prod-up nginx_start
down-prod: docker-prod-down-clear

# С мониторингом
up-monitoring: build-base docker-monitoring-build docker-monitoring-up nginx_start
restart-monitoring: docker-down-monitoring docker-network-create build-base docker-monitoring-build docker-monitoring-up nginx_start
down-monitoring: docker-monitoring-down-clear

# Полный стек с мониторингом для local/dev
up-local-monitoring: build-base docker-local-monitoring-build docker-local-monitoring-up nginx_local_start
restart-local-monitoring: docker-down-local-monitoring docker-network-create build-base docker-local-monitoring-build docker-local-monitoring-up nginx_local_start
down-local-monitoring: docker-local-monitoring-down-clear

# Совместимость со старыми командами
up: up-local
init: init-local
restart: restart-local
down: down-local
build: docker-build

build-base: build-base-cli build-base-fpm

build-base-cli:
	docker build --build-arg UGN=$(UGN) --build-arg UID=$(UID) --build-arg GID=$(GID)  --build-arg ENVIRONMENT=$(ENVIRONMENT)  --build-arg DEBUG=$(DEBUG) \
		-t my/php-base-cli:$(PHP_VERSION) -f docker/php/base/cli/$(PHP_VERSION)/Dockerfile .

build-base-fpm:
	docker build --build-arg UGN=$(UGN) --build-arg UID=$(UID) --build-arg GID=$(GID)  --build-arg ENVIRONMENT=$(ENVIRONMENT)  --build-arg DEBUG=$(DEBUG) \
		-t my/php-base-fpm:$(PHP_VERSION) -f docker/php/base/fpm/$(PHP_VERSION)/Dockerfile .

docker-network-create:
	@if ! docker network inspect $(NETWORK_NAME) >/dev/null 2>&1; then \
		echo "Creating external network '$(NETWORK_NAME)'..."; \
		docker network create $(NETWORK_NAME); \
	else \
		echo "Network '$(NETWORK_NAME)' already exists."; \
	fi

# === НОВЫЕ DOCKER COMPOSE КОМАНДЫ ===

# Локальная разработка
docker-local-build:
	$(DOCKER_COMPOSE_LOCAL) build --build-arg PHP_VERSION=${PHP_VERSION}

docker-local-up:
	$(DOCKER_COMPOSE_LOCAL) up -d

docker-local-down:
	$(DOCKER_COMPOSE_LOCAL) down

docker-local-down-clear:
	$(DOCKER_COMPOSE_LOCAL) down -v --remove-orphans

# Продакшн
docker-prod-build:
	$(DOCKER_COMPOSE_PROD) build --build-arg PHP_VERSION=${PHP_VERSION}

docker-prod-up:
	$(DOCKER_COMPOSE_PROD) up -d

docker-prod-down:
	$(DOCKER_COMPOSE_PROD) down

docker-prod-down-clear:
	$(DOCKER_COMPOSE_PROD) down -v --remove-orphans

# Мониторинг
docker-monitoring-build:
	$(DOCKER_COMPOSE) --profile monitoring build --build-arg PHP_VERSION=${PHP_VERSION}

docker-monitoring-up:
	$(DOCKER_COMPOSE) --profile monitoring up -d

docker-monitoring-down:
	$(DOCKER_COMPOSE) --profile monitoring down

docker-monitoring-down-clear:
	$(DOCKER_COMPOSE) --profile monitoring down -v --remove-orphans

# Локальная разработка + мониторинг
docker-local-monitoring-build:
	$(DOCKER_COMPOSE) --profile local --profile dev --profile monitoring build --build-arg PHP_VERSION=${PHP_VERSION}

docker-local-monitoring-up:
	$(DOCKER_COMPOSE) --profile local --profile dev --profile monitoring up -d

docker-local-monitoring-down:
	$(DOCKER_COMPOSE) --profile local --profile dev --profile monitoring down

docker-local-monitoring-down-clear:
	$(DOCKER_COMPOSE) --profile local --profile dev --profile monitoring down -v --remove-orphans

# Совместимость со старыми командами
docker-build: docker-local-build
docker-up: docker-local-up
docker-down: docker-local-down
docker-down-clear: docker-local-down-clear
docker-down-clear-local: docker-local-down-clear
docker-local-pull:
	$(DOCKER_COMPOSE_LOCAL) pull
docker-pull:
	$(DOCKER_COMPOSE) pull
reload-local-cron:
	$(DOCKER_COMPOSE_LOCAL) restart cron
reload-cron:
	$(DOCKER_COMPOSE) restart cron
composer-local-install:
	$(DOCKER_COMPOSE_LOCAL) run --rm php-cli composer install
composer-install:
	$(DOCKER_COMPOSE) run --rm php-cli composer install

tests-local-run:
	$(DOCKER_COMPOSE_LOCAL) run --rm php-cli composer test
tests-run:
	$(DOCKER_COMPOSE) run --rm php-cli composer test
create-unit-test:
	$(DOCKER_COMPOSE) run --rm php-cli php vendor/bin/codecept init unit

restore_dump:
	$(DOCKER_COMPOSE) exec mysql bash -c "mysql -u root -p'${DB_ROOT_PASSWORD}' ${DB_NAME} < /dump/dump.sql"
restore_local_dump:
	$(DOCKER_COMPOSE_LOCAL) exec mysql bash -c "mysql -u root -p'${DB_ROOT_PASSWORD}' ${DB_NAME} < /dump/dump.sql"
create_dump:
	$(DOCKER_COMPOSE) exec mysql bash -c "mysqldump -u root -p'${DB_ROOT_PASSWORD}' ${DB_NAME} | gzip > /dump/dump.sql.gz"
create_dump_local:
	$(DOCKER_COMPOSE_LOCAL) exec mysql bash -c "mysqldump -u root -p'${DB_ROOT_PASSWORD}' ${DB_NAME} | gzip > /dump/dump.sql.gz"
add_local_ssl:
	$(DOCKER_COMPOSE_LOCAL) exec nginx bash -c "/usr/local/bin/script/ssl.sh ${DOMAIN} ${SSL}"
add_ssl:
	$(DOCKER_COMPOSE) exec nginx bash -c "/usr/local/bin/script/ssl.sh ${DOMAIN} ${SSL}"
add_local_site:
	$(DOCKER_COMPOSE_LOCAL) exec --user root nginx bash -c "/usr/local/bin/script/site.sh $(word 2, $(MAKECMDGOALS))"
	$(DOCKER_COMPOSE_LOCAL) exec --user root php-fpm bash -c "/usr/local/bin/add_site.sh $(word 2, $(MAKECMDGOALS))"
add_site:
	$(DOCKER_COMPOSE) exec --user root nginx bash -c "/usr/local/bin/script/site.sh $(word 2, $(MAKECMDGOALS))"
	$(DOCKER_COMPOSE) exec --user root php-fpm bash -c "/usr/local/bin/add_site.sh $(word 2, $(MAKECMDGOALS))"

nginx_start:
	$(DOCKER_COMPOSE) exec --user root nginx bash -c "/usr/local/bin/script/main.sh"
nginx_local_start:
	$(DOCKER_COMPOSE_LOCAL) exec --user root nginx bash -c "/usr/local/bin/script/main.sh"

add_local_rabbit:
	@RABBIT_CONFIG=${RABBIT_CONFIG} DOMAIN=${DOMAIN} \
	$(DOCKER_COMPOSE_LOCAL) exec nginx bash -c "/usr/local/bin/script/rabbit.sh $${1:-$$RABBIT_CONFIG} $${2:-$$DOMAIN}"
add_rabbit:
	@RABBIT_CONFIG=${RABBIT_CONFIG} DOMAIN=${DOMAIN} \
	$(DOCKER_COMPOSE) exec nginx bash -c "/usr/local/bin/script/rabbit.sh $${1:-$$RABBIT_CONFIG} $${2:-$$DOMAIN}"
add_local_mail:
	$(DOCKER_COMPOSE_LOCAL) exec nginx bash -c "/usr/local/bin/script/mail.sh ${MAIL_CONFIG} ${DOMAIN}"
add_mail:
	$(DOCKER_COMPOSE) exec nginx bash -c "/usr/local/bin/script/mail.sh ${MAIL_CONFIG} ${DOMAIN}"
check_local_nginx:
	$(DOCKER_COMPOSE_LOCAL) exec nginx bash -c "nginx -t"
check_nginx:
	$(DOCKER_COMPOSE) exec nginx bash -c "nginx -t"
reload_local_nginx:
	$(DOCKER_COMPOSE_LOCAL) exec nginx bash -c "nginx -s reload"
reload_nginx:
	$(DOCKER_COMPOSE) exec nginx bash -c "nginx -s reload"
bash_local_nginx:
	$(DOCKER_COMPOSE_LOCAL) exec nginx bash
bash_nginx:
	$(DOCKER_COMPOSE) exec nginx bash
bash_cli:
	$(DOCKER_COMPOSE) exec php-cli bash
bash_cli_local:
	$(DOCKER_COMPOSE_LOCAL) exec php-cli bash

# Команды для мониторинга
monitoring-up:
	$(DOCKER_COMPOSE_LOCAL) --profile monitoring up -d
monitoring-up-prod:
	$(DOCKER_COMPOSE) --profile monitoring up -d
monitoring-down:
	$(DOCKER_COMPOSE_LOCAL) --profile monitoring down
monitoring-down-prod:
	$(DOCKER_COMPOSE) --profile monitoring down

# Команды для Portainer Agent
portainer-up:
	$(DOCKER_COMPOSE_LOCAL) --profile portainer up -d
portainer-up-prod:
	$(DOCKER_COMPOSE) --profile portainer up -d
portainer-down:
	$(DOCKER_COMPOSE_LOCAL) --profile portainer down
portainer-down-prod:
	$(DOCKER_COMPOSE) --profile portainer down

# Команды для бэкапов (старые, используют контейнер backup)
backup-db-local:
	$(DOCKER_COMPOSE_LOCAL) exec backup /scripts/backup.sh database
backup-db-container:
	$(DOCKER_COMPOSE) exec backup /scripts/backup.sh database
backup-files-local:
	$(DOCKER_COMPOSE_LOCAL) exec backup /scripts/backup.sh files
backup-files-container:
	$(DOCKER_COMPOSE) exec backup /scripts/backup.sh files
backup-full-local:
	$(DOCKER_COMPOSE_LOCAL) exec backup /scripts/backup.sh full
backup-full-container:
	$(DOCKER_COMPOSE) exec backup /scripts/backup.sh full
backup-cleanup-container:
	$(DOCKER_COMPOSE) exec backup /scripts/backup.sh cleanup

# Команды для работы с окружениями
set-local:
	cp .env.local .env
set-dev:
	cp .env.dev .env
set-prod:
	cp .env.prod .env

# Команды для SSL (старые, используют контейнер nginx)
ssl-generate-local:
	$(DOCKER_COMPOSE_LOCAL) exec nginx /usr/local/bin/script/ssl.sh ${DOMAIN} ${SSL}
ssl-generate-container:
	$(DOCKER_COMPOSE) exec nginx /usr/local/bin/script/ssl.sh ${DOMAIN} ${SSL}

# Команды для логов
logs-nginx-local:
	$(DOCKER_COMPOSE_LOCAL) logs -f nginx
logs-nginx:
	$(DOCKER_COMPOSE) logs -f nginx
logs-php-local:
	$(DOCKER_COMPOSE_LOCAL) logs -f php-fpm
logs-php:
	$(DOCKER_COMPOSE) logs -f php-fpm
logs-mysql-local:
	$(DOCKER_COMPOSE_LOCAL) logs -f mysql
logs-grafana-local:
	$(DOCKER_COMPOSE_LOCAL) logs -f grafana
logs-grafana:
	$(DOCKER_COMPOSE) logs -f grafana
logs-backup-local:
	$(DOCKER_COMPOSE_LOCAL) logs -f backup
logs-backup:
	$(DOCKER_COMPOSE) logs -f backup

# Команды для проверки статуса
status-local:
	$(DOCKER_COMPOSE_LOCAL) ps
status:
	$(DOCKER_COMPOSE) ps

# Команды для очистки
clean-volumes:
	docker volume prune -f
clean-images:
	docker image prune -f
clean-all:
	docker system prune -af

# Команды для мониторинга дискового пространства
disk-usage:
	df -h
	docker system df

# ==========================================
# УПРАВЛЕНИЕ САЙТАМИ
# ==========================================

# Добавление нового сайта
# Использование: make site-add DOMAIN=example.com PHP_VERSION=8.3
site-add:
	@if [ -z "$(DOMAIN)" ]; then \
		echo "ОШИБКА: Необходимо указать DOMAIN. Пример: make site-add DOMAIN=example.com"; \
		exit 1; \
	fi
	@./docker/common/scripts/site-manager.sh add "$(DOMAIN)" "$(PHP_VERSION)"

# Удаление сайта
# Использование: make site-remove DOMAIN=example.com
site-remove:
	@if [ -z "$(DOMAIN)" ]; then \
		echo "ОШИБКА: Необходимо указать DOMAIN. Пример: make site-remove DOMAIN=example.com"; \
		exit 1; \
	fi
	@./docker/common/scripts/site-manager.sh remove "$(DOMAIN)"

# Список всех сайтов
site-list:
	@./docker/common/scripts/site-manager.sh list

# Создание SSL сертификата для сайта
# Использование: make ssl-generate DOMAIN=example.com
ssl-generate:
	@if [ -z "$(DOMAIN)" ]; then \
		echo "ОШИБКА: Необходимо указать DOMAIN. Пример: make ssl-generate DOMAIN=example.com"; \
		exit 1; \
	fi
	@./docker/common/scripts/site-manager.sh ssl "$(DOMAIN)" generate

# Удаление SSL сертификата
# Использование: make ssl-remove DOMAIN=example.com
ssl-remove:
	@if [ -z "$(DOMAIN)" ]; then \
		echo "ОШИБКА: Необходимо указать DOMAIN. Пример: make ssl-remove DOMAIN=example.com"; \
		exit 1; \
	fi
	@./docker/common/scripts/site-manager.sh ssl "$(DOMAIN)" remove

# ==========================================
# СИСТЕМА БЭКАПОВ
# ==========================================

# Бэкап базы данных
# Использование: make backup-db [SITE=example.com]
backup-db:
	@./docker/common/scripts/backup-manager.sh database $(SITE)

# Бэкап файлов
# Использование: make backup-files [SITE=example.com]
backup-files:
	@./docker/common/scripts/backup-manager.sh files $(SITE)

# Полный бэкап (база + файлы)
# Использование: make backup-full [SITE=example.com]
backup-full:
	@./docker/common/scripts/backup-manager.sh full $(SITE)

# Очистка старых бэкапов
backup-cleanup:
	@./docker/common/scripts/backup-manager.sh cleanup

# Список бэкапов
backup-list:
	@./docker/common/scripts/backup-manager.sh list

# Список бэкапов БД
backup-list-db:
	@./docker/common/scripts/backup-manager.sh list database

# Список бэкапов файлов
backup-list-files:
	@./docker/common/scripts/backup-manager.sh list files

# Восстановление базы данных
# Использование: make backup-restore-db FILE=backup.sql.gz [DB_NAME=database_name]
backup-restore-db:
	@if [ -z "$(FILE)" ]; then \
		echo "ОШИБКА: Необходимо указать FILE. Пример: make backup-restore-db FILE=backup.sql.gz"; \
		exit 1; \
	fi
	@./docker/common/scripts/backup-manager.sh restore database "$(FILE)" $(DB_NAME)

# Восстановление файлов
# Использование: make backup-restore-files FILE=backup.tar.gz [SITE=example.com]
backup-restore-files:
	@if [ -z "$(FILE)" ]; then \
		echo "ОШИБКА: Необходимо указать FILE. Пример: make backup-restore-files FILE=backup.tar.gz"; \
		exit 1; \
	fi
	@./docker/common/scripts/backup-manager.sh restore files "$(FILE)" $(SITE)

# ==========================================
# БЫСТРЫЕ КОМАНДЫ ДЛЯ МУЛЬТИСАЙТОВ
# ==========================================

# Создание Bitrix сайта с автоматической настройкой
# Использование: make bitrix-site DOMAIN=my-site.local [PHP_VERSION=8.3]
bitrix-site: site-add
	@echo "Создание структуры Bitrix для $(DOMAIN)..."
	@mkdir -p www/$(DOMAIN)/www/bitrix
	@mkdir -p www/$(DOMAIN)/www/upload
	@echo "Структура Bitrix создана для $(DOMAIN)"
	@echo "Перезапустите контейнеры: make restart-$(ENVIRONMENT)"

# Клонирование существующего сайта
# Использование: make site-clone FROM=source.com TO=target.com
site-clone:
	@if [ -z "$(FROM)" ] || [ -z "$(TO)" ]; then \
		echo "ОШИБКА: Необходимо указать FROM и TO. Пример: make site-clone FROM=source.com TO=target.com"; \
		exit 1; \
	fi
	@if [ ! -d "www/$(FROM)" ]; then \
		echo "ОШИБКА: Сайт-источник $(FROM) не найден"; \
		exit 1; \
	fi
	@echo "Клонирование сайта $(FROM) в $(TO)..."
	@cp -r www/$(FROM) www/$(TO)
	@./docker/common/scripts/site-manager.sh add "$(TO)" "$(PHP_VERSION)"
	@echo "Сайт $(TO) создан как копия $(FROM)"
	@echo "Перезапустите контейнеры: make restart-$(ENVIRONMENT)"

# ==========================================
# АВТОКОНФИГУРАЦИЯ СИСТЕМЫ
# ==========================================

# Автоматическая конфигурация на основе характеристик системы
auto-config:
	@./docker/common/scripts/auto-config.sh --environment $(ENVIRONMENT)

# Автоконфигурация с принудительной перезаписью
auto-config-force:
	@./docker/common/scripts/auto-config.sh --environment $(ENVIRONMENT) --force

# Автоконфигурация для продакшн
auto-config-prod:
	@./docker/common/scripts/auto-config.sh --environment prod --force

# Предварительный просмотр автоконфигурации
auto-config-preview:
	@./docker/common/scripts/auto-config.sh --environment $(ENVIRONMENT) --dry-run

# Ручная конфигурация с указанием параметров
# Использование: make auto-config-manual CPU_CORES=8 RAM_GB=16
auto-config-manual:
	@if [ -z "$(CPU_CORES)" ] || [ -z "$(RAM_GB)" ]; then \
		echo "ОШИБКА: Необходимо указать CPU_CORES и RAM_GB. Пример: make auto-config-manual CPU_CORES=8 RAM_GB=16"; \
		exit 1; \
	fi
	@./docker/common/scripts/auto-config.sh --cpu-cores $(CPU_CORES) --ram-gb $(RAM_GB) --environment $(ENVIRONMENT) --force

# ==========================================
# ПОМОЩЬ И ИНФОРМАЦИЯ
# ==========================================

# Показать помощь по управлению сайтами
help-sites:
	@echo "Команды управления сайтами:"
	@echo "  make site-add DOMAIN=example.com [PHP_VERSION=8.3]  - Добавить сайт"
	@echo "  make site-remove DOMAIN=example.com                 - Удалить сайт"
	@echo "  make site-list                                      - Список сайтов"
	@echo "  make bitrix-site DOMAIN=example.com                 - Создать Bitrix сайт"
	@echo "  make site-clone FROM=source.com TO=target.com       - Клонировать сайт"
	@echo ""
	@echo "Команды SSL:"
	@echo "  make ssl-generate DOMAIN=example.com                - Создать SSL сертификат"
	@echo "  make ssl-remove DOMAIN=example.com                  - Удалить SSL сертификат"

# Показать помощь по бэкапам
help-backup:
	@echo "Команды управления бэкапами:"
	@echo "  make backup-db [SITE=example.com]                   - Бэкап базы данных"
	@echo "  make backup-files [SITE=example.com]                - Бэкап файлов"
	@echo "  make backup-full [SITE=example.com]                 - Полный бэкап"
	@echo "  make backup-cleanup                                 - Очистка старых бэкапов"
	@echo "  make backup-list                                    - Список всех бэкапов"
	@echo "  make backup-list-db                                 - Список бэкапов БД"
	@echo "  make backup-list-files                              - Список бэкапов файлов"
	@echo ""
	@echo "Восстановление:"
	@echo "  make backup-restore-db FILE=backup.sql.gz           - Восстановить БД"
	@echo "  make backup-restore-files FILE=backup.tar.gz        - Восстановить файлы"

# Показать помощь по автоконфигурации
help-autoconfig:
	@echo "Команды автоконфигурации системы:"
	@echo "  make auto-config                                    - Автоконфигурация под текущее окружение"
	@echo "  make auto-config-force                              - Принудительная перезапись конфигов"
	@echo "  make auto-config-prod                               - Автоконфигурация для продакшн"
	@echo "  make auto-config-preview                            - Предварительный просмотр"
	@echo ""
	@echo "Ручная конфигурация:"
	@echo "  make auto-config-manual CPU_CORES=8 RAM_GB=16       - Ручное указание параметров"
	@echo ""
	@echo "Примеры:"
	@echo "  make auto-config                                    - Автодетект для local окружения"
	@echo "  make auto-config-preview                            - Посмотреть что будет сгенерировано"
	@echo "  make auto-config-prod                               - Сгенерировать конфиги для продакшн"
	@echo "  make auto-config-manual CPU_CORES=4 RAM_GB=8        - Для сервера с 4 ядрами и 8GB RAM"

# Показать все доступные команды
help:
	@echo "=== BITRIX DOCKER ENVIRONMENT ==="
	@echo ""
	@echo "Основные команды:"
	@echo "  make init-local     - Полная инициализация (локально)"
	@echo "  make init           - Полная инициализация (продакшн)"
	@echo "  make up-local       - Запуск (локально)"
	@echo "  make up             - Запуск (продакшн)"
	@echo "  make restart-local  - Перезапуск (локально)"
	@echo "  make restart        - Перезапуск (продакшн)"
	@echo "  make down-local     - Остановка (локально)"
	@echo "  make down           - Остановка (продакшн)"
	@echo ""
	@echo "Переключение окружений:"
	@echo "  make set-local      - Переключиться на local"
	@echo "  make set-dev        - Переключиться на dev"
	@echo "  make set-prod       - Переключиться на prod"
	@echo ""
	@echo "Автоконфигурация системы:"
	@echo "  make auto-config         - Автоматическая конфигурация"
	@echo "  make auto-config-force   - Принудительная автоконфигурация"
	@echo "  make auto-config-preview - Предварительный просмотр"
	@echo ""
	@echo "Подробная помощь:"
	@echo "  make help-sites     - Команды управления сайтами"
	@echo "  make help-backup    - Команды управления бэкапами"
	@echo "  make help-autoconfig - Команды автоконфигурации"