-- =============================================================================
-- 01-schemas.sql — Schema and role bootstrap
--
-- Brainwave uses schema-level isolation between microservices.
-- Each service owns its schema. Cross-schema reads are explicitly controlled.
--
-- Schemas:
--   user_management  — UserHub (users, roles, permissions, outbox)
--   doc              — KnowHub (documents, versions, lifecycle, idempotency)
--   audit            — AuditHub (immutable audit event log)
--
-- DB users:
--   userhub_app      — UserHub application user (user_management schema only)
--   knowhub_app      — KnowHub application user (doc schema only)
--   audithub_app     — AuditHub application user (audit schema only, INSERT+SELECT)
--
-- This separation enforces the TDD principle: services cannot accidentally
-- read each other's tables. A bug in KnowHub cannot corrupt user records.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- Schemas
-- ---------------------------------------------------------------------------
CREATE SCHEMA IF NOT EXISTS user_management;
CREATE SCHEMA IF NOT EXISTS doc;
CREATE SCHEMA IF NOT EXISTS audit;

-- ---------------------------------------------------------------------------
-- Application roles — Least privilege per service
-- ---------------------------------------------------------------------------

-- UserHub app user: full access to user_management schema
DO $$
BEGIN
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'userhub_app') THEN
    CREATE ROLE userhub_app WITH LOGIN PASSWORD 'userhub_dev_password';
  END IF;
END
$$;

-- KnowHub app user: full access to doc schema
DO $$
BEGIN
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'knowhub_app') THEN
    CREATE ROLE knowhub_app WITH LOGIN PASSWORD 'knowhub_dev_password';
  END IF;
END
$$;

-- AuditHub app user: INSERT + SELECT on audit schema only (never UPDATE/DELETE)
DO $$
BEGIN
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'audithub_app') THEN
    CREATE ROLE audithub_app WITH LOGIN PASSWORD 'audithub_dev_password';
  END IF;
END
$$;

-- Grant schema-level privileges
GRANT USAGE, CREATE ON SCHEMA user_management TO userhub_app;
GRANT USAGE, CREATE ON SCHEMA doc TO knowhub_app;
GRANT USAGE, CREATE ON SCHEMA audit TO audithub_app;
