#!/usr/bin/env bash
# Phase 2 — firewall rules. Idempotent.
#
# Tunnel-only ingress (V4 lockdown): only IAP SSH on tcp:22. No 80/443 — Cloudflare
# Tunnel reaches the VM via OUTBOUND cloudflared connection from the VM, so no
# inbound HTTP firewall holes are needed. Phase 4 wires the tunnel.
#
# Usage:  ./infra/gcp/firewall.sh [--audit-only]
# Env overrides:
#   PROJECT_ID  (default: flowitup-folio-prod)
set -euo pipefail

PROJECT_ID="${PROJECT_ID:-flowitup-folio-prod}"
NETWORK_TAG="flowitup-folio-prod"
IAP_SSH_RULE="allow-iap-ssh"
IAP_RANGE="35.235.240.0/20"   # GCP IAP TCP-forwarding source range (fixed, public)

AUDIT_ONLY=0
[[ "${1:-}" == "--audit-only" ]] && AUDIT_ONLY=1

log() { printf '[firewall] %s\n' "$*"; }

gcloud config set project "$PROJECT_ID" >/dev/null

if [[ "$AUDIT_ONLY" -eq 0 ]]; then
  # 1. Create our IAP-only rule.
  if ! gcloud compute firewall-rules describe "$IAP_SSH_RULE" >/dev/null 2>&1; then
    log "creating $IAP_SSH_RULE"
    gcloud compute firewall-rules create "$IAP_SSH_RULE" \
      --description="IAP-tunneled SSH from gcloud (${IAP_RANGE})" \
      --direction=INGRESS \
      --action=ALLOW \
      --rules=tcp:22 \
      --source-ranges="$IAP_RANGE" \
      --target-tags="$NETWORK_TAG"
  else
    log "$IAP_SSH_RULE exists"
  fi

  # 2. Delete the 3 wide-open rules GCP creates by default in every new VPC.
  # `default-allow-internal` (10.128.0.0/9) stays — it's VPC-internal, harmless.
  # `default-allow-icmp/ssh/rdp` are 0.0.0.0/0 — public surface our design forbids.
  for rule in default-allow-ssh default-allow-rdp default-allow-icmp; do
    if gcloud compute firewall-rules describe "$rule" >/dev/null 2>&1; then
      log "deleting world-open default rule: $rule"
      gcloud compute firewall-rules delete "$rule" --quiet
    fi
  done
fi

# 3. Audit: list every ingress rule and flag anyone with 0.0.0.0/0 source.
# (gcloud's filter language can't reliably match the literal CIDR — chokes on
# the dots/slash. Post-process the listing instead.)
log "ingress rules audit:"
gcloud compute firewall-rules list \
  --filter='direction=INGRESS AND disabled=false' \
  --format='table(name,sourceRanges.list():label=SRC,allowed[].map().firewall_rule().list():label=ALLOW,targetTags.list():label=TAGS)'

world_open=$(gcloud compute firewall-rules list \
  --filter='direction=INGRESS AND disabled=false' \
  --format='csv[no-heading](name,sourceRanges.list())' \
  | /usr/bin/awk -F, '$2 ~ /(^|;)0\.0\.0\.0\/0(;|$)/ {print $1}')
if [[ -n "$world_open" ]]; then
  echo "FAIL: world-open ingress rules remain: $world_open" >&2
  echo "      Phase 2 (Tunnel-only) requires NO 0.0.0.0/0 ingress." >&2
  exit 1
fi

log "done. Only $IAP_SSH_RULE allows ingress (plus VPC-internal default-allow-internal)."
