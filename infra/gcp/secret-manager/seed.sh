#!/usr/bin/env bash
# Phase 6 — interactive seed of the 20 canonical Secret Manager keys.
# Idempotent: existing secrets are skipped (use --rotate <key> to add a new version).
#
# Reads each value via `read -s` (no terminal echo, no shell history), pipes to
# stdin of `gcloud secrets versions add` so the value never touches a file.
#
# Usage:
#   ./infra/gcp/secret-manager/seed.sh                   # seed missing keys
#   ./infra/gcp/secret-manager/seed.sh --rotate <key>    # add a new version of one key
#
# Prereqs: caller is project Owner / Secret Manager Admin; phase 1 done
# (vm-runtime-sa exists).
set -euo pipefail

PROJECT_ID="${PROJECT_ID:-flowitup-folio-prod}"
RUNTIME_SA="vm-runtime-sa@${PROJECT_ID}.iam.gserviceaccount.com"

# 20 canonical keys (Red Team + V3). The 2 CF keys (folio-cf-*) are MIRRORED
# from GitHub Secrets as a backup; the VM does NOT consume them, so render-env
# skips them. Listed here so seed coverage matches the audit table.
KEYS=(
  folio-postgres-user
  folio-postgres-password
  folio-postgres-db
  folio-secret-key
  folio-jwt-secret-key
  folio-s3-access-key
  folio-s3-secret-key
  folio-s3-bucket
  folio-s3-public-endpoint-url
  folio-cors-origins
  folio-next-public-api-base-url
  folio-resend-api-key
  folio-resend-from-email
  folio-ratelimit-storage-uri
  folio-behind-proxy
  folio-gcs-hmac-access-key
  folio-gcs-hmac-secret-key
  folio-admin-bootstrap-password
  folio-cf-api-token
  folio-cf-zone-id
)

# --rotate <key>: add a new version of one existing secret, skip everything else.
ROTATE_KEY=""
if [[ "${1:-}" == "--rotate" ]]; then
  ROTATE_KEY="${2:?usage: $0 --rotate <key>}"
  printf '%s\n' "${KEYS[@]}" | /usr/bin/grep -qx "$ROTATE_KEY" || {
    echo "ERROR: '$ROTATE_KEY' not in canonical list" >&2; exit 2
  }
fi

paste_secret() {
  local key="$1" tmp
  printf 'Paste value for %s (input hidden): ' "$key" >&2
  read -rs tmp
  echo >&2
  [[ -n "$tmp" ]] || { echo "ERROR: empty value rejected for $key" >&2; return 1; }
  printf '%s' "$tmp"
  unset tmp
}

bind_runtime_sa() {
  local key="$1"
  gcloud secrets add-iam-policy-binding "$key" \
    --member="serviceAccount:${RUNTIME_SA}" \
    --role=roles/secretmanager.secretAccessor \
    --project="$PROJECT_ID" \
    --condition=None >/dev/null
}

for key in "${KEYS[@]}"; do
  exists=0
  gcloud secrets describe "$key" --project="$PROJECT_ID" >/dev/null 2>&1 && exists=1

  if [[ -n "$ROTATE_KEY" ]]; then
    [[ "$key" == "$ROTATE_KEY" ]] || continue
    [[ "$exists" -eq 1 ]] || { echo "ERROR: $key does not exist; create first" >&2; exit 1; }
    paste_secret "$key" | gcloud secrets versions add "$key" --data-file=- --project="$PROJECT_ID" >/dev/null
    echo "  rotated $key (new version)"
    continue
  fi

  if [[ "$exists" -eq 1 ]]; then
    # Reconcile bind every run — idempotent, self-heals if a prior run created
    # the secret but failed to bind (transient IAM error → re-run would have
    # skipped bind forever otherwise).
    bind_runtime_sa "$key"
    echo "  $key — exists, bind reconciled (use --rotate $key to add new version)"
    continue
  fi

  paste_secret "$key" | gcloud secrets create "$key" \
    --replication-policy=automatic \
    --data-file=- \
    --labels=env=prod \
    --project="$PROJECT_ID" >/dev/null
  bind_runtime_sa "$key"
  echo "  created $key + bound vm-runtime-sa accessor"
done

echo ""
echo "done. Audit:"
echo "  gcloud secrets list --filter='labels.env=prod' --project=$PROJECT_ID"
