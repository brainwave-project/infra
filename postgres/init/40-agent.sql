-- =============================================================================
-- 40-agent.sql — AgentHub reasoning store (Phase 3)
-- Owner: agent_role | Schema: agent
--
-- Records every agent run, step, and decision for audit, debugging, and future
-- evaluation (TDD §9). LangGraph's PostgresSaver also lives here: it CREATEs and
-- manages its own checkpoint tables (checkpoints, checkpoint_writes, ...), so
-- agent_role must be able to create objects in this schema.
--
-- `CREATE SCHEMA ... AUTHORIZATION agent_role` already makes agent_role the
-- owner (ownership implies CREATE), but we GRANT it explicitly so the intent is
-- visible and the checkpointer keeps working even if the connecting role is ever
-- changed to a non-owner (review note on §13.4).
--
-- This script bootstraps a FRESH dev database (runs once on container creation).
-- =============================================================================

-- ---------------------------------------------------------------------------
-- Role
-- ---------------------------------------------------------------------------
DO $$
BEGIN
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'agent_role') THEN
    CREATE ROLE agent_role WITH LOGIN PASSWORD 'agent_dev_password';
  END IF;
END
$$;

-- ---------------------------------------------------------------------------
-- Schema + grants
-- ---------------------------------------------------------------------------
CREATE SCHEMA IF NOT EXISTS agent AUTHORIZATION agent_role;

GRANT USAGE, CREATE ON SCHEMA agent TO agent_role;   -- CREATE: LangGraph checkpointer

-- ---------------------------------------------------------------------------
-- Enums
-- ---------------------------------------------------------------------------
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'run_kind') THEN
    CREATE TYPE agent.run_kind AS ENUM ('CRAG', 'INGESTION');
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'run_status') THEN
    CREATE TYPE agent.run_status AS ENUM ('RUNNING', 'SUCCEEDED', 'ABSTAINED', 'FAILED');
  END IF;
END
$$;

-- ---------------------------------------------------------------------------
-- agent.agent_runs — one row per CRAG / ingestion run (TDD §9.2)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS agent.agent_runs (
    id             UUID             PRIMARY KEY DEFAULT gen_random_uuid(),
    kind           agent.run_kind   NOT NULL,
    thread_id      TEXT             NOT NULL,          -- LangGraph checkpoint key (chat session id | document id)
    actor_user_id  TEXT,                               -- X-User-Id (CRAG) | event actor (ingestion)
    status         agent.run_status NOT NULL DEFAULT 'RUNNING',
    loops          INTEGER          NOT NULL DEFAULT 0, -- corrective iterations (CRAG) / routing steps (ingestion)
    started_at     TIMESTAMPTZ      NOT NULL DEFAULT now(),
    ended_at       TIMESTAMPTZ,
    correlation_id TEXT                                -- joins logs ⇄ Langfuse trace
);

CREATE INDEX IF NOT EXISTS idx_agent_runs_thread  ON agent.agent_runs(thread_id);
CREATE INDEX IF NOT EXISTS idx_agent_runs_actor   ON agent.agent_runs(actor_user_id);
CREATE INDEX IF NOT EXISTS idx_agent_runs_status  ON agent.agent_runs(status) WHERE status = 'RUNNING';

COMMENT ON TABLE agent.agent_runs IS 'One row per agent run. agent-hub reasons only; this is a trajectory/audit log, never a system of record.';

-- ---------------------------------------------------------------------------
-- agent.agent_steps — ordered node/decision trace within a run (TDD §9.3)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS agent.agent_steps (
    id             UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    run_id         UUID        NOT NULL REFERENCES agent.agent_runs(id) ON DELETE CASCADE,
    seq            INTEGER     NOT NULL,               -- order within the run
    node           TEXT        NOT NULL,               -- retrieve | grade | classifier | ...
    decision       TEXT,                               -- conditional-edge outcome / supervisor route
    input_summary  TEXT,                               -- REDACTED summary — never full document text (§14)
    output_summary TEXT,                               -- REDACTED summary
    latency_ms     INTEGER,
    created_at     TIMESTAMPTZ NOT NULL DEFAULT now(),

    CONSTRAINT uq_step_seq UNIQUE (run_id, seq)
);

CREATE INDEX IF NOT EXISTS idx_agent_steps_run ON agent.agent_steps(run_id);

COMMENT ON COLUMN agent.agent_steps.input_summary  IS 'Redacted summary only — full document bodies never enter the observability store (§14 trace redaction).';

-- ---------------------------------------------------------------------------
-- agent.agent_governance — runtime-tunable RAG/CRAG knobs (TDD §13.5)
-- Single-row table (id = 1): one governance profile per environment. The whole
-- knob set is stored as JSONB so adding a control later needs no migration — the
-- app merges stored overrides over its shipped defaults. Operator writes come via
-- the ADMIN-only PUT /api/agent/governance; the reasoning path reads a cached copy.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS agent.agent_governance (
    id          INTEGER     PRIMARY KEY DEFAULT 1,
    data        JSONB       NOT NULL,
    updated_by  TEXT,                                  -- X-User-Id of the last editor
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT now(),

    CONSTRAINT agent_governance_singleton CHECK (id = 1)
);

COMMENT ON TABLE agent.agent_governance IS 'Single-row runtime config for retrieval + CRAG (top-K, cross-encoder, temperatures, loop caps). Overlays shipped defaults; never a system of record.';

-- ---------------------------------------------------------------------------
-- Grants — agent_role owns the schema (AUTHORIZATION above) so it already has
-- rights on these tables; explicit grants + default privileges keep parity with
-- the other services and cover the checkpointer tables LangGraph creates later.
-- ---------------------------------------------------------------------------
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES    IN SCHEMA agent TO agent_role;
GRANT USAGE, SELECT                  ON ALL SEQUENCES IN SCHEMA agent TO agent_role;

ALTER DEFAULT PRIVILEGES IN SCHEMA agent
    GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES    TO agent_role;
ALTER DEFAULT PRIVILEGES IN SCHEMA agent
    GRANT USAGE, SELECT                  ON SEQUENCES TO agent_role;
