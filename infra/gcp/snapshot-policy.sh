#!/usr/bin/env bash
# Phase 7 — weekly GCE disk snapshots for the boot disk + data disk.
# Runs from operator laptop (not the VM).
#
# Idempotent: existing policy is updated, missing policy is created. Re-run
# safely after edits.
#
# Schedule: Sun 02:00 UTC, retain 4 weeks (~$0.05/GB-mo for snapshots in eu-west1).
set -euo pipefail

PROJECT_ID="${PROJECT_ID:-flowitup-folio-prod}"
REGION="${REGION:-europe-west1}"
ZONE="${ZONE:-europe-west1-b}"
VM_NAME="${VM_NAME:-flowitup-folio-prod-1}"
DATA_DISK_NAME="${DATA_DISK_NAME:-flowitup-folio-prod-data}"
POLICY_NAME="${POLICY_NAME:-folio-snapshot-weekly}"
RETENTION_DAYS="${RETENTION_DAYS:-28}"  # 4 weeks

log() { printf '[snapshot-policy] %s\n' "$*"; }

# 1. Create or update the resource policy.
if gcloud compute resource-policies describe "$POLICY_NAME" \
     --region="$REGION" --project="$PROJECT_ID" >/dev/null 2>&1; then
  log "policy $POLICY_NAME exists; gcloud doesn't support 'update' for snapshot schedules → recreate"
  log "  detaching from disks first…"
  for d in "$VM_NAME" "$DATA_DISK_NAME"; do
    gcloud compute disks remove-resource-policies "$d" \
      --resource-policies="$POLICY_NAME" --zone="$ZONE" --project="$PROJECT_ID" 2>/dev/null || true
  done
  gcloud compute resource-policies delete "$POLICY_NAME" \
    --region="$REGION" --project="$PROJECT_ID" --quiet
fi

log "creating policy $POLICY_NAME (Sun 02:00 UTC, retain ${RETENTION_DAYS}d)"
gcloud compute resource-policies create snapshot-schedule "$POLICY_NAME" \
  --region="$REGION" \
  --project="$PROJECT_ID" \
  --weekly-schedule="sunday" \
  --start-time="02:00" \
  --max-retention-days="$RETENTION_DAYS" \
  --on-source-disk-delete=apply-retention-policy \
  --storage-location="$REGION" \
  --description="Weekly snapshots of folio prod disks, retain ${RETENTION_DAYS}d"

# 2. Attach to boot disk (named after VM by default) and data disk.
for disk in "$VM_NAME" "$DATA_DISK_NAME"; do
  log "attaching policy to disk $disk"
  gcloud compute disks add-resource-policies "$disk" \
    --resource-policies="$POLICY_NAME" \
    --zone="$ZONE" \
    --project="$PROJECT_ID"
done

log "done. Verify with:"
log "  gcloud compute resource-policies describe $POLICY_NAME --region=$REGION --project=$PROJECT_ID"
log "  gcloud compute disks describe $VM_NAME --zone=$ZONE --project=$PROJECT_ID --format='value(resourcePolicies)'"
log ""
log "First snapshot will run next Sunday at 02:00 UTC. To trigger one immediately for testing:"
log "  gcloud compute disks snapshot $DATA_DISK_NAME --zone=$ZONE --project=$PROJECT_ID --snapshot-names=manual-test-\$(date +%Y%m%d-%H%M)"
