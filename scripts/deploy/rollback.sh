#!/usr/bin/env bash
# Phase 5 — manual rollback. Run on the VM (or via gcloud compute ssh).
# Pulls a specific SHA tag from Artifact Registry and restarts the service.
# Does NOT run migrations — rolling back code with a forward-only schema is
# risky; prefer rolling FORWARD with a fix. If you must roll back schema,
# do it manually.
#
# Invocation:
#   /opt/folio/scripts/rollback.sh <service> [<sha>]
# If <sha> omitted, queries AR for the previous SHA tag (chronological).
set -euo pipefail

SVC="${1:?usage: $0 <service> [<sha>]}"
SHA="${2:-}"

case "$SVC" in
  api|frontend|worker) ;;
  *) echo "rollback: invalid service '$SVC' (allowed: api, frontend, worker)" >&2; exit 2 ;;
esac

PROJECT_ID="${PROJECT_ID:-flowitup-folio-prod}"
REGION="${REGION:-europe-west1}"
AR_REPO="${AR_REPO:-folio}"
IMG="${REGION}-docker.pkg.dev/${PROJECT_ID}/${AR_REPO}/${SVC}"

if [[ -z "$SHA" ]]; then
  # Find current running tag via OCI revision label (set by docker/build-push-action
  # in deploy-{api,frontend}.yml). Auto-detect ONLY works for images built by
  # this workflow — old/manually-built images without the label fall back to
  # "pick the most recent tag != latest", which may be wrong. If unsure, pass
  # SHA explicitly: ./rollback.sh api <prev-sha>
  current=$(docker inspect --format '{{index .Config.Labels "org.opencontainers.image.revision"}}' \
    "${COMPOSE_PROJECT_NAME:-folio}-${SVC}-1" 2>/dev/null || echo "")
  echo "current $SVC running with revision label: ${current:-unknown}"
  echo "querying AR for previous SHA tags…"
  # gcloud lists tags newest-first; pick the second one (skip current/latest).
  SHA=$(gcloud artifacts docker tags list "$IMG" \
    --sort-by='~UPDATE_TIME' --format='value(TAG)' --limit=10 \
    | /usr/bin/grep -vE '^(latest|stable|prod)$' \
    | /usr/bin/awk -v skip="$current" 'NR==1 && $0==skip {next} {print; exit}')
  [[ -n "$SHA" ]] || { echo "rollback: could not determine previous SHA — pass explicitly" >&2; exit 1; }
fi

[[ "$SHA" =~ ^[0-9a-f]{7,40}$ ]] || { echo "rollback: invalid SHA '$SHA'" >&2; exit 2; }

echo "[rollback] $SVC → $SHA"
cd /opt/folio
export IMAGE_TAG="$SHA"
COMPOSE=(docker compose -f docker-compose.yml -f docker-compose.prod.yml --env-file /opt/folio/.env)

"${COMPOSE[@]}" pull "$SVC"
"${COMPOSE[@]}" up -d --no-deps "$SVC"
# api shares image with worker — roll worker back too
[[ "$SVC" == "api" ]] && "${COMPOSE[@]}" up -d --no-deps worker

/opt/folio/scripts/wait-healthy.sh "$SVC"
[[ "$SVC" == "api" ]] && /opt/folio/scripts/wait-healthy.sh worker
echo "[rollback] ok: $SVC@$SHA"
