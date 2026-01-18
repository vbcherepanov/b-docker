-- ============================================================================
-- MySQL/MariaDB Initial Setup for Bitrix Docker Multisite
-- Runs once when database is first initialized
-- ============================================================================

-- Create exporter user for Prometheus monitoring (optional)
CREATE USER IF NOT EXISTS 'exporter'@'%' IDENTIFIED BY 'exporter_password';
GRANT PROCESS, REPLICATION CLIENT, SELECT ON *.* TO 'exporter'@'%';

FLUSH PRIVILEGES;

-- Note: Per-site databases are created dynamically via `make site-add`
-- The main database is created via MYSQL_DATABASE env variable
