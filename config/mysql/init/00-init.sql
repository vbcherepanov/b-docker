-- ============================================================================
-- MySQL/MariaDB Initial Setup for Bitrix Docker Multisite
-- Runs once when database is first initialized
-- ============================================================================

-- Note: Exporter user is created via 01-exporter.sh script
-- which reads MYSQL_EXPORTER_PASSWORD from environment

-- Note: Per-site databases are created dynamically via `make site-add`
-- The main database is created via MYSQL_DATABASE env variable
