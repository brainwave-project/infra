# =============================================================================
# Brainwave Infrastructure — Makefile
# =============================================================================
# Shortcuts for multi-file Docker Compose commands.
# Always run from the infra/ repo root.
#
#   make dev            Start local dev stack (infra only)
#   make dev-services   Start local dev stack + app services
#   make staging        Start staging stack (infra only)
#   make prod           Start prod stack (infra only)
#   make down           Stop current environment (preserves volumes)
#   make reset          Stop + destroy all volumes (clean slate)
#   make ps             Show running service status
#   make logs           Tail all logs
#   make logs s=kong    Tail a specific service
# =============================================================================

# Base compose files
BASE   := docker/compose.yml
MON    := docker/compose.monitoring.yml

DEV_F  := -f $(BASE) -f docker/compose.dev.yml      -f $(MON) --env-file env/.env.dev
STG_F  := -f $(BASE) -f docker/compose.staging.yml  -f $(MON) --env-file env/.env.staging
PRD_F  := -f $(BASE) -f docker/compose.prod.yml     -f $(MON) --env-file env/.env.prod

.PHONY: dev dev-services dev-down staging staging-services prod prod-services \
        down reset ps logs lint urls monitoring

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
#        make logs s=kong   → single service
logs:
ifdef s
	docker compose $(DEV_F) logs -f $(s)
else
	docker compose $(DEV_F) logs -f
endif

# ---------------------------------------------------------------------------
# Quick reference: management UIs
# ---------------------------------------------------------------------------
urls:
	@echo ""
	@echo "  Application:"
	@echo "    UI ........................ http://localhost:5173"
	@echo "    Kong (API gateway) ........ http://localhost:8000"
	@echo ""
	@echo "  Service Swagger:"
	@echo "    auth-hub .................. http://localhost:3000/api/docs"
	@echo "    user-hub .................. http://localhost:3001/api/docs"
	@echo "    know-hub .................. http://localhost:3002/api/docs"
	@echo ""
	@echo "  Admin UIs:"
	@echo "    Keycloak Admin ............ http://localhost:8080/admin   (admin / admin_dev_pass)"
	@echo "    Kong Admin API ............ http://localhost:8001"
	@echo "    Konga (Kong UI) ........... http://localhost:1337"
	@echo "    MinIO Console ............. http://localhost:9001         (minio-admin / minio_dev_pass_8chars)"
	@echo ""
	@echo "  Monitoring:"
	@echo "    Prometheus ................ http://localhost:9090"
	@echo "    Grafana ................... http://localhost:3030         (admin / admin)"
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
