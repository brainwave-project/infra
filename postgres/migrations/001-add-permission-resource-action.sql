-- =============================================================================
-- Migration 001 — Expand permissions catalogue with resource/action columns
--                 and align role_permissions with new seed data.
--
-- Run against existing dev/staging DBs:
--   docker exec -i brainwave-postgres psql -U postgres -d brainwave < migrations/001-add-permission-resource-action.sql
-- =============================================================================

BEGIN;

-- ---------------------------------------------------------------------------
-- Step 1: Add resource + action columns to permissions (not null with defaults)
-- ---------------------------------------------------------------------------
ALTER TABLE user_management.permissions
    ADD COLUMN IF NOT EXISTS resource VARCHAR(50),
    ADD COLUMN IF NOT EXISTS action   VARCHAR(50);

-- ---------------------------------------------------------------------------
-- Step 2: Backfill resource + action from the old name format
--         (old format was "create_document" → new is "document:create")
-- ---------------------------------------------------------------------------
UPDATE user_management.permissions SET resource = 'document', action = 'create'  WHERE name = 'create_document';
UPDATE user_management.permissions SET resource = 'document', action = 'read'    WHERE name = 'read_document';
UPDATE user_management.permissions SET resource = 'document', action = 'update'  WHERE name = 'update_document';
UPDATE user_management.permissions SET resource = 'document', action = 'delete'  WHERE name = 'delete_document';
UPDATE user_management.permissions SET resource = 'user',     action = 'manage'  WHERE name = 'manage_users';

-- ---------------------------------------------------------------------------
-- Step 3: Rename old permission names → new "resource:action" convention
-- ---------------------------------------------------------------------------
UPDATE user_management.permissions SET name = 'document:create'  WHERE name = 'create_document';
UPDATE user_management.permissions SET name = 'document:read'    WHERE name = 'read_document';
UPDATE user_management.permissions SET name = 'document:update'  WHERE name = 'update_document';
UPDATE user_management.permissions SET name = 'document:delete'  WHERE name = 'delete_document';
-- manage_users → split into user:create, user:update, user:delete, user:read
DELETE FROM user_management.role_permissions
  WHERE permission_id = (SELECT id FROM user_management.permissions WHERE name = 'manage_users');
DELETE FROM user_management.permissions WHERE name = 'manage_users';

-- ---------------------------------------------------------------------------
-- Step 4: Add new permissions that didn't exist before
-- ---------------------------------------------------------------------------
INSERT INTO user_management.permissions (name, resource, action, description) VALUES
    ('document:archive', 'document', 'archive', 'Archive documents'),
    ('note:read',        'note',     'read',    'Read notes on documents'),
    ('note:create',      'note',     'create',  'Add notes to documents'),
    ('note:update',      'note',     'update',  'Edit own notes'),
    ('note:delete',      'note',     'delete',  'Delete notes'),
    ('user:read',        'user',     'read',    'View user list and profiles'),
    ('user:create',      'user',     'create',  'Create new users'),
    ('user:update',      'user',     'update',  'Update user status and details'),
    ('user:delete',      'user',     'delete',  'Disable users'),
    ('role:read',        'role',     'read',    'View roles and their permissions'),
    ('role:assign',      'role',     'assign',  'Assign roles to users'),
    ('permission:manage','permission','manage', 'Grant or revoke permissions on roles')
ON CONFLICT (name) DO NOTHING;

-- Backfill resource/action for any remaining NULLs
UPDATE user_management.permissions SET resource = split_part(name, ':', 1), action = split_part(name, ':', 2)
WHERE resource IS NULL OR action IS NULL;

-- Now make not null
ALTER TABLE user_management.permissions
    ALTER COLUMN resource SET NOT NULL,
    ALTER COLUMN action   SET NOT NULL;

-- ---------------------------------------------------------------------------
-- Step 5: Add granted_at / granted_by to role_permissions
-- ---------------------------------------------------------------------------
ALTER TABLE user_management.role_permissions
    ADD COLUMN IF NOT EXISTS granted_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    ADD COLUMN IF NOT EXISTS granted_by INT REFERENCES user_management.users(id);

-- ---------------------------------------------------------------------------
-- Step 6: Re-seed role assignments for new permissions
-- ---------------------------------------------------------------------------
DO $$
DECLARE
    admin_id  INT;
    editor_id INT;
    viewer_id INT;
BEGIN
    SELECT id INTO admin_id  FROM user_management.roles WHERE name = 'ADMIN';
    SELECT id INTO editor_id FROM user_management.roles WHERE name = 'EDITOR';
    SELECT id INTO viewer_id FROM user_management.roles WHERE name = 'VIEWER';

    -- ADMIN: all permissions
    INSERT INTO user_management.role_permissions (role_id, permission_id)
        SELECT admin_id, id FROM user_management.permissions
        ON CONFLICT DO NOTHING;

    -- EDITOR: extended set
    INSERT INTO user_management.role_permissions (role_id, permission_id)
        SELECT editor_id, id FROM user_management.permissions
        WHERE name IN (
            'document:read', 'document:create', 'document:update', 'document:archive',
            'note:read',     'note:create',     'note:update',     'note:delete',
            'user:read',     'role:read'
        )
        ON CONFLICT DO NOTHING;

    -- VIEWER: read-only
    INSERT INTO user_management.role_permissions (role_id, permission_id)
        SELECT viewer_id, id FROM user_management.permissions
        WHERE name IN ('document:read', 'note:read', 'user:read', 'role:read')
        ON CONFLICT DO NOTHING;
END
$$;

COMMIT;

-- Verify
SELECT r.name AS role, COUNT(rp.permission_id) AS perm_count
FROM user_management.roles r
LEFT JOIN user_management.role_permissions rp ON rp.role_id = r.id
GROUP BY r.name ORDER BY r.name;
