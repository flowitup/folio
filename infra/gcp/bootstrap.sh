#!/usr/bin/env bash
# Phase 1 — GCP bootstrap. Idempotent: safe to re-run.
# Creates project, links billing, enables APIs, creates AR repo, GCS buckets,
# 3 service accounts with least-privilege bindings.
#
# Usage:
#   BILLING_ACCOUNT=XXXXXX-XXXXXX-XXXXXX ./infra/gcp/bootstrap.sh
#
# Optional flags:
#   --rotate-deploy-key   Mint a new JSON key for deploy-sa (paste into GitHub secret GCP_SA_KEY).
#   --rotate-hmac         Mint new GCS HMAC keys for backup-sa (paste into Secret Manager in phase 6).
#
# Optional env overrides:
#   PROJECT_ID (default: flowitup-folio-prod)
#   REGION     (default: europe-west1)
#   ADMIN_EMAIL (default: mt.bui.fr@gmail.com)
set -euo pipefail

PROJECT_ID="${PROJECT_ID:-flowitup-folio-prod}"
REGION="${REGION:-europe-west1}"
BILLING_ACCOUNT="${BILLING_ACCOUNT:?set BILLING_ACCOUNT=XXXXXX-XXXXXX-XXXXXX}"
ADMIN_EMAIL="${ADMIN_EMAIL:-mt.bui.fr@gmail.com}"
AR_REPO="folio"
PRIMARY_BUCKET="${PROJECT_ID}-backups"
ARCHIVE_BUCKET="${PROJECT_ID}-backups-archive"

ROTATE_DEPLOY_KEY=0
ROTATE_HMAC=0
for arg in "$@"; do
  case "$arg" in
    --rotate-deploy-key) ROTATE_DEPLOY_KEY=1 ;;
    --rotate-hmac)       ROTATE_HMAC=1 ;;
    -h|--help) sed -n '2,20p' "$0"; exit 0 ;;
    *) echo "unknown flag: $arg" >&2; exit 2 ;;
  esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
log() { printf '[bootstrap] %s\n' "$*"; }
sa() { printf '%s@%s.iam.gserviceaccount.com' "$1" "$PROJECT_ID"; }

# 1. Project — require explicit confirmation on create to prevent typo-creates-wrong-project
if ! gcloud projects describe "$PROJECT_ID" >/dev/null 2>&1; then
  printf '[bootstrap] project %s does not exist. Create it? Type "yes" to confirm: ' "$PROJECT_ID"
  read -r confirm
  [[ "$confirm" == "yes" ]] || { echo "aborted." >&2; exit 1; }
  log "creating project $PROJECT_ID"
  gcloud projects create "$PROJECT_ID"
else
  log "project $PROJECT_ID exists"
fi
gcloud config set project "$PROJECT_ID" >/dev/null

# 2. Billing
log "linking billing account $BILLING_ACCOUNT"
gcloud beta billing projects link "$PROJECT_ID" --billing-account="$BILLING_ACCOUNT" >/dev/null

# 3. APIs (single idempotent call)
log "enabling APIs"
gcloud services enable \
  compute.googleapis.com \
  artifactregistry.googleapis.com \
  secretmanager.googleapis.com \
  storage.googleapis.com \
  logging.googleapis.com \
  monitoring.googleapis.com \
  iap.googleapis.com \
  billingbudgets.googleapis.com \
  iamcredentials.googleapis.com

# 4. Budget alert ($50 / $80 / $100 / $120 of $100) — fail-soft.
# Budget API returns generic INVALID_ARGUMENT on minor flag-format drift across
# gcloud versions. If create fails, log a console URL and continue — the rest
# of bootstrap (AR, buckets, SAs, IAM) is independent and security-critical.
log "creating budget alert (idempotent, non-blocking)"
PROJECT_NUMBER="$(gcloud projects describe "$PROJECT_ID" --format='value(projectNumber)')"
budget_name="flowitup-folio-prod-budget"
if gcloud billing budgets list --billing-account="$BILLING_ACCOUNT" \
    --filter="displayName=$budget_name" --format="value(name)" 2>/dev/null | grep -q .; then
  log "budget $budget_name already exists"
elif gcloud billing budgets create \
    --billing-account="$BILLING_ACCOUNT" \
    --display-name="$budget_name" \
    --budget-amount=100USD \
    --threshold-rule=percent=0.5 \
    --threshold-rule=percent=0.8 \
    --threshold-rule=percent=1.0 \
    --threshold-rule=percent=1.2 \
    --filter-projects="projects/${PROJECT_NUMBER}" 2>/dev/null; then
  log "budget $budget_name created"
else
  log "WARN: budget create failed (gcloud version drift). Create manually:"
  log "      https://console.cloud.google.com/billing/${BILLING_ACCOUNT}/budgets?authuser=0"
  log "      Name: $budget_name | Amount: \$100 | Thresholds: 50/80/100/120% | Project filter: ${PROJECT_ID}"
  log "      Continuing — budget is a cost guardrail, not a deploy blocker."
fi

# 5. Artifact Registry
log "ensuring AR repo $AR_REPO in $REGION"
if ! gcloud artifacts repositories describe "$AR_REPO" --location="$REGION" >/dev/null 2>&1; then
  gcloud artifacts repositories create "$AR_REPO" --repository-format=docker --location="$REGION"
fi

# 6. Primary backup bucket: versioned, 30d lifecycle on noncurrent, 7d retention lock, UBLA
log "ensuring primary backup bucket gs://$PRIMARY_BUCKET"
if ! gcloud storage buckets describe "gs://$PRIMARY_BUCKET" >/dev/null 2>&1; then
  gcloud storage buckets create "gs://$PRIMARY_BUCKET" \
    --location="$REGION" --uniform-bucket-level-access
  gcloud storage buckets update "gs://$PRIMARY_BUCKET" --versioning
fi
gcloud storage buckets update "gs://$PRIMARY_BUCKET" --lifecycle-file="${SCRIPT_DIR}/lifecycle.json"
gcloud storage buckets update "gs://$PRIMARY_BUCKET" --retention-period=7d || \
  log "primary retention already set (locked); skipping"

# 7. Archive bucket: 365d retention lock, UBLA
log "ensuring archive backup bucket gs://$ARCHIVE_BUCKET"
if ! gcloud storage buckets describe "gs://$ARCHIVE_BUCKET" >/dev/null 2>&1; then
  gcloud storage buckets create "gs://$ARCHIVE_BUCKET" \
    --location="$REGION" --uniform-bucket-level-access
fi
gcloud storage buckets update "gs://$ARCHIVE_BUCKET" --retention-period=365d || \
  log "archive retention already set (locked); skipping"

# 8. Service accounts
for s in deploy-sa vm-runtime-sa backup-sa; do
  if ! gcloud iam service-accounts describe "$(sa "$s")" >/dev/null 2>&1; then
    log "creating SA $s"
    gcloud iam service-accounts create "$s" --display-name="$s"
  else
    log "SA $s exists"
  fi
done

# 9. IAM bindings — least-privilege, per Red Team Fixes (2026-04-29)
log "binding project roles"
for role in roles/artifactregistry.writer roles/iap.tunnelResourceAccessor roles/compute.osLogin; do
  gcloud projects add-iam-policy-binding "$PROJECT_ID" \
    --member="serviceAccount:$(sa deploy-sa)" --role="$role" --condition=None >/dev/null
done
for role in roles/artifactregistry.reader roles/logging.logWriter roles/monitoring.metricWriter; do
  gcloud projects add-iam-policy-binding "$PROJECT_ID" \
    --member="serviceAccount:$(sa vm-runtime-sa)" --role="$role" --condition=None >/dev/null
done
# vm-runtime-sa: roles/secretmanager.secretAccessor is bound PER-SECRET in phase 6 (least-privilege).
# vm-runtime-sa: NO write access to backup buckets — backup scripts impersonate backup-sa.

log "binding bucket-level roles for backup-sa"
# objectCreator on both buckets — write side
for bucket in "$PRIMARY_BUCKET" "$ARCHIVE_BUCKET"; do
  gcloud storage buckets add-iam-policy-binding "gs://$bucket" \
    --member="serviceAccount:$(sa backup-sa)" --role=roles/storage.objectCreator >/dev/null
done
# objectViewer on PRIMARY bucket only — required by gsutil/gcloud-storage cp
# (both pre-flight HEAD/GET before write). Archive bucket is write-once so
# no view perm needed there.
gcloud storage buckets add-iam-policy-binding "gs://$PRIMARY_BUCKET" \
  --member="serviceAccount:$(sa backup-sa)" --role=roles/storage.objectViewer >/dev/null

# vm-runtime-sa needs objectViewer on PRIMARY bucket for verify-latest-dump.sh
# (downloads + restores latest dump as a sanity check).
gcloud storage buckets add-iam-policy-binding "gs://$PRIMARY_BUCKET" \
  --member="serviceAccount:$(sa vm-runtime-sa)" --role=roles/storage.objectViewer >/dev/null

log "allowing vm-runtime-sa to impersonate backup-sa (token creator)"
gcloud iam service-accounts add-iam-policy-binding "$(sa backup-sa)" \
  --member="serviceAccount:$(sa vm-runtime-sa)" \
  --role=roles/iam.serviceAccountTokenCreator >/dev/null

# 10. (Optional) deploy-sa JSON key — only when explicitly rotating.
# Written to a tempdir (mode 700) to keep it out of the worktree if the operator
# runs `git add .` by reflex.
if [[ "$ROTATE_DEPLOY_KEY" -eq 1 ]]; then
  keydir="$(mktemp -d -t deploy-sa-key.XXXXXX)"
  chmod 700 "$keydir"
  out="$keydir/deploy-sa-key.json"
  gcloud iam service-accounts keys create "$out" --iam-account="$(sa deploy-sa)"
  log "key written to: $out"
  log "  -> paste contents into GitHub repo secret GCP_SA_KEY"
  log "  -> then: shred -u '$out' && rmdir '$keydir'  (or rm -P on macOS)"
fi

# 11. (Optional) GCS HMAC keys for backup-sa (mc/MinIO mirror) — paste into SM in phase 6
if [[ "$ROTATE_HMAC" -eq 1 ]]; then
  log "minting HMAC keys for backup-sa"
  log "  -> paste accessId  into Secret Manager: folio-gcs-hmac-access-key (phase 6)"
  log "  -> paste secret    into Secret Manager: folio-gcs-hmac-secret-key (phase 6)"
  gcloud storage hmac create "$(sa backup-sa)"
fi

log "done. Verify with: ./infra/gcp/bootstrap.sh --help and the README checklist."
