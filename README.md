# Brainwave — Infrastructure

Local development stack and declarative infrastructure-as-code for the Brainwave platform. This repo owns every piece of infrastructure that is shared across microservices: Docker Compose, Kong gateway config, Keycloak realm, PostgreSQL init scripts, MinIO bucket setup, and CI/CD.

---

## What's Here

```
infra/
├── Makefile                      # Shortcuts: make dev / make staging / make prod
├── docker/
│   ├── compose.yml               # Base config (shared across all environments)
│   ├── compose.dev.yml           # Dev: start-dev, all ports, hot-reload mounts
│   ├── compose.staging.yml       # Staging: Keycloak on PG, registry images, reservations
│   └── compose.prod.yml          # Prod: no admin port, hard limits, security hardening
├── env/
│   ├── .env.dev                  # Dev defaults (committed — throwaway credentials)
│   ├── .env.staging.example      # Staging template (copy → .env.staging, gitignored)
│   └── .env.prod.example         # Prod template (copy → .env.prod, NEVER commit)
├── keycloak/
│   └── realm-export.json         # Realm auto-imported on startup
├── kong/
│   └── kong.yml                  # DB-less declarative gateway config
├── postgres/
│   └── init/
│       ├── 00-extensions.sql     # uuid-ossp, pgcrypto, citext
│       ├── 01-schemas.sql        # Schemas + least-privilege roles
│       ├── 02-user-management.sql # UserHub tables (user_management schema)
│       └── 03-knowhub.sql        # KnowHub tables (doc schema)
├── minio/
│   └── init.sh                   # Bucket creation + lifecycle policies
├── scripts/
│   └── rotate-kong-jwt-key.sh    # Key rotation procedure + safety guide
└── .github/
    └── workflows/
        ├── validate.yml           # Compose lint, Kong lint, SQL lint, secrets scan
        └── release.yml            # Semantic release on main
```

---

## Quick Start

```bash
# 1. Clone and enter the repo
git clone <repo-url> && cd infra

# 2. Start the dev stack (uses env/.env.dev — already committed with safe defaults)
make dev

# 3. Watch health status
make ps

# 4. Optionally start app services (requires sibling repos: ../auth-hub, ../user-hub, ../know-hub)
make dev-services
```

All services start in dependency order. Kong won't come up until Keycloak is healthy. The Postgres init scripts run once on first boot.

```bash
make down        # Stop containers (keeps volumes — data is preserved)
make reset       # Stop + destroy all volumes (clean slate, all data lost)
make logs        # Tail all logs
make logs s=kong # Tail a single service
```

### Staging / Production

```bash
# Staging — copy template and fill in real values first
cp env/.env.staging.example env/.env.staging
# edit env/.env.staging ...
make staging

# Production
cp env/.env.prod.example env/.env.prod
# edit env/.env.prod — use strong generated secrets (openssl rand -hex 32)
make prod
```

The raw Docker Compose commands (if you prefer not to use Make):
```bash
# Dev
docker compose -f docker/compose.yml -f docker/compose.dev.yml \
  --env-file env/.env.dev up -d

# Staging
docker compose -f docker/compose.yml -f docker/compose.staging.yml \
  --env-file env/.env.staging up -d

# Prod
docker compose -f docker/compose.yml -f docker/compose.prod.yml \
  --env-file env/.env.prod up -d
```

---

## Service URLs

| Service        | URL                                    | Notes                          |
|----------------|----------------------------------------|--------------------------------|
| Kong Proxy     | http://localhost:8000                  | All API traffic goes here      |
| Kong Admin API | http://localhost:8001                  | Local only — never expose      |
| Keycloak Admin | http://localhost:8080/admin            | admin / see .env               |
| Keycloak OIDC  | http://localhost:8080/realms/brainwave | Token issuer                   |
| PostgreSQL     | localhost:6632                         | brainwave / see .env           |
| MongoDB        | localhost:27017                        | brainwave / see .env           |
| MinIO Console  | http://localhost:9001                  | minio-admin / see .env         |
| MinIO S3 API   | http://localhost:9000                  | S3-compatible endpoint         |
| Auth Hub       | http://localhost:3000 (--profile)      | Via Kong: /api/auth/*          |
| User Hub       | http://localhost:3001 (--profile)      | Via Kong: /api/users/*         |
| Know Hub       | http://localhost:3002 (--profile)      | Via Kong: /api/documents/*     |

---

## Dev Test Users

These users are pre-seeded into the `brainwave` Keycloak realm.

| Username   | Password  | Role   | Use Case                        |
|------------|-----------|--------|---------------------------------|
| dev-admin  | admin123  | ADMIN  | Full access, user management    |
| dev-editor | editor123 | EDITOR | Create/update documents         |
| dev-viewer | viewer123 | VIEWER | Read-only access                |

### Get a Token

```bash
# Get an access token for dev-admin (uses brainwave-dev client — dev only)
curl -s -X POST http://localhost:8080/realms/brainwave/protocol/openid-connect/token \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "grant_type=password" \
  -d "client_id=brainwave-dev" \
  -d "username=dev-admin" \
  -d "password=admin123" | jq .access_token
```

> The `brainwave-dev` client uses direct grant (Resource Owner Password flow). This is a dev-only client. In production, all clients must use PKCE (`brainwave-public`) or client credentials (`auth-hub-service`).

### Call the API via Kong

```bash
TOKEN=$(curl -s -X POST http://localhost:8080/realms/brainwave/protocol/openid-connect/token \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "grant_type=password" \
  -d "client_id=brainwave-dev" \
  -d "username=dev-admin" \
  -d "password=admin123" | jq -r .access_token)

# Introspect via auth-hub (no JWT required on this route)
curl -H "Authorization: Bearer $TOKEN" http://localhost:8000/api/auth/tokens/introspect

# Any user-hub or know-hub route (JWT validated at Kong edge)
curl -H "Authorization: Bearer $TOKEN" http://localhost:8000/api/users/me
```

---

## Architecture Decisions

### Kong DB-less Mode + Pre-seeded RSA Key Pair

Kong runs in declarative (`KONG_DATABASE=off`) mode. This means the Kong config is immutable at runtime — no Admin API writes. The gateway config is the `kong/kong.yml` file committed to this repo.

The challenge: Kong OSS doesn't poll Keycloak's JWKS endpoint automatically (that's Kong Enterprise's `openid-connect` plugin). To solve the chicken-and-egg problem of needing the public key before Kong starts:

1. A 2048-bit RSA key pair is pre-generated.
2. The **private key** is seeded into `keycloak/realm-export.json` under `components` (Keycloak uses it to sign tokens).
3. The **public key** PEM is hardcoded into `kong/kong.yml` as the RS256 JWT credential for the `keycloak-issuer` consumer.

Both Keycloak and Kong share the same key pair. Kong validates RS256 tokens without any network call to Keycloak.

**Key rotation** — see `scripts/rotate-kong-jwt-key.sh` for the full procedure. In production, consider Kong Enterprise's `openid-connect` plugin for automatic JWKS rotation.

### PostgreSQL Schemas as Service Isolation Boundary

Each microservice owns a dedicated schema and a least-privilege role:

| Service  | Schema             | Role          |
|----------|--------------------|---------------|
| UserHub  | `user_management`  | `userhub_app` |
| KnowHub  | `doc`              | `knowhub_app` |

The roles are granted only on their own schema. Cross-service table access is structurally impossible at the database layer — not just enforced in application code.

### Transactional Outbox (user_events)

`user_management.user_events` is written in the same transaction as the business operation (user created, role changed, etc.). This guarantees the event is never lost even if the message broker is down. A worker polls for `status = 'pending'` and delivers to downstream consumers.

### Immutable Lifecycle Table

`doc.document_lifecycle` is append-only at the DB level:

```sql
REVOKE UPDATE, DELETE ON doc.document_lifecycle FROM knowhub_app;
```

`knowhub_app` has INSERT and SELECT only. No application-level trick can corrupt the audit trail.

### Idempotency in PostgreSQL (Not Redis)

`doc.idempotency_keys` uses a composite primary key `(key, user_id)` with a status column. Idempotency checks are done in the same DB transaction as the business operation, giving ACID guarantees. Redis would be faster but loses the atomicity that makes idempotency meaningful for document writes.

### MinIO Bucket Separation

| Bucket             | Purpose                         | Retention     |
|--------------------|---------------------------------|---------------|
| `documents-hot`    | Active documents (< 90 days)    | None          |
| `documents-cold`   | Archived documents              | None          |
| `logs`             | Operational logs                | 30 days       |
| `logs-diagnostic`  | Debug/trace logs (gated)        | 3 days        |

Diagnostic logs have a 3-day TTL to prevent uncontrolled storage growth.

---

## Key Rotation

See `scripts/rotate-kong-jwt-key.sh` for the step-by-step procedure. The high-level flow:

1. Generate a new RSA-2048 key pair.
2. Update `keycloak/realm-export.json` with the new private key (set `priority` higher than the current key so Keycloak uses it for new tokens).
3. Update the `rsa_public_key` in `kong/kong.yml` for the `keycloak-issuer` consumer.
4. **Keep the old credential** in `kong.yml` during the transition window (old tokens remain valid until they expire).
5. Deploy both files. After `accessTokenLifespan` (15 minutes) passes, remove the old credential from `kong.yml`.

---

## What to Build Next

The infra layer is complete. Build order for the microservices:

1. **Core** — Shared library: Pino logger, correlation-id middleware, base error classes, gRPC client factory. Everything else imports from here.

2. **AuthHub — Admin API gRPC methods** — `GetUser`, `ListRoles`, `AssignRole` RPCs are declared in the TDD but not yet implemented. The HTTP routes and `ValidateToken` gRPC are done.

3. **UserHub** — State machine (pending_identity → active → suspended/disabled), Outbox worker, REST + gRPC stubs. Depends on Core.

4. **KnowHub** — Document state machine (RECEIVED → PERSISTING → AVAILABLE → ...), Saga orchestrator, MinIO/MongoDB dual writes, idempotency layer. Depends on Core.

---

## Notes

### Auth Hub Dockerfile

`auth-hub/Dockerfile` currently has `CMD ["nodemon", "src/index.js"]` — this references a compiled `.js` file but the project is TypeScript. The `compose.yml` in this repo overrides the command for local dev:

```yaml
auth-hub:
  command: sh -c "npm install && npx ts-node --esm src/index.ts"
```

Fix the Dockerfile in the `auth-hub` repo before building production images.
