-- =============================================================================
-- 06-chat.sql — KnowHub Conversational RAG (Phase 2)
-- Owner: knowhub_app | Schema: chat
--
-- Persists chat sessions, messages, and citation provenance for the RAG layer.
-- Co-located with doc.documents and sem.document_chunks so a citation is a
-- foreign-key relationship into the knowledge base — not an opaque string.
--
-- Design (per Conversational RAG TDD v1.0 §7):
--   - chat_sessions   : one conversation, owned by a Keycloak subject (tenant).
--   - chat_messages   : user/assistant/system turns; assistant rows carry the
--                       generation model + token counts + Langfuse trace id.
--   - message_citations: the exact chunks an assistant message was grounded in,
--                       ranked in prompt order — the UI's verifiable "Sources".
--
-- This script bootstraps a FRESH dev database. The equivalent change for an
-- existing/prod database is the Prisma migration in
-- know-hub/prisma/migrations/*_chat_schema/migration.sql. Both are idempotent.
-- =============================================================================

CREATE SCHEMA IF NOT EXISTS chat;
GRANT USAGE ON SCHEMA chat TO knowhub_app;

-- Message author. 'system' is reserved for future system-authored notes.
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_type t JOIN pg_namespace n ON n.oid = t.typnamespace
    WHERE t.typname = 'message_role' AND n.nspname = 'chat'
  ) THEN
    CREATE TYPE chat.message_role AS ENUM ('user', 'assistant', 'system');
  END IF;
END$$;

-- ---------------------------------------------------------------------------
-- chat.chat_sessions — one row per conversation
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS chat.chat_sessions (
    id          uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
    owner_id    uuid        NOT NULL,              -- Keycloak subject (tenant boundary)
    title       text        NOT NULL DEFAULT 'New conversation',
    created_at  timestamptz NOT NULL DEFAULT now(),
    updated_at  timestamptz NOT NULL DEFAULT now()
);

-- Sidebar query: a user's sessions, most-recently-active first.
CREATE INDEX IF NOT EXISTS idx_sessions_owner
    ON chat.chat_sessions (owner_id, updated_at DESC);

-- ---------------------------------------------------------------------------
-- chat.chat_messages — user/assistant turns, ordered within a session
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS chat.chat_messages (
    id                 uuid              PRIMARY KEY DEFAULT gen_random_uuid(),
    session_id         uuid              NOT NULL REFERENCES chat.chat_sessions(id) ON DELETE CASCADE,
    role               chat.message_role NOT NULL,
    content            text              NOT NULL,
    model              text,                          -- generation model (audit/repro)
    prompt_tokens      integer,                       -- from Ollama final frame
    completion_tokens  integer,
    langfuse_trace_id  text,                          -- link a message to its trace
    created_at         timestamptz       NOT NULL DEFAULT now()
);

-- Load a conversation in order; fetch the last N for context.
CREATE INDEX IF NOT EXISTS idx_messages_session
    ON chat.chat_messages (session_id, created_at);

-- ---------------------------------------------------------------------------
-- chat.message_citations — provenance: which chunks grounded an answer
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS chat.message_citations (
    id                uuid         PRIMARY KEY DEFAULT gen_random_uuid(),
    message_id        uuid         NOT NULL REFERENCES chat.chat_messages(id) ON DELETE CASCADE,
    document_id       uuid         NOT NULL,         -- doc.documents.id (internal)
    chunk_id          uuid         NOT NULL,         -- sem.document_chunks.id
    rank              integer      NOT NULL,         -- 1-based order in the prompt
    similarity_score  numeric(6,4) NOT NULL
);

-- Render sources for a message in prompt order.
CREATE INDEX IF NOT EXISTS idx_citations_message
    ON chat.message_citations (message_id, rank);

COMMENT ON TABLE chat.message_citations IS 'Provenance is first-class: each assistant message links to the exact chunks it was grounded in, ranked in prompt order.';

-- ---------------------------------------------------------------------------
-- Grants — knowhub_app owns the chat schema at runtime.
-- ---------------------------------------------------------------------------
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA chat TO knowhub_app;

ALTER DEFAULT PRIVILEGES IN SCHEMA chat
    GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES    TO knowhub_app;
ALTER DEFAULT PRIVILEGES IN SCHEMA chat
    GRANT USAGE, SELECT                  ON SEQUENCES TO knowhub_app;
