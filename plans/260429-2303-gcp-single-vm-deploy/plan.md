---
title: "GCP Single-VM Deploy (Option A)"
description: "Deploy Folio (6-service Docker stack) to a single GCE e2-standard-2 VM in europe-west1, fronted by Cloudflare, with GitHub Actions → SSH deploy and GCS-backed backups. Target ~$80/mo within $100 AI Ultra credit."
status: pending
priority: P1
branch: "claude/clever-elion-04ea3a"
tags: [deploy, infra, gcp, cloudflare, docker]
blockedBy: []
blocks: []
created: "2026-04-29T21:26:15.639Z"
createdBy: "ck:plan"
source: skill
---

# GCP Single-VM Deploy (Option A)

## Overview

Production deploy of the Folio app to GCP using the Option A architecture agreed in the brainstorm. One `e2-standard-2` VM in `europe-west1` runs all 6 Docker services (Flask API, RQ worker, Postgres 16, Redis 7, MinIO, Next.js SSR). Cloudflare handles DNS, TLS, and edge caching via orange-cloud proxy or Tunnel. Code ships through GitHub Actions → Artifact Registry → SSH `docker compose pull`. Postgres + MinIO back up nightly to GCS; weekly disk snapshots cover the rest.

**Source brainstorm:** [reports/brainstorm-260429-2303-gcp-deploy-strategy.md](./../reports/brainstorm-260429-2303-gcp-deploy-strategy.md)

**Budget:** ~$80/mo (eu-west1 list price) — fits inside $100 AI Ultra credit. Month-13 cost (no credit): $80/mo out of pocket.

**Acknowledged tradeoff:** self-managed Postgres in Docker = user owns DB recovery. Revisit Option B (Cloud SQL) at first DB scare or 50+ paying users.

## Phases

| Phase | Name | Status |
|-------|------|--------|
| 1 | [GCP Bootstrap](./phase-01-gcp-bootstrap.md) | Complete (2026-04-30) |
| 2 | [VM Provisioning](./phase-02-vm-provisioning.md) | Complete (2026-04-30) |
| 3 | [VM Bootstrap](./phase-03-vm-bootstrap.md) | Complete (2026-04-30) |
| 4 | [Cloudflare Wiring](./phase-04-cloudflare-wiring.md) | Complete (2026-04-30) |
| 5 | [CI/CD Pipeline](./phase-05-ci-cd-pipeline.md) | Code complete (2026-04-30) — operator wiring deferred |
| 6 | [Secrets Management](./phase-06-secrets-management.md) | Complete (2026-05-03) |
| 7 | [Backup Strategy](./phase-07-backup-strategy.md) | Code complete (2026-05-03) — VM-side smoke-test deferred to phase 9 |
| 8 | [Observability](./phase-08-observability.md) | Code complete (2026-05-03) — uptime alert snoozed until phase 9 |
| 9 | [First Deploy](./phase-09-first-deploy.md) | Pending |
| 10 | [Restore Drill](./phase-10-restore-drill.md) | Pending |
| 11 | [Runbook](./phase-11-runbook.md) | Pending |

## Phase ordering

```
1 → 2 → 3 → 6 → 4 → 5 → 7 → 8 → 9 → 10 → 11
        │              │
        └─ phase 6 (secrets) blocks any phase touching .env
```

Critical path: 1 → 2 → 3 → 9. Phases 4, 7, 8 can parallelize once 3 done.

## Dependencies

No cross-plan dependencies. App code (`folio-back-end`, `folio-front-end`) assumed deploy-ready.

## Open inputs needed before phase 1

### Resolved (committable, non-secret)

| Input | Value | Source |
|---|---|---|
| GCP project name | `flowitup-folio-prod` (new project) | V5 |
| Domain | `flowitup.com` (already on Cloudflare) | V6 + operator |
| App hostname | `folio.flowitup.com` | operator |
| SMTP provider | Resend | V3 |
| Admin email (bootstrap) | `mt.bui.fr@gmail.com` | operator |
| Region | `europe-west1` (Belgium) | brainstorm |
| Staging | none (prod-only) | V2 |
| Existing data migration | none (fresh start) | V7 |

### Required at execution time (NOT committed — paste directly into Secret Manager / GCP console)

| Secret | Where it goes | When |
|---|---|---|
| GCP billing account ID | `gcloud beta billing projects link flowitup-folio-prod --billing-account=<ID>` | Phase 1, step 3 |
| Resend API key | SM key `folio-resend-api-key` (via `read -s` + stdin pipe to `gcloud secrets versions add`) | Phase 6, seed step |
| Resend `from` address | SM key `folio-resend-from-email` (e.g. `noreply@flowitup.com`) | Phase 6 |
| Admin bootstrap password | SM key `folio-admin-bootstrap-password` (operator-generated, ≥ 20 chars from password manager) | Phase 9 |
| All other 18 SM keys | per phase-6 canonical list | Phase 6 |

**Secret handoff convention** (used by all seed scripts):
```bash
read -s -p "Paste <secret name>: " V && \
  printf %s "$V" | gcloud secrets versions add <key> --data-file=- --project=flowitup-folio-prod
unset V
```
- `read -s` = no echo to terminal
- piped via stdin = no shell history
- `unset V` immediately after = no env-var hangover
- never written to a file, never committed

**Reminder:** the Resend key first provided in conversation 2026-04-30 must be **rotated** before use — paste the new key, not the original.

## Out of scope

- Migration from existing Coolify/Hetzner deploy (no data carry-over assumed; if data exists, add a one-shot migration phase).
- Multi-region / HA failover (Option B/C territory).
- Kubernetes / GKE.
- Cloudflare R2 swap for GCS (deferred — user constrained to GCP).

## Red Team Review

### Session — 2026-04-29
**Findings:** 15 (15 accepted, 0 rejected)
**Severity breakdown:** 7 Critical, 8 High, 0 Medium
**Reviewers:** Security Adversary, Failure Mode Analyst, Assumption Destroyer, Scope & Complexity Critic
**Verification tier:** Full (4 roles, 15+ claims/phase)

| # | Finding | Severity | Disposition | Applied To |
|---|---------|----------|-------------|------------|
| 1 | `flask db upgrade` / `flask seed admin` are fictional CLI commands; real path is `python scripts/seed.py --with-admin` | Critical | Accept | Phase 5, 9, 10 |
| 2 | Per-deploy migrations missing in CI workflow; `/health` is shallow so schema-drift deploys pass healthcheck | Critical | Accept | Phase 5 |
| 3 | WAL `archive_command='/scripts/pg-wal-archive.sh'` runs in `postgres:16-alpine` with no gsutil and no script mount → halts commits | Critical | Accept | Phase 7 |
| 4 | Default `${POSTGRES_USER:-construction}`, `${S3_ACCESS_KEY:-minioadmin}` leak to prod; SM key list incomplete; `JWT_SECRET_KEY` naming mismatch | Critical | Accept | Phase 3, 6, 9 |
| 5 | `mc mirror --overwrite --remove` deletes GCS backups when MinIO source is wiped | Critical | Accept | Phase 7 |
| 6 | GitHub Actions runner cannot reach VM via IAP-only firewall (raw `ssh` from `ubuntu-latest`) | Critical | Accept | Phase 1, 2, 5 |
| 7 | `wait-healthy.sh` hangs on worker (`healthcheck: disable: true`); phase 9 "all 6 healthy" unreachable | Critical | Accept | Phase 5, 9 |
| 8 | No `ProxyFix` wrapper in Flask → rate limiter sees one IP behind Cloudflare → trivially bypassed | High | Accept | Phase 4 |
| 9 | `vm-runtime-sa` has GCS r/w to backup bucket; `backup-sa` defined but unused; retention lock only in risk table | High | Accept | Phase 1, 7 |
| 10 | Internal `5432`/`6379`/`9000`/`9001` published on `0.0.0.0` → one firewall slip exposes Postgres + MinIO console with default creds | High | Accept | Phase 3, 4 |
| 11 | `S3_ENDPOINT_URL=http://minio:9000` is docker-internal; presigned URL probe in smoke-test would issue browser-unreachable URLs; `S3AttachmentStorage` has no presign method | High | Accept | Phase 9 |
| 12 | Cloudflare `_next/static/*` cached 1-month edge TTL but frontend deploy has no `purge_cache` API call | High | Accept | Phase 5 |
| 13 | `mc` requires GCS HMAC key; phase 1 forbids SA keys; HMAC carve-out never minted, never in Secret Manager | High | Accept | Phase 1, 6, 7 |
| 14 | Existing 569-line `scripts/smoke-test.sh` duplicated by new `scripts/test/smoke-test.sh` | High | Accept | Phase 9 |
| 15 | Phase 3 named-volume → bind-mount migration loses data; UID `1000:1000` wrong (postgres:16-alpine uses UID 70) | High | Accept (modified) | Phase 3 |

### Whole-Plan Consistency Sweep
- Files reread: plan.md, phase-01 through phase-11 (12 files)
- Decision deltas checked: 15
- Banner pattern: each affected phase carries a `> [REVISED 2026-04-29]` banner at the top + `## Red Team Fixes (2026-04-29)` section at the bottom. Original sections retained as history; banner declares fixes section authoritative.
- Cross-phase grep results (stale terms confirmed contained):
  - "5 min RPO" — appears only in phase-07 + phase-10 superseded sections + plan-md sweep notes; banners point to ≤24 h.
  - `flask seed admin` — phase-09 superseded step 5c only; banner + fixes section override.
  - `scripts/test/smoke-test.sh` — phase-09 superseded "Related Code Files" only; banner overrides.
  - `archive_command` / `pg-wal-archive` — phase-07 superseded steps 4–5 + risk row (which is also struck-through); banner declares dropped.
  - `folio-jwt-secret` (without `-key`) — phase-06 superseded list only; corrected list in fixes section.
  - `mc mirror --overwrite --remove` — phase-07 superseded step 7 only; replacement script in fixes section.
  - `1000:1000` UID — phase-03 superseded success criterion only; replacement criteria in fixes section.
  - `ssh -i $SSH_KEY` — phase-05 superseded architecture diagram only; gcloud IAP wrapper in fixes section.
- Reconciled cross-phase impacts:
  - Phase 1 ↔ Phase 7: `backup-sa` now active (was orphaned); HMAC carve-out documented in both.
  - Phase 1 ↔ Phase 5: `deploy-sa` gains `roles/iap.tunnelResourceAccessor`; phase 2 banner notes IAM dep.
  - Phase 7 ↔ Phase 10: WAL drop propagated (phase 10 RPO/replay both updated).
  - Phase 6 ↔ Phase 3: prod compose override (`docker-compose.prod.yml`) referenced from both phases for the `:?required` env enforcement.
- Unresolved contradictions: **0** — plan is consistent after fixes.

### Acknowledged trade-offs (still in effect after fixes)
- Self-managed Postgres on single VM (Option A choice) — operator owns recovery.
- RPO downgraded honestly from "≤5 min (aspirational)" to "≤24 h (real)". WAL/PITR deferred to a future phase or an Option B migration.
- ~~Scope-critic YAGNI cuts NOT applied — flagged for a follow-up simplification pass if desired.~~ **Applied in Validation Session below.**

## Validation Log

### Session 1 — 2026-04-29
**Mode:** prompt (per Plan Context). **Questions asked:** 8 (within 3-8 range).
**Verification pass:** SKIPPED — `## Red Team Review` already contains Full-tier verification evidence (15 findings, all evidence-backed). No `[UNVERIFIED]` tags found in sweep.

#### Decisions

| # | Topic | Decision | Impact |
|---|---|---|---|
| V1 | YAGNI cuts | **Apply all 6** | Plan ~33h → ~20h |
| V2 | Staging environment | **Skip — prod-only** | No second VM. Phase 2 unchanged. |
| V3 | Outbound SMTP | **Resend** | Phase 6 SM keys add `folio-resend-api-key`. Phase 4 adds SPF + DKIM CNAME records. Phase 9 risk row "new IP → spam" mitigated by Resend's reputation. |
| V4 | Cloudflare ingress | **Tunnel only** — delete A-record path | Phase 4 keeps Tunnel section, drops A-record/Caddy section. Phase 2 firewall does NOT open 80/443 publicly at all (was already conditional in red-team fixes). Static IP unnecessary. |
| V5 | GCP project | **New project `flowitup-folio-prod`** | Phase 1 step 2 confirmed `gcloud projects create flowitup-folio-prod`. AI Ultra credit attaches at billing-account level. |
| V6 | Domain | **Already at Cloudflare** | Phase 4 just adds records. No phase-0 registration needed. |
| V7 | Existing Coolify/Hetzner data | **Fresh start, no migration** | Out-of-scope assumption stands. Phase 9 seeds admin only. |

#### YAGNI cuts applied (V1)

| # | Cut | Affected phase | Effort reclaimed |
|---|---|---|---|
| Y1 | Drop fail2ban | Phase 3 | ~30 min |
| Y2 | Drop secrets render-timer (boot-only render) | Phase 6 | ~45 min |
| Y3 | Trim alert policies 5 → 2 (uptime + disk only) | Phase 8 | ~1h |
| Y4 | Drop drill auto-trigger (Cloud Scheduler + Cloud Function + janitor cron) | Phase 10 | ~1.5h |
| Y5 | Lock hedged decisions: gcloud bash script, Tunnel-only, shared worker image | Phase 2, 4, 5 | ~2h |
| Y6 | Reduce doc surfaces 5 → 2 (drop quick-reference + codebase-summary update) | Phase 11 | ~1h |

#### Updated effort estimate

| Phase | Pre-validation | Post-validation |
|---|---|---|
| 1 | 2h | 1.5h |
| 2 | 3h | 2h |
| 3 | 3h | 2h |
| 4 | 2h | 1h |
| 5 | 4h | 3h |
| 6 | 2h | 1h |
| 7 | 4h | 2h |
| 8 | 3h | 1.5h |
| 9 | 4h | 3h |
| 10 | 4h | 2.5h |
| 11 | 2h | 1h |
| **Total** | **~33h** | **~20.5h** |

### Whole-Plan Consistency Sweep
- Files reread: plan.md + phase-01..phase-11
- Decision deltas checked: 7 (V1–V7) + 6 YAGNI sub-cuts (Y1–Y6)
- Each affected phase carries `## Validation Decisions (2026-04-29 Session 1)` section listing applied cuts; banner at top of phase points to it as authoritative alongside red-team fixes.
- Cross-phase impacts:
  - Resend choice (V3) propagated to phase 4 (DNS records) + phase 6 (SM key) + phase 9 (smoke-test outbound email canary).
  - Tunnel-only lock (V4) ratifies what red-team already implied — no further rule changes; phase 2 firewall confirmed Tunnel-only.
  - YAGNI cut Y5 deletes "either Terraform or gcloud" hedge (locks gcloud) and "shared or separate worker workflow" hedge (locks shared image — already in `docker-compose.yml`).
- Unresolved contradictions: **0**.

### Recommendation

Plan is ready for `/ck:cook`. All red-team Critical/High findings applied. All validation decisions propagated. No `[UNVERIFIED]` tags. No cross-phase contradictions. Honest effort estimate ~20.5h.
