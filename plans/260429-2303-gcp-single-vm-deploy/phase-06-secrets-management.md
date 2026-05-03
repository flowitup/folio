---
phase: 6
title: "Secrets Management"
status: pending
priority: P1
effort: "2h"
dependencies: [3]
---

# Phase 6: Secrets Management

> **[REVISED 2026-04-29]** Canonical SM-key list expanded from 7 → 22 → 20 keys. Key naming corrected: `JWT_SECRET_KEY` → `folio-jwt-secret-key`. HMAC keys for `mc` + admin-bootstrap password added. **YAGNI Y2:** systemd render-env timer DELETED (was security theater — daily rewrite doesn't propagate to running containers). **V3:** SMTP keys swapped — 4 generic `folio-smtp-*` keys replaced by `folio-resend-api-key` + `folio-resend-from-email`. **The `## Red Team Fixes` and `## Validation Decisions` sections at the end are authoritative**; supersede the original architecture secret list and timer setup.

## Overview

Production secrets live in **Google Secret Manager**, fetched at VM boot (and on demand) by a small wrapper that renders `/opt/folio/.env`. CI never sees prod secret values. Local dev / `.env.example` stays in repo unchanged.

## Requirements

- **Functional:** All required env vars (DB password, JWT secret, SMTP creds, S3 keys, etc.) present in `/opt/folio/.env` before `docker compose up`. Rotation possible without VM rebuild.
- **Non-functional:** Secrets at rest encrypted (Secret Manager default), VM SA has read-only access, no plaintext secrets in git, in CI logs, or in VM metadata.

## Architecture

```
Google Secret Manager (flowitup-folio-prod)
├── folio-postgres-password
├── folio-secret-key              (Flask SECRET_KEY)
├── folio-jwt-secret
├── folio-smtp-pass
├── folio-s3-secret-key           (MinIO root password)
├── folio-cors-origins
└── folio-next-public-api-base-url

vm-runtime-sa  →  roles/secretmanager.secretAccessor (per secret)

VM startup / cron:
/opt/folio/scripts/render-env.sh  reads each secret  →  writes /opt/folio/.env (mode 600, owner deploy)
                                                    │
                                                    └─ also writes a checksum file; if drift, alert
```

## Related Code Files

- Create: `infra/gcp/secret-manager/seed.sh` — initial seed of secrets (one-shot, prompts for values).
- Create: `infra/gcp/scripts/render-env.sh` — fetches secrets via gcloud and renders `.env`.
- Create: `/etc/systemd/system/folio-render-env.service` — runs render-env.sh.
- Create: `/etc/systemd/system/folio-render-env.timer` — daily refresh (catches rotations).
- Modify: VM startup-script (phase 3) → install systemd unit + timer.
- Update: `.env.example` — documents which keys must exist in Secret Manager.

## Implementation Steps

1. Define canonical key list in `.env.example`. Convention: SM key = `folio-<kebab-case-env-var>`.
2. Write `seed.sh` to create each secret if missing (`gcloud secrets create ... --replication-policy=automatic`). Reads values from stdin (operator pastes, never committed).
3. Grant `vm-runtime-sa` `roles/secretmanager.secretAccessor` per secret (not project-wide).
4. Write `render-env.sh`:
   - For each key: `gcloud secrets versions access latest --secret=<key>` → write to temp file.
   - Atomic rename → `/opt/folio/.env` (mode 600, owner `deploy:deploy`).
   - Compute SHA256, log to systemd journal.
   - Exit non-zero on any fetch failure (don't render partial env).
5. Install systemd unit + timer (daily at 04:30 UTC).
6. Run `render-env.sh` once during VM bootstrap (called from phase 3 startup).
7. Document rotation: update secret version in SM → trigger `systemctl start folio-render-env.service` → `docker compose up -d` to pick up new env.
8. Audit: `gcloud secrets list --filter="labels.env=prod"` matches `.env.example` keys.

## Success Criteria

- [ ] All canonical secrets exist in SM, none missing.
- [ ] `cat /opt/folio/.env` contains all expected keys, file mode 600.
- [ ] `vm-runtime-sa` can read; `deploy-sa` cannot (verified by attempted access).
- [ ] Rotating a secret + restart cycle picks up new value end-to-end.
- [ ] No plaintext secret in: git history, GitHub Actions logs, VM metadata, journald default rings.
- [ ] Daily timer fires; log shows successful render.

## Risk Assessment

| Risk | Mitigation |
|---|---|
| Secret accidentally logged by app | Flask `before_request` filter strips known secret names; never `print(env)`. |
| `.env` written world-readable | Atomic rename writes to temp at 600 mode first; renamefails if mode wrong. |
| Rotation forgotten → SMTP fails silently | Daily timer surfaces fetch errors; uptime check on /health includes outbound email canary monthly. |
| SA gains over-broad access | Per-secret IAM binding, not project-level. |
| Secret Manager outage blocks startup | If `.env` already exists and SM unreachable, log warning but keep existing file (don't truncate). |
| Operator pastes secret into wrong terminal | `seed.sh` uses `read -s`; no echo; no shell history (`HISTIGNORE`). |

## Red Team Fixes (2026-04-29)

Findings 4, 13 apply here. Override the secret list and convention as follows.

### Mechanical SM-key derivation from actual env vars (no hand-curated list)

Original plan listed 7 secrets — too few. The correct approach: **enumerate every env var the app actually reads**, then mint an SM key per credential-bearing one. Run during phase 1 implementation:

```bash
grep -rhoE 'get_env\("[A-Z_]+"' folio-back-end/config/ | \
  sed -E 's/get_env\("([A-Z_]+)".*/\1/' | sort -u
```

### Canonical SM-key list (corrected, exhaustive)

Naming convention: SM key = `folio-<lowercased-snake-to-kebab>` of the env var name. So `JWT_SECRET_KEY` → **`folio-jwt-secret-key`** (NOT the original `folio-jwt-secret`, which would resolve to env var `JWT_SECRET` — a name the app does not read, causing crash on the dev-default check).

| SM key | Env var | Purpose |
|---|---|---|
| `folio-postgres-user` | `POSTGRES_USER` | DB role name |
| `folio-postgres-password` | `POSTGRES_PASSWORD` | DB role password |
| `folio-postgres-db` | `POSTGRES_DB` | DB name |
| `folio-secret-key` | `SECRET_KEY` | Flask SECRET_KEY |
| `folio-jwt-secret-key` | `JWT_SECRET_KEY` | JWT signing |
| `folio-s3-access-key` | `S3_ACCESS_KEY` | MinIO root user / S3 access |
| `folio-s3-secret-key` | `S3_SECRET_KEY` | MinIO root password / S3 secret |
| `folio-s3-bucket` | `S3_BUCKET` | bucket name |
| `folio-s3-public-endpoint-url` | `S3_PUBLIC_ENDPOINT_URL` | public URL for presigned URLs (phase 9 finding) |
| `folio-cors-origins` | `CORS_ORIGINS` | comma-list of allowed origins |
| `folio-next-public-api-base-url` | `NEXT_PUBLIC_API_BASE_URL` | client-side API base (build-time bake) |
| `folio-smtp-host` | `SMTP_HOST` | outbound mail |
| `folio-smtp-port` | `SMTP_PORT` | outbound mail |
| `folio-smtp-user` | `SMTP_USER` | outbound mail |
| `folio-smtp-pass` | `SMTP_PASS` | outbound mail |
| `folio-ratelimit-storage-uri` | `RATELIMIT_STORAGE_URI` | dedicated Redis DB for rate limiter (`redis://redis:6379/2`) |
| `folio-behind-proxy` | `BEHIND_PROXY` | enables ProxyFix (phase 4 fix) |
| `folio-gcs-hmac-access-key` | (consumed by `mc` config, not Flask) | MinIO → GCS mirror auth |
| `folio-gcs-hmac-secret-key` | (consumed by `mc` config, not Flask) | MinIO → GCS mirror auth |
| `folio-admin-bootstrap-password` | (consumed by `scripts/seed.py`) | first-deploy admin password (phase 9) |
| `folio-cf-api-token` | (consumed by GitHub Actions, not on VM) | Cloudflare cache purge — stored as GitHub Secret, also mirrored here |
| `folio-cf-zone-id` | same | CF zone identifier |

### Rotation reality (Finding 8 honesty)

Daily render-env timer rewrites `/opt/folio/.env` but does NOT propagate to running containers. Rotation procedure (added to runbook in phase 11):

1. Update secret version in Secret Manager.
2. SSH to VM, run `sudo systemctl start folio-render-env.service` → confirms successful re-render.
3. `cd /opt/folio && docker compose up -d --force-recreate <svc-list>` for services that consume the changed var.
4. For DB password rotation: dual-credential window required (add new role, repoint app, drop old) — naive rotation breaks app-DB auth window. Documented in phase 11 runbook.
5. For `NEXT_PUBLIC_*` rotation: requires frontend image rebuild + redeploy (build-time bake).

### Updated Success Criteria (additions)

- [ ] All 22 SM keys exist (mechanical enum'd from `grep get_env`).
- [ ] `JWT_SECRET_KEY` → `folio-jwt-secret-key` mapping verified end-to-end (deploy boots without dev-default RuntimeError).
- [ ] `RATELIMIT_STORAGE_URI` set to `redis://redis:6379/2` — separate DB from RQ jobs.
- [ ] HMAC keys (`folio-gcs-hmac-*`) present in SM; `mc alias set` on the VM uses them.
- [ ] CI lint step `docker compose -f docker-compose.yml -f docker-compose.prod.yml config` aborts when ANY listed env var is unset.

## Validation Decisions (2026-04-29 Session 1)

**Y2 — Drop the systemd render-env timer.**

Original plan: daily timer at 04:30 UTC re-renders `/opt/folio/.env` from Secret Manager. **Removed** because the timer rewriting `.env` does NOT propagate to running containers (rotation requires `docker compose up -d --force-recreate`). The timer was security theater.

**Action:**
- Keep `render-env.sh` (called once during VM bootstrap from `startup.sh`).
- Keep `folio-render-env.service` (oneshot) — invoked manually during rotation.
- **Delete** `folio-render-env.timer`.
- Document rotation as an explicit 3-step manual op in phase 11 runbook (already specified in the red-team rotation reality section above).

**V3 — SMTP=Resend: add API key to canonical SM list.**

Add to the canonical 22-key list (replacing the 4 separate `folio-smtp-*` keys, which Resend doesn't use):

| SM key | Env var | Purpose |
|---|---|---|
| `folio-resend-api-key` | `RESEND_API_KEY` | Resend SMTP/API token |
| `folio-resend-from-email` | `RESEND_FROM_EMAIL` | sender address (e.g. `noreply@domain.tld`) |

**Removed from list:** `folio-smtp-host`, `folio-smtp-port`, `folio-smtp-user`, `folio-smtp-pass`. The `folio-back-end` mailer config switches to Resend's HTTP API or SMTP relay (`smtp.resend.com:465`, user=`resend`, pass=`<api-key>`). Existing `SMTP_*` env vars can map: `SMTP_HOST=smtp.resend.com`, `SMTP_PORT=465`, `SMTP_USER=resend`, `SMTP_PASS=<api-key>`. So Code change is minimal — only `SMTP_PASS` actually needs the API key, others are constants.

**Final list size:** 20 keys (was 22 — replaced 4 SMTP keys with 2 Resend keys).

**Effort reclaimed:** ~45 min (no timer, no drift-detection alarm, no fake-rotation illusion).
