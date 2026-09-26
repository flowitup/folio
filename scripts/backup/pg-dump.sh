#!/usr/bin/env bash
# Daily Postgres logical dump -> GCS (Hetzner edition).
# Upload via mc + GCS HMAC (backup-sa, append-only) - no gcloud on this host.
set -euo pipefail
ENV_FILE="${ENV_FILE:-/opt/folio/.env}"
BACKUP_BUCKET="${BACKUP_BUCKET:-flowitup-folio-prod-backups}"
log() { /usr/bin/logger -t pg-dump -s "$*" 2>&1; }
[[ -r "$ENV_FILE" ]] || { log "ERROR: $ENV_FILE not readable"; exit 1; }
POSTGRES_USER=$(/usr/bin/awk -F= '/^POSTGRES_USER=/ {print $2}' "$ENV_FILE")
POSTGRES_DB=$(/usr/bin/awk -F= '/^POSTGRES_DB=/ {print $2}' "$ENV_FILE")
GCS_KEY=$(/usr/bin/awk -F= '/^GCS_HMAC_ACCESS_KEY=/ {print $2}' "$ENV_FILE")
GCS_SEC=$(/usr/bin/awk -F= '/^GCS_HMAC_SECRET_KEY=/ {print $2}' "$ENV_FILE")
[[ -n "$POSTGRES_USER" && -n "$POSTGRES_DB" && -n "$GCS_KEY" && -n "$GCS_SEC" ]] || { log "ERROR: missing env"; exit 1; }
PG_CTR=$(/usr/bin/docker ps --filter 'ancestor=postgres:16-alpine' --format '{{.Names}}' | head -1)
[[ -n "$PG_CTR" ]] || { log "ERROR: no postgres container running"; exit 2; }
DATE=$(date -u +%F)
KEY="pg-dumps/${DATE}.dump"
log "starting dump: $POSTGRES_DB -> gs://${BACKUP_BUCKET}/${KEY}"
if ! /usr/bin/docker exec "$PG_CTR" pg_dump -U "$POSTGRES_USER" -d "$POSTGRES_DB" -Fc \
   | /usr/bin/docker run --rm -i -e MC_HOST_gcs="https://${GCS_KEY}:${GCS_SEC}@storage.googleapis.com" quay.io/minio/mc:latest pipe "gcs/${BACKUP_BUCKET}/${KEY}" >/dev/null 2>&1; then
  log "ERROR: dump or upload failed"; exit 3
fi
log "ok: uploaded $KEY"
