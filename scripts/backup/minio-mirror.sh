#!/usr/bin/env bash
# Phase 7 — daily MinIO → GCS mirror via mc (S3-compatible client).
# Runs ON THE VM via cron at 03:30 UTC.
#
# Why mc (not gsutil): mc speaks S3 on both ends, can sync MinIO ↔ GCS
# directly without disk staging. Uses HMAC keys (only S3-compatible auth GCS
# supports) bound to backup-sa. HMAC carve-out is the ONLY non-deploy-sa key
# in the system — see infra/gcp/iam-policies/backup-sa.yaml.
#
# Drift guard: refuses to mirror if source object count drops > 5% vs last
# successful run. Prevents wiped-MinIO from propagating to backup. Original
# plan used `mc mirror --remove` which destroyed backups on source corruption
# — explicitly DROPPED per Red Team finding 5.
set -euo pipefail

PROJECT_ID="${PROJECT_ID:-flowitup-folio-prod}"
ENV_FILE="${ENV_FILE:-/opt/folio/.env}"
BACKUP_BUCKET="${BACKUP_BUCKET:-${PROJECT_ID}-backups}"
LAST_COUNT_FILE="${LAST_COUNT_FILE:-/var/lib/folio/last-mc-count}"
DROP_THRESHOLD_PCT="${DROP_THRESHOLD_PCT:-95}"  # refuse if SRC < (LAST * 95 / 100)

log() { /usr/bin/logger -t minio-mirror -s "$*" 2>&1; }

[[ -r "$ENV_FILE" ]] || { log "ERROR: $ENV_FILE not readable"; exit 1; }

# Read creds from rendered .env (rendered by folio-render-env.service from SM).
S3_ACCESS_KEY=$(/usr/bin/awk -F= '/^S3_ACCESS_KEY=/ {print $2}' "$ENV_FILE")
S3_SECRET_KEY=$(/usr/bin/awk -F= '/^S3_SECRET_KEY=/ {print $2}' "$ENV_FILE")
S3_BUCKET=$(/usr/bin/awk -F= '/^S3_BUCKET=/ {print $2}' "$ENV_FILE")
GCS_HMAC_ACCESS=$(/usr/bin/awk -F= '/^GCS_HMAC_ACCESS_KEY=/ {print $2}' "$ENV_FILE")
GCS_HMAC_SECRET=$(/usr/bin/awk -F= '/^GCS_HMAC_SECRET_KEY=/ {print $2}' "$ENV_FILE")

for v in S3_ACCESS_KEY S3_SECRET_KEY S3_BUCKET GCS_HMAC_ACCESS GCS_HMAC_SECRET; do
  [[ -n "${!v}" ]] || { log "ERROR: $v missing from $ENV_FILE"; exit 1; }
done

# `mc` runs as a short-lived container — no host install required.
# --network host: connects to localhost:9000 (MinIO bound to 127.0.0.1:9000 in prod compose).
# Aliases configured via MC_HOST_<name> env vars (more robust than `mc alias set` in ephemeral container).
MC_RUN=(/usr/bin/docker run --rm --network host
  -e MC_HOST_minio="http://${S3_ACCESS_KEY}:${S3_SECRET_KEY}@127.0.0.1:9000"
  -e MC_HOST_gcs="https://${GCS_HMAC_ACCESS}:${GCS_HMAC_SECRET}@storage.googleapis.com"
  minio/mc:latest)

# Source object count — for drift guard.
SRC_COUNT=$("${MC_RUN[@]}" ls --recursive "minio/${S3_BUCKET}" 2>/dev/null | /usr/bin/wc -l | /usr/bin/tr -d ' ')
[[ "$SRC_COUNT" =~ ^[0-9]+$ ]] || { log "ERROR: source count not numeric: $SRC_COUNT"; exit 2; }

/usr/bin/install -d -m 755 -o root -g root "$(dirname "$LAST_COUNT_FILE")"
LAST_COUNT=$(/usr/bin/cat "$LAST_COUNT_FILE" 2>/dev/null || echo 0)

if [[ "$LAST_COUNT" -gt 0 ]]; then
  THRESHOLD=$(( LAST_COUNT * DROP_THRESHOLD_PCT / 100 ))
  if [[ "$SRC_COUNT" -lt "$THRESHOLD" ]]; then
    log "ABORT: source dropped >$(( 100 - DROP_THRESHOLD_PCT ))% ($LAST_COUNT → $SRC_COUNT, threshold=$THRESHOLD). Refusing to mirror — possible source corruption."
    exit 3
  fi
fi

# Actual mirror — overwrite is fine (object versioning on the bucket retains old).
# NO --remove flag (Red Team finding 5).
log "mirror start: minio/${S3_BUCKET} → gcs/${BACKUP_BUCKET}/minio-mirror/${S3_BUCKET}/  (src=$SRC_COUNT objects)"
if ! "${MC_RUN[@]}" mirror --overwrite \
     "minio/${S3_BUCKET}" \
     "gcs/${BACKUP_BUCKET}/minio-mirror/${S3_BUCKET}/"; then
  log "ERROR: mirror failed mid-run"
  exit 4
fi

# Persist count for next run's drift check.
printf '%s\n' "$SRC_COUNT" > "$LAST_COUNT_FILE"
log "ok: mirrored $SRC_COUNT objects (last=$LAST_COUNT → now=$SRC_COUNT)"
