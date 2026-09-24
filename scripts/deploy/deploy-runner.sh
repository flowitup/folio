#!/usr/bin/env bash
# Phase 5 — VM-side deploy script. Called by CI via `gcloud compute ssh --tunnel-through-iap`.
# Pulls the new image from Artifact Registry, runs migrations (api/worker only),
# swaps the container with --no-deps so unrelated services aren't bounced, then
# polls health.
#
# Invocation:
#   /opt/folio/scripts/deploy-runner.sh <SHA> <SVC>
# where SVC ∈ {api, frontend}; "api" also restarts "worker" (shared image, Y5)
# and "ai-browser" (own image, same SHA, built by the same CI run — assistant
# browser-automation container, see docker-compose.prod.yml).
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
# ai-browser sits behind the "assistant" compose profile so a plain local
# `docker compose up` never builds the 2.5 GB Chrome image. Prod runs it only
# while the assistant is switched on (FEATURE_ASSISTANT=1 in /opt/folio/.env);
# otherwise every api deploy stops and removes it.
ASSISTANT_ON=0
grep -qE '^FEATURE_ASSISTANT=1[[:space:]]*$' /opt/folio/.env && ASSISTANT_ON=1
if [[ "$ASSISTANT_ON" == "1" ]]; then
  export COMPOSE_PROFILES="${COMPOSE_PROFILES:-assistant}"
fi
COMPOSE=(docker compose -f docker-compose.yml -f docker-compose.prod.yml --env-file /opt/folio/.env)

log() { printf '[deploy-runner %s] %s\n' "$(date -u +%H:%M:%S)" "$*"; }

# 1. Pull new image
log "pulling $SVC:$SHA"
"${COMPOSE[@]}" pull "$SVC"

# Worker shares the api image (Y5) — pull it together so step 3 can swap both.
SKIP_AI_BROWSER=$(( 1 - ASSISTANT_ON ))
if [[ "$SVC" == "api" ]]; then
  "${COMPOSE[@]}" pull worker
fi
if [[ "$SVC" == "api" && "$ASSISTANT_ON" == "1" ]]; then
  # ai-browser is its own image, built by the same CI run at the same SHA.
  # On the very first rollout after this was added (or if that build step
  # ever fails on its own) the tag may not exist yet — that must not abort
  # the api/worker deploy already in flight, so warn and skip instead.
  log "pulling ai-browser:$SHA"
  if ! "${COMPOSE[@]}" pull ai-browser; then
    log "WARNING: ai-browser:$SHA pull failed — skipping ai-browser this run"
    SKIP_AI_BROWSER=1
  fi
fi

# 2. Run DB migrations BEFORE swapping traffic. Api deploy only (worker shares schema).
# NOTE: `flask db upgrade` assumes Flask-Migrate. If folio-back-end uses alembic
# directly or a custom script, replace this command — see infra/gcp/README.md
# Phase 5 "open verification" note.
if [[ "$SVC" == "api" ]]; then
  # The ai-browser side-car polls assistant_jobs with SELECT ... FOR UPDATE; a
  # transaction it leaves open blocks any ALTER TABLE on that table for as long
  # as it runs (the v0.4.0 deploy hung on exactly that). Stop it before the DDL;
  # step 3 recreates it from the new image. lock_timeout turns any remaining
  # blocker into a clear error instead of a hang that outlives the SSH session.
  log "stopping ai-browser before migrations"
  "${COMPOSE[@]}" stop ai-browser || log "WARNING: ai-browser was not running"
  log "running migrations (flask db upgrade)"
  # FLASK_APP=app:create_app matches folio-back-end's hexagonal layout
  # (factory function in app/__init__.py). docs/deployment-guide.md §3.1.
  "${COMPOSE[@]}" run --rm -e FLASK_APP=app:create_app -e PGOPTIONS="-c lock_timeout=120s" api flask db upgrade
fi

# 3. Swap container(s) with --no-deps so dependencies (db/redis/minio) aren't bounced.
log "swapping container $SVC"
"${COMPOSE[@]}" up -d --no-deps "$SVC"
if [[ "$SVC" == "api" ]]; then
  "${COMPOSE[@]}" up -d --no-deps worker
  if [[ "$SKIP_AI_BROWSER" == "0" ]]; then
    "${COMPOSE[@]}" up -d --no-deps ai-browser
  elif [[ "$ASSISTANT_ON" == "1" ]]; then
    log "skipping ai-browser swap (image not pulled)"
  else
    log "assistant switched off — removing ai-browser"
    "${COMPOSE[@]}" --profile assistant rm -sf ai-browser || log "WARNING: could not remove ai-browser"
  fi
fi

# 4. Wait for health (handles worker/ai-browser no-healthcheck).
/opt/folio/scripts/wait-healthy.sh "$SVC"
if [[ "$SVC" == "api" ]]; then
  /opt/folio/scripts/wait-healthy.sh worker
  # ai-browser serves no traffic and is double-gated (flag + keys): a sick side-car
  # must not fail the deploy — that would skip the pointer bump while the api is
  # already live. Warn loudly instead.
  if [[ "$SKIP_AI_BROWSER" == "0" ]]; then
    /opt/folio/scripts/wait-healthy.sh ai-browser \
      || log "WARNING: ai-browser not healthy after the swap — check 'docker logs folio-ai-browser-1'"
  fi
fi

log "deploy ok: $SVC@$SHA"
