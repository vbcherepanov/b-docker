# Bitrix Docker Multisite Environment

Production-ready Docker environment for 1C-Bitrix with full multisite support, per-site isolation, monitoring, and automated management.

## Table of Contents

- [Features](#features)
- [System Requirements](#system-requirements)
- [Quick Start](#quick-start)
- [Architecture](#architecture)
- [Make Commands Reference](#make-commands-reference)
- [Multisite Management](#multisite-management)
- [Per-Site Configuration](#per-site-configuration)
- [Backup System](#backup-system)
- [Monitoring](#monitoring)
- [Security](#security)
- [Troubleshooting](#troubleshooting)
- [FAQ](#faq)

---

## Features

### Multisite Architecture
- **Complete site isolation** - each site has its own database, SMTP config, and cron
- **One-command site management** - `make site-add SITE=shop.local` creates everything
- **Per-site backups** - backup/restore individual sites or all at once
- **Domain-based log filtering** - filter logs by domain in Grafana

### Technology Stack
- **PHP 7.4 / 8.3 / 8.4** - configurable via `.env`
- **MySQL 8.0 / MariaDB 10.11** - configurable via `.env`
- **Nginx** - optimized for Bitrix with rate limiting
- **Redis** - caching and sessions
- **Memcached** - additional caching layer

### Monitoring & Logging
- **Grafana** - dashboards and visualization
- **Prometheus** - metrics collection
- **Loki** - centralized logging (1 year retention)
- **Promtail** - log collection with domain labels

### Security
- **Fail2ban** - brute force protection
- **ModSecurity WAF** - web application firewall
- **Rate limiting** - DDoS protection
- **Security headers** - XSS, CSRF protection
- **Non-root containers** - enhanced security

### Automation
- **Auto-optimization** - configures based on server resources
- **Auto-backup** - scheduled database and file backups
- **One-command deployment** - `make first-run` sets up everything

---

## System Requirements

### Required Software

| Software | Minimum Version | Check Command |
|----------|----------------|---------------|
| **Docker** | 20.10+ | `docker --version` |
| **Docker Compose** | 2.0+ (V2) | `docker compose version` |
| **Git** | 2.0+ | `git --version` |
| **Make** | 3.0+ | `make --version` |

### Hardware Requirements

| Resource | Minimum | Recommended | Production |
|----------|---------|-------------|------------|
| **CPU** | 2 cores | 4 cores | 8+ cores |
| **RAM** | 4 GB | 8 GB | 16+ GB |
| **Disk** | 20 GB | 50 GB | 100+ GB SSD |

### Supported Platforms

| Platform | Status | Notes |
|----------|--------|-------|
| **Ubuntu 20.04+** | Fully supported | Recommended |
| **Debian 11+** | Fully supported | |
| **CentOS 8+** | Fully supported | |
| **macOS (Intel)** | Fully supported | |
| **macOS (Apple Silicon)** | Fully supported | ARM64 native |
| **Windows 10/11** | Supported | Requires WSL 2 |

### Installation on Ubuntu/Debian

```bash
# Update system
sudo apt update && sudo apt upgrade -y

# Install Docker
curl -fsSL https://get.docker.com | sh
sudo usermod -aG docker $USER

# Install Docker Compose (V2 plugin)
sudo apt install docker-compose-plugin

# Install Make and Git
sudo apt install make git -y

# Logout and login to apply docker group
exit
```

### Installation on macOS

```bash
# Install Docker Desktop from https://docker.com/products/docker-desktop
# Or via Homebrew:
brew install --cask docker

# Install Make (included in Xcode Command Line Tools)
xcode-select --install

# Install Git
brew install git
```

### Installation on Windows (WSL 2)

```powershell
# Enable WSL 2
wsl --install

# Install Ubuntu from Microsoft Store
# Then follow Ubuntu installation steps above
```

---

## Quick Start

### 1. Clone Repository

```bash
git clone <your-repo-url> b-docker
cd b-docker
```

### 2. Initial Setup

```bash
# Full automated setup (generates secrets, optimizes configs, validates)
make setup
```

### 3. First Run

```bash
# For local development
make first-run

# For production
make first-run-prod
```

### 4. Add Your First Site

```bash
# Add site (creates directories, nginx config, database, per-site configs)
make site-add SITE=mysite.local

# Add to /etc/hosts
echo "127.0.0.1 mysite.local www.mysite.local" | sudo tee -a /etc/hosts
```

### 5. Access Your Site

- **Site**: http://mysite.local
- **MailHog**: http://localhost:8025 (local dev)
- **Grafana**: http://localhost:3000

---

## Architecture

### Directory Structure

```
b-docker/
├── docker-compose.bitrix.yml     # Main compose file
├── Makefile                      # All management commands
├── .env                          # Active configuration
│
├── www/                          # Sites root (multisite)
│   ├── shop.local/
│   │   └── www/                  # Document root
│   │       ├── index.php
│   │       ├── bitrix/
│   │       └── upload/
│   └── blog.local/
│       └── www/
│
├── config/
│   ├── sites/                    # Per-site configurations
│   │   ├── _template/            # Templates for new sites
│   │   │   ├── site.env.template
│   │   │   ├── database-init.sql.template
│   │   │   └── msmtp.conf.template
│   │   ├── shop.local/
│   │   │   ├── site.env          # DB credentials
│   │   │   ├── database-init.sql # SQL for DB creation
│   │   │   └── msmtp.conf        # SMTP config
│   │   └── blog.local/
│   │       └── ...
│   ├── nginx/
│   │   └── sites/                # Nginx configs per site
│   ├── cron/                     # Multisite cron
│   ├── mysql/                    # MySQL configs
│   ├── redis/                    # Redis config
│   ├── grafana/                  # Grafana dashboards
│   ├── prometheus/               # Prometheus rules
│   ├── loki/                     # Loki config
│   └── promtail/                 # Promtail with domain labels
│
├── docker/
│   ├── php/
│   │   ├── base/                 # Base PHP images
│   │   └── bitrix/               # Bitrix container
│   ├── nginx/
│   ├── mysql/
│   └── ...
│
├── backups/                      # Backup storage
│   ├── database/                 # DB backups per site
│   ├── files/                    # File backups per site
│   └── full/                     # Full backups (DB + files)
│
├── volume/                       # Persistent data
│   ├── logs/                     # All logs
│   ├── mysql/                    # MySQL data
│   └── grafana/                  # Grafana data
│
├── ssl/                          # SSL certificates
└── scripts/                      # Utility scripts
```

### Container Architecture

```
                    Internet
                       │
                       ▼
              ┌────────────────┐
              │     Nginx      │ :80/:443
              │  (reverse proxy)│
              └───────┬────────┘
                      │
        ┌─────────────┼─────────────┐
        │             │             │
        ▼             ▼             ▼
  ┌──────────┐  ┌──────────┐  ┌──────────┐
  │ PHP-FPM  │  │ PHP-FPM  │  │ PHP-FPM  │
  │ shop.local│  │blog.local│  │ api.local│
  └────┬─────┘  └────┬─────┘  └────┬─────┘
       │             │             │
       └─────────────┼─────────────┘
                     │
        ┌────────────┼────────────┐
        │            │            │
        ▼            ▼            ▼
  ┌──────────┐ ┌──────────┐ ┌──────────┐
  │  MySQL   │ │  Redis   │ │Memcached │
  │(per-site │ │ (shared) │ │ (shared) │
  │   DBs)   │ │          │ │          │
  └──────────┘ └──────────┘ └──────────┘
```

---

## Make Commands Reference

### Quick Start Commands

```bash
make setup              # Prepare environment (secrets, optimization, validation)
make first-run          # Full initialization from scratch (local)
make first-run-prod     # Full initialization for production
make quick-start        # Quick start without full setup
```

### Environment Management

```bash
# Local development (with MySQL, Redis, MailHog, monitoring)
make local              # Start
make local-down         # Stop
make local-restart      # Restart
make local-logs         # View logs
make local-ps           # Container status

# Development server
make dev                # Start
make dev-down           # Stop
make dev-restart        # Restart
make dev-logs           # View logs

# Production (with monitoring, backup, RabbitMQ)
make prod               # Start
make prod-down          # Stop
make prod-restart       # Restart
make prod-logs          # View logs
```

### Site Management (Multisite)

```bash
# Add site (FULL AUTOMATION)
make site-add SITE=shop.local              # Basic site
make site-add SITE=shop.local SSL=yes      # With self-signed SSL
make site-add SITE=shop.local SSL=letsencrypt  # With Let's Encrypt
make site-add SITE=shop.local PHP=8.4      # With specific PHP version

# What site-add does automatically:
# 1. Creates www/{site}/www/ directories
# 2. Creates nginx config
# 3. Generates per-site configs (DB credentials, SMTP)
# 4. Creates database and MySQL user
# 5. Reloads nginx

# Remove site (COMPLETE REMOVAL)
make site-remove SITE=shop.local           # Removes files, configs, DB

# Site information
make site-list                             # List all sites
make site-reload                           # Reload nginx

# SSL management
make site-ssl SITE=shop.local              # Generate self-signed SSL
make site-ssl-le SITE=shop.local           # Get Let's Encrypt certificate

# Database management
make db-list-sites                         # List all per-site databases
make db-init-site SITE=shop.local          # Manually create DB for site
```

### Backup System (Per-Site)

```bash
# Information
make backup-sites                          # List sites available for backup
make backup-list                           # List all backups
make backup-list-db                        # List database backups
make backup-list-files                     # List file backups

# Create backups
make backup-db                             # Backup all site databases
make backup-db SITE=shop.local             # Backup single site DB
make backup-files                          # Backup all site files
make backup-files SITE=shop.local          # Backup single site files
make backup-full                           # Full backup (DB + files) all sites
make backup-full SITE=shop.local           # Full backup single site

# Restore backups
make backup-restore-db FILE=backups/database/shop_local_20260118.sql.gz
make backup-restore-db FILE=backup.sql.gz SITE=shop.local
make backup-restore-files FILE=backups/files/shop_local_20260118.tar.gz
make backup-restore-files FILE=backup.tar.gz SITE=shop.local
make backup-restore-full DIR=backups/full/shop_local_20260118_120000

# Maintenance
make backup-cleanup                        # Remove old backups
```

### Security

```bash
# Security services
make security-up                           # Start Fail2ban
make security-up-full                      # Start Fail2ban + ModSecurity
make security-down                         # Stop security services
make security-restart                      # Restart security services
make security-status                       # Status of security services

# Fail2ban management
make fail2ban-status                       # Fail2ban status
make fail2ban-jails                        # List all jails
make fail2ban-banned                       # List banned IPs
make fail2ban-unban IP=192.168.1.100       # Unban IP
make fail2ban-ban IP=192.168.1.100         # Ban IP

# Monitoring & stats
make security-logs                         # Fail2ban logs
make security-attacks                      # Recent attacks
make security-stats                        # Security statistics
make security-test                         # Test configuration
```

### Monitoring

```bash
# Monitoring stack
make monitoring-up                         # Start Grafana, Prometheus, Loki
make monitoring-up-prod                    # Start for production
make monitoring-down                       # Stop monitoring

# Portainer (container management UI)
make portainer-up                          # Start Portainer
make portainer-down                        # Stop Portainer
```

### Logs

```bash
make logs-nginx                            # Nginx logs
make logs-nginx-local                      # Nginx logs (local)
make logs-php                              # PHP-FPM logs
make logs-php-local                        # PHP-FPM logs (local)
make logs-mysql                            # MySQL logs
make logs-grafana                          # Grafana logs
make logs-backup                           # Backup logs
```

### Container Access

```bash
make bash_cli                              # PHP CLI shell
make bash_cli_local                        # PHP CLI shell (local)
make bash_nginx                            # Nginx shell
make bash_local_nginx                      # Nginx shell (local)
```

### Nginx Management

```bash
make check_nginx                           # Test nginx config
make check_local_nginx                     # Test nginx config (local)
make reload_nginx                          # Reload nginx
make reload_local_nginx                    # Reload nginx (local)
```

### Database

```bash
make create_dump                           # Create DB dump
make create_dump_local                     # Create DB dump (local)
make restore_dump                          # Restore DB dump
make restore_local_dump                    # Restore DB dump (local)
```

### Build & Clean

```bash
make build-base                            # Build base PHP images
make build-base-cli                        # Build PHP CLI base
make build-base-fpm                        # Build PHP FPM base
make docker-network-create                 # Create Docker network

make clean-volumes                         # Clean Docker volumes
make clean-images                          # Clean Docker images
make clean-all                             # Clean everything
make disk-usage                            # Show disk usage
```

### Configuration

```bash
make setup                                 # Full environment setup
make validate                              # Validate .env file
make auto-config                           # Auto-configure for current hardware
make auto-config-force                     # Force reconfigure
make auto-config-prod                      # Configure for production
make auto-config-preview                   # Preview configuration changes
make auto-config-manual CPU_CORES=8 RAM_GB=16  # Manual configuration
```

### Help

```bash
make help                                  # Main help
make help-quick                            # Quick reference
make help-sites                            # Site management help
make help-backup                           # Backup system help
make help-security                         # Security help
make help-autoconfig                       # Auto-configuration help
```

---

## Multisite Management

### Adding a New Site

```bash
# Simple command creates everything
make site-add SITE=shop.local
```

This command automatically:
1. Creates directory structure: `www/shop.local/www/`
2. Generates nginx configuration
3. Creates per-site configs with unique DB credentials
4. Creates MySQL database and user
5. Reloads nginx

### Site Structure

After adding a site, you get:

```
www/shop.local/
└── www/                          # Document root
    ├── index.php                 # Test page
    ├── bitrix/                   # Bitrix core (install here)
    │   ├── cache/
    │   └── managed_cache/
    ├── upload/                   # User uploads
    └── local/                    # Custom code

config/sites/shop.local/
├── site.env                      # Database credentials
├── database-init.sql             # SQL for DB creation
└── msmtp.conf                    # SMTP configuration

config/nginx/sites/shop.local.conf  # Nginx config
```

### Removing a Site

```bash
# Removes everything: files, configs, database
make site-remove SITE=shop.local
```

### Listing Sites

```bash
make site-list
```

---

## Per-Site Configuration

Each site has isolated configuration:

### Database Isolation

Every site gets its own MySQL database and user:

```bash
# config/sites/shop.local/site.env
DB_NAME=shop_local
DB_USER=shop_local_user
DB_PASSWORD=<auto-generated-secure-password>
```

### SMTP Configuration

Per-site email routing:

```bash
# config/sites/shop.local/msmtp.conf
account shop_local
host mailhog
port 1025
from noreply@shop.local
```

### Cron (Multisite)

Single cron dispatcher handles all sites:

```bash
# Runs Bitrix agents for each site automatically
* * * * * /usr/local/bin/scripts/multisite-cron.sh agents
```

### Logs with Domain Labels

Filter logs by domain in Grafana:

```logql
{job="nginx", domain="shop.local"}
{job="cron", domain="blog.local"}
```

---

## Backup System

### Backup Structure

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

### Per-Site Backups

```bash
# Backup single site
make backup-full SITE=shop.local

# Backup all sites
make backup-full

# List available sites
make backup-sites
```

### Restore

```bash
# Restore database
make backup-restore-db FILE=backups/database/shop_local_20260118.sql.gz SITE=shop.local

# Restore files
make backup-restore-files FILE=backups/files/shop_local_20260118.tar.gz SITE=shop.local

# Restore full backup
make backup-restore-full DIR=backups/full/shop_local_20260118_120000 SITE=shop.local
```

### Automatic Cleanup

```bash
# Remove backups older than BACKUP_RETENTION_DAYS (default: 7)
make backup-cleanup
```

---

## Monitoring

### Grafana

**URL**: http://localhost:3000
**Default credentials**: admin / (from `.env` GRAFANA_ADMIN_PASSWORD)

**Available Dashboards**:
- System Metrics - CPU, RAM, Disk
- Nginx Analytics - requests, errors, response times
- MySQL Performance - queries, connections, slow queries
- Redis Stats - cache hits, memory usage
- Security Dashboard - blocked IPs, attack patterns

### Log Search (Grafana Explore)

```logql
# PHP errors
{container_name="bitrix"} |= "error"

# Slow MySQL queries
{job="mysql"} |= "slow"

# Bitrix agents (cron)
{job="cron"}

# Filter by domain
{job="nginx", domain="shop.local"}

# Fail2ban blocks
{job="fail2ban"} |= "Ban"
```

### Prometheus Metrics

**URL**: http://localhost:9090

Available metrics:
- Container metrics (cAdvisor)
- Nginx metrics (nginx-exporter)
- MySQL metrics (mysqld-exporter)
- Redis metrics (redis-exporter)

---

## Security

### Fail2ban Protection

Automatically blocks IPs after:
- 5 failed login attempts
- Excessive 404 errors
- SQL injection attempts
- XSS attempts

```bash
# Check banned IPs
make fail2ban-banned

# Unban IP
make fail2ban-unban IP=192.168.1.100
```

### Rate Limiting

Nginx rate limits:
- Login/Admin: 5 req/min
- API: 10 req/sec
- Static: 30 req/sec
- General: 2 req/sec

### Security Headers

Automatically applied:
- `X-Frame-Options: SAMEORIGIN`
- `X-Content-Type-Options: nosniff`
- `X-XSS-Protection: 1; mode=block`
- `Referrer-Policy: no-referrer-when-downgrade`

### SSL/TLS

```bash
# Self-signed (development)
make site-ssl SITE=shop.local

# Let's Encrypt (production)
make site-ssl-le SITE=shop.local
```

---

## Troubleshooting

### 502 Bad Gateway

```bash
# Check PHP-FPM status
docker compose -f docker-compose.bitrix.yml exec bitrix supervisorctl status

# Restart PHP-FPM
docker compose -f docker-compose.bitrix.yml exec bitrix supervisorctl restart php-fpm

# Check logs
make logs-php
```

### Database Connection Failed

```bash
# Check MySQL status
docker compose -f docker-compose.bitrix.yml exec mysql mysqladmin ping

# Verify credentials
cat config/sites/shop.local/site.env

# Check if database exists
docker compose -f docker-compose.bitrix.yml exec mysql mysql -u root -p'$DB_ROOT_PASSWORD' -e "SHOW DATABASES"
```

### Site Not Loading After Adding

```bash
# Check nginx config
make check_nginx

# Reload nginx
make reload_nginx

# Verify /etc/hosts
cat /etc/hosts | grep shop.local

# Check site files exist
ls -la www/shop.local/www/
```

### Permission Denied

```bash
# Fix file permissions
sudo chown -R $(id -u):$(id -g) www/
sudo chmod -R 755 www/
sudo chmod -R 777 www/*/www/upload www/*/www/bitrix/cache
```

### Container Won't Start

```bash
# Check logs
docker compose -f docker-compose.bitrix.yml logs bitrix

# Rebuild containers
make build-base
make local-restart
```

---

## FAQ

### How do I switch PHP version?

```bash
# Edit .env
PHP_VERSION=8.4  # or 8.3, 7.4

# Rebuild
make build-base
make local-restart
```

### How do I switch MySQL to MariaDB?

```bash
# Edit .env
MYSQL_IMAGE=mariadb:10.11

# Restart
make local-restart
```

### Where are the logs?

- **Files**: `./volume/logs/` (7 days retention)
- **Grafana/Loki**: http://localhost:3000 (1 year retention)

### How do I access container shell?

```bash
make bash_cli_local    # PHP CLI
make bash_local_nginx  # Nginx
```

### How do I configure SMTP for production?

Edit the per-site msmtp config:

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

### How do I add custom PHP modules?

Edit `docker/php/base/fpm/{version}/Dockerfile` and rebuild:

```bash
make build-base
make local-restart
```

---

## Production Checklist

Before deploying to production:

- [ ] Change ALL passwords in `.env`
- [ ] Set `DEBUG=0`
- [ ] Configure SSL (`SSL=letsencrypt`)
- [ ] Set up firewall (allow only 80, 443, 22)
- [ ] Configure automatic backups
- [ ] Set up external backup storage (S3, rsync)
- [ ] Configure Grafana alerts
- [ ] Enable Fail2ban (`make security-up`)
- [ ] Enable Bitrix composite cache
- [ ] Test backup/restore procedure

---

## License

MIT License

---

## Support

1. Check [Troubleshooting](#troubleshooting)
2. Check [FAQ](#faq)
3. View logs: `make local-logs`
4. Check container status: `make local-ps`

---

**Production Ready!** This environment provides everything needed to run one or multiple Bitrix sites with full isolation, monitoring, security, and automated management.
