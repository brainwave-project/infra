-- =============================================================================
-- 00-extensions.sql — PostgreSQL extensions
-- Runs first. All extensions must be created before schemas reference them.
-- =============================================================================

-- UUID generation for primary keys and generated IDs
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Cryptographic functions (pgcrypto) — gen_random_uuid() used across schemas
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- Case-insensitive text — for email uniqueness checks (optional but useful)
CREATE EXTENSION IF NOT EXISTS "citext";
