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

-- pgvector — 768-dim embedding storage + HNSW ANN index for KnowHub Semantic Layer.
-- Provided by the pgvector/pgvector:pg16 image. Must exist before the sem schema
-- (05-semantic.sql) declares any vector() columns.
CREATE EXTENSION IF NOT EXISTS "vector";
