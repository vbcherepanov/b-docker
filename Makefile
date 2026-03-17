#!make
ifneq ("$(wildcard .env)","")
  include .env
  export
endif

DOCKER_COMPOSE = docker compose -f docker-compose.bitrix.yml
DOCKER_COMPOSE_LOCAL = docker compose -f docker-compose.bitrix.yml --profile local --profile dev
DOCKER_COMPOSE_PROD = docker compose -f docker-compose.bitrix.yml --profile prod --profile monitoring --profile backup
UID ?= $(shell id -u)
GID ?= $(shell id -g)
UGN ?=bitrix
NETWORK_NAME ?=${DOMAIN}_network
DOCKER_SUBNET ?=172.20.0.0/16

.PHONY: reload-cron up init down build docker-build docker-up docker-down-clear test init composer-install cli cron-agent tests-run init-system create-unit-test create_dump monitoring-up monitoring-down portainer-up portainer-down backup-db backup-files backup-full set-local set-dev set-prod ssl-generate logs-nginx logs-php status clean-volumes clean-images clean-all disk-usage setup first-run quick-start split-local split-prod split-down split-ps split-logs bash-fpm bash-cli bash-cron bash-supervisor split-rebuild-php

# ============================================================================
# 🚀 БЫСТРЫЙ СТАРТ (НАЧАЛО РАБОТЫ С НУЛЯ)
# ============================================================================
# make setup      - Подготовка окружения (генерация секретов, оптимизация, валидация)
# make first-run  - Полная инициализация с нуля (setup + build + up)
# make quick-start - Быстрый запуск для разработки

# Полная подготовка окружения (БЕЗ запуска контейнеров)
setup:
	@echo "╔════════════════════════════════════════════════════════════╗"
	@echo "║          BITRIX DOCKER - ПОДГОТОВКА ОКРУЖЕНИЯ              ║"
	@echo "╚════════════════════════════════════════════════════════════╝"
	@echo ""
	@echo "📋 Шаг 1/4: Генерация безопасных паролей..."
	@chmod +x ./scripts/generate-secrets.sh && ./scripts/generate-secrets.sh --update-env
	@echo ""
	@echo "⚙️  Шаг 2/4: Оптимизация конфигураций под сервер..."
	@chmod +x ./scripts/auto-optimize.sh && ./scripts/auto-optimize.sh --force --update-env
	@echo ""
	@echo "🔒 Шаг 3/4: Применение security fixes..."
	@chmod +x ./scripts/apply-security-fixes.sh && ./scripts/apply-security-fixes.sh
	@echo ""
	@echo "✅ Шаг 4/4: Валидация конфигурации..."
	@chmod +x ./scripts/validate-env.sh && ./scripts/validate-env.sh
	@echo ""
	@echo "╔════════════════════════════════════════════════════════════╗"
	@echo "║  ✅ ПОДГОТОВКА ЗАВЕРШЕНА!                                  ║"
	@echo "║                                                            ║"
	@echo "║  Следующий шаг: make first-run                             ║"
	@echo "╚════════════════════════════════════════════════════════════╝"

# Инициализация основного сайта (мультисайтовая структура + per-site конфиг)
init-main-site:
	@echo "📁 Создание структуры основного сайта $(DOMAIN)..."
	@chmod +x ./scripts/site.sh
	@./scripts/site.sh add $(DOMAIN) --no-confirm $(if $(filter free,$(SSL)),--ssl=letsencrypt) $(if $(filter self,$(SSL)),--ssl)
	@echo "✅ Структура и конфигурация созданы для $(DOMAIN)"

# Полная инициализация с нуля (для первого запуска)
first-run: setup docker-network-create init-main-site ensure-defaults build-base
	@echo ""
	@echo "🏗️  Сборка и запуск контейнеров..."
	$(DOCKER_COMPOSE) $(PROFILES_LOCAL) build
	$(DOCKER_COMPOSE) $(PROFILES_LOCAL) up -d
	@echo "⏳ Ожидание готовности MySQL..."
	@sleep 30
	@echo "🗄️  Инициализация базы данных для $(DOMAIN)..."
	@if [ -f "config/sites/$(DOMAIN)/database-init.sql" ]; then \
		docker exec -i $(DOMAIN)_mysql bash -c 'mysql -uroot -p"$$MYSQL_ROOT_PASSWORD"' < config/sites/$(DOMAIN)/database-init.sql && \
		echo "✅ База данных создана" || \
		echo "⚠️  Ошибка создания БД. Выполни: make db-init SITE=$(DOMAIN)"; \
	else \
		echo "⚠️  config/sites/$(DOMAIN)/database-init.sql не найден, пропуск"; \
	fi
	@echo "🔧 Настройка nginx..."
	@$(DOCKER_COMPOSE) $(PROFILES_LOCAL) exec --user root nginx /usr/local/bin/script/main.sh || true
	@echo ""
	@echo "╔════════════════════════════════════════════════════════════╗"
	@echo "║  🎉 ПЕРВЫЙ ЗАПУСК ЗАВЕРШЁН!                                ║"
	@echo "║                                                            ║"
	@echo "║  🌐 Сайт:      http://$(DOMAIN)                            ║"
	@echo "║  📧 MailHog:   http://$(DOMAIN):8025                       ║"
	@echo "║  📊 Grafana:   http://$(DOMAIN):3000                       ║"
	@echo "║                                                            ║"
	@echo "║  Команды:                                                  ║"
	@echo "║    make local-logs   - Логи                                ║"
	@echo "║    make local-ps     - Статус контейнеров                  ║"
	@echo "║    make local-down   - Остановить                          ║"
	@echo "╚════════════════════════════════════════════════════════════╝"

# Быстрый старт (без полной настройки)
quick-start: docker-network-create build-base
	@echo "🚀 Быстрый старт..."
	$(DOCKER_COMPOSE) $(PROFILES_LOCAL) build
	$(DOCKER_COMPOSE) $(PROFILES_LOCAL) up -d
	@echo "✅ Контейнеры запущены. Статус: make local-ps"

# Первый запуск для production
first-run-prod: setup docker-network-create init-main-site ensure-defaults build-base
	@echo ""
	@echo "🏗️  Сборка и запуск контейнеров (production)..."
	$(DOCKER_COMPOSE) $(PROFILES_PROD) build
	$(DOCKER_COMPOSE) $(PROFILES_PROD) up -d
	@echo "⏳ Ожидание готовности MySQL..."
	@sleep 30
	@echo "🗄️  Инициализация базы данных для $(DOMAIN)..."
	@if [ -f "config/sites/$(DOMAIN)/database-init.sql" ]; then \
		docker exec -i $(DOMAIN)_mysql bash -c 'mysql -uroot -p"$$MYSQL_ROOT_PASSWORD"' < config/sites/$(DOMAIN)/database-init.sql && \
		echo "✅ База данных создана" || \
		echo "⚠️  Ошибка создания БД. Выполни: make db-init SITE=$(DOMAIN)"; \
	else \
		echo "⚠️  config/sites/$(DOMAIN)/database-init.sql не найден, пропуск"; \
	fi
	@$(DOCKER_COMPOSE) $(PROFILES_PROD) exec --user root nginx /usr/local/bin/script/main.sh || true
	@echo ""
	@if [ "$(SSL)" = "free" ]; then \
		echo "🔒 Запрос SSL сертификата и обновление конфига..."; \
		./scripts/site.sh ssl-le $(DOMAIN) && \
		echo "✅ SSL сертификат получен и nginx обновлён" || \
		echo "⚠️  SSL не получен. Запусти позже: make ssl-init"; \
	fi
	@echo ""
	@echo "🔄 Установка автозапуска (systemd)..."
	@if [ "$$(id -u)" = "0" ]; then \
		./scripts/install-service.sh install --yes; \
	else \
		echo "⚠️  Для установки автозапуска нужны права root"; \
		echo "   Выполни: sudo make install-service"; \
	fi
	@echo "🧹 Настройка автоочистки Docker..."
	@if [ "$$(id -u)" = "0" ]; then \
		./scripts/docker-cleanup.sh --setup-cron 2>/dev/null || true; \
	fi
	@echo ""
	@echo "╔════════════════════════════════════════════════════════════╗"
	@echo "║  🎉 PRODUCTION ЗАПУЩЕН!                                    ║"
	@echo "╚════════════════════════════════════════════════════════════╝"
	@echo ""
	@echo "  🌐 Сайт: https://$(DOMAIN)/"
	@echo ""
	@echo "  📋 Следующие шаги:"
	@echo "    1. Установить Bitrix: https://$(DOMAIN)/bitrixsetup.php"
	@echo "    2. Если автозапуск не установился:"
	@echo "       sudo make install-service"
	@echo ""

# Запрос SSL сертификата (использовать после первого запуска если SSL не получен)
ssl-init:
	@echo "🔒 Запрос SSL сертификата для $(DOMAIN)..."
	$(DOCKER_COMPOSE) exec --user root nginx sh -c \
		'. /usr/local/bin/script/func/main.sh && ensure_cert "$(DOMAIN)" "$(LETSENCRYPT_EMAIL)"'
	@echo "🔄 Перезагрузка nginx..."
	$(DOCKER_COMPOSE) exec --user root nginx nginx -s reload
	@echo "✅ SSL настроен для $(DOMAIN)"

# Инициализация БД для сайта (использовать: make db-init SITE=domain.com)
SITE ?= $(DOMAIN)
db-init:
	@echo "🗄️  Инициализация базы данных для $(SITE)..."
	@if [ ! -f "config/sites/$(SITE)/database-init.sql" ]; then \
		echo "❌ Файл config/sites/$(SITE)/database-init.sql не найден"; \
		echo "   Сначала создай сайт: ./scripts/site.sh add $(SITE)"; \
		exit 1; \
	fi
	@docker exec -i $(DOMAIN)_mysql bash -c 'mysql -uroot -p"$$MYSQL_ROOT_PASSWORD"' \
		< config/sites/$(SITE)/database-init.sql && \
		echo "✅ База данных создана для $(SITE)" || \
		(echo "❌ Ошибка. Проверь: docker compose -f docker-compose.bitrix.yml ps mysql"; exit 1)

# Инициализация БД для ВСЕХ сайтов
db-init-all:
	@echo "🗄️  Инициализация баз данных для всех сайтов..."
	@for sql_file in config/sites/*/database-init.sql; do \
		if [ -f "$$sql_file" ]; then \
			site=$$(basename $$(dirname "$$sql_file")); \
			echo "  → $$site..."; \
			docker exec -i $(DOMAIN)_mysql bash -c 'mysql -uroot -p"$$MYSQL_ROOT_PASSWORD"' \
				< "$$sql_file" 2>/dev/null && \
				echo "    ✅ OK" || \
				echo "    ⚠️  Ошибка (возможно уже существует)"; \
		fi; \
	done
	@echo "✅ Готово"

# ============================================================================
# ПРОСТЫЕ КОМАНДЫ ДЛЯ ЗАПУСКА ВСЕГО СТЕКА
# ============================================================================
# make local  - запуск ВСЕГО для локальной разработки
# make dev    - запуск ВСЕГО для dev сервера
# make prod   - запуск ВСЕГО для production

# LOCAL: local + push + monitoring (всё для разработки)
PROFILES_LOCAL = --profile local --profile push --profile monitoring
local: build-base
	$(DOCKER_COMPOSE) $(PROFILES_LOCAL) build
	$(DOCKER_COMPOSE) $(PROFILES_LOCAL) up -d
local-down:
	$(DOCKER_COMPOSE) $(PROFILES_LOCAL) down
local-restart: local-down local
local-logs:
	$(DOCKER_COMPOSE) $(PROFILES_LOCAL) logs -f
local-ps:
	$(DOCKER_COMPOSE) $(PROFILES_LOCAL) ps

# DEV: dev + push + monitoring (для dev сервера)
PROFILES_DEV = --profile dev --profile push --profile monitoring
dev: build-base
	$(DOCKER_COMPOSE) $(PROFILES_DEV) build
	$(DOCKER_COMPOSE) $(PROFILES_DEV) up -d
dev-down:
	$(DOCKER_COMPOSE) $(PROFILES_DEV) down
dev-restart: dev-down dev
dev-logs:
	$(DOCKER_COMPOSE) $(PROFILES_DEV) logs -f
dev-ps:
	$(DOCKER_COMPOSE) $(PROFILES_DEV) ps

# PROD: prod + push + monitoring + backup + rabbitmq (для production)
PROFILES_PROD = --profile prod --profile push --profile monitoring --profile backup --profile rabbitmq
prod: build-base
	$(DOCKER_COMPOSE) $(PROFILES_PROD) build
	$(DOCKER_COMPOSE) $(PROFILES_PROD) up -d
prod-down:
	$(DOCKER_COMPOSE) $(PROFILES_PROD) down
prod-restart: prod-down prod
prod-logs:
	$(DOCKER_COMPOSE) $(PROFILES_PROD) logs -f
prod-ps:
	$(DOCKER_COMPOSE) $(PROFILES_PROD) ps

# ============================================================================
# СТАРЫЕ КОМАНДЫ (для совместимости)
# ============================================================================

# Локальная разработка (с MySQL, Redis, MailHog)
up-local: build-base docker-local-build docker-local-up nginx_local_start
init-local: docker-down-clear-local docker-network-create build-base docker-local-build docker-local-up nginx_local_start
restart-local: docker-down-local docker-network-create build-base docker-local-build docker-local-up nginx_local_start
down-local: docker-local-down-clear

# Полный локальный стек с RabbitMQ
up-local-full: build-base docker-local-full-build docker-local-full-up nginx_local_start
init-local-full: docker-down-clear-local-full docker-network-create build-base docker-local-full-build docker-local-full-up nginx_local_start
restart-local-full: docker-down-local-full docker-network-create build-base docker-local-full-build docker-local-full-up nginx_local_start
down-local-full: docker-local-full-down-clear

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

# Ensure default configs exist before any build
ensure-defaults:
	@chmod +x ./scripts/ensure-defaults.sh && ./scripts/ensure-defaults.sh

build-base: ensure-defaults build-base-cli build-base-fpm

build-base-cli:
	docker build --build-arg UGN=$(UGN) --build-arg UID=$(UID) --build-arg GID=$(GID)  --build-arg ENVIRONMENT=$(ENVIRONMENT)  --build-arg DEBUG=$(DEBUG) \
		-t my/php-base-cli:$(PHP_VERSION) -f docker/php/base/cli/$(PHP_VERSION)/Dockerfile .

build-base-fpm:
	docker build --build-arg UGN=$(UGN) --build-arg UID=$(UID) --build-arg GID=$(GID)  --build-arg ENVIRONMENT=$(ENVIRONMENT)  --build-arg DEBUG=$(DEBUG) \
		-t my/php-base-fpm:$(PHP_VERSION) -f docker/php/base/fpm/$(PHP_VERSION)/Dockerfile .

docker-network-create:
	@if ! docker network inspect $(NETWORK_NAME) >/dev/null 2>&1; then \
		echo "Creating external network '$(NETWORK_NAME)'..."; \
		docker network create --driver bridge --subnet $(DOCKER_SUBNET) $(NETWORK_NAME); \
	else \
		echo "Network '$(NETWORK_NAME)' already exists."; \
	fi

# === НОВЫЕ DOCKER COMPOSE КОМАНДЫ ===

# Локальная разработка
docker-local-build: ensure-defaults
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

# Локальная разработка с RabbitMQ
docker-local-full-build:
	$(DOCKER_COMPOSE) --profile local --profile dev --profile rabbitmq build --build-arg PHP_VERSION=${PHP_VERSION}

docker-local-full-up:
	$(DOCKER_COMPOSE) --profile local --profile dev --profile rabbitmq up -d

docker-local-full-down:
	$(DOCKER_COMPOSE) --profile local --profile dev --profile rabbitmq down

docker-local-full-down-clear:
	$(DOCKER_COMPOSE) --profile local --profile dev --profile rabbitmq down -v --remove-orphans

# Совместимость со старыми командами
docker-build: docker-local-build
docker-up: docker-local-up
docker-down: docker-local-down
docker-down-clear: docker-local-down-clear
docker-down-clear-local: docker-local-down-clear
docker-down-clear-local-full: docker-local-full-down-clear
docker-down-clear-prod: docker-prod-down-clear
docker-down-monitoring: docker-monitoring-down
docker-down-local-monitoring: docker-local-monitoring-down
docker-down-local-full: docker-local-full-down
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
	$(DOCKER_COMPOSE) --profile local --profile dev --profile monitoring up -d
monitoring-up-prod:
	$(DOCKER_COMPOSE) --profile prod --profile monitoring up -d
monitoring-down:
	$(DOCKER_COMPOSE) --profile local --profile dev --profile monitoring down
monitoring-down-prod:
	$(DOCKER_COMPOSE) --profile prod --profile monitoring down

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

# ============================================================================
# SPLIT PHP ARCHITECTURE
# Run separate containers for PHP-FPM, CLI, Cron, Supervisor
# Instead of the unified "bitrix" container
# Usage: make split-local / make split-prod
# ============================================================================

## Split mode: local development
## NOTE: --scale bitrix=0 prevents the unified bitrix container from starting,
## avoiding port 9000 conflict with php-fpm (split architecture)
split-local:
	$(DOCKER_COMPOSE) --profile local --profile split --profile monitoring up -d --build --scale bitrix=0

## Split mode: production
## NOTE: --scale bitrix=0 prevents the unified bitrix container from starting
split-prod:
	$(DOCKER_COMPOSE) --profile prod --profile split --profile monitoring --profile backup --profile rabbitmq up -d --build --scale bitrix=0

## Split mode: stop
split-down:
	$(DOCKER_COMPOSE) --profile split down

## Split mode: status
split-ps:
	$(DOCKER_COMPOSE) --profile split ps

## Split mode: logs
split-logs:
	$(DOCKER_COMPOSE) --profile split logs -f

## Bash into php-fpm container
bash-fpm:
	docker exec -it $${DOMAIN}_php-fpm sh

## Bash into php-cli container
bash-cli:
	docker exec -it $${DOMAIN}_php-cli sh

## Bash into cron container
bash-cron:
	docker exec -it $${DOMAIN}_cron sh

## Bash into supervisor container
bash-supervisor:
	docker exec -it $${DOMAIN}_supervisor sh

## Rebuild only PHP services (split mode)
split-rebuild-php:
	$(DOCKER_COMPOSE) --profile split build php-fpm php-cli cron supervisor

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
	$(DOCKER_COMPOSE) --profile local --profile dev logs -f mysql
logs-mysql:
	$(DOCKER_COMPOSE) logs -f mysql
logs-grafana-local:
	$(DOCKER_COMPOSE) --profile local --profile dev --profile monitoring logs -f grafana
logs-grafana:
	$(DOCKER_COMPOSE) --profile monitoring logs -f grafana
logs-backup-local:
	$(DOCKER_COMPOSE) --profile local --profile dev --profile backup logs -f backup
logs-backup:
	$(DOCKER_COMPOSE) --profile backup logs -f backup

# Диагностика MySQL (если не запускается)
mysql-diag:
	@echo "╔════════════════════════════════════════════════════════════╗"
	@echo "║          ДИАГНОСТИКА MYSQL/MARIADB                         ║"
	@echo "╚════════════════════════════════════════════════════════════╝"
	@echo ""
	@echo "📊 Ресурсы сервера:"
	@echo "  RAM: $$(free -h 2>/dev/null | awk '/^Mem:/{print $$2}' || sysctl -n hw.memsize 2>/dev/null | awk '{print $$1/1024/1024/1024 "GB"}')"
	@echo "  CPU: $$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null) cores"
	@echo ""
	@echo "📦 Контейнер MySQL:"
	@docker inspect $(DOMAIN)_mysql --format='  Status: {{.State.Status}}' 2>/dev/null || echo "  ❌ Контейнер не найден"
	@docker inspect $(DOMAIN)_mysql --format='  Health: {{.State.Health.Status}}' 2>/dev/null || true
	@docker inspect $(DOMAIN)_mysql --format='  Restarts: {{.RestartCount}}' 2>/dev/null || true
	@echo ""
	@echo "📋 Последние логи:"
	@docker logs $(DOMAIN)_mysql --tail 30 2>&1 || true
	@echo ""
	@echo "🔧 Конфигурация из .env:"
	@grep -E "^(MYSQL_IMAGE|MYSQL_INNODB|DB_|MYSQL_MEMORY)" .env 2>/dev/null || echo "  .env не найден"
	@echo ""
	@echo "💡 Рекомендации:"
	@echo "  1. Проверьте что RAM >= buffer_pool + 1GB"
	@echo "  2. Для маленьких серверов используйте: MYSQL_IMAGE=mariadb:10.11"
	@echo "  3. Перегенерируйте конфиги: make optimize"
	@echo "  4. Удалите volume и пересоздайте: make mysql-reset"

# Пересоздание MySQL с нуля (ОСТОРОЖНО - удаляет данные!)
mysql-reset:
	@echo "⚠️  ВНИМАНИЕ: Это удалит все данные MySQL!"
	@read -p "Продолжить? [y/N] " confirm && [ "$$confirm" = "y" ] || exit 1
	$(DOCKER_COMPOSE) stop mysql
	docker rm -f $(DOMAIN)_mysql 2>/dev/null || true
	docker volume rm $(DOMAIN)_mysql_data 2>/dev/null || true
	@echo "✅ Volume удалён. Запустите: make prod (или make local)"

# Оптимизация конфигов под текущий сервер
optimize:
	@./scripts/auto-optimize.sh --update-env --force

# Команды для проверки статуса
status-local:
	$(DOCKER_COMPOSE_LOCAL) ps
status:
	$(DOCKER_COMPOSE) ps

# ==========================================
# 🧹 ОЧИСТКА DOCKER (ЭКОНОМИЯ ДИСКА)
# ==========================================

# Показать использование диска Docker
docker-status:
	@./scripts/docker-cleanup.sh --status

# Мягкая очистка (безопасно, только dangling)
docker-clean:
	@./scripts/docker-cleanup.sh --soft

# Полная очистка (все неиспользуемые images)
docker-clean-full:
	@./scripts/docker-cleanup.sh --full

# Агрессивная очистка (включая build cache) — ОСТОРОЖНО!
docker-clean-aggressive:
	@./scripts/docker-cleanup.sh --aggressive

# Настроить еженедельную очистку через cron
docker-clean-cron:
	@sudo ./scripts/docker-cleanup.sh --setup-cron

# Показать рекомендуемый daemon.json
docker-daemon-config:
	@./scripts/docker-cleanup.sh --daemon-config

# Старые команды (для совместимости)
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
# 📜 УПРАВЛЕНИЕ ЛОГАМИ
# ==========================================

# Показать статус логов (размер, количество файлов)
logs-status:
	@./scripts/logs-rotate.sh --status

# Ротация логов (сжатие старых)
logs-rotate:
	@./scripts/logs-rotate.sh --rotate

# Принудительная ротация
logs-rotate-force:
	@./scripts/logs-rotate.sh --rotate --force

# Удалить старые логи (по умолчанию старше 30 дней)
# Использование: make logs-cleanup
#               make logs-cleanup RETENTION_DAYS=7
logs-cleanup:
	@RETENTION_DAYS=$(RETENTION_DAYS) ./scripts/logs-rotate.sh --cleanup

# Полная очистка логов (ротация + удаление старых)
logs-maintain:
	@./scripts/logs-rotate.sh --rotate
	@./scripts/logs-rotate.sh --cleanup

# Настроить автоматическую ротацию через cron
logs-setup-cron:
	@./scripts/logs-rotate.sh --setup-cron

# Очистить ВСЕ логи (осторожно!)
logs-clear-all:
	@echo "⚠️  ВНИМАНИЕ: Будут удалены ВСЕ логи!"
	@read -p "Продолжить? [y/N]: " confirm && [ "$$confirm" = "y" ] || exit 0
	@find ./volume/logs -type f -name "*.log*" -delete 2>/dev/null || true
	@find ./volume/logs -type f -name "*.gz" -delete 2>/dev/null || true
	@echo "✅ Все логи удалены"

# ==========================================
# 💾 СИСТЕМА БЭКАПОВ (PER-SITE)
# ==========================================

# Список доступных сайтов для бэкапа
# Использование: make backup-sites
backup-sites:
	@./docker/common/scripts/backup-manager.sh sites

# Бэкап базы данных
# Использование: make backup-db                    # Все сайты
#               make backup-db SITE=example.com   # Конкретный сайт
backup-db:
	@./docker/common/scripts/backup-manager.sh database $(SITE)

# Бэкап файлов
# Использование: make backup-files                    # Все сайты
#               make backup-files SITE=example.com   # Конкретный сайт
backup-files:
	@./docker/common/scripts/backup-manager.sh files $(SITE)

# Полный бэкап (база + файлы)
# Использование: make backup-full                    # Все сайты
#               make backup-full SITE=example.com   # Конкретный сайт
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
# Использование: make backup-restore-db FILE=backup.sql.gz                    # В основную БД
#               make backup-restore-db FILE=backup.sql.gz SITE=example.com   # В per-site БД
backup-restore-db:
	@if [ -z "$(FILE)" ]; then \
		echo "❌ ОШИБКА: Необходимо указать FILE"; \
		echo ""; \
		echo "Примеры:"; \
		echo "  make backup-restore-db FILE=backups/database/shop_local_20260118.sql.gz"; \
		echo "  make backup-restore-db FILE=backup.sql.gz SITE=shop.local"; \
		echo ""; \
		echo "Доступные бэкапы:"; \
		./docker/common/scripts/backup-manager.sh list database 2>/dev/null | head -20 || echo "  (нет бэкапов)"; \
		exit 1; \
	fi
	@./docker/common/scripts/backup-manager.sh restore database "$(FILE)" $(SITE)

# Восстановление файлов
# Использование: make backup-restore-files FILE=backup.tar.gz                    # Все сайты
#               make backup-restore-files FILE=backup.tar.gz SITE=example.com   # Конкретный сайт
backup-restore-files:
	@if [ -z "$(FILE)" ]; then \
		echo "❌ ОШИБКА: Необходимо указать FILE"; \
		echo ""; \
		echo "Примеры:"; \
		echo "  make backup-restore-files FILE=backups/files/shop_local_20260118.tar.gz"; \
		echo "  make backup-restore-files FILE=backup.tar.gz SITE=shop.local"; \
		echo ""; \
		echo "Доступные бэкапы:"; \
		./docker/common/scripts/backup-manager.sh list files 2>/dev/null | head -20 || echo "  (нет бэкапов)"; \
		exit 1; \
	fi
	@./docker/common/scripts/backup-manager.sh restore files "$(FILE)" $(SITE)

# Восстановление полного бэкапа (БД + файлы)
# Использование: make backup-restore-full DIR=backups/full/shop_local_20260118 [SITE=example.com]
backup-restore-full:
	@if [ -z "$(DIR)" ]; then \
		echo "❌ ОШИБКА: Необходимо указать DIR (папку полного бэкапа)"; \
		echo ""; \
		echo "Примеры:"; \
		echo "  make backup-restore-full DIR=backups/full/shop_local_20260118_120000"; \
		echo "  make backup-restore-full DIR=backups/full/shop_local_20260118_120000 SITE=shop.local"; \
		echo ""; \
		echo "Доступные полные бэкапы:"; \
		ls -1d backups/full/*/ 2>/dev/null | head -20 || echo "  (нет бэкапов)"; \
		exit 1; \
	fi
	@./docker/common/scripts/backup-manager.sh restore full "$(DIR)" $(SITE)

# ==========================================
# PER-SITE DATABASE MANAGEMENT
# ==========================================

# Инициализация базы данных для сайта
# Использование: make db-init-site SITE=shop.local
db-init-site:
	@if [ -z "$(SITE)" ]; then \
		echo "ОШИБКА: Необходимо указать SITE. Пример: make db-init-site SITE=shop.local"; \
		exit 1; \
	fi
	@if [ ! -f "config/sites/$(SITE)/database-init.sql" ]; then \
		echo "ОШИБКА: Файл config/sites/$(SITE)/database-init.sql не найден"; \
		echo "Сначала добавьте сайт: make site-add SITE=$(SITE)"; \
		exit 1; \
	fi
	@echo "🗄️  Создание базы данных для $(SITE)..."
	@docker exec -i $(DOMAIN)_mysql mysql -u root -p'$(DB_ROOT_PASSWORD)' < config/sites/$(SITE)/database-init.sql
	@echo "✅ База данных и пользователь созданы для $(SITE)"
	@grep -E "^(DB_NAME|DB_USER)=" config/sites/$(SITE)/site.env | sed 's/^/   /'

# Список per-site баз данных
db-list-sites:
	@echo "📋 Per-site базы данных:"
	@echo ""
	@for dir in config/sites/*/; do \
		site=$$(basename "$$dir"); \
		if [ "$$site" != "_template" ] && [ -f "$$dir/site.env" ]; then \
			db_name=$$(grep '^DB_NAME=' "$$dir/site.env" | cut -d'=' -f2); \
			db_user=$$(grep '^DB_USER=' "$$dir/site.env" | cut -d'=' -f2); \
			echo "  📦 $$site"; \
			echo "     DB: $$db_name | User: $$db_user"; \
		fi; \
	done
	@echo ""

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

# ==========================================
# 🌐 УПРАВЛЕНИЕ САЙТАМИ (МУЛЬТИСАЙТ)
# ==========================================

# Добавить сайт (ПОЛНАЯ АВТОМАТИЗАЦИЯ)
# Создаёт: директории, nginx конфиг, per-site конфиги, БД, перезагружает всё
# Использование: make site-add SITE=example.com
#               make site-add SITE=example.com SSL=yes
#               make site-add SITE=example.com PHP=8.4 SSL=letsencrypt
site-add:
	@if [ -z "$(SITE)" ]; then \
		echo "❌ Укажите домен: make site-add SITE=example.com"; \
		exit 1; \
	fi
	@echo ""
	@echo "╔════════════════════════════════════════════════════════════╗"
	@echo "║  🚀 ДОБАВЛЕНИЕ САЙТА: $(SITE)"
	@echo "╚════════════════════════════════════════════════════════════╝"
	@echo ""
	@echo "📁 [1/4] Создание структуры и конфигов..."
	@./scripts/site.sh add $(SITE) $(if $(PHP),--php=$(PHP)) $(if $(filter yes true 1,$(SSL)),--ssl) $(if $(filter letsencrypt le,$(SSL)),--ssl=letsencrypt)
	@echo ""
	@echo "🗄️  [2/4] Создание базы данных..."
	@if docker ps --format '{{.Names}}' | grep -q "$(DOMAIN)_mysql"; then \
		if [ -f "config/sites/$(SITE)/database-init.sql" ]; then \
			docker exec -i $(DOMAIN)_mysql mysql -u root -p'$(DB_ROOT_PASSWORD)' < config/sites/$(SITE)/database-init.sql 2>/dev/null && \
			echo "   ✅ База данных создана" || \
			echo "   ⚠️  БД уже существует или ошибка (это нормально при повторном добавлении)"; \
		fi; \
	else \
		echo "   ⚠️  MySQL не запущен, БД будет создана позже: make db-init-site SITE=$(SITE)"; \
	fi
	@echo ""
	@echo "🔄 [3/4] Перезагрузка nginx..."
	@if docker ps --format '{{.Names}}' | grep -q "$(DOMAIN)_nginx"; then \
		docker exec $(DOMAIN)_nginx nginx -t 2>/dev/null && \
		docker exec $(DOMAIN)_nginx nginx -s reload 2>/dev/null && \
		echo "   ✅ Nginx перезагружен" || \
		echo "   ⚠️  Ошибка перезагрузки nginx"; \
	else \
		echo "   ⚠️  Nginx не запущен"; \
	fi
	@echo ""
	@echo "📋 [4/4] Итоговая информация..."
	@echo ""
	@echo "╔════════════════════════════════════════════════════════════╗"
	@echo "║  ✅ САЙТ $(SITE) ДОБАВЛЕН!"
	@echo "╚════════════════════════════════════════════════════════════╝"
	@echo ""
	@echo "  📂 Document Root:  www/$(SITE)/www/"
	@echo "  ⚙️  Site Config:    config/sites/$(SITE)/"
	@echo "  🌐 Nginx Config:   config/nginx/sites/$(SITE).conf"
	@if [ -f "config/sites/$(SITE)/site.env" ]; then \
		echo ""; \
		echo "  🗄️  Database:"; \
		grep -E "^(DB_NAME|DB_USER|DB_PASSWORD)=" config/sites/$(SITE)/site.env | sed 's/^/     /'; \
	fi
	@echo ""
	@echo "  📝 Добавь в /etc/hosts:"
	@echo "     127.0.0.1 $(SITE) www.$(SITE)"
	@echo ""

# Удалить сайт (ПОЛНОЕ УДАЛЕНИЕ: файлы + конфиги + БД)
# Использование: make site-remove SITE=example.com
site-remove:
	@if [ -z "$(SITE)" ]; then \
		echo "❌ Укажите домен: make site-remove SITE=example.com"; \
		exit 1; \
	fi
	@echo ""
	@echo "╔════════════════════════════════════════════════════════════╗"
	@echo "║  🗑️  УДАЛЕНИЕ САЙТА: $(SITE)"
	@echo "╚════════════════════════════════════════════════════════════╝"
	@echo ""
	@echo "⚠️  ВНИМАНИЕ: Будут удалены:"
	@echo "   - Файлы сайта: www/$(SITE)/"
	@echo "   - Конфигурации: config/sites/$(SITE)/"
	@echo "   - Nginx конфиг: config/nginx/sites/$(SITE).conf"
	@if [ -f "config/sites/$(SITE)/site.env" ]; then \
		db_name=$$(grep '^DB_NAME=' config/sites/$(SITE)/site.env | cut -d'=' -f2); \
		db_user=$$(grep '^DB_USER=' config/sites/$(SITE)/site.env | cut -d'=' -f2); \
		echo "   - База данных: $$db_name"; \
		echo "   - Пользователь БД: $$db_user"; \
	fi
	@echo ""
	@read -p "Продолжить? [y/N]: " confirm && [ "$$confirm" = "y" ] || exit 0
	@echo ""
	@echo "🗄️  Удаление базы данных..."
	@if docker ps --format '{{.Names}}' | grep -q "$(DOMAIN)_mysql" && [ -f "config/sites/$(SITE)/site.env" ]; then \
		db_name=$$(grep '^DB_NAME=' config/sites/$(SITE)/site.env | cut -d'=' -f2); \
		db_user=$$(grep '^DB_USER=' config/sites/$(SITE)/site.env | cut -d'=' -f2); \
		docker exec $(DOMAIN)_mysql mysql -u root -p'$(DB_ROOT_PASSWORD)' -e "DROP DATABASE IF EXISTS \`$$db_name\`; DROP USER IF EXISTS '$$db_user'@'%';" 2>/dev/null && \
		echo "   ✅ База данных и пользователь удалены" || \
		echo "   ⚠️  Ошибка удаления БД (возможно уже удалена)"; \
	else \
		echo "   ⚠️  MySQL не запущен или site.env не найден"; \
	fi
	@echo ""
	@echo "📁 Удаление файлов и конфигов..."
	@./scripts/site.sh remove $(SITE) --no-confirm
	@echo ""
	@echo "🔄 Перезагрузка nginx..."
	@if docker ps --format '{{.Names}}' | grep -q "$(DOMAIN)_nginx"; then \
		docker exec $(DOMAIN)_nginx nginx -s reload 2>/dev/null && \
		echo "   ✅ Nginx перезагружен" || true; \
	fi
	@echo ""
	@echo "✅ Сайт $(SITE) полностью удалён"

# Список всех сайтов
site-list:
	@./scripts/site.sh list

# Включить SSL для сайта (самоподписанный)
# Использование: make site-ssl SITE=example.com
site-ssl:
	@if [ -z "$(SITE)" ]; then \
		echo "❌ Укажите домен: make site-ssl SITE=example.com"; \
		exit 1; \
	fi
	@./scripts/site.sh ssl $(SITE)

# Получить Let's Encrypt сертификат
# Использование: make site-ssl-le SITE=example.com
site-ssl-le:
	@if [ -z "$(SITE)" ]; then \
		echo "❌ Укажите домен: make site-ssl-le SITE=example.com"; \
		exit 1; \
	fi
	@./scripts/site.sh ssl-le $(SITE)

# Перезагрузить nginx (после изменения конфигов)
site-reload:
	@./scripts/site.sh reload

# Показать помощь по управлению сайтами
help-sites:
	@echo ""
	@echo "═══════════════════════════════════════════════════════════"
	@echo "  🌐 УПРАВЛЕНИЕ САЙТАМИ (МУЛЬТИСАЙТ)"
	@echo "═══════════════════════════════════════════════════════════"
	@echo ""
	@echo "  🚀 Добавление сайта (полная автоматизация):"
	@echo "    make site-add SITE=shop.local                    # Создаёт всё!"
	@echo "    make site-add SITE=shop.local SSL=yes            # + SSL"
	@echo "    make site-add SITE=prod.com SSL=letsencrypt      # + Let's Encrypt"
	@echo "    make site-add SITE=api.local PHP=8.4             # + PHP 8.4"
	@echo ""
	@echo "    Автоматически создаёт:"
	@echo "    ✓ Директории www/{site}/www/"
	@echo "    ✓ Nginx конфиг"
	@echo "    ✓ Per-site конфиги (DB credentials, SMTP)"
	@echo "    ✓ Базу данных и пользователя MySQL"
	@echo "    ✓ Перезагружает nginx"
	@echo ""
	@echo "  🗑️  Удаление сайта (полное):"
	@echo "    make site-remove SITE=old.local                  # Удаляет ВСЁ включая БД"
	@echo ""
	@echo "  📋 Управление:"
	@echo "    make site-list                                   # Список сайтов"
	@echo "    make site-reload                                 # Перезагрузить nginx"
	@echo "    make db-list-sites                               # Список per-site БД"
	@echo "    make db-init-site SITE=...                       # Создать БД вручную"
	@echo ""
	@echo "  🔐 SSL сертификаты:"
	@echo "    make site-ssl SITE=shop.local                    # Self-signed SSL"
	@echo "    make site-ssl-le SITE=prod.com                   # Let's Encrypt"
	@echo ""
	@echo "  📁 Структура файлов:"
	@echo "    www/"
	@echo "    └── example.com/"
	@echo "        └── www/              <- Document root"
	@echo "            ├── index.php"
	@echo "            ├── bitrix/"
	@echo "            └── upload/"
	@echo ""
	@echo "    config/sites/"
	@echo "    └── example.com/"
	@echo "        ├── site.env          <- DB credentials"
	@echo "        ├── msmtp.conf        <- Per-site SMTP"
	@echo "        └── database-init.sql <- SQL для создания БД"
	@echo "            └── bitrix/"
	@echo ""
	@echo "  После добавления сайта добавьте в /etc/hosts:"
	@echo "    127.0.0.1 shop.local www.shop.local"
	@echo ""

# Показать помощь по бэкапам
help-backup:
	@echo ""
	@echo "═══════════════════════════════════════════════════════════"
	@echo "  💾 СИСТЕМА БЭКАПОВ (PER-SITE)"
	@echo "═══════════════════════════════════════════════════════════"
	@echo ""
	@echo "  📋 Информация:"
	@echo "    make backup-sites                                  # Список сайтов для бэкапа"
	@echo "    make backup-list                                   # Все бэкапы"
	@echo "    make backup-list-db                                # Только БД"
	@echo "    make backup-list-files                             # Только файлы"
	@echo ""
	@echo "  📦 Создание бэкапов:"
	@echo "    make backup-db                                     # БД всех сайтов"
	@echo "    make backup-db SITE=shop.local                     # БД одного сайта"
	@echo "    make backup-files                                  # Файлы всех сайтов"
	@echo "    make backup-files SITE=shop.local                  # Файлы одного сайта"
	@echo "    make backup-full                                   # Полный бэкап всех"
	@echo "    make backup-full SITE=shop.local                   # Полный бэкап одного"
	@echo ""
	@echo "  ♻️  Восстановление:"
	@echo "    make backup-restore-db FILE=backup.sql.gz          # В основную БД"
	@echo "    make backup-restore-db FILE=... SITE=shop.local    # В per-site БД"
	@echo "    make backup-restore-files FILE=backup.tar.gz       # Файлы"
	@echo "    make backup-restore-full DIR=backups/full/...      # Полный бэкап"
	@echo ""
	@echo "  🧹 Обслуживание:"
	@echo "    make backup-cleanup                                # Удалить старые бэкапы"
	@echo ""
	@echo "  📁 Структура бэкапов:"
	@echo "    backups/"
	@echo "    ├── database/"
	@echo "    │   ├── shop_local_20260118_120000.sql.gz"
	@echo "    │   └── blog_local_20260118_120000.sql.gz"
	@echo "    ├── files/"
	@echo "    │   ├── shop_local_20260118_120000.tar.gz"
	@echo "    │   └── blog_local_20260118_120000.tar.gz"
	@echo "    └── full/"
	@echo "        └── shop_local_20260118_120000/"
	@echo "            ├── database.sql.gz"
	@echo "            ├── files.tar.gz"
	@echo "            └── manifest.txt"
	@echo ""
	@echo "  💡 Примеры:"
	@echo "    # Бэкап только магазина"
	@echo "    make backup-full SITE=shop.local"
	@echo ""
	@echo "    # Восстановить БД из бэкапа"
	@echo "    make backup-restore-db FILE=backups/database/shop_local_20260118.sql.gz SITE=shop.local"
	@echo ""
	@echo "    # Восстановить полный бэкап"
	@echo "    make backup-restore-full DIR=backups/full/shop_local_20260118_120000 SITE=shop.local"
	@echo ""

# Показать помощь по очистке Docker
help-docker:
	@echo ""
	@echo "═══════════════════════════════════════════════════════════"
	@echo "  🧹 ОЧИСТКА DOCKER (ЭКОНОМИЯ ДИСКА)"
	@echo "═══════════════════════════════════════════════════════════"
	@echo ""
	@echo "  📊 Мониторинг:"
	@echo "    make docker-status              # Использование диска"
	@echo ""
	@echo "  🧹 Очистка (выбери нужный уровень):"
	@echo "    make docker-clean               # SOFT: dangling только"
	@echo "    make docker-clean-full          # FULL: все неиспользуемые"
	@echo "    make docker-clean-aggressive    # MAX: включая build cache"
	@echo ""
	@echo "  ⏰ Автоматизация:"
	@echo "    make docker-clean-cron          # Еженедельная очистка"
	@echo ""
	@echo "  ⚙️  Настройка Docker daemon:"
	@echo "    make docker-daemon-config       # Показать рекомендации"
	@echo ""
	@echo "  📋 Что удаляется:"
	@echo "    --soft:       Остановленные контейнеры"
	@echo "                  Dangling images (untagged)"
	@echo "                  Неиспользуемые networks"
	@echo "                  Dangling volumes"
	@echo ""
	@echo "    --full:       Всё из --soft +"
	@echo "                  ВСЕ неиспользуемые images"
	@echo ""
	@echo "    --aggressive: Всё из --full +"
	@echo "                  Build cache"
	@echo "                  Buildx cache"
	@echo "                  ⚠️  Следующий build будет медленнее!"
	@echo ""
	@echo "  💡 Рекомендации:"
	@echo "    - make docker-clean             # Еженедельно"
	@echo "    - make docker-clean-full        # Ежемесячно"
	@echo "    - make docker-clean-aggressive  # При критичном диске"
	@echo ""
	@echo "  📁 Что занимает место:"
	@echo "    /var/lib/docker      - Images, containers, volumes"
	@echo "    /var/lib/containerd  - Containerd snapshots"
	@echo ""

# Показать помощь по логам
help-logs:
	@echo ""
	@echo "═══════════════════════════════════════════════════════════"
	@echo "  📜 УПРАВЛЕНИЕ ЛОГАМИ"
	@echo "═══════════════════════════════════════════════════════════"
	@echo ""
	@echo "  📊 Мониторинг:"
	@echo "    make logs-status                    # Размер и статус логов"
	@echo ""
	@echo "  🔄 Ротация:"
	@echo "    make logs-rotate                    # Ротация больших логов"
	@echo "    make logs-rotate-force              # Принудительная ротация"
	@echo ""
	@echo "  🧹 Очистка:"
	@echo "    make logs-cleanup                   # Удалить логи старше 30 дней"
	@echo "    make logs-cleanup RETENTION_DAYS=7  # Удалить старше 7 дней"
	@echo "    make logs-maintain                  # Ротация + очистка"
	@echo "    make logs-clear-all                 # Удалить ВСЕ логи (осторожно!)"
	@echo ""
	@echo "  ⏰ Автоматизация:"
	@echo "    make logs-setup-cron                # Настроить ежедневную ротацию"
	@echo ""
	@echo "  📁 Docker логи:"
	@echo "    docker logs container_name          # Логи контейнера"
	@echo "    docker logs -f --tail 100 nginx     # Follow последних 100 строк"
	@echo ""
	@echo "  📁 Структура логов:"
	@echo "    volume/logs/"
	@echo "    ├── nginx/       # Nginx access/error logs"
	@echo "    ├── php/         # PHP error logs"
	@echo "    ├── php-fpm/     # PHP-FPM logs"
	@echo "    ├── mysql/       # MySQL logs (if enabled)"
	@echo "    ├── cron/        # Cron job logs"
	@echo "    ├── supervisor/  # Supervisor logs"
	@echo "    └── msmtp/       # Mail logs"
	@echo ""
	@echo "  💡 Docker logging уже настроен:"
	@echo "    - max-size: 10m per file"
	@echo "    - max-file: 3 files per container"
	@echo "    Дополнительно рекомендуется ротация app логов."
	@echo ""

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
	@echo "╔════════════════════════════════════════════════════════════╗"
	@echo "║            BITRIX DOCKER ENVIRONMENT v2.0                  ║"
	@echo "╚════════════════════════════════════════════════════════════╝"
	@echo ""
	@echo "🚀 БЫСТРЫЙ СТАРТ (новый проект):"
	@echo "  make setup          - Подготовка (секреты + оптимизация + валидация)"
	@echo "  make first-run      - Полная инициализация с нуля (всё в одной команде!)"
	@echo "  make first-run-prod - Полная инициализация для production"
	@echo "  make quick-start    - Быстрый запуск (без настройки)"
	@echo "  make optimize       - Пересоздать конфиги под текущий сервер"
	@echo ""
	@echo "📦 Управление контейнерами:"
	@echo "  make local          - Запуск для локальной разработки"
	@echo "  make dev            - Запуск для dev сервера"
	@echo "  make prod           - Запуск для production"
	@echo "  make local-down     - Остановить (local)"
	@echo "  make local-restart  - Перезапустить (local)"
	@echo "  make local-logs     - Логи (local)"
	@echo "  make local-ps       - Статус контейнеров"
	@echo ""
	@echo "💾 Бэкапы (per-site):"
	@echo "  make backup-sites                           - Список сайтов для бэкапа"
	@echo "  make backup-full [SITE=shop.local]          - Полный бэкап"
	@echo "  make backup-db [SITE=shop.local]            - Бэкап БД"
	@echo "  make backup-files [SITE=shop.local]         - Бэкап файлов"
	@echo "  make backup-list                            - Список бэкапов"
	@echo "  make help-backup                            - Подробная справка"
	@echo ""
	@echo "🔒 Безопасность:"
	@echo "  make security-up    - Включить Fail2ban"
	@echo "  make security-stats - Статистика атак"
	@echo ""
	@echo "📜 Логи:"
	@echo "  make logs-status    - Статус логов (размер)"
	@echo "  make logs-rotate    - Ротация логов"
	@echo "  make logs-cleanup   - Удалить старые логи"
	@echo ""
	@echo "🔧 Диагностика:"
	@echo "  make mysql-diag     - Диагностика MySQL (если не запускается)"
	@echo "  make mysql-reset    - Пересоздать MySQL с нуля (удалит данные!)"
	@echo "  make optimize       - Пересоздать конфиги под текущий сервер"
	@echo ""
	@echo "🧹 Очистка Docker:"
	@echo "  make docker-status  - Использование диска"
	@echo "  make docker-clean   - Мягкая очистка (безопасно)"
	@echo "  make docker-clean-full - Полная очистка"
	@echo ""
	@echo "🔄 Автозапуск (systemd):"
	@echo "  make install-service   - Установить автозапуск"
	@echo "  make service-status    - Статус сервиса"
	@echo "  make install-watchdog  - Установить health watchdog (cron)"
	@echo "  make watchdog-logs     - Логи watchdog"
	@echo ""
	@echo "⚙️  Настройка:"
	@echo "  make auto-config    - Автоконфигурация под сервер"
	@echo "  make validate       - Валидация .env"
	@echo ""
	@echo "📖 Подробная помощь:"
	@echo "  make help-quick     - Шпаргалка по основным командам"
	@echo "  make help-sites     - Управление сайтами"
	@echo "  make help-backup    - Управление бэкапами"
	@echo "  make help-security  - Безопасность"
	@echo "  make help-autoconfig - Автоконфигурация"
	@echo "  make help-logs      - Управление логами"
	@echo "  make help-docker    - Очистка Docker (диск)"

# Шпаргалка по основным командам
help-quick:
	@echo ""
	@echo "═══════════════════════════════════════════════════════════"
	@echo "  ШПАРГАЛКА ПО КОМАНДАМ"
	@echo "═══════════════════════════════════════════════════════════"
	@echo ""
	@echo "  🆕 Первый запуск:"
	@echo "      make first-run"
	@echo ""
	@echo "  🔄 Ежедневная работа:"
	@echo "      make local          # Запустить"
	@echo "      make local-down     # Остановить"
	@echo "      make local-restart  # Перезапустить"
	@echo "      make local-logs     # Логи"
	@echo ""
	@echo "  💾 Бэкапы (per-site):"
	@echo "      make backup-sites               # Список сайтов"
	@echo "      make backup-full SITE=shop.local # Бэкап сайта"
	@echo "      make backup-list                # Список бэкапов"
	@echo ""
	@echo "  🐚 Доступ к контейнерам:"
	@echo "      make bash_cli_local # PHP CLI"
	@echo "      make bash_nginx     # Nginx"
	@echo ""
	@echo "  📊 Мониторинг:"
	@echo "      make local-ps       # Статус"
	@echo "      make disk-usage     # Место на диске"
	@echo ""

# Валидация .env файла
validate:
	@chmod +x ./scripts/validate-env.sh && ./scripts/validate-env.sh

# ==========================================
# 🔄 SYSTEMD SERVICE (АВТОЗАПУСК)
# ==========================================

# Установить systemd сервис для автозапуска после перезагрузки
# Использование: sudo make install-service
install-service:
	@echo "🔄 Установка systemd сервиса..."
	@sudo ./scripts/install-service.sh install

# Удалить systemd сервис
uninstall-service:
	@sudo ./scripts/install-service.sh uninstall

# Статус сервиса
service-status:
	@./scripts/install-service.sh status

# Логи сервиса
service-logs:
	@sudo journalctl -u bitrix-docker -n 50 -f

# Установить health watchdog cron (проверка контейнеров каждые 5 мин)
install-watchdog:
	@sudo ./scripts/install-watchdog-cron.sh install

# Удалить health watchdog cron
uninstall-watchdog:
	@sudo ./scripts/install-watchdog-cron.sh remove

# Логи watchdog
watchdog-logs:
	@tail -50 /var/log/bitrix-docker-watchdog.log 2>/dev/null || echo "Лог watchdog пуст или не найден"

# === КОМАНДЫ БЕЗОПАСНОСТИ ===

# Управление Fail2ban
security-up:
	@echo "🔒 Запуск системы безопасности..."
	$(DOCKER_COMPOSE) --profile security up -d fail2ban

security-up-full:
	@echo "🔒 Запуск полной системы безопасности (Fail2ban + ModSecurity)..."
	$(DOCKER_COMPOSE) --profile security up -d

security-down:
	@echo "🔒 Остановка системы безопасности..."
	$(DOCKER_COMPOSE) --profile security down

security-restart:
	@echo "🔒 Перезапуск системы безопасности..."
	$(DOCKER_COMPOSE) --profile security restart

security-logs:
	@echo "🔒 Логи системы безопасности..."
	$(DOCKER_COMPOSE) --profile security logs -f fail2ban

security-logs-modsec:
	@echo "🔒 Логи ModSecurity..."
	$(DOCKER_COMPOSE) --profile security logs -f modsecurity

security-status:
	@echo "🔒 Статус системы безопасности..."
	@$(DOCKER_COMPOSE) --profile security ps fail2ban modsecurity || echo "Сервисы безопасности не запущены"

# Управление Fail2ban
fail2ban-status:
	@echo "🔒 Статус Fail2ban..."
	$(DOCKER_COMPOSE) exec fail2ban fail2ban-client status

fail2ban-jails:
	@echo "🔒 Список jail'ов Fail2ban..."
	$(DOCKER_COMPOSE) exec fail2ban fail2ban-client status --all

fail2ban-unban:
	@echo "🔒 Разблокировка IP адреса..."
	@if [ -z "$(IP)" ]; then \
		echo "❌ Укажите IP адрес: make fail2ban-unban IP=x.x.x.x"; \
		exit 1; \
	fi
	@$(DOCKER_COMPOSE) exec fail2ban fail2ban-client set nginx-req-limit unbanip $(IP) || true
	@$(DOCKER_COMPOSE) exec fail2ban fail2ban-client set nginx-403 unbanip $(IP) || true
	@$(DOCKER_COMPOSE) exec fail2ban fail2ban-client set nginx-404 unbanip $(IP) || true
	@$(DOCKER_COMPOSE) exec fail2ban fail2ban-client set nginx-botsearch unbanip $(IP) || true
	@$(DOCKER_COMPOSE) exec fail2ban fail2ban-client set nginx-brute unbanip $(IP) || true
	@$(DOCKER_COMPOSE) exec fail2ban fail2ban-client set nginx-sqli unbanip $(IP) || true
	@$(DOCKER_COMPOSE) exec fail2ban fail2ban-client set nginx-xss unbanip $(IP) || true
	@echo "✅ IP $(IP) разблокирован во всех jail'ах"

fail2ban-ban:
	@echo "🔒 Блокировка IP адреса..."
	@if [ -z "$(IP)" ]; then \
		echo "❌ Укажите IP адрес: make fail2ban-ban IP=x.x.x.x"; \
		exit 1; \
	fi
	@$(DOCKER_COMPOSE) exec fail2ban fail2ban-client set nginx-req-limit banip $(IP)
	@echo "✅ IP $(IP) заблокирован"

fail2ban-banned:
	@echo "🔒 Список заблокированных IP..."
	@$(DOCKER_COMPOSE) exec fail2ban fail2ban-client status nginx-req-limit
	@$(DOCKER_COMPOSE) exec fail2ban fail2ban-client status nginx-403
	@$(DOCKER_COMPOSE) exec fail2ban fail2ban-client status nginx-404

# Тестирование безопасности
security-test:
	@echo "🔒 Тестирование конфигурации безопасности..."
	@$(DOCKER_COMPOSE) exec fail2ban fail2ban-client -t
	@echo "✅ Конфигурация Fail2ban корректна"

# Мониторинг атак
security-attacks:
	@echo "🔒 Последние атаки..."
	@tail -50 ./volume/logs/fail2ban/fail2ban.log | grep Ban || echo "Нет заблокированных IP"

security-stats:
	@echo "🔒 Статистика безопасности..."
	@echo "=== Fail2ban статистика ==="
	@grep "Ban " ./volume/logs/fail2ban/fail2ban.log | wc -l | xargs echo "Всего заблокировано IP:"
	@echo ""
	@echo "=== Nginx статистика атак ==="
	@grep -c " 403 " ./volume/logs/nginx/access.log | xargs echo "403 ошибки:" || echo "403 ошибки: 0"
	@grep -c " 404 " ./volume/logs/nginx/access.log | xargs echo "404 ошибки:" || echo "404 ошибки: 0"
	@grep -c " 429 " ./volume/logs/nginx/access.log | xargs echo "Rate limit срабатывания:" || echo "Rate limit срабатывания: 0"

# Справка по безопасности
help-security:
	@echo ""
	@echo "=== КОМАНДЫ БЕЗОПАСНОСТИ ==="
	@echo ""
	@echo "Управление системой безопасности:"
	@echo "  make security-up       - Запуск Fail2ban"
	@echo "  make security-up-full  - Запуск Fail2ban + ModSecurity"
	@echo "  make security-down     - Остановка системы безопасности"
	@echo "  make security-restart  - Перезапуск системы безопасности"
	@echo "  make security-status   - Статус сервисов безопасности"
	@echo ""
	@echo "Управление Fail2ban:"
	@echo "  make fail2ban-status   - Статус Fail2ban"
	@echo "  make fail2ban-jails    - Список всех jail'ов"
	@echo "  make fail2ban-banned   - Список заблокированных IP"
	@echo "  make fail2ban-unban IP=x.x.x.x  - Разблокировать IP"
	@echo "  make fail2ban-ban IP=x.x.x.x    - Заблокировать IP"
	@echo ""
	@echo "Мониторинг и статистика:"
	@echo "  make security-logs     - Логи Fail2ban"
	@echo "  make security-logs-modsec - Логи ModSecurity"
	@echo "  make security-attacks  - Последние атаки"
	@echo "  make security-stats    - Статистика безопасности"
	@echo "  make security-test     - Тестирование конфигурации"
	@echo ""
	@echo "Примеры использования:"
	@echo "  make security-up                    # Запустить защиту"
	@echo "  make fail2ban-unban IP=192.168.1.1 # Разбанить IP"
	@echo "  make security-stats                 # Посмотреть статистику"