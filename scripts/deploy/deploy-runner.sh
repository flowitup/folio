#!/usr/bin/env bash
# Phase 5 — VM-side deploy script. Called by CI via `gcloud compute ssh --tunnel-through-iap`.
# Pulls the new image from Artifact Registry, runs migrations (api only),
# swaps the container with --no-deps so unrelated services aren't bounced, then
# polls health.
#
# Invocation:
#   /opt/folio/scripts/deploy-runner.sh <SHA> <SVC>
# where SVC ∈ {api, frontend}.
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

# 2. Run DB migrations BEFORE swapping traffic. Api deploy only.
# NOTE: `flask db upgrade` assumes Flask-Migrate. If folio-back-end uses alembic
# directly or a custom script, replace this command — see infra/gcp/README.md
# Phase 5 "open verification" note.
if [[ "$SVC" == "api" ]]; then
  log "running migrations (flask db upgrade)"
  # FLASK_APP=app:create_app matches folio-back-end's hexagonal layout
  # (factory function in app/__init__.py). docs/deployment-guide.md §3.1.
  "${COMPOSE[@]}" run --rm -e FLASK_APP=app:create_app -e PGOPTIONS="-c lock_timeout=120s" api flask db upgrade
fi

# 3. Swap container with --no-deps so dependencies (db/redis/minio) aren't bounced.
log "swapping container $SVC"
"${COMPOSE[@]}" up -d --no-deps "$SVC"

# 4. Wait for health (services with no healthcheck count as healthy once running).
/opt/folio/scripts/wait-healthy.sh "$SVC"

log "deploy ok: $SVC@$SHA"
