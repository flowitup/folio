#!/usr/bin/env bash
# Phase 5 — VM-side deploy script. Called by CI via `gcloud compute ssh --tunnel-through-iap`.
# Pulls the new image from Artifact Registry, runs migrations (api/worker only),
# swaps the container with --no-deps so unrelated services aren't bounced, then
# polls health.
#
# Invocation:
#   /opt/folio/scripts/deploy-runner.sh <SHA> <SVC>
# where SVC ∈ {api, frontend}; "api" also restarts "worker" (shared image, Y5).
set -euo pipefail

SHA="${1:?usage: $0 <git-sha> <service>}"
SVC="${2:?usage: $0 <git-sha> <service>}"

# Whitelist services — guard against arbitrary command injection if the SA
# forced-command boundary ever leaks.
case "$SVC" in
  api|frontend) ;;
  *) echo "deploy-runner: invalid service '$SVC' (allowed: api, frontend)" >&2; exit 2 ;;
esac

# Whitelist SHA: 7-40 hex chars (matches GitHub default).
[[ "$SHA" =~ ^[0-9a-f]{7,40}$ ]] || { echo "deploy-runner: invalid SHA '$SHA'" >&2; exit 2; }

cd /opt/folio
export IMAGE_TAG="$SHA"
COMPOSE=(docker compose -f docker-compose.yml -f docker-compose.prod.yml --env-file /opt/folio/.env)

log() { printf '[deploy-runner %s] %s\n' "$(date -u +%H:%M:%S)" "$*"; }

# 1. Pull new image
log "pulling $SVC:$SHA"
"${COMPOSE[@]}" pull "$SVC"

# Worker shares the api image (Y5) — pull it together so step 3 can swap both.
[[ "$SVC" == "api" ]] && "${COMPOSE[@]}" pull worker

# 2. Run DB migrations BEFORE swapping traffic. Api deploy only (worker shares schema).
# NOTE: `flask db upgrade` assumes Flask-Migrate. If folio-back-end uses alembic
# directly or a custom script, replace this command — see infra/gcp/README.md
# Phase 5 "open verification" note.
if [[ "$SVC" == "api" ]]; then
  log "running migrations (flask db upgrade)"
  # FLASK_APP=app:create_app matches folio-back-end's hexagonal layout
  # (factory function in app/__init__.py). docs/deployment-guide.md §3.1.
  "${COMPOSE[@]}" run --rm -e FLASK_APP=app:create_app api flask db upgrade
fi

# 3. Swap container(s) with --no-deps so dependencies (db/redis/minio) aren't bounced.
log "swapping container $SVC"
"${COMPOSE[@]}" up -d --no-deps "$SVC"
if [[ "$SVC" == "api" ]]; then
  "${COMPOSE[@]}" up -d --no-deps worker
fi

# 4. Wait for health (handles worker no-healthcheck).
/opt/folio/scripts/wait-healthy.sh "$SVC"
[[ "$SVC" == "api" ]] && /opt/folio/scripts/wait-healthy.sh worker

log "deploy ok: $SVC@$SHA"
