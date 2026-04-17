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

DEV_F  := -f $(BASE) -f docker/compose.dev.yml     --env-file env/.env.dev
STG_F  := -f $(BASE) -f docker/compose.staging.yml --env-file env/.env.staging
PRD_F  := -f $(BASE) -f docker/compose.prod.yml    --env-file env/.env.prod

.PHONY: dev dev-services dev-down staging staging-services prod prod-services \
        down reset ps logs lint

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
