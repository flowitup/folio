#!/usr/bin/env bash
# Daily janitor: erase documents, photos/videos and analyses that users deleted
# more than RETENTION_DAYS ago (rows + MinIO objects). Deleting in the app only
# hides an item; this job is what actually removes the files, so deleted files
# also leave the MinIO -> GCS mirror after the retention window.
# Runs ON THE VM via cron (see install-backup-cron.sh), inside the running api
# container so it uses the same image, env and storage settings as the API.
#
# Failure modes:
#   - api container not running          → exit 2, log
#   - janitor exits non-zero (1 or 2)    → exit 3, log (2 = a source purged nothing and had failures)
set -euo pipefail

RETENTION_DAYS="${RETENTION_DAYS:-30}"
COMPOSE_DIR="${COMPOSE_DIR:-/opt/folio}"
ENV_FILE="${ENV_FILE:-/opt/folio/.env}"

log() { /usr/bin/logger -t purge-deleted-files -s "$*" 2>&1; }

cd "$COMPOSE_DIR"
COMPOSE=(/usr/bin/docker compose -f docker-compose.yml -f docker-compose.prod.yml --env-file "$ENV_FILE")

if [[ -z "$("${COMPOSE[@]}" ps -q api 2>/dev/null)" ]]; then
  log "ERROR: api container not running"
  exit 2
fi

log "starting: retention_days=${RETENTION_DAYS}"
# PYTHONPATH=/app: `python scripts/x.py` puts /app/scripts first on sys.path, so the
# repo-root modules the janitor imports (wiring, config) would not be found.
if ! "${COMPOSE[@]}" exec -T -e PYTHONPATH=/app api python scripts/purge_soft_deleted_files.py --retention-days "$RETENTION_DAYS"; then
  log "ERROR: janitor failed"
  exit 3
fi
log "ok"
