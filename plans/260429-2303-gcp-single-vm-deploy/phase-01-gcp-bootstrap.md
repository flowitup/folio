---
phase: 1
title: "GCP Bootstrap"
status: pending
priority: P1
effort: "2h"
dependencies: []
---

# Phase 1: GCP Bootstrap

> **[REVISED 2026-04-29]** SA roles + bucket retention + HMAC keys updated by red-team fixes. **The `## Red Team Fixes (2026-04-29)` section at the end is authoritative**; supersedes Architecture and Implementation Steps where they conflict.

## Overview

Create / select GCP project, enable required APIs, configure billing with the AI Ultra credit, set up Artifact Registry and a deploy service account. No VM yet — pure account-level setup so subsequent phases have a clean target.

## Requirements

- **Functional:** Project ready, APIs enabled, deploy SA can push images, billing alerts catch overruns.
- **Non-functional:** Least-privilege IAM, billing budget alerts ≤ $100/mo, region locked to `europe-west1`.

## Architecture

```
GCP Project (flowitup-folio-prod)
├── Billing Account (AI Ultra credit attached, $100 budget alert)
├── APIs enabled
│   ├── compute.googleapis.com           (GCE)
│   ├── artifactregistry.googleapis.com  (image hosting)
│   ├── secretmanager.googleapis.com     (env)
│   ├── storage.googleapis.com           (GCS backups)
│   ├── logging.googleapis.com           (Cloud Logging)
│   ├── monitoring.googleapis.com        (uptime checks)
│   └── iap.googleapis.com               (IAP-tunneled SSH)
├── Artifact Registry repo: europe-west1-docker.pkg.dev/flowitup-folio-prod/folio
├── GCS bucket: flowitup-folio-prod-backups (eu-west1, versioned, 30-day lifecycle)
└── Service Accounts
    ├── deploy-sa@        (CI/CD: AR push, SSH-via-IAP)
    ├── vm-runtime-sa@    (attached to VM: AR pull, GCS r/w, Secret Manager read)
    └── backup-sa@        (cron: GCS write only)
```

## Related Code Files

- Create: `infra/gcp/bootstrap.sh` — idempotent script (gcloud commands).
- Create: `infra/gcp/iam-policies/*.yaml` — SA bindings.
- Create: `docs/deployment-guide.md` (stub — filled in phase 11).

## Implementation Steps

1. Decide project name (e.g. `flowitup-folio-prod`) and confirm billing account ID.
2. `gcloud projects create flowitup-folio-prod` (or reuse existing — prompt user).
3. Link AI Ultra billing account: `gcloud beta billing projects link flowitup-folio-prod --billing-account=XXX`.
4. Enable APIs above (one `gcloud services enable` call, listed flags).
5. Create budget alert: $50 (50 %), $80 (80 %), $100 (100 %), $120 (over-credit) → notify deployer email.
6. Create Artifact Registry repo `folio` in `europe-west1`, format `docker`.
7. Create GCS bucket `flowitup-folio-prod-backups` with versioning + 30-day lifecycle on noncurrent versions.
8. Create three SAs with documented roles (deploy / vm-runtime / backup).
9. Generate JSON key for `deploy-sa` only (used by GitHub Actions). Other SAs use Workload Identity / VM-attached identity — no keys.
10. Document SA emails + project ID in `infra/gcp/README.md`.

## Success Criteria

- [ ] `gcloud projects describe flowitup-folio-prod` returns OK with billing linked.
- [ ] All 7 APIs report `ENABLED`.
- [ ] Budget alerts visible in Billing console.
- [ ] `gcloud artifacts repositories list --location=europe-west1` shows `folio`.
- [ ] `gsutil ls gs://flowitup-folio-prod-backups` works.
- [ ] All 3 SAs exist with correct roles (no Owner/Editor).
- [ ] `deploy-sa` JSON key downloaded and added to GitHub Secrets as `GCP_SA_KEY`.

## Risk Assessment

| Risk | Mitigation |
|---|---|
| Over-broad IAM (Editor role) | Use predefined granular roles only; lint with `gcloud iam policy-troubleshoot`. |
| Billing alert misconfigured → silent overrun | Verify by triggering test alert (set budget at $1 temporarily). |
| AI Ultra credit not applied to project | Confirm in Billing console "Credits" tab before any billable resource created. |
| SA key leaks | Only `deploy-sa` JSON key + GCS HMAC key for `backup-sa`; rotate every 90 days; grant minimal scopes. |

## Red Team Fixes (2026-04-29)

Findings 6, 9, 13 apply here. Override earlier sections as follows.

### Service account roles — corrected scopes

| SA | Use | IAM roles | Key |
|---|---|---|---|
| `deploy-sa` | GitHub Actions: AR push + IAP-tunneled gcloud SSH | `roles/artifactregistry.writer`, `roles/iap.tunnelResourceAccessor`, `roles/compute.osLogin` | JSON key in `GCP_SA_KEY` GitHub secret |
| `vm-runtime-sa` | VM workload: AR pull, Secret Manager read | `roles/artifactregistry.reader`, `roles/secretmanager.secretAccessor` (per-secret), `roles/logging.logWriter`, `roles/monitoring.metricWriter` | None (VM-attached identity) |
| `backup-sa` | Dump/WAL/MinIO uploaders via `--impersonate-service-account` from VM | `roles/storage.objectCreator` on `flowitup-folio-prod-backups` only (NO delete, NO admin) | GCS HMAC key (S3-compat for `mc`), stored in Secret Manager |

**Critical:** `vm-runtime-sa` MUST NOT have GCS write to the backup bucket. Backup scripts impersonate `backup-sa` from the VM. A VM compromise can't wipe backups.

### Backup bucket retention lock — explicit step (was buried in risk table)

Add to step 7 of Implementation Steps:
```bash
gsutil lifecycle set lifecycle.json gs://flowitup-folio-prod-backups
gsutil retention set 7d gs://flowitup-folio-prod-backups            # bucket-level retention lock
gsutil bucketpolicyonly set on gs://flowitup-folio-prod-backups     # uniform IAM, no per-object ACLs
```

A second bucket `flowitup-folio-prod-backups-archive` (monthly snapshots, 365-day retention lock) holds the long-term archival copy. `backup-sa` has `objectCreator` on it; nothing has delete.

### GCS HMAC key for `mc` (MinIO mirror) — net new

Add after step 9:
- `gcloud storage hmac create backup-sa@flowitup-folio-prod.iam.gserviceaccount.com` → outputs access-key + secret-key.
- Store in Secret Manager: `folio-gcs-hmac-access-key`, `folio-gcs-hmac-secret-key`.
- Document carve-out in `infra/gcp/README.md`: HMAC required because `mc` (MinIO client) speaks S3 protocol, not native GCS.

### Updated Success Criteria (additions)

- [ ] `deploy-sa` has `roles/iap.tunnelResourceAccessor` (verify: `gcloud iap tunnel ssh-test` from a runner with this SA).
- [ ] `backup-sa` has ONLY `roles/storage.objectCreator` (no delete, no admin).
- [ ] `vm-runtime-sa` has NO write access to backup bucket.
- [ ] Backup bucket retention policy = 7 days, bucket policy only ON.
- [ ] HMAC keys minted, stored in Secret Manager (NOT in GitHub Secrets, NOT in repo).
