# Env layout

Two-tier hybrid:

```
env/
├── .env.dev                  # shared infra creds + ports (committed, dev throwaway)
├── .env.prod                 # shared infra creds + ports (gitignored, real values)
├── .env.prod.example         # template for .env.prod
├── .env.staging.example      # template for .env.staging
└── services/
    ├── auth-hub.dev.env      # per-service literal config (committed)
    ├── auth-hub.prod.env
    ├── user-hub.dev.env
    ├── user-hub.prod.env
    ├── know-hub.dev.env
    ├── know-hub.prod.env
    ├── audit-hub.dev.env
    └── audit-hub.prod.env
```

## How the two tiers split

**Shared tier — `env/.env.<environment>`**
- Loaded via `--env-file` by `make dev` / `make prod`.
- Used for `${VAR}` substitution in compose YAML.
- Contains anything multiple services share or anything compose needs to interpolate: Postgres / Mongo / MinIO root creds, Keycloak admin password, Kafka brokers, every service's port.
- One file per environment.

**Per-service tier — `env/services/<service>.<environment>.env`**
- Loaded via `env_file:` on each service block in compose.
- Passed *literally* to the container — no `${...}` interpolation.
- Contains the values that are constant for that service in that environment: `NODE_ENV`, `SERVICE_NAME`, `LOG_LEVEL`, in-network hostnames (`DB_HOST=postgres`), Keycloak realm/client IDs, etc.
- One file per (service, environment) pair.

The compose `environment:` block on each service still carries anything that needs `${...}` interpolation — DB credentials, the JWT client secret, the Kafka broker list, the service's exposed port — because docker-compose only interpolates inside compose YAML, not inside files referenced from `env_file:`.

## Why this split

- Rotating a shared secret (e.g. `POSTGRES_PASSWORD`) is one edit in one file.
- Adding a service-only config flag (e.g. a new feature toggle for know-hub) doesn't touch any other service's file.
- Reading "what config does user-hub get?" → look at one small file plus the user-hub block in compose, instead of scrolling through every service's environment block.

## Adding a new service

1. Create `services/<new-service>.dev.env` and `<new-service>.prod.env` with `NODE_ENV`, `SERVICE_NAME`, `LOG_LEVEL`, plus any in-network hostnames or static config the service needs.
2. In each compose override (`compose.dev.yml`, `compose.prod.yml`), add the service block with:
   ```yaml
   env_file:
     - ../env/services/<new-service>.<env>.env
   environment:
     PORT: ${NEW_SERVICE_PORT:-XXXX}
     # only ${...} interpolations or per-deployment overrides here
   ```
3. Add `NEW_SERVICE_PORT` (and any new shared creds) to `env/.env.dev` and `env/.env.prod.example`.

## Why not pure per-service files

Putting every value (including DB passwords and broker lists) into per-service files means duplicating shared values across N files. Rotating a shared password becomes an N-line edit instead of 1, and silent drift is a real failure mode.

## Why not pure monolithic

Today's per-environment files (~80 lines each) mix "infra owns this" with "user-hub owns this." With a fifth and sixth service that gets unmanageable. The per-service tier scales linearly with service count and keeps each file small.
