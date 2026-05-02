#!/usr/bin/env bash
# Phase 7 — daily Postgres logical dump → GCS.
# Runs ON THE VM via cron at 03:00 UTC. Impersonates backup-sa (append-only).
#
# Idempotent within a day: same DATE key overwrites (Postgres versioning on
# bucket retains the previous version for 30 days).
#
# Failure modes:
#   - postgres container not running  → exit 2, log
#   - pg_dump fails                    → exit 3, log
#   - gsutil upload fails              → exit 4, log (token expiry, network, quota)
set -euo pipefail

PROJECT_ID="${PROJECT_ID:-flowitup-folio-prod}"
ENV_FILE="${ENV_FILE:-/opt/folio/.env}"
BACKUP_BUCKET="${BACKUP_BUCKET:-${PROJECT_ID}-backups}"
BACKUP_SA="backup-sa@${PROJECT_ID}.iam.gserviceaccount.com"

log() { /usr/bin/logger -t pg-dump -s "$*" 2>&1; }

[[ -r "$ENV_FILE" ]] || { log "ERROR: $ENV_FILE not readable"; exit 1; }

# Source DB connection from rendered .env (avoids hard-coding values).
POSTGRES_USER=$(/usr/bin/awk -F= '/^POSTGRES_USER=/ {print $2}' "$ENV_FILE")
POSTGRES_DB=$(/usr/bin/awk -F= '/^POSTGRES_DB=/ {print $2}' "$ENV_FILE")
[[ -n "$POSTGRES_USER" && -n "$POSTGRES_DB" ]] || \
  { log "ERROR: POSTGRES_USER/DB missing from $ENV_FILE"; exit 1; }

# Impersonate backup-sa for write to backup bucket. vm-runtime-sa has
# tokenCreator on backup-sa; backup-sa has objectCreator on the bucket only.
export CLOUDSDK_AUTH_IMPERSONATE_SERVICE_ACCOUNT="$BACKUP_SA"

# Find postgres container by image ancestor (compose names it `<project>-db-1`,
# not anything containing "postgres" — so filter on the underlying image).
PG_CTR=$(/usr/bin/docker ps --filter 'ancestor=postgres:16-alpine' --format '{{.Names}}' | head -1)
[[ -n "$PG_CTR" ]] || { log "ERROR: no postgres container running"; exit 2; }

DATE=$(date -u +%F)
KEY="pg-dumps/${DATE}.dump"
DEST="gs://${BACKUP_BUCKET}/${KEY}"

log "starting dump: $POSTGRES_DB → $DEST (via $PG_CTR, as $BACKUP_SA)"

# pg_dump -Fc = custom format (already internally compressed; no extra gzip needed).
# Stream stdout → gsutil stdin → no temp file on disk.
# `set -o pipefail` on `set -e` catches mid-pipe failures.
# gsutil cp does CRC32 validation built-in; if it returns 0, the object landed.
# Use `gcloud storage cp` (newer than gsutil) — needs only objects.create on
# the destination object, doesn't probe with a list call like gsutil does.
if ! /usr/bin/docker exec "$PG_CTR" pg_dump -U "$POSTGRES_USER" -d "$POSTGRES_DB" -Fc \
     | /usr/bin/gcloud storage cp - "$DEST" 2>&1 >/dev/null; then
  log "ERROR: dump or upload failed"
  exit 3
fi

# We don't verify size after upload — backup-sa is append-only (no list/get
# perms by design, ransomware protection). Validation happens weekly via
# verify-latest-dump.sh, which runs as vm-runtime-sa with read access.
log "ok: uploaded $KEY"
