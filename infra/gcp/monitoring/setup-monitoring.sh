#!/usr/bin/env bash
# Phase 8 — set up minimal Cloud Monitoring (Y3 trimmed: 2 alerts, no canary).
# Runs from operator laptop.
#
# Creates:
#   1. Email notification channel (idempotent by display-name)
#   2. Uptime check: GET https://folio.flowitup.com/api/v1/health every 60s, multi-region
#   3. Alert policy: uptime check fails  → email
#   4. Alert policy: disk usage > 85% on data disk (sustained 10 min) → email
#
# Dropped per Y3:
#   - CPU > 80% (fires during legit migrations on 2-vCPU VM)
#   - RAM > 90% (fires during build pulls)
#   - Log-based 5xx-rate metric (premature without baseline)
#   - Weekly canary email (uptime failure already pages)
#
# Required gcloud component: alpha (`gcloud components install alpha --quiet`)
set -euo pipefail

PROJECT_ID="${PROJECT_ID:-flowitup-folio-prod}"
ALERT_EMAIL="${ALERT_EMAIL:-mt.bui.fr@gmail.com}"
HEALTH_URL_HOST="${HEALTH_URL_HOST:-folio.flowitup.com}"
HEALTH_URL_PATH="${HEALTH_URL_PATH:-/health}"  # Flask exposes /health at root, not /api/v1/health
UPTIME_CHECK_NAME="folio-prod-health"
ALERT_NAME_UPTIME="Folio prod — health endpoint down"
ALERT_NAME_DISK="Folio prod — disk usage > 85%"
CHANNEL_DISPLAY="Folio ops email"

log() { printf '[monitoring] %s\n' "$*"; }

# --- 1. Email notification channel ---------------------------------------
log "ensuring email notification channel for $ALERT_EMAIL"
CHANNEL_ID=$(gcloud alpha monitoring channels list \
  --project="$PROJECT_ID" \
  --filter="displayName=\"$CHANNEL_DISPLAY\"" \
  --format='value(name)' 2>/dev/null | head -1)

if [[ -z "$CHANNEL_ID" ]]; then
  CHANNEL_ID=$(gcloud alpha monitoring channels create \
    --project="$PROJECT_ID" \
    --display-name="$CHANNEL_DISPLAY" \
    --type=email \
    --channel-labels="email_address=$ALERT_EMAIL" \
    --format='value(name)')
  log "  created: $CHANNEL_ID"
else
  log "  exists:  $CHANNEL_ID"
fi

# --- 2. Uptime check -----------------------------------------------------
log "ensuring uptime check on https://${HEALTH_URL_HOST}${HEALTH_URL_PATH}"
UPTIME_NAME=$(gcloud monitoring uptime list-configs \
  --project="$PROJECT_ID" \
  --filter="displayName=\"$UPTIME_CHECK_NAME\"" \
  --format='value(name)' 2>/dev/null | head -1)

if [[ -z "$UPTIME_NAME" ]]; then
  gcloud monitoring uptime create "$UPTIME_CHECK_NAME" \
    --project="$PROJECT_ID" \
    --resource-type=uptime-url \
    --resource-labels="host=${HEALTH_URL_HOST},project_id=${PROJECT_ID}" \
    --path="$HEALTH_URL_PATH" \
    --port=443 \
    --protocol=https \
    --validate-ssl=true \
    --status-classes=2xx \
    --period=1 \
    --timeout=10 \
    --regions=usa-oregon,europe,asia-pacific >/dev/null
  UPTIME_NAME=$(gcloud monitoring uptime list-configs \
    --project="$PROJECT_ID" \
    --filter="displayName=\"$UPTIME_CHECK_NAME\"" \
    --format='value(name)' | head -1)
  log "  created: $UPTIME_NAME"
else
  log "  exists:  $UPTIME_NAME"
fi

UPTIME_CHECK_ID=$(basename "$UPTIME_NAME")

# --- 3. Alert policy: uptime ---------------------------------------------
log "ensuring alert policy: $ALERT_NAME_UPTIME"
EXISTING_UPTIME=$(gcloud alpha monitoring policies list \
  --project="$PROJECT_ID" \
  --filter="displayName=\"$ALERT_NAME_UPTIME\"" \
  --format='value(name)' 2>/dev/null | head -1)

if [[ -z "$EXISTING_UPTIME" ]]; then
  TMP_POL=$(mktemp)
  cat > "$TMP_POL" <<EOF
displayName: $ALERT_NAME_UPTIME
combiner: OR
conditions:
  - displayName: Uptime check failed
    conditionThreshold:
      filter: |
        metric.type="monitoring.googleapis.com/uptime_check/check_passed"
        resource.type="uptime_url"
        metric.label."check_id"="$UPTIME_CHECK_ID"
      aggregations:
        - alignmentPeriod: 60s
          perSeriesAligner: ALIGN_NEXT_OLDER
          crossSeriesReducer: REDUCE_COUNT_FALSE
          groupByFields:
            - resource.label.host
      comparison: COMPARISON_GT
      thresholdValue: 1
      duration: 60s
      trigger:
        count: 1
    # NOTE for above: thresholdValue=1 + REDUCE_COUNT_FALSE means "fire when
    # at least 1 region reported a failure in the last alignment window".
notificationChannels:
  - $CHANNEL_ID
alertStrategy:
  autoClose: 86400s
EOF
  gcloud alpha monitoring policies create \
    --project="$PROJECT_ID" --policy-from-file="$TMP_POL" >/dev/null
  rm -f "$TMP_POL"
  log "  created"
else
  log "  exists:  $EXISTING_UPTIME"
fi

# --- 4. Alert policy: disk ----------------------------------------------
log "ensuring alert policy: $ALERT_NAME_DISK"
EXISTING_DISK=$(gcloud alpha monitoring policies list \
  --project="$PROJECT_ID" \
  --filter="displayName=\"$ALERT_NAME_DISK\"" \
  --format='value(name)' 2>/dev/null | head -1)

if [[ -z "$EXISTING_DISK" ]]; then
  TMP_POL=$(mktemp)
  cat > "$TMP_POL" <<EOF
displayName: $ALERT_NAME_DISK
combiner: OR
conditions:
  - displayName: Disk usage > 85%
    conditionThreshold:
      filter: |
        metric.type="agent.googleapis.com/disk/percent_used"
        resource.type="gce_instance"
        metric.label."state"="used"
      aggregations:
        - alignmentPeriod: 300s
          perSeriesAligner: ALIGN_MEAN
          crossSeriesReducer: REDUCE_MAX
          groupByFields:
            - resource.label.instance_id
            - metric.label.device
      comparison: COMPARISON_GT
      thresholdValue: 85
      duration: 600s
notificationChannels:
  - $CHANNEL_ID
alertStrategy:
  autoClose: 86400s
documentation:
  content: |
    Disk usage on the Folio prod VM exceeded 85%. Investigate:
      gcloud compute ssh flowitup-folio-prod-1 --tunnel-through-iap \\
        --zone=europe-west1-b -- 'df -h && sudo du -sh /var/lib/docker/* 2>/dev/null | sort -h | tail -10'
    Common causes: Docker image accumulation (image-prune cron should handle),
    log growth, MinIO bucket bloat. Free space → restart Docker → unblock writes.
  mimeType: text/markdown
EOF
  gcloud alpha monitoring policies create \
    --project="$PROJECT_ID" --policy-from-file="$TMP_POL" >/dev/null
  rm -f "$TMP_POL"
  log "  created"
else
  log "  exists:  $EXISTING_DISK"
fi

log ""
log "done. Verify in Console:"
log "  https://console.cloud.google.com/monitoring/alerting?project=$PROJECT_ID"
log "  https://console.cloud.google.com/monitoring/uptime?project=$PROJECT_ID"
log ""
log "EXPECT: until phase 9 (first deploy) completes and the API is up, the"
log "        uptime check will be RED and the email channel WILL alert. Mute"
log "        in the Console (Alert policies → Edit → Snooze) until phase 9."
