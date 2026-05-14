#!/bin/bash
# =============================================================================
# Brainwave Kafka — Topic initialisation (runs once on first boot)
# =============================================================================
# Naming convention: brainwave.<domain>.events
#
# Topics:
#   brainwave.auth.events      — Login, logout, failed-login events (auth-hub)
#   brainwave.user.events      — User lifecycle events (user-hub)
#   brainwave.document.events  — Document + note lifecycle events (know-hub)
#
# Consumer groups (informational — created on first consumer connect):
#   brainwave.audit-hub        — audit-hub reads all three topics
#
# Partitions: 3 (allows up to 3 parallel consumers per group in prod)
# Replication: 1 (single-broker dev cluster)
# Retention:   7 days (604800000 ms)
# =============================================================================

set -e

BOOTSTRAP="kafka:9092"
RETENTION_MS=604800000   # 7 days
PARTITIONS=3
REPLICATION=1

create_topic() {
  local TOPIC=$1
  echo "[kafka-init] Creating topic: ${TOPIC}"
  /opt/kafka/bin/kafka-topics.sh \
    --bootstrap-server "${BOOTSTRAP}" \
    --create \
    --if-not-exists \
    --topic "${TOPIC}" \
    --partitions "${PARTITIONS}" \
    --replication-factor "${REPLICATION}" \
    --config retention.ms="${RETENTION_MS}" \
    --config cleanup.policy=delete
}

echo "[kafka-init] Waiting for Kafka to be ready..."
/opt/kafka/bin/kafka-topics.sh --bootstrap-server "${BOOTSTRAP}" --list > /dev/null 2>&1 || sleep 5

echo "[kafka-init] Creating Brainwave platform topics..."
create_topic "brainwave.auth.events"
create_topic "brainwave.user.events"
create_topic "brainwave.document.events"

echo "[kafka-init] Verifying topics..."
/opt/kafka/bin/kafka-topics.sh --bootstrap-server "${BOOTSTRAP}" --list | grep "brainwave\."

echo "[kafka-init] Done."
