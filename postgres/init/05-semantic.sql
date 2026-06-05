-- =============================================================================
-- 05-semantic.sql — KnowHub Semantic Layer (Phase 1)
-- Owner: knowhub_app | Schema: sem
--
-- Adds the vector store that turns KnowHub from a document store into a
-- knowledge base searchable by meaning. Co-located with doc.documents so that
-- vector queries and metadata joins stay inside one PostgreSQL round-trip.
--
-- Design (per Semantic Layer TDD v1.0):
--   - One row per text chunk (512 tokens, 64 overlap) of a document.
--   - embedding is a 768-dim nomic-embed-text vector — NULL until the Semantic
--     Worker has processed it. A document is valid and downloadable long before
--     its chunks are embedded; embedding is derived, regenerable data.
--   - HNSW (cosine) index powers ANN similarity; GIN(tsvector) powers FTS — the
--     two halves of hybrid RRF search.
--   - doc.documents.embedding_status communicates pipeline progress to the UI.
--
-- This script bootstraps a FRESH dev database. The equivalent change for an
-- existing/prod database is the Prisma migration in
-- know-hub/prisma/migrations/*_semantic_layer/migration.sql. Both are idempotent.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- Schema + grants
-- ---------------------------------------------------------------------------
CREATE SCHEMA IF NOT EXISTS sem;

GRANT USAGE ON SCHEMA sem TO knowhub_app;

-- ---------------------------------------------------------------------------
-- sem.document_chunks — chunk text + 768-dim embedding
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS sem.document_chunks (
    id           UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    document_id  UUID        NOT NULL,         -- FK → doc.documents.id (internal id)
    chunk_index  INTEGER     NOT NULL,         -- 0-based position in document
    content      TEXT        NOT NULL,         -- raw text of this chunk
    token_count  INTEGER     NOT NULL,         -- approximate word-boundary tokens
    embedding    vector(768),                  -- NULL until Ollama processes it
    model        VARCHAR(80) NOT NULL DEFAULT 'nomic-embed-text',
    embedded_at  TIMESTAMPTZ,                  -- NULL if not yet embedded
    created_at   TIMESTAMPTZ DEFAULT now(),

    CONSTRAINT fk_document
        FOREIGN KEY (document_id)
        REFERENCES doc.documents(id) ON DELETE CASCADE,

    CONSTRAINT uq_document_chunk
        UNIQUE (document_id, chunk_index)      -- idempotent re-indexing
);

COMMENT ON TABLE  sem.document_chunks IS 'One row per text chunk. embedding is derived data regenerable from the MinIO/Mongo payload — never the source of truth.';
COMMENT ON COLUMN sem.document_chunks.embedding IS '768-dim nomic-embed-text vector (float32). NULL until the Semantic Worker embeds the chunk.';

-- HNSW index for ANN cosine search (m=16 connections/node, ef_construction=64).
CREATE INDEX IF NOT EXISTS idx_chunks_hnsw
    ON sem.document_chunks
    USING hnsw (embedding vector_cosine_ops)
    WITH (m = 16, ef_construction = 64);

-- Generated tsvector column + GIN index for the FTS half of hybrid RRF search.
ALTER TABLE sem.document_chunks
    ADD COLUMN IF NOT EXISTS content_tsv tsvector
    GENERATED ALWAYS AS (to_tsvector('english', content)) STORED;

CREATE INDEX IF NOT EXISTS idx_chunks_fts
    ON sem.document_chunks USING gin(content_tsv);

-- ---------------------------------------------------------------------------
-- doc.documents.embedding_status — pipeline progress, surfaced to the UI
--   PENDING   uploaded, worker has not processed it yet
--   INDEXING  worker is actively chunking + embedding
--   INDEXED   all chunks embedded — fully searchable by concept
--   FAILED    worker error — admin can POST /api/semantic/reindex/:id
--   SKIPPED   content-type has no extractable text layer
-- ---------------------------------------------------------------------------
ALTER TABLE doc.documents
    ADD COLUMN IF NOT EXISTS embedding_status VARCHAR(20) NOT NULL DEFAULT 'PENDING';

-- Partial index — only the actionable states the worker needs to find.
CREATE INDEX IF NOT EXISTS idx_docs_embed_status
    ON doc.documents(embedding_status)
    WHERE embedding_status IN ('PENDING', 'FAILED');

-- ---------------------------------------------------------------------------
-- Grants to knowhub_app (table created above must be granted explicitly;
-- default privileges then cover any future sem tables).
-- ---------------------------------------------------------------------------
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA sem TO knowhub_app;

ALTER DEFAULT PRIVILEGES IN SCHEMA sem
    GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES    TO knowhub_app;
ALTER DEFAULT PRIVILEGES IN SCHEMA sem
    GRANT USAGE, SELECT                  ON SEQUENCES TO knowhub_app;
