-- =============================================================================
-- 41-doc-agent-columns.sql — Phase-3 ingestion-crew columns on doc.documents
-- Owner: knowhub_app | Schema: doc
--
-- The agentic ingestion crew (agent-hub) classifies documents and records HOW
-- each was chunked. know-hub remains the single writer of these columns (it
-- owns doc.documents); agent-hub only proposes the values via the gRPC
-- UpdateMetadata RPC (Principle 5 / ADR-AGT-06).
--
-- Runs after 03-knowhub.sql (doc.documents must exist). Idempotent.
-- =============================================================================

ALTER TABLE doc.documents
    ADD COLUMN IF NOT EXISTS doc_type       TEXT,   -- contract | deck | chat | article | ...
    ADD COLUMN IF NOT EXISTS topic          TEXT,   -- Classifier topical facet
    ADD COLUMN IF NOT EXISTS chunk_strategy TEXT;   -- clause | slide | turn | fixed (provenance)

COMMENT ON COLUMN doc.documents.doc_type       IS 'Classifier verdict (agent-hub). Filter/group docs by type.';
COMMENT ON COLUMN doc.documents.topic          IS 'Classifier topical facet for search & dashboards.';
COMMENT ON COLUMN doc.documents.chunk_strategy IS 'Provenance: which strategy the Chunker used for this document.';

-- Facet indexes for filtering/dashboards.
CREATE INDEX IF NOT EXISTS idx_docs_doc_type ON doc.documents(doc_type) WHERE doc_type IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_docs_topic    ON doc.documents(topic)    WHERE topic    IS NOT NULL;
