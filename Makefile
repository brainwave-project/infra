# =============================================================================
# Brainwave Infrastructure — Makefile
# =============================================================================
# Shortcuts for multi-file Docker Compose commands.
# Always run from the infra/ directory.
#
#   make dev              Start local dev stack (infra + observability, no app services)
#   make dev-services     Same as make services — full dev stack including all hubs
#   make services         Alias for dev-services (infra + observability + auth/user/know/audit hubs)
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

# Eval stack — no observability overlay, no Kong/Keycloak/auth/user/audit hubs.
EVAL_F := -f $(BASE) -f docker/compose.dev.yml -f docker/compose.evals.yml --env-file env/.env.dev

# Infra tier the eval harness actually needs.
EVAL_INFRA  := postgres mongodb minio kafka ollama
EVAL_INIT   := minio-init kafka-init ollama-init

.PHONY: dev dev-services services dev-down staging staging-services prod prod-services \
        down reset ps logs urls lint no-restart \
        evals evals-up evals-seed evals-run evals-ragas evals-ragas-real \
        evals-gate evals-promote \
        evals-shell evals-ps evals-logs evals-down evals-reset evals-lab evals-ui \
        evals-arabic-list evals-arabic-diagnostic \
        evals-arabic-pilot-prepare evals-arabic-pilot-run \
        evals-arabic-dense-diagnostic evals-arabic-dense-pilot \
        evals-arabic-full-prepare evals-arabic-full-bm25 evals-arabic-full-dense \
        evals-arabic-main-analyze evals-arabic-main-export

# ---------------------------------------------------------------------------
# Dev
# ---------------------------------------------------------------------------
dev:
	docker compose $(DEV_F) up -d

# Brings up every compose service: base infra, observability, and --profile services hubs.
# One-shot jobs (minio-init, kafka-init) run then exit — they are expected not to stay Up.
dev-services:
	docker compose $(DEV_F) --profile services up -d --remove-orphans
	@echo ""
	@echo "Compose project started (profile: services)."
	@echo "  App containers: auth-hub, user-hub, know-hub, audit-hub"
	@echo "  Not in Docker:  ui — run separately: cd ../ui && npm run dev  (http://localhost:5173)"
	@echo "  Check status:   make ps"

# Alias — same as dev-services
services: dev-services

dev-down:
	docker compose $(DEV_F) down

# ---------------------------------------------------------------------------
# Staging
# ---------------------------------------------------------------------------
staging:
	docker compose $(STG_F) up -d

staging-services:
	docker compose $(STG_F) --profile services up -d --remove-orphans

# ---------------------------------------------------------------------------
# Production
# ---------------------------------------------------------------------------
prod:
	docker compose $(PRD_F) up -d

prod-services:
	docker compose $(PRD_F) --profile services up -d --remove-orphans

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
	@echo "  │  audit-hub            http://localhost:3003/api/docs                │"
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
# Evaluation stack  (Domain 1: measurement · Domain 2: Arabic retrieval)
# ---------------------------------------------------------------------------
# A lean slice: postgres, mongo, minio, kafka, ollama, know-hub + a one-shot
# eval-runner. No Kong, Keycloak, auth/user/audit hubs, or observability stack.
#
# The agent-hub SERVICE is deliberately not started — its Kafka consumer would
# double-index alongside know-hub's semantic worker. The harness runs as
# eval-runner instead and builds the CRAG graph in-process.
#
#   make evals          Full flow: up → seed → score → report
#   make evals-up       Stack only
#   make evals-seed     Ingest the corpus, wait for INDEXED
#   make evals-run      Retrieval suite only (fast — no LLM judge)
#   make evals-ragas    Generation suite only (slow — local 8B judge)
#   make evals-gate     Compare newest report to the baseline; non-zero on regression
#   make evals-promote  Adopt the newest report as the baseline
#   make evals-shell    Interactive shell in the runner
#   make evals-lab      Stack + eval-api (:3005) for the UI's Evaluation section
#   make evals-ui       Start the Vite UI (:5173); keep this terminal open
#   make evals-arabic-diagnostic     Import and run the authored BM25 diagnostic
#   make evals-arabic-pilot-prepare  Download and prepare the bounded MIRACL train pilot
#   make evals-arabic-pilot-run      Import and run the six controlled BM25 pilot conditions
#   make evals-arabic-dense-diagnostic / evals-arabic-dense-pilot
#   make evals-arabic-full-prepare / evals-arabic-full-bm25 / evals-arabic-full-dense
#   make evals-arabic-main-analyze / evals-arabic-main-export
#   make evals-release-gate  Eval Lab release gate on the exported snapshot (what CI runs)
#   make evals-down     Stop the eval stack (incl. eval-api)
# ---------------------------------------------------------------------------

evals: evals-up
	@echo ""
	@echo "==> Running eval suite (seed + retrieval + generation)"
	docker compose $(EVAL_F) run --rm eval-runner \
		python -m agent_hub.eval.run_suite --suite all

evals-up:
	@echo "==> [1/3] infrastructure tier"
	docker compose $(EVAL_F) up -d $(EVAL_INFRA)
	@echo "==> [2/3] one-shot init (buckets, topics, ollama models)"
	@echo "    first run pulls ~5GB of models — subsequent runs reuse the volume"
	docker compose $(EVAL_F) up $(EVAL_INIT)
	@echo "==> [3/3] know-hub (semantic worker ON, --no-deps skips keycloak/auth-hub)"
	docker compose $(EVAL_F) up -d --no-deps know-hub
	@echo ""
	@echo "    know-hub   http://localhost:3002/api/docs"
	@echo "    postgres   localhost:6632"
	@echo "    ollama     http://localhost:11434"

evals-seed:
	docker compose $(EVAL_F) run --rm eval-runner \
		python -m agent_hub.eval.seed

evals-run:
	docker compose $(EVAL_F) run --rm eval-runner \
		python -m agent_hub.eval.run_suite --suite retrieval

# Built-in rubric judge (agent_hub.eval.judge) — one venv, always works.
evals-ragas:
	docker compose $(EVAL_F) run --rm eval-runner \
		python -m agent_hub.eval.run_suite --suite ragas --skip-seed

# RAGAS proper, in its own venv. Two stages, because RAGAS and agent-hub cannot
# share a virtualenv (see compose.evals.yml). Stage 1 drives CRAG and dumps
# plain JSON; stage 2 scores it with RAGAS and imports no agent_hub code.
# Usage: make evals-ragas-real            (English, 6 questions)
#        make evals-ragas-real lang=ar n=4
lang ?= en
n    ?= 6
evals-ragas-real:
	@echo "==> stage 1/2  CRAG outcomes ($(lang), $(n) questions) — agent-hub venv"
	docker compose $(EVAL_F) run --rm eval-runner \
		python -m agent_hub.eval.ragas_eval --lang $(lang) --limit $(n) \
			--dump-outcomes src/agent_hub/eval/outcomes/outcomes-$(lang).json
	@echo ""
	@echo "==> stage 2/2  RAGAS scoring — isolated venv (first run installs ragas)"
	docker compose $(EVAL_F) run --rm ragas-runner \
		python scripts/ragas_score.py \
			--in src/agent_hub/eval/outcomes/outcomes-$(lang).json \
			--out src/agent_hub/eval/outcomes/ragas-$(lang).json

evals-gate:
	docker compose $(EVAL_F) run --rm eval-runner \
		python -m agent_hub.eval.gate

evals-promote:
	docker compose $(EVAL_F) run --rm eval-runner \
		python -m agent_hub.eval.gate --promote-latest

evals-shell:
	docker compose $(EVAL_F) run --rm eval-runner bash

# Eval Lab release gate (Release Gate page → Export for CI writes the snapshot).
# The same command CI runs; exit 1 = BLOCK, 2 = the gate could not run.
RELEASE := src/agent_hub/eval/release
evals-release-gate:
	docker compose $(EVAL_F) exec eval-api \
		python -m agent_hub.eval.lab.gate_cli \
			--policy $(RELEASE)/policy.json \
			--baseline $(RELEASE)/baseline.json \
			--candidate $(RELEASE)/candidate.json

# Interactive Eval Lab: the lean stack plus the eval-api service that backs the
# UI's Evaluation section (Golden Sets · Retrieval · Experiments · Stats Lab ·
# Generation · Judge Lab · Release Gate). The UI itself still runs on the host.
evals-lab: evals-up
	@echo "==> eval-api (Eval Lab backend, :3005 — first run installs its venv)"
	docker compose $(EVAL_F) up -d --no-deps eval-api
	@echo "    waiting for eval-api..."
	@ready=0; for i in $$(seq 1 90); do \
		if curl -sf http://localhost:3005/health/live >/dev/null 2>&1; then ready=1; break; fi; \
		sleep 2; \
	done; \
	if [ $$ready -eq 1 ]; then echo "    eval-api ready"; \
	else echo "    eval-api not ready yet — check: make evals-logs s=eval-api"; fi
	@echo ""
	@echo "  ┌─ Eval Lab ─────────────────────────────────────────────────────────┐"
	@echo "  │  UI (run on host)     cd ../ui && npm run dev                       │"
	@echo "  │  Evaluation section   http://localhost:5173/evaluation              │"
	@echo "  │  eval-api docs        http://localhost:3005/api/eval/docs           │"
	@echo "  │  know-hub             http://localhost:3002/api/docs                │"
	@echo "  │  Stop                 make evals-down                               │"
	@echo "  └────────────────────────────────────────────────────────────────────┘"
	@echo "  No Kong/Keycloak on this stack: the Evaluation section needs no login in"
	@echo "  dev builds; other pages will redirect to /login."

# Keep this command in its own terminal while using the browser.
evals-ui:
	npm --prefix ../ui run dev

# Arabic normalization shortcuts used by docs/experiment-3. They run inside
# eval-api so every command shares its mounted dataset store and saved IDs.
evals-arabic-list:
	docker compose $(EVAL_F) exec -T eval-api \
		/bin/sh /workspace/infra/scripts/evals-arabic-pilot.sh list

evals-arabic-diagnostic:
	docker compose $(EVAL_F) exec -T eval-api \
		/bin/sh /workspace/infra/scripts/evals-arabic-pilot.sh diagnostic

evals-arabic-pilot-prepare:
	docker compose $(EVAL_F) exec -T eval-api \
		/bin/sh /workspace/infra/scripts/evals-arabic-pilot.sh prepare

evals-arabic-pilot-run:
	docker compose $(EVAL_F) exec -T eval-api \
		/bin/sh /workspace/infra/scripts/evals-arabic-pilot.sh run

evals-arabic-dense-diagnostic:
	docker compose $(EVAL_F) exec -T eval-api \
		/bin/sh /workspace/infra/scripts/evals-arabic-pilot.sh dense-diagnostic

evals-arabic-dense-pilot:
	docker compose $(EVAL_F) exec -T eval-api \
		/bin/sh /workspace/infra/scripts/evals-arabic-pilot.sh dense-pilot

evals-arabic-full-prepare:
	docker compose $(EVAL_F) exec -T eval-api \
		/bin/sh /workspace/infra/scripts/evals-arabic-pilot.sh full-prepare $(query_limit)

evals-arabic-full-bm25:
	docker compose $(EVAL_F) exec -T eval-api \
		/bin/sh /workspace/infra/scripts/evals-arabic-pilot.sh full-bm25

evals-arabic-full-dense:
	docker compose $(EVAL_F) exec -T eval-api \
		/bin/sh /workspace/infra/scripts/evals-arabic-pilot.sh full-dense

evals-arabic-main-analyze:
	docker compose $(EVAL_F) exec -T eval-api \
		/bin/sh /workspace/infra/scripts/evals-arabic-pilot.sh main-analyze

evals-arabic-main-export:
	docker compose $(EVAL_F) exec -T eval-api \
		/bin/sh /workspace/infra/scripts/evals-arabic-pilot.sh main-export

evals-ps:
	docker compose $(EVAL_F) ps

# Usage: make evals-logs        → all
#        make evals-logs s=know-hub
evals-logs:
ifdef s
	docker compose $(EVAL_F) logs -f $(s)
else
	docker compose $(EVAL_F) logs -f
endif

# Both profiles are named explicitly: know-hub belongs to `services`, and a
# plain `down` skips services whose profile is not active — leaving it running
# after what looked like a clean shutdown.
evals-down:
	docker compose $(EVAL_F) --profile services --profile evals down --remove-orphans

# ⚠ Also drops the eval venv volumes — the next run reinstalls ragas (slow).
evals-reset:
	docker compose $(EVAL_F) --profile services --profile evals down -v --remove-orphans

# ---------------------------------------------------------------------------
# Stop containers auto-starting with Docker Desktop
# ---------------------------------------------------------------------------
# The compose files now set restart:"no", but a restart policy is only applied
# when a container is CREATED. Existing containers keep the policy they were
# born with, so this rewrites them in place — run once, after pulling this
# change. New containers need nothing.
no-restart:
	@echo "==> Clearing restart policy on all brainwave containers"
	@docker update --restart=no $$(docker ps -aq --filter "name=brainwave-") 2>/dev/null \
		|| echo "    (no brainwave containers found — nothing to do)"
	@echo "    Done. They will no longer start with Docker Desktop."

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
	@echo "--- Compose (evals) ---"
	docker compose $(EVAL_F) config --quiet
	@echo "--- Kong ---"
	deck file validate --state kong/kong.yml
	@echo "All checks passed."
