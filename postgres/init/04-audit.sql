-- =============================================================================
-- 04-audit.sql — AuditHub schema
-- Owner: audithub_app | Schema: audit
--
-- Design decisions:
--   - append-only: no UPDATE or DELETE on audit_events (enforced at app level)
--   - actor_id is the Keycloak sub (UUID string) — links to users.keycloak_id
--   - metadata is JSONB for flexible per-event context without schema churn
--   - indexes on actor_id + occurred_at support the two primary query patterns:
--       1. GET /audit/activity/me  — filter by actor_id, order by occurred_at
--       2. GET /audit/activity     — filter by action / service / date range
-- =============================================================================

SET search_path TO audit;

-- ---------------------------------------------------------------------------
-- audit_events — Immutable record of every material platform action
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS audit.audit_events (
    id               UUID          PRIMARY KEY DEFAULT gen_random_uuid(),
    event_id         UUID          NOT NULL UNIQUE,     -- dedup key (from Kafka message key)

    -- When / Who
    occurred_at      TIMESTAMPTZ   NOT NULL,
    actor_id         TEXT          NOT NULL,            -- Keycloak sub
    actor_email      TEXT,
    actor_roles      TEXT[]        DEFAULT '{}',

    -- What
    action           TEXT          NOT NULL,            -- e.g. DOCUMENT_UPLOADED
    service          TEXT          NOT NULL,            -- auth-hub | user-hub | know-hub

    -- On which resource
    resource_type    TEXT,                              -- Document | User | Note
    resource_id      TEXT,                              -- resource UUID/ID
    resource_name    TEXT,                              -- human-readable label

    -- Result
    outcome          TEXT          NOT NULL DEFAULT 'SUCCESS'
                     CHECK (outcome IN ('SUCCESS', 'FAILURE')),

    -- Traceability
    correlation_id   TEXT,

    -- Flexible per-event context (state transitions, old/new values, etc.)
    metadata         JSONB,

    created_at       TIMESTAMPTZ   NOT NULL DEFAULT now()
);

-- ---------------------------------------------------------------------------
-- Indexes
-- ---------------------------------------------------------------------------

-- Primary query: "all activity for user X, newest first" (ActivityPage)
CREATE INDEX IF NOT EXISTS idx_audit_events_actor_occurred
    ON audit.audit_events (actor_id, occurred_at DESC);

-- Admin query: filter by action type
CREATE INDEX IF NOT EXISTS idx_audit_events_action
    ON audit.audit_events (action);

-- Filter by service
CREATE INDEX IF NOT EXISTS idx_audit_events_service
    ON audit.audit_events (service);

-- Date-range scans
CREATE INDEX IF NOT EXISTS idx_audit_events_occurred_at
    ON audit.audit_events (occurred_at DESC);

-- ---------------------------------------------------------------------------
-- Grants — audithub_app can INSERT and SELECT only (never UPDATE/DELETE)
-- ---------------------------------------------------------------------------
GRANT SELECT, INSERT ON audit.audit_events TO audithub_app;
GRANT USAGE ON SCHEMA audit TO audithub_app;
