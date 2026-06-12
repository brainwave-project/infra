#!/bin/bash
# =============================================================================
# 07-langfuse.sh — Langfuse role + database bootstrap
#
# Langfuse is a third-party app that manages its own schema migrations, so it
# needs its own DATABASE (not just a schema). We give it a dedicated role and
# database inside the same Postgres instance rather than spinning a second
# Postgres container.
#
# Password matches LANGFUSE_DB_PASSWORD=langfuse_dev_pass in env/.env.dev.
# Change in prod via the env file — this script only runs on a fresh volume.
# =============================================================================
set -e

# Create the langfuse role (idempotent)
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<-EOSQL
    DO \$\$
    BEGIN
      IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'langfuse') THEN
        CREATE ROLE langfuse WITH LOGIN PASSWORD 'langfuse_dev_pass';
      END IF;
    END
    \$\$;
EOSQL

# CREATE DATABASE cannot run inside a transaction block — use a standalone -c call.
# Check first so the script is safe to re-run.
DB_EXISTS=$(psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" \
    -tAc "SELECT 1 FROM pg_database WHERE datname='langfuse'")

if [ -z "$DB_EXISTS" ]; then
    psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" \
        -c "CREATE DATABASE langfuse OWNER langfuse"
    echo "07-langfuse: created database 'langfuse'"
else
    echo "07-langfuse: database 'langfuse' already exists — skipped"
fi
