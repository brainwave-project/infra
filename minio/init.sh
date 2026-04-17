#!/bin/sh
# =============================================================================
# MinIO Bucket Initialisation
# Run as a one-shot container after MinIO is healthy (see compose.yml).
#
# Buckets created:
#   documents-hot         Hot document storage  — KnowHub binary payloads (active versions)
#   documents-cold        Cold document storage — KnowHub archived versions (lifecycle migration)
#   logs                  Operational logs      — Fluent Bit/Vector NDJSON batches (30d retention)
#   logs-diagnostic       Diagnostic logs       — Gated, short-lived debug traces (3d retention)
#
# Lifecycle policies enforce retention at the storage layer.
# No application code manages retention. MinIO handles it.
# =============================================================================

set -e

MINIO_ALIAS="local"
MINIO_URL="http://${MINIO_HOST:-minio}:9000"

echo "[minio-init] Waiting for MinIO at ${MINIO_URL}..."
until mc alias set "${MINIO_ALIAS}" "${MINIO_URL}" "${MINIO_ROOT_USER}" "${MINIO_ROOT_PASSWORD}" 2>/dev/null; do
  echo "[minio-init] MinIO not ready yet, retrying in 3s..."
  sleep 3
done

echo "[minio-init] Connected. Creating buckets..."

# ---------------------------------------------------------------------------
# Helper: create bucket if it doesn't already exist
# ---------------------------------------------------------------------------
create_bucket() {
  BUCKET=$1
  if mc ls "${MINIO_ALIAS}/${BUCKET}" >/dev/null 2>&1; then
    echo "[minio-init] Bucket '${BUCKET}' already exists — skipping."
  else
    mc mb "${MINIO_ALIAS}/${BUCKET}"
    echo "[minio-init] Created bucket '${BUCKET}'"
  fi
}

# ---------------------------------------------------------------------------
# Document storage buckets
# ---------------------------------------------------------------------------
create_bucket "documents-hot"
create_bucket "documents-cold"

# ---------------------------------------------------------------------------
# Log storage buckets
# ---------------------------------------------------------------------------
create_bucket "logs"
create_bucket "logs-diagnostic"

# ---------------------------------------------------------------------------
# Lifecycle policies — storage-layer retention (no app code needed)
#
# Operational logs: auto-delete after 30 days
# Diagnostic logs:  auto-delete after 3 days
# Cold docs:        no auto-delete (manual retention policy review)
# ---------------------------------------------------------------------------

echo "[minio-init] Setting lifecycle policy on 'logs' (30d retention)..."
cat > /tmp/logs-lifecycle.json << 'LIFECYCLE'
{
  "Rules": [
    {
      "ID": "operational-logs-30d",
      "Status": "Enabled",
      "Filter": { "Prefix": "" },
      "Expiration": { "Days": 30 }
    }
  ]
}
LIFECYCLE
mc ilm import "${MINIO_ALIAS}/logs" < /tmp/logs-lifecycle.json

echo "[minio-init] Setting lifecycle policy on 'logs-diagnostic' (3d retention)..."
cat > /tmp/logs-diagnostic-lifecycle.json << 'LIFECYCLE'
{
  "Rules": [
    {
      "ID": "diagnostic-logs-3d",
      "Status": "Enabled",
      "Filter": { "Prefix": "" },
      "Expiration": { "Days": 3 }
    }
  ]
}
LIFECYCLE
mc ilm import "${MINIO_ALIAS}/logs-diagnostic" < /tmp/logs-diagnostic-lifecycle.json

# ---------------------------------------------------------------------------
# Anonymous access — buckets are private by default (correct)
# KnowHub accesses MinIO via the API using MINIO_ROOT_USER credentials.
# No public access is granted.
# ---------------------------------------------------------------------------

echo "[minio-init] All buckets initialised:"
mc ls "${MINIO_ALIAS}"

echo "[minio-init] Done."
