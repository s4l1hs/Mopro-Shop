-- 00-extensions.sql — install required Postgres extensions on postgres-ecom
-- Runs once on empty volume during container first-start.

CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE EXTENSION IF NOT EXISTS pg_stat_statements;
