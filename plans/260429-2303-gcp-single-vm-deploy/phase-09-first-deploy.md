---
phase: 9
title: "First Deploy"
status: pending
priority: P1
effort: "4h"
dependencies: [4, 5, 6, 7]
---

# Phase 9: First Deploy

> **[REVISED 2026-04-29]** Migration command fixed (`flask db upgrade` requires `FLASK_APP=wsgi:app`). Admin seed via existing `scripts/seed.py --with-admin`, not fictional `flask seed admin`. Smoke-test extends existing `scripts/smoke-test.sh`, NOT a new `scripts/test/smoke-test.sh`. Presigned-URL probe dropped (no implementation in code). Worker success criterion changed from "healthy" to "Up + RQ canary round-trip". **The `## Red Team Fixes (2026-04-29)` section at the end is authoritative**; supersedes Architecture, Implementation Steps, and Success Criteria where they conflict.

## Overview

End-to-end smoke test: trigger CI, wait for green, hit prod URL, verify auth + DB write + worker pickup + email + file upload to MinIO. This is the gate before declaring "production ready."

## Requirements

- **Functional:** All 6 services up; user can register, log in, create a project, add a worker, log attendance, trigger labor export, upload an attachment, receive an email.
- **Non-functional:** Migration applied cleanly; admin user seeded; no errors in logs over 30 min observation; p95 < 600 ms via Cloudflare.

## Architecture

```
Pre-deploy checklist (manual):
├── DNS resolved, TLS valid (phase 4 done)
├── Secrets in /opt/folio/.env (phase 6 done)
├── Backups running (phase 7 done)
├── CI green (phase 5 done)
└── Operator on deck

Deploy sequence (CI-driven):
1. push folio-back-end main → image built+pushed
2. push folio-front-end main → image built+pushed
3. SSH deploy:
   a. docker compose pull
   b. docker compose run --rm api flask db upgrade
   c. docker compose run --rm api flask seed admin   # one-shot
   d. docker compose up -d
   e. wait-healthy.sh ALL services
4. smoke-test.sh hits public URL endpoints
5. observation window (30 min) — monitor logs & alerts
```

## Related Code Files

- Create: `scripts/deploy/migrate.sh` — runs alembic / flask db upgrade.
- Create: `scripts/deploy/seed-admin.sh` — creates first admin (idempotent, prompts password from SM).
- Create: `scripts/test/smoke-test.sh` — curl-based end-to-end probe.
- Modify: `docker-compose.yml` — declare image tags via `${IMAGE_TAG:-latest}` so first deploy pins SHA.
- Update: `docs/deployment-guide.md` — first-deploy section.

## Implementation Steps

1. Confirm phases 1–7 complete (manual checklist).
2. Push initial image builds: tag `v0.1.0`-equivalent. Push both back-end + front-end via CI.
3. SSH in, `cd /opt/folio`, set IMAGE_TAG to the SHA, `docker compose pull`.
4. Run `migrate.sh`: `docker compose run --rm api flask db upgrade`. Verify zero errors.
5. Run `seed-admin.sh`: creates admin user from prompt (password from SM key `folio-admin-bootstrap-password`).
6. `docker compose up -d` (full stack).
7. `wait-healthy.sh` polls all 6 services. Fail loud if any unhealthy after 5 min.
8. `smoke-test.sh`:
   - `GET /health` → 200.
   - `POST /api/v1/auth/login` with seeded admin → 200 + cookie.
   - `GET /api/v1/projects` → 200 array.
   - `POST /api/v1/projects` → 201.
   - `POST /api/v1/projects/<id>/workers` → 201.
   - Upload a small file → presigned URL works → MinIO has the object.
   - Trigger an email-sending action → SMTP log shows success.
   - Trigger a queued job → worker picks up within 10 s.
9. Observe logs + dashboard for 30 min. Any 5xx > 0.5 % or memory creep → roll back.
10. Mark deployment in journal (commit a tag + plan update).

## Success Criteria

- [ ] All 6 containers `healthy` per `docker compose ps`.
- [ ] `smoke-test.sh` exits 0 with all probes green.
- [ ] Cloudflare analytics shows traffic with cache-hit ratio > 50 % on static.
- [ ] Cloud Monitoring dashboard green for 30 min.
- [ ] No ERROR log line in 30-min window (informational allowed).
- [ ] Backups (phase 7) show first dump produced after deploy.
- [ ] Admin user can log in via browser.
- [ ] p95 latency on `/api/v1/projects` < 400 ms (excluding TLS handshake).

## Risk Assessment

| Risk | Mitigation |
|---|---|
| Migration fails on prod | Dry-run `flask db upgrade --sql` first on staging dump; have rollback SQL ready. |
| Seed admin password mismatch | Password sourced from SM key, verified via login probe in smoke-test. |
| MinIO bucket missing → uploads 500 | Pre-create buckets in startup script (`mc mb minio/construction-attachments`). |
| Worker can't reach Redis (network namespace mistake) | Compose service name resolution — verified in smoke-test job probe. |
| First-day traffic spike crashes single VM | Cloudflare proxy + cache absorbs static; if API saturates, vertical-scale to e2-standard-4 (~$100/mo) — keep budget. |
| Email goes to spam (new IP) | Outbound SMTP via SendGrid/Mailgun, not VM's IP; SPF/DKIM via Cloudflare DNS records. |
| Forgot to remove default-credential dev fallbacks | Phase-9 smoke-test asserts production env vars set; CI lint blocks dev defaults in prod compose override. |

## Red Team Fixes (2026-04-29)

Findings 1, 4, 7, 11, 14 apply here. Override migration / seed / smoke-test sections.

### Migration command — fix the fictional CLI

Original: `docker compose run --rm api flask db upgrade`. **Broken** — the api image `CMD` is `gunicorn 'app:create_app()'`, no `FLASK_APP` env, no Flask CLI commands registered. Replacement:

```bash
docker compose run --rm \
  -e FLASK_APP=wsgi:app \
  api flask db upgrade
```

(`wsgi:app` is the gunicorn entrypoint module already shipped in the image.) Fallback if Flask-Migrate has issues: `alembic -c alembic.ini upgrade head` invoked similarly.

### Admin seed — use the existing script, not a fake CLI

Original: `flask seed admin`. **Doesn't exist** — there's no `@app.cli.command` named `seed` in the codebase. The real admin-seed path is the existing `scripts/seed.py`:

```bash
docker compose run --rm \
  -e ADMIN_EMAIL='admin@<domain>' \
  -e ADMIN_PASSWORD="$(gcloud secrets versions access latest --secret=folio-admin-bootstrap-password)" \
  api python scripts/seed.py --with-admin
```

`folio-admin-bootstrap-password` is added to the SM key list (phase 6 fix).

### Smoke-test — extend existing `scripts/smoke-test.sh`, don't create a new file

Original: "Create: `scripts/test/smoke-test.sh`." **Reverted** — the existing 569-line `scripts/smoke-test.sh` already supports `--host`, admin seeding, `/health` probe, login. Extend it with prod-specific probes (RQ pickup canary, multi-IP rate-limit check, file upload via real path).

Run as: `./scripts/smoke-test.sh --host https://<domain> --context prod`.

### Drop the "presigned URL" probe — code path doesn't exist

Original step 8 line: "Upload a small file → presigned URL works → MinIO has the object." `S3AttachmentStorage` only has `put`/`get_stream`/`delete` — no `generate_presigned_url`. Plus `S3_ENDPOINT_URL=http://minio:9000` is docker-internal so any presigned URL would be browser-unreachable.

**Replacement step 8:** Real upload path probe (matches the actual code):
- `POST /api/v1/projects/<id>/attachments` multipart upload (existing endpoint).
- Server streams to MinIO via `S3AttachmentStorage.put`.
- `GET /api/v1/attachments/<id>/download` returns body.
- Smoke-test asserts SHA256 round-trip equality.

If presigned URLs are required later (large file uploads, browser-direct), that's a separate feature: add `S3_PUBLIC_ENDPOINT_URL` env, add CF route for `files.<domain>` → `127.0.0.1:9000`, implement `generate_presigned_url` in `S3AttachmentStorage`. **Out of scope for this deploy.**

### Worker healthcheck wording fix

Original success criterion: "All 6 containers `healthy` per `docker compose ps`." **Unreachable** — worker has `healthcheck: disable: true`. Replacement:

- [ ] 5 containers (api, frontend, db, redis, minio) report `healthy`; worker reports `Up` (no healthcheck).
- [ ] Worker liveness verified by smoke-test queueing a no-op job and asserting it's picked up within 10 s (proxy for "worker is alive").

### Updated Success Criteria (replacements)

- [ ] DB migrations run via `docker compose run --rm -e FLASK_APP=wsgi:app api flask db upgrade` — exits 0.
- [ ] Admin seeded via `python scripts/seed.py --with-admin` reading `ADMIN_PASSWORD` from SM.
- [ ] 5 containers healthy + worker Up + RQ canary job round-trips < 10 s.
- [ ] Real-upload smoke probe (multipart POST → GET) succeeds; SHA256 round-trip equal.
- [ ] Existing `scripts/smoke-test.sh` extended (no new `scripts/test/smoke-test.sh` created).
