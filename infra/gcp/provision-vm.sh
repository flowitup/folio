#!/usr/bin/env bash
# Phase 2 — provision the prod VM + persistent data disk. Idempotent.
# Tunnel-only ingress (V4 lockdown): no static external IP, no 80/443 firewall.
# Disk is attached but NOT formatted/mounted — phase 3 (vm-bootstrap) does that.
#
# Usage:  ./infra/gcp/provision-vm.sh
# Optional env overrides:
#   PROJECT_ID          (default: flowitup-folio-prod)
#   ZONE                (default: europe-west1-b)
#   VM_NAME             (default: flowitup-folio-prod-1)
#   MACHINE_TYPE        (default: e2-standard-2)
#   IMAGE_FAMILY        (default: ubuntu-2404-lts-amd64)
#   IMAGE_PROJECT       (default: ubuntu-os-cloud)
#   DATA_DISK_NAME      (default: flowitup-folio-prod-data)
#   DATA_DISK_SIZE_GB   (default: 50)
#   BOOT_DISK_SIZE_GB   (default: 30)
#   DISK_TYPE           (default: pd-balanced)
set -euo pipefail

PROJECT_ID="${PROJECT_ID:-flowitup-folio-prod}"
ZONE="${ZONE:-europe-west1-b}"
VM_NAME="${VM_NAME:-flowitup-folio-prod-1}"
MACHINE_TYPE="${MACHINE_TYPE:-e2-standard-2}"
IMAGE_FAMILY="${IMAGE_FAMILY:-ubuntu-2404-lts-amd64}"
IMAGE_PROJECT="${IMAGE_PROJECT:-ubuntu-os-cloud}"
DATA_DISK_NAME="${DATA_DISK_NAME:-flowitup-folio-prod-data}"
DATA_DISK_SIZE_GB="${DATA_DISK_SIZE_GB:-50}"
BOOT_DISK_SIZE_GB="${BOOT_DISK_SIZE_GB:-30}"
DISK_TYPE="${DISK_TYPE:-pd-balanced}"
SA_EMAIL="vm-runtime-sa@${PROJECT_ID}.iam.gserviceaccount.com"
NETWORK_TAG="flowitup-folio-prod"
DEVICE_NAME="folio-data"   # appears as /dev/disk/by-id/google-folio-data inside the VM

log() { printf '[provision-vm] %s\n' "$*"; }

# Sanity: vm-runtime-sa must exist (phase 1).
if ! gcloud iam service-accounts describe "$SA_EMAIL" --project="$PROJECT_ID" >/dev/null 2>&1; then
  echo "ERROR: $SA_EMAIL not found. Run phase 1 (./infra/gcp/bootstrap.sh) first." >&2
  exit 1
fi

gcloud config set project "$PROJECT_ID" >/dev/null

# 1. Data disk — created separately so VM delete doesn't wipe data.
if ! gcloud compute disks describe "$DATA_DISK_NAME" --zone="$ZONE" >/dev/null 2>&1; then
  log "creating data disk $DATA_DISK_NAME (${DATA_DISK_SIZE_GB} GB $DISK_TYPE)"
  gcloud compute disks create "$DATA_DISK_NAME" \
    --size="${DATA_DISK_SIZE_GB}GB" --type="$DISK_TYPE" --zone="$ZONE"
else
  log "data disk $DATA_DISK_NAME exists"
fi

# 2. VM
if ! gcloud compute instances describe "$VM_NAME" --zone="$ZONE" >/dev/null 2>&1; then
  log "creating VM $VM_NAME ($MACHINE_TYPE, $IMAGE_FAMILY)"
  gcloud compute instances create "$VM_NAME" \
    --zone="$ZONE" \
    --machine-type="$MACHINE_TYPE" \
    --image-family="$IMAGE_FAMILY" --image-project="$IMAGE_PROJECT" \
    --boot-disk-size="${BOOT_DISK_SIZE_GB}GB" --boot-disk-type="$DISK_TYPE" \
    --disk="name=${DATA_DISK_NAME},device-name=${DEVICE_NAME},mode=rw,boot=no,auto-delete=no" \
    --service-account="$SA_EMAIL" \
    --scopes=cloud-platform \
    --tags="$NETWORK_TAG" \
    --labels=folio_env=prod \
    --metadata=enable-oslogin=TRUE \
    --shielded-secure-boot --shielded-vtpm --shielded-integrity-monitoring \
    --deletion-protection
else
  log "VM $VM_NAME exists — verifying critical settings"
fi

# 3. Idempotent reconciliation — re-apply settings on every run (drift correction).
gcloud compute instances add-labels "$VM_NAME" --zone="$ZONE" --labels=folio_env=prod >/dev/null
gcloud compute instances add-tags   "$VM_NAME" --zone="$ZONE" --tags="$NETWORK_TAG" >/dev/null
gcloud compute instances update     "$VM_NAME" --zone="$ZONE" --deletion-protection >/dev/null
gcloud compute instances add-metadata "$VM_NAME" --zone="$ZONE" \
  --metadata=enable-oslogin=TRUE >/dev/null

# 4. Confirm data disk is attached with auto-delete=no (catches drift if someone
# attached it interactively with auto-delete=yes). gcloud --format projections
# don't support JMESPath filter expressions; flatten the array first.
auto_delete=$(gcloud compute instances describe "$VM_NAME" --zone="$ZONE" \
  --flatten='disks[]' --filter="disks.deviceName=${DEVICE_NAME}" \
  --format='value(disks.autoDelete)' 2>/dev/null || true)
if [[ -n "$auto_delete" && "$auto_delete" != "False" && "$auto_delete" != "false" ]]; then
  log "WARN: data disk auto-delete is '$auto_delete'; setting to no"
  gcloud compute instances set-disk-auto-delete "$VM_NAME" --zone="$ZONE" \
    --disk="$DATA_DISK_NAME" --no-auto-delete >/dev/null
fi

log "done."
log "  VM:        $VM_NAME ($ZONE)"
log "  Data disk: $DATA_DISK_NAME -> /dev/disk/by-id/google-${DEVICE_NAME} (mount in phase 3)"
log "  IAP SSH:   gcloud compute ssh $VM_NAME --tunnel-through-iap --zone=$ZONE --project=$PROJECT_ID"
