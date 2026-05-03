#!/usr/bin/env bash
# Phase 7 — weekly verification that latest pg_dump is actually restorable.
# Runs ON THE VM via cron (Sun 04:00 UTC).
#
# Strategy:
#   1. Download latest dump from gs://flowitup-folio-prod-backups/pg-dumps/
#   2. Spin up a sidecar Postgres container on a random port
#   3. pg_restore into it
#   4. Run a sanity query (SELECT 1; — schema-agnostic, just proves connection)
#   5. Tear down sidecar regardless of outcome
#
# Failure to restore == backup is corrupt. Logs to journald with tag
# "backup-verify"; alert policy in phase 8 can later watch for failures.
set -euo pipefail

PROJECT_ID="${PROJECT_ID:-flowitup-folio-prod}"
ENV_FILE="${ENV_FILE:-/opt/folio/.env}"
BACKUP_BUCKET="${BACKUP_BUCKET:-${PROJECT_ID}-backups}"
BACKUP_SA="backup-sa@${PROJECT_ID}.iam.gserviceaccount.com"
WORK_DIR="${WORK_DIR:-/var/lib/folio/restore-test}"

log() { /usr/bin/logger -t backup-verify -s "$*" 2>&1; }

# Read DB name from .env so we restore into the same logical DB.
POSTGRES_USER=$(/usr/bin/awk -F= '/^POSTGRES_USER=/ {print $2}' "$ENV_FILE")
POSTGRES_DB=$(/usr/bin/awk -F= '/^POSTGRES_DB=/ {print $2}' "$ENV_FILE")
[[ -n "$POSTGRES_USER" && -n "$POSTGRES_DB" ]] || { log "ERROR: POSTGRES_USER/DB missing"; exit 1; }

# We can READ the bucket only via vm-runtime-sa if it has objectViewer. By
# default backup-sa is write-only, so we need impersonation OR a one-off
# objectViewer binding. Use impersonation (consistent w/ pg-dump.sh).
# NOTE: backup-sa lacks objectViewer per its policy; verify must use a
# different SA. For now: use vm-runtime-sa's default credentials and rely on
# the operator granting it transient read via:
#   gcloud storage buckets add-iam-policy-binding gs://${BACKUP_BUCKET} \
#     --member=serviceAccount:vm-runtime-sa@... --role=roles/storage.objectViewer
# Documented in infra/gcp/README.md (phase 7 section).
unset CLOUDSDK_AUTH_IMPERSONATE_SERVICE_ACCOUNT 2>/dev/null || true

/usr/bin/install -d -m 700 "$WORK_DIR"
LATEST_KEY=$(/usr/bin/gsutil ls "gs://${BACKUP_BUCKET}/pg-dumps/" 2>/dev/null | /usr/bin/sort | /usr/bin/tail -1)
[[ -n "$LATEST_KEY" ]] || { log "ERROR: no dumps found in gs://${BACKUP_BUCKET}/pg-dumps/"; exit 2; }

LOCAL_DUMP="${WORK_DIR}/$(/usr/bin/basename "$LATEST_KEY")"
log "downloading $LATEST_KEY → $LOCAL_DUMP"
/usr/bin/gsutil -q cp "$LATEST_KEY" "$LOCAL_DUMP"

# Sidecar container — random suffix to avoid name conflicts on overlap.
SUFFIX=$(/usr/bin/od -An -tx1 -N4 /dev/urandom | /usr/bin/tr -d ' ')
SIDE_NAME="folio-restore-test-${SUFFIX}"
SIDE_PORT=55432  # arbitrary, on 127.0.0.1, container-only

cleanup() {
  /usr/bin/docker rm -f "$SIDE_NAME" >/dev/null 2>&1 || true
  /usr/bin/rm -f "$LOCAL_DUMP"
}
trap cleanup EXIT

log "starting sidecar: $SIDE_NAME"
/usr/bin/docker run -d --rm \
  --name "$SIDE_NAME" \
  -e POSTGRES_USER="$POSTGRES_USER" \
  -e POSTGRES_PASSWORD="verify-only-$(/usr/bin/od -An -tx1 -N8 /dev/urandom | /usr/bin/tr -d ' ')" \
  -e POSTGRES_DB="$POSTGRES_DB" \
  -p "127.0.0.1:${SIDE_PORT}:5432" \
  postgres:16-alpine >/dev/null

# Wait for ready (max 30s).
for _ in $(seq 1 30); do
  if /usr/bin/docker exec "$SIDE_NAME" pg_isready -U "$POSTGRES_USER" -d "$POSTGRES_DB" >/dev/null 2>&1; then
    break
  fi
  sleep 1
done

# Restore.
log "restoring into $SIDE_NAME"
if ! /usr/bin/docker exec -i "$SIDE_NAME" pg_restore \
       --clean --if-exists --no-owner --no-privileges \
       -U "$POSTGRES_USER" -d "$POSTGRES_DB" < "$LOCAL_DUMP"; then
  log "ERROR: pg_restore failed — backup is unusable"
  exit 3
fi

# Sanity query — just proves DB is queryable post-restore.
ROW=$(/usr/bin/docker exec "$SIDE_NAME" psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -tAc 'SELECT 1;' 2>/dev/null || true)
[[ "$ROW" == "1" ]] || { log "ERROR: post-restore SELECT 1 failed (got: $ROW)"; exit 4; }

log "ok: $LATEST_KEY restored cleanly into sidecar"
