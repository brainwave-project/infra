-- =============================================================================
-- 02-user-management.sql — UserHub schema
-- Owner: userhub_app | Schema: user_management
--
-- Design decisions (per AuthHub TDD v2.0):
--   - No passwords, tokens, or session data stored here.
--     PostgreSQL stores BUSINESS data only.
--     Keycloak stores identity/auth data.
--     The single link between them is keycloak_id (the JWT "sub" claim).
--   - user_events is the Transactional Outbox table.
--     Events are written in the SAME transaction as the business change.
--     A background worker reads and publishes them. If the transaction rolls back,
--     the event is also rolled back — no orphaned notifications.
-- =============================================================================

SET search_path TO user_management;

-- ---------------------------------------------------------------------------
-- users — Business user record (NOT the authentication record)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS user_management.users (
    id              SERIAL          PRIMARY KEY,
    keycloak_id     UUID            NOT NULL UNIQUE,  -- maps to JWT "sub" claim
    email           CITEXT          NOT NULL UNIQUE,  -- CITEXT = case-insensitive
    full_name       VARCHAR(255),
    display_name    VARCHAR(100),
    account_status  VARCHAR(20)     NOT NULL DEFAULT 'pending_identity'
                    CHECK (account_status IN ('pending_identity', 'active', 'suspended', 'disabled', 'failed')),
    created_at      TIMESTAMPTZ     NOT NULL DEFAULT now(),
    updated_at      TIMESTAMPTZ     NOT NULL DEFAULT now()
);

COMMENT ON TABLE  user_management.users IS 'Business user records. No passwords, tokens, or session data stored here.';
COMMENT ON COLUMN user_management.users.keycloak_id IS 'Keycloak sub claim. The only link between this record and the IdP.';
COMMENT ON COLUMN user_management.users.account_status IS 'pending_identity = Keycloak record not yet created. active = fully provisioned. suspended = access blocked.';

-- ---------------------------------------------------------------------------
-- roles — Coarse roles mirrored from Keycloak (ADMIN, EDITOR, VIEWER)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS user_management.roles (
    id          SERIAL          PRIMARY KEY,
    name        VARCHAR(100)    NOT NULL UNIQUE,  -- must match Keycloak realm role names
    description TEXT,
    created_at  TIMESTAMPTZ     NOT NULL DEFAULT now()
);

COMMENT ON TABLE user_management.roles IS 'Coarse roles. Names must match Keycloak realm role names exactly.';

-- Seed roles to match Keycloak realm-export.json
INSERT INTO user_management.roles (name, description) VALUES
    ('ADMIN',  'Full platform access: manage users, all documents, system config'),
    ('EDITOR', 'Create, read, and update documents. Cannot delete or manage users'),
    ('VIEWER', 'Read-only access to documents they have been granted access to')
ON CONFLICT (name) DO NOTHING;

-- ---------------------------------------------------------------------------
-- user_roles — Junction table: user ↔ role assignment
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS user_management.user_roles (
    user_id     INT             NOT NULL REFERENCES user_management.users(id)  ON DELETE CASCADE,
    role_id     INT             NOT NULL REFERENCES user_management.roles(id)  ON DELETE CASCADE,
    assigned_at TIMESTAMPTZ     NOT NULL DEFAULT now(),
    assigned_by INT             REFERENCES user_management.users(id),  -- NULL = system assignment
    PRIMARY KEY (user_id, role_id)
);

-- ---------------------------------------------------------------------------
-- permissions — Fine-grained permission definitions
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS user_management.permissions (
    id          SERIAL          PRIMARY KEY,
    name        VARCHAR(100)    NOT NULL UNIQUE,  -- e.g. "create_document", "delete_document"
    description TEXT,
    created_at  TIMESTAMPTZ     NOT NULL DEFAULT now()
);

-- Seed permissions per TDD
INSERT INTO user_management.permissions (name, description) VALUES
    ('create_document', 'Upload and create new documents'),
    ('read_document',   'Read and download documents'),
    ('update_document', 'Update document content (creates new version)'),
    ('delete_document', 'Soft-delete documents (owner or admin only)'),
    ('manage_users',    'Create, suspend, and manage user accounts (admin only)')
ON CONFLICT (name) DO NOTHING;

-- ---------------------------------------------------------------------------
-- role_permissions — Which permissions each role has
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS user_management.role_permissions (
    role_id         INT NOT NULL REFERENCES user_management.roles(id)       ON DELETE CASCADE,
    permission_id   INT NOT NULL REFERENCES user_management.permissions(id) ON DELETE CASCADE,
    PRIMARY KEY (role_id, permission_id)
);

-- Seed role-permission mappings
DO $$
DECLARE
    admin_id  INT;
    editor_id INT;
    viewer_id INT;
    perm_ids  INT[];
BEGIN
    SELECT id INTO admin_id  FROM user_management.roles WHERE name = 'ADMIN';
    SELECT id INTO editor_id FROM user_management.roles WHERE name = 'EDITOR';
    SELECT id INTO viewer_id FROM user_management.roles WHERE name = 'VIEWER';

    -- ADMIN: all permissions
    INSERT INTO user_management.role_permissions (role_id, permission_id)
        SELECT admin_id, id FROM user_management.permissions
        ON CONFLICT DO NOTHING;

    -- EDITOR: create, read, update (no delete, no manage_users)
    INSERT INTO user_management.role_permissions (role_id, permission_id)
        SELECT editor_id, id FROM user_management.permissions
        WHERE name IN ('create_document', 'read_document', 'update_document')
        ON CONFLICT DO NOTHING;

    -- VIEWER: read only
    INSERT INTO user_management.role_permissions (role_id, permission_id)
        SELECT viewer_id, id FROM user_management.permissions
        WHERE name = 'read_document'
        ON CONFLICT DO NOTHING;
END
$$;

-- ---------------------------------------------------------------------------
-- user_events — Transactional Outbox (per AuthHub TDD s5.6)
--
-- Written in the SAME transaction as the business operation.
-- A background worker reads unprocessed events and publishes them.
-- processed_at = NULL means the event is pending.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS user_management.user_events (
    id              SERIAL          PRIMARY KEY,
    event_type      VARCHAR(50)     NOT NULL
                    CHECK (event_type IN ('user.created', 'user.activated', 'user.suspended', 'user.deleted', 'user.role_changed')),
    user_id         INT             NOT NULL,  -- does NOT reference users(id) — survives user deletion
    keycloak_id     UUID            NOT NULL,
    payload         JSONB,
    created_at      TIMESTAMPTZ     NOT NULL DEFAULT now(),
    processed_at    TIMESTAMPTZ,               -- NULL = pending. Set by worker when processed.
    error           TEXT                       -- Set if processing failed; allows investigation.
);

COMMENT ON TABLE  user_management.user_events IS 'Transactional outbox. Events are written atomically with business changes. Never mutate after creation.';
COMMENT ON COLUMN user_management.user_events.processed_at IS 'NULL = pending. Set by the outbox worker. Never updated by business code.';

CREATE INDEX IF NOT EXISTS idx_user_events_pending
    ON user_management.user_events (created_at)
    WHERE processed_at IS NULL;

-- ---------------------------------------------------------------------------
-- user_preferences — Key-value preferences per user
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS user_management.user_preferences (
    user_id     INT             NOT NULL REFERENCES user_management.users(id) ON DELETE CASCADE,
    key         VARCHAR(50)     NOT NULL,   -- e.g. "theme", "language", "notifications"
    value       TEXT,
    updated_at  TIMESTAMPTZ     NOT NULL DEFAULT now(),
    PRIMARY KEY (user_id, key)
);

-- ---------------------------------------------------------------------------
-- updated_at trigger for users table
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION user_management.set_updated_at()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$;

CREATE OR REPLACE TRIGGER users_set_updated_at
    BEFORE UPDATE ON user_management.users
    FOR EACH ROW EXECUTE FUNCTION user_management.set_updated_at();

-- ---------------------------------------------------------------------------
-- Grants to userhub_app
-- ---------------------------------------------------------------------------
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES    IN SCHEMA user_management TO userhub_app;
GRANT USAGE, SELECT                  ON ALL SEQUENCES IN SCHEMA user_management TO userhub_app;

-- Future tables will also be auto-granted
ALTER DEFAULT PRIVILEGES IN SCHEMA user_management
    GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES    TO userhub_app;
ALTER DEFAULT PRIVILEGES IN SCHEMA user_management
    GRANT USAGE, SELECT                  ON SEQUENCES TO userhub_app;
