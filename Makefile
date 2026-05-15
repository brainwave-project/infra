# =============================================================================
# Brainwave Infrastructure — Makefile
# =============================================================================
# Shortcuts for multi-file Docker Compose commands.
# Always run from the infra/ directory.
#
#   make dev              Start local dev stack (infra + observability, no app services)
#   make dev-services     Start local dev stack + all app services
#   make dev-down         Stop dev stack
#   make staging          Start staging stack
#   make prod             Start prod stack
#   make down             Stop current environment (preserves volumes)
#   make reset            Stop + destroy all volumes (clean slate)
#   make ps               Show running service status
#   make logs             Tail all logs
#   make logs s=kong      Tail a specific service
#   make urls             Print all management UI URLs
# =============================================================================

# Base compose files
BASE := docker/compose.yml
OBS  := docker/compose.observability.yml   # full observability stack (metrics+logs+traces)

DEV_F  := -f $(BASE) -f docker/compose.dev.yml     -f $(OBS) --env-file env/.env.dev
STG_F  := -f $(BASE) -f docker/compose.staging.yml -f $(OBS) --env-file env/.env.staging
PRD_F  := -f $(BASE) -f docker/compose.prod.yml    -f $(OBS) --env-file env/.env.prod

.PHONY: dev dev-services dev-down staging staging-services prod prod-services \
        down reset ps logs urls lint

# ---------------------------------------------------------------------------
# Dev
# ---------------------------------------------------------------------------
dev:
	docker compose $(DEV_F) up -d

dev-services:
	docker compose $(DEV_F) --profile services up -d

dev-down:
	docker compose $(DEV_F) down

# ---------------------------------------------------------------------------
# Staging
# ---------------------------------------------------------------------------
staging:
	docker compose $(STG_F) up -d

staging-services:
	docker compose $(STG_F) --profile services up -d

# ---------------------------------------------------------------------------
# Production
# ---------------------------------------------------------------------------
prod:
	docker compose $(PRD_F) up -d

prod-services:
	docker compose $(PRD_F) --profile services up -d

# ---------------------------------------------------------------------------
# Shared
# ---------------------------------------------------------------------------

# Stop containers but keep volumes (safe — data is preserved)
down:
	docker compose $(DEV_F) down

# ⚠ Destroys ALL volumes — drops all data
reset:
	docker compose $(DEV_F) down -v

ps:
	docker compose $(DEV_F) ps

# Usage: make logs          → all services
#        make logs s=loki   → single service
logs:
ifdef s
	docker compose $(DEV_F) logs -f $(s)
else
	docker compose $(DEV_F) logs -f
endif

# ---------------------------------------------------------------------------
# Quick reference: all management UIs
# ---------------------------------------------------------------------------
urls:
	@echo ""
	@echo "  ┌─ Application ──────────────────────────────────────────────────────┐"
	@echo "  │  UI (Vite dev)        http://localhost:5173                         │"
	@echo "  │  Kong (API gateway)   http://localhost:8000                         │"
	@echo "  └────────────────────────────────────────────────────────────────────┘"
	@echo ""
	@echo "  ┌─ Service Swagger ──────────────────────────────────────────────────┐"
	@echo "  │  auth-hub             http://localhost:3000/api/docs                │"
	@echo "  │  user-hub             http://localhost:3001/api/docs                │"
	@echo "  │  know-hub             http://localhost:3002/api/docs                │"
	@echo "  └────────────────────────────────────────────────────────────────────┘"
	@echo ""
	@echo "  ┌─ Observability (Three Pillars) ────────────────────────────────────┐"
	@echo "  │  Grafana (dashboards) http://localhost:3030         (admin/admin)   │"
	@echo "  │  Prometheus (metrics) http://localhost:9090                         │"
	@echo "  │  Alertmanager         http://localhost:9093                         │"
	@echo "  │  Loki (logs)          http://localhost:3100                         │"
	@echo "  │  Tempo (traces)       http://localhost:3200                         │"
	@echo "  │  OTel zPages          http://localhost:5679                         │"
	@echo "  │  cAdvisor (ctrs)      http://localhost:8181                         │"
	@echo "  │  Node Exporter        http://localhost:9100/metrics                 │"
	@echo "  └────────────────────────────────────────────────────────────────────┘"
	@echo ""
	@echo "  ┌─ Admin UIs ────────────────────────────────────────────────────────┐"
	@echo "  │  Keycloak Admin       http://localhost:8080/admin   (admin/...)     │"
	@echo "  │  Kong Admin API       http://localhost:8001                         │"
	@echo "  │  Konga (Kong UI)      http://localhost:1337                         │"
	@echo "  │  MinIO Console        http://localhost:9001         (minio-admin/…) │"
	@echo "  └────────────────────────────────────────────────────────────────────┘"
	@echo ""

# ---------------------------------------------------------------------------
# Validation (also runs in CI)
# ---------------------------------------------------------------------------
lint:
	@echo "--- Compose (dev) ---"
	docker compose $(DEV_F) config --quiet
	@echo "--- Compose (staging) ---"
	docker compose $(STG_F) config --quiet
	@echo "--- Compose (prod) ---"
	docker compose $(PRD_F) config --quiet
	@echo "--- Kong ---"
	deck file validate --state kong/kong.yml
	@echo "All checks passed."
