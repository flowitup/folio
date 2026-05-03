# 2026-05-03 — Production Go-Live

**Outcome:** ✅ Folio is live at https://folio.flowitup.com.
**Plan:** [`260429-2303-gcp-single-vm-deploy`](../../plans/260429-2303-gcp-single-vm-deploy/plan.md) — 11 phases applied.
**Repo:** [github.com/flowitup/folio](https://github.com/flowitup/folio) (private), PR #1.

## Timeline

| Date | Phase | Notes |
|---|---|---|
| 2026-04-29 | Plan + brainstorm + Red Team | 15 findings, 6 YAGNI cuts (Y1-Y6) |
| 2026-04-30 | Phases 1-5 | GCP bootstrap, VM, cloudflared, CI templates |
| 2026-05-03 | Phases 6-9, 11 | Secrets, backups, observability, first deploy, runbook |
| 2026-05-03 | Submodule conversion + PR #1 | nested clones → real git submodules |

## What worked the first time

- **Cloudflare Tunnel** — outbound-only TLS, zero firewall openings. Connected within 60 s of `cloudflared service install`.
- **Per-secret IAM bindings** — 20 SM keys each with their own `secretAccessor` on `vm-runtime-sa`. Loud failure if any miss.
- **Compose v2 prod override** — `${VAR:?required}` fail-fast caught zero leaked dev defaults to prod.
- **gsutil → gcloud impersonation chain** — `vm-runtime-sa` impersonates `backup-sa` cleanly; no SA key files on disk.
- **Snapshot policy** — `gcloud compute resource-policies create snapshot-schedule` + attach. No drift, no surprises.

## Hot-fixes during deploy (lessons)

### 1. snap gcloud is incompatible with hardened systemd

**Symptom:** `folio-render-env.service` exited 1 with `WARNING: cannot create user data directory: cannot create snap home dir: mkdir /root/snap: read-only file system`.

**Root cause:** Ubuntu 24.04 GCE images ship `google-cloud-cli` as a snap. Snap apps need to write under `/root/snap`, blocked by `ProtectHome=true` in the hardened systemd unit.

**Fix:** Replace snap gcloud with apt-installed gcloud in `infra/gcp/cloud-init/startup.sh`. Snap on a server is a code smell — designed for desktop apps with auto-updates; on a server it adds `snapd`, AppArmor profiles, squashfs mounts, and slower startup.

**Also:** Added `Environment=CLOUDSDK_CONFIG=/tmp/gcloud-config` to the unit so gcloud's config dir lands in `PrivateTmp` instead of the sealed `/root/.config/`.

### 2. `FROM_EMAIL` vs `RESEND_FROM_EMAIL` naming mismatch

**Symptom:** Admin seed crashed with `ValueError: FROM_EMAIL must not be empty` despite `RESEND_FROM_EMAIL` being set.

**Root cause:** The plan's Phase 6 mapped SM key `folio-resend-from-email` → env `RESEND_FROM_EMAIL`. The back-end `wiring.py` reads `os.environ.get("FROM_EMAIL", "")`. Names didn't match.

**Fix:** Aliased `FROM_EMAIL=${RESEND_FROM_EMAIL:?required}` in `docker-compose.prod.yml` for api + worker. Cheaper than changing back-end code; back-end fix is queued for Q+1.

### 3. `/health` route is at root, not under `/api/v1`

**Symptom:** Cloud Monitoring uptime check (configured against `/api/v1/health`) returned 404.

**Root cause:** Flask exposes `/health` at the application root (matches Dockerfile healthcheck `urllib.request.urlopen('http://localhost:5000/health')`). The cloudflared ingress only routed `/api/*` and `/` (frontend), so `/health` fell through to Next.js → 404.

**Fix:** Added a `path: ^/health$ → http://localhost:5000` route to `cloudflared-config.yml` BEFORE the catch-all. Updated `setup-monitoring.sh` default path to `/health`. Updated existing uptime check via `gcloud monitoring uptime update`.

### 4. backup-sa needed `objectViewer` (and `iamcredentials.googleapis.com` API)

**Symptom:** `pg-dump.sh` failed with `403 storage.objects.get denied` on backup-sa, then with `IAM Service Account Credentials API has not been used`.

**Root cause:** Both `gsutil cp` and `gcloud storage cp` perform a HEAD/GET pre-flight before writing. `roles/storage.objectCreator` alone doesn't permit that. Plus `iamcredentials.googleapis.com` was not in the bootstrap's API enable list — without it, `vm-runtime-sa` cannot impersonate `backup-sa`.

**Fix:**
- Added `roles/storage.objectViewer` on backup-sa for the **primary** bucket only (archive bucket is write-once, no view perm needed).
- Added `iamcredentials.googleapis.com` to `bootstrap.sh` API enable list.
- Documented the carve-out in `infra/gcp/iam-policies/backup-sa.yaml` — backup-sa still cannot delete or modify; bucket retention lock + versioning compensate.

### 5. JWT cookies missing `Secure` flag in browser → "can't create project"

**Symptom:** API works perfectly via `curl` (login 200, project create 201) but the user cannot create a project in the browser. Browser receives login 200 but next request returns 401.

**Root cause:** `Set-Cookie` headers carried `SameSite=None` without `Secure`. Modern browsers (Chrome 80+, Firefox, Safari) RFC-reject this combination — the cookies are silently dropped. curl ignores the rule, which is why CLI tests passed.

**Why?** Back-end's `config/__init__.py` derives JWT cookie config from `_is_production = get_env("FLASK_ENV") == "production"`. Without `FLASK_ENV=production`, Flask-JWT-Extended ran in dev mode (Secure=False, SameSite=None, CSRF off).

**Fix:** Added `FLASK_ENV=production` to api + worker env in `docker-compose.prod.yml`. Triggered:
- `JWT_COOKIE_SECURE=True`
- `JWT_COOKIE_SAMESITE=Strict` (was None)
- `JWT_COOKIE_CSRF_PROTECT=True` (front-end already wired for `csrf_access_token` cookie + `X-CSRF-TOKEN` header)
- Plus `app/__init__.py` fail-fast assertion that no "dev-" prefix in JWT_SECRET_KEY/SECRET_KEY (passed — both are 64-byte hex).

**Verification post-fix:**
```
set-cookie: access_token_cookie=...; Secure; HttpOnly; Path=/; SameSite=Strict
set-cookie: csrf_access_token=...;   Secure; Path=/; SameSite=Strict
set-cookie: refresh_token_cookie=...; Secure; HttpOnly; Path=/; SameSite=Strict
set-cookie: csrf_refresh_token=...;  Secure; Path=/; SameSite=Strict
```

This was the bug that mattered most — a prod deploy that "works in curl but fails in the browser" is the worst kind of bug because it passes basic smoke tests.

## Operational lessons

### Browser flows must be explicitly tested

A 200 from curl is not equivalent to a working UI. Future smoke-tests should run a headless browser flow (Playwright) for state-changing requests, not just curl.

### `FLASK_ENV` is load-bearing, not cosmetic

Many config defaults derive from it. Setting it should be the FIRST thing prod compose does, not the last. Consider moving to a explicit `IS_PRODUCTION=1` boolean to avoid the implicit string-comparison.

### Service-account impersonation needs the iamcredentials API

Easy to miss because the API isn't in the default GCP enabled list. Always part of bootstrap.

### Log everything, redact what's needed

When the user pasted `tail -5 /opt/folio/.env`, three live secrets ended up in the chat. Diagnostics should default to redacted (`awk` the names, not the values). The `pg-dump.sh` script's `gcloud said: ...` truncation-to-first-line was correct preventive design.

### Submodule conversion is non-trivial mid-flight

Going from nested clones → real git submodules required `git rm --cached` first because the parent index already tracked the dirs as gitlinks. Three failed attempts before success. Document this for next monorepo conversion.

## What we'd do differently

1. **Set `FLASK_ENV=production` from Phase 6, not Phase 9.** Would have caught the cookie issue before the user did.
2. **Bake `FROM_EMAIL` consolidation into Phase 6.** The alias is a tech debt note in the runbook now (§ "tech debt" not yet a section — TODO).
3. **Health-route ingress should be in Phase 4** (cloudflared config), not added as a Phase 9 hot-fix.
4. **Smoke-test Phase 9 should include a real browser run**, not just curl.
5. **Add `FLASK_ENV` to Phase 9 success criteria explicitly**, since it's the difference between "API responds 200" and "UI works."

## Outstanding (intentionally deferred)

- ⏰ Q+1: First quarterly restore drill (deployment-guide §5.5)
- ⏰ Q+1: Convert `FROM_EMAIL`/`RESEND_FROM_EMAIL` to a single canonical name in back-end
- ⏰ Q+1: Set up AR cleanup policy (keep last 30 SHAs, delete after 30 d)
- ⏰ Q+1: WAL archiving evaluation when DB approaches 100 MB or first paying customer arrives
- 📅 First incident: add CPU/RAM/5xx alerts as Y3 was speculative-trim — bring back the ones that prove necessary

## Final commit list (PR #1)

```
0f178ca  docs(deploy): add console quick-links + AR registry section
a614245  fix(prod): set FLASK_ENV=production for secure JWT cookies
2f2c212  feat(infra): phases 1-5 catch-up — bootstrap, VM, CF, CI/CD scripts
9d2d7f0  docs(infra): phase 11 — deployment runbook + plan history
7fb8c7c  feat(infra): phase 9 — first deploy live
e695b89  feat(infra): phase 7+8 — backups + observability
b367ed6  fix(infra): finish phase 6 — apt gcloud, CLOUDSDK_CONFIG, cdn.flowitup.com
```

Plus on master: `a7fe3cb chore: convert nested clones to git submodules`.

## Cost so far

VM created 2026-04-30, ran for 3 days. Inside $100 AI Ultra credit:

- Compute: 3 d × ~$1.65/d = ~$5
- Disk: 3 d × ~$0.30/d = ~$1
- AR storage (179 MB): negligible
- GCS storage (38 KB pg-dump): negligible
- Network (build pushes): ~$0.30
- **Total to date: ~$6** (well inside credit)

Runway on $100 credit: ~50 d if no further build pushes / data growth.

---

*Written same-day. Tabletop walk-through scheduled for next Monday standup.*
