-- =============================================================================
-- 03-knowhub.sql — KnowHub schema (Document Persistence Service)
-- Owner: knowhub_app | Schema: doc
--
-- Design decisions (per KnowHub TDD v2.0):
--   - PostgreSQL is the AUTHORITY. A document exists only when PostgreSQL says so.
--     If MinIO has the file but PostgreSQL has no row → the document does not exist.
--   - State machine: every document is always in exactly ONE explicit state.
--     Consumers MUST check state before consuming (AVAILABLE = safe to read).
--   - document_lifecycle is append-only. NEVER UPDATE or DELETE rows.
--     It is NOT event sourcing — it explains how state was reached (state is in documents.state).
--   - idempotency_keys are stored in PostgreSQL (NOT Redis) because atomicity
--     between the key and the document row is the only way to prevent race conditions.
--   - document_versions are immutable after ACTIVE. Only state column may change.
--     (PENDING → ACTIVE → SUPERSEDED or INVALID)
-- =============================================================================

SET search_path TO doc;

-- ---------------------------------------------------------------------------
-- documents — Single source of truth for every document
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS doc.documents (
    id              UUID            PRIMARY KEY DEFAULT gen_random_uuid(),
    document_id     UUID            NOT NULL UNIQUE,    -- stable public identifier for callers
    owner_id        UUID            NOT NULL,            -- Keycloak sub of the creating user
    tenant_id       UUID,                               -- future multi-tenancy
    title           VARCHAR(500),
    content_type    VARCHAR(100)    NOT NULL,            -- e.g. "application/pdf", "application/json"
    state           VARCHAR(20)     NOT NULL DEFAULT 'RECEIVED'
                    CHECK (state IN ('RECEIVED', 'PERSISTING', 'AVAILABLE', 'UPDATING', 'FAILED', 'ARCHIVED', 'DELETED')),
    current_version INT             NOT NULL DEFAULT 1,
    payload_engine  VARCHAR(10)     NOT NULL
                    CHECK (payload_engine IN ('mongo', 'minio')),
    storage_tier    VARCHAR(10)     NOT NULL DEFAULT 'hot'
                    CHECK (storage_tier IN ('hot', 'cold')),
    checksum        VARCHAR(128),                        -- SHA-256 of original payload
    size_bytes      BIGINT,
    created_at      TIMESTAMPTZ     NOT NULL DEFAULT now(),
    updated_at      TIMESTAMPTZ     NOT NULL DEFAULT now()
);

COMMENT ON TABLE  doc.documents IS 'Authoritative record for every document. PostgreSQL is the source of truth.';
COMMENT ON COLUMN doc.documents.state IS 'Current lifecycle state. AVAILABLE = safe for consumers to read. PERSISTING = payload write in progress. FAILED = requires investigation.';
COMMENT ON COLUMN doc.documents.document_id IS 'Stable public identifier exposed to callers. id is internal. Using two UUIDs keeps internal keys decoupled from public API contract.';
COMMENT ON COLUMN doc.documents.payload_engine IS 'Which storage backend holds this document: "mongo" for structured payloads, "minio" for binary/large files.';

CREATE INDEX IF NOT EXISTS idx_documents_owner     ON doc.documents (owner_id);
CREATE INDEX IF NOT EXISTS idx_documents_state     ON doc.documents (state);
CREATE INDEX IF NOT EXISTS idx_documents_tenant    ON doc.documents (tenant_id) WHERE tenant_id IS NOT NULL;

-- ---------------------------------------------------------------------------
-- document_versions — Immutable version history
-- Every content update appends a new row. Rows are NEVER overwritten.
-- Only the state column transitions after creation (PENDING → ACTIVE → SUPERSEDED/INVALID).
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS doc.document_versions (
    id              UUID            PRIMARY KEY DEFAULT gen_random_uuid(),
    document_id     UUID            NOT NULL REFERENCES doc.documents(document_id) ON DELETE RESTRICT,
    version         INT             NOT NULL,
    state           VARCHAR(15)     NOT NULL DEFAULT 'PENDING'
                    CHECK (state IN ('PENDING', 'ACTIVE', 'SUPERSEDED', 'INVALID')),
    payload_engine  VARCHAR(10)     NOT NULL CHECK (payload_engine IN ('mongo', 'minio')),
    payload_ref     TEXT            NOT NULL,  -- MongoDB document _id (as string) or MinIO object key
    storage_tier    VARCHAR(10)     NOT NULL DEFAULT 'hot' CHECK (storage_tier IN ('hot', 'cold')),
    checksum        VARCHAR(128)    NOT NULL,  -- SHA-256 of the versioned payload
    size_bytes      BIGINT          NOT NULL,
    created_by      UUID            NOT NULL,  -- Keycloak sub of user who created this version
    created_at      TIMESTAMPTZ     NOT NULL DEFAULT now(),
    UNIQUE (document_id, version)
);

COMMENT ON TABLE  doc.document_versions IS 'Immutable version history. Never overwrite payload_ref, checksum, or size_bytes after ACTIVE. Only state may transition.';
COMMENT ON COLUMN doc.document_versions.payload_ref IS 'MongoDB ObjectId string or MinIO object key (doc/{tenant}/{doc_id}/v{version}/{checksum}).';

CREATE INDEX IF NOT EXISTS idx_versions_document ON doc.document_versions (document_id, version DESC);

-- ---------------------------------------------------------------------------
-- document_lifecycle — Append-only audit trail of state transitions
--
-- NOT event sourcing. State is authoritative in documents.state.
-- This table explains how state was reached — it does NOT rebuild state.
-- Replaying lifecycle rows will NOT give you current state. Use documents.state.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS doc.document_lifecycle (
    id              SERIAL          PRIMARY KEY,
    document_id     UUID            NOT NULL REFERENCES doc.documents(document_id) ON DELETE RESTRICT,
    from_state      VARCHAR(20),    -- NULL for the initial RECEIVED transition
    to_state        VARCHAR(20)     NOT NULL,
    from_version    INT,            -- NULL when no version is involved
    to_version      INT,
    actor_id        VARCHAR(255),   -- Keycloak sub, "system", or job name
    actor_type      VARCHAR(10)     NOT NULL
                    CHECK (actor_type IN ('user', 'system', 'job')),
    reason          TEXT            NOT NULL,  -- e.g. "document.create", "persistence_complete", "compensation"
    correlation_id  UUID,           -- links to originating request — bridges logs and audit records
    metadata        JSONB,          -- optional structured context without polluting columns
    created_at      TIMESTAMPTZ     NOT NULL DEFAULT now()
);

COMMENT ON TABLE doc.document_lifecycle IS 'Append-only audit trail. Never UPDATE or DELETE rows. Explains state transitions — does not rebuild state.';

-- DB-level enforcement: knowhub_app may INSERT but NOT UPDATE or DELETE lifecycle rows
-- (grants applied after table creation, see bottom of file)

CREATE INDEX IF NOT EXISTS idx_lifecycle_document    ON doc.document_lifecycle (document_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_lifecycle_correlation ON doc.document_lifecycle (correlation_id) WHERE correlation_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_lifecycle_actor       ON doc.document_lifecycle (actor_id) WHERE actor_id IS NOT NULL;

-- ---------------------------------------------------------------------------
-- idempotency_keys — Prevents duplicate operations under retry conditions
--
-- Written in the SAME transaction as the document metadata row.
-- Either both commit or neither does. This is the only way to guarantee atomicity.
-- Stored in PostgreSQL (NOT Redis) — correctness requires transactionality.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS doc.idempotency_keys (
    key             VARCHAR(255)    NOT NULL,
    user_id         UUID            NOT NULL,
    operation_type  VARCHAR(50)     NOT NULL  -- "document.create", "document.update"
                    CHECK (operation_type IN ('document.create', 'document.update', 'document.delete')),
    status          VARCHAR(15)     NOT NULL DEFAULT 'IN_PROGRESS'
                    CHECK (status IN ('IN_PROGRESS', 'COMPLETED', 'FAILED')),
    result_ref      UUID,           -- document_id on success
    created_at      TIMESTAMPTZ     NOT NULL DEFAULT now(),
    expires_at      TIMESTAMPTZ     NOT NULL,  -- TTL: created_at + 24h (configurable)
    PRIMARY KEY (key, user_id)
);

COMMENT ON TABLE doc.idempotency_keys IS 'Prevents duplicate document operations on client retry. Written atomically with the document row. Stored in PostgreSQL for transactional atomicity — not Redis.';
COMMENT ON COLUMN doc.idempotency_keys.status IS 'IN_PROGRESS = first attempt running. COMPLETED = return result_ref. FAILED = allow retry.';

CREATE INDEX IF NOT EXISTS idx_idempotency_expires ON doc.idempotency_keys (expires_at);

-- ---------------------------------------------------------------------------
-- updated_at trigger for documents
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION doc.set_updated_at()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$;

CREATE OR REPLACE TRIGGER documents_set_updated_at
    BEFORE UPDATE ON doc.documents
    FOR EACH ROW EXECUTE FUNCTION doc.set_updated_at();

-- ---------------------------------------------------------------------------
-- Grants to knowhub_app
-- ---------------------------------------------------------------------------
GRANT SELECT, INSERT, UPDATE, DELETE ON doc.documents         TO knowhub_app;
GRANT SELECT, INSERT, UPDATE, DELETE ON doc.document_versions TO knowhub_app;
GRANT SELECT, INSERT, UPDATE, DELETE ON doc.idempotency_keys  TO knowhub_app;
GRANT USAGE, SELECT ON SEQUENCE doc.document_lifecycle_id_seq TO knowhub_app;
-- idempotency_keys has a composite PK (key, user_id) — no sequence to grant.

-- document_lifecycle: INSERT only. No UPDATE, no DELETE. Audit trail is immutable.
GRANT INSERT, SELECT ON doc.document_lifecycle TO knowhub_app;
REVOKE UPDATE, DELETE ON doc.document_lifecycle FROM knowhub_app;

-- Future tables
ALTER DEFAULT PRIVILEGES IN SCHEMA doc
    GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES    TO knowhub_app;
ALTER DEFAULT PRIVILEGES IN SCHEMA doc
    GRANT USAGE, SELECT                  ON SEQUENCES TO knowhub_app;
