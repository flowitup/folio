---
phase: 2
title: "VM Provisioning"
status: pending
priority: P1
effort: "3h"
dependencies: [1]
---

# Phase 2: VM Provisioning

> **[REVISED 2026-04-29]** IAP firewall rule unchanged but `deploy-sa` now needs `roles/iap.tunnelResourceAccessor` (added in phase 1 fixes). **YAGNI lock-in:** Tooling = gcloud bash script (NOT Terraform). Tunnel-only ingress = no static IP, no port 80/443 firewall rules. See **`## Red Team Fixes`** + **`## Validation Decisions`** at end (both authoritative).

## Overview

Provision the single `e2-standard-2` VM in `europe-west1`, attached to a `pd-balanced` 50 GB data disk, with a static external IP, locked-down firewall, and the `vm-runtime-sa` attached. Idempotent infra-as-code preferred — Terraform if user is comfortable, else `gcloud` script.

## Requirements

- **Functional:** VM boots, has internet egress, `vm-runtime-sa` attached, OS Login enabled, firewall blocks inbound except 22 (IAP) and 80/443 (Cloudflare IPs only).
- **Non-functional:** Reproducible (script can re-run after `terraform destroy`), tagged for cost tracking, deletion protection ON for prod.

## Architecture

```
VPC: default (or custom folio-vpc)
└── europe-west1-b
    └── instance: flowitup-folio-prod-1
        ├── machine-type: e2-standard-2 (2 vCPU, 8 GB)
        ├── image: ubuntu-2404-lts-amd64 (locked 2026-04-30)
        ├── boot disk: 30 GB pd-balanced
        ├── data disk: 50 GB pd-balanced (mounted /var/lib/folio)
        ├── network tags: [flowitup-folio-prod, http-cf, https-cf]
        ├── service account: vm-runtime-sa@
        ├── static external IP: flowitup-folio-prod-ip (or skip if Tunnel-only)
        ├── deletion protection: true
        └── metadata: enable-oslogin=TRUE
Firewall rules:
├── allow-iap-ssh         tcp:22  src=35.235.240.0/20  (IAP range)
├── allow-cf-http         tcp:80  src=Cloudflare IPv4 list, target-tag=http-cf
└── allow-cf-https        tcp:443 src=Cloudflare IPv4 list, target-tag=https-cf
```

## Related Code Files

- Create: `infra/gcp/terraform/main.tf` — VM, disk, IP, firewall (or `infra/gcp/provision-vm.sh` if no Terraform).
- Create: `infra/gcp/terraform/variables.tf` — project, region, zone, machine type.
- Create: `infra/gcp/terraform/cloudflare-ips.tf` — fetch CF IP list dynamically (data source) instead of hardcoding.

## Implementation Steps

1. Decide tooling: Terraform vs `gcloud` script. Default Terraform for diff visibility.
2. Reserve static external IP `flowitup-folio-prod-ip` in `europe-west1` (skip if going Tunnel-only).
3. Create the data disk separately so `terraform destroy` of the VM doesn't wipe data.
4. Create VM with attached disk, `vm-runtime-sa`, OS Login enabled, deletion protection ON.
5. Create three firewall rules above. Pull Cloudflare IP list from `https://www.cloudflare.com/ips-v4` via Terraform `http` data source — no hardcoded IPs.
6. Verify SSH via IAP: `gcloud compute ssh flowitup-folio-prod-1 --tunnel-through-iap --zone=europe-west1-b`.
7. Mount data disk at `/var/lib/folio` (format ext4, add to `/etc/fstab` with `nofail,discard`).
8. Tag the VM for cost tracking (`label folio_env=prod`).
9. Document `terraform apply` runbook in `infra/gcp/README.md`.

## Success Criteria

- [ ] `gcloud compute instances list` shows `flowitup-folio-prod-1` RUNNING.
- [ ] SSH via IAP works; SSH on public IP refuses.
- [ ] `df -h /var/lib/folio` shows the 50 GB data disk mounted.
- [ ] `terraform plan` is clean after `apply` (no drift).
- [ ] Firewall ingress on 80/443 only from Cloudflare IPs (verified with `nmap` from non-CF host → blocked).
- [ ] Deletion protection enabled.

## Risk Assessment

| Risk | Mitigation |
|---|---|
| Accidental `terraform destroy` deletes data disk | Data disk in separate Terraform module + `prevent_destroy=true` lifecycle. |
| Cloudflare IP list changes silently | Re-fetch on `terraform apply`; alert if list-hash changes between applies. |
| Public 22 left open | Explicit firewall rule for IAP range only; add `gcloud compute firewall-rules list` audit to runbook. |
| Wrong region picked → latency hit | Lock region in Terraform vars; CI check rejects non-eu-west1 plans. |
| VM size undersized for full stack | Monitor RAM/CPU after phase 9; resize is one-step (`gcloud compute instances set-machine-type`). |

## Red Team Fixes (2026-04-29)

Finding 6 applies here. Override clarifications below.

### IAP SSH from CI — must be reachable for deploy

Phase 5 will execute `gcloud compute ssh --tunnel-through-iap` from the GitHub Actions runner using `deploy-sa` credentials. The firewall rule `allow-iap-ssh tcp:22 src=35.235.240.0/20` (already in plan) is correct, AND `deploy-sa` must hold `roles/iap.tunnelResourceAccessor` on the project (added in phase 1 fixes). Plain `ssh -i $SSH_KEY deploy@<vm-ip>` from `ubuntu-latest` runners is BLOCKED by this firewall — confirmed correct, plan 5 must use the gcloud wrapper.

### Updated Success Criteria (addition)

- [ ] From a clean `ubuntu-latest` runner, `gcloud compute ssh deploy@flowitup-folio-prod-1 --tunnel-through-iap --zone=europe-west1-b --command="echo ok"` returns `ok`. Plain `ssh` to the VM's external IP is rejected by the firewall.

## Validation Decisions (2026-04-29 Session 1)

**Y5 — Tooling locked: gcloud bash script (NOT Terraform).**

Original step 1 said "Decide tooling: Terraform vs `gcloud` script. Default Terraform for diff visibility." **Decision:** `gcloud`-only. Reasons:
- Solo operator, one VM — diff visibility benefit doesn't pay back the Terraform setup cost.
- Faster iteration when learning GCP IAM / compute semantics.
- Idempotent enough via `gcloud compute instances describe || gcloud compute instances create`.

**Action:** Delete Terraform mentions from "Related Code Files" and Implementation Steps. Replace with:
- Create: `infra/gcp/provision-vm.sh` (idempotent gcloud script).
- Create: `infra/gcp/firewall.sh` (idempotent firewall rules + Cloudflare IP fetch via curl).
- Delete: `infra/gcp/terraform/` references throughout.

**Tunnel-only also locked here (V4):** firewall does NOT include `allow-cf-http`/`allow-cf-https` rules; phase 4 confirms Tunnel-only ingress. No static IP needed (phase 4 uses CNAME to `<tunnel-uuid>.cfargotunnel.com`).

**Updated Success Criteria (replacement):**
- [ ] `provision-vm.sh` is idempotent (re-runs without error if VM already exists).
- [ ] No static external IP allocated (Tunnel-only ingress).
- [ ] Firewall rules: only `allow-iap-ssh` (no port 80/443 open from any source).
