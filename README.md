# Folio

Umbrella repo for Folio: two submodules (backend, frontend) plus the deploy
workflows and scripts that ship and run them on the prod host.

```
folio-back-end/   → Flask 3 + hexagonal + SQLAlchemy + RQ        (flowitup/folio-back-end)
folio-front-end/  → Next.js 16 + next-intl + Tailwind + shadcn   (flowitup/folio-front-end)
scripts/          → deploy-runner, rollback, host backups       (see scripts/README.md)
```

Both submodules are public repos; this umbrella repo is private. The mobile
app (Expo, talks to the same API) lives in its own repo, not a submodule:
[flowitup/folio-mobile-app](https://github.com/flowitup/folio-mobile-app).

Live: https://folio.flowitup.com

---

## Local development

The base `docker-compose.yml` requires every secret-bearing variable
(`${VAR:?required}`) so an accidental `docker compose up` on the host cannot
boot prod with development defaults. Compose checks those in each file before
it merges the dev overlay, so local dev needs the submodules and a `.env` next
to the compose files. The `.env` is gitignored; the values below are the
dev-only defaults from `docker-compose.dev.yml`:

```bash
git submodule update --init
cat > .env <<'EOF'
POSTGRES_USER=construction
POSTGRES_PASSWORD=construction
POSTGRES_DB=construction
SECRET_KEY=dev-secret-key-change-in-production
CORS_ORIGINS=http://localhost:3000
EMAIL_PROVIDER=smtp
S3_ENDPOINT_URL=http://minio:9000
S3_ACCESS_KEY=minioadmin
S3_SECRET_KEY=minioadmin
S3_BUCKET=construction-attachments
S3_REGION=us-east-1
NEXT_PUBLIC_API_BASE_URL=http://localhost:5000/api/v1
API_INTERNAL_BASE_URL=http://api:5000/api/v1
EOF
docker compose -f docker-compose.yml -f docker-compose.dev.yml up
```

The stack includes an `ai-browser` service (assistant browser-automation
container, `folio-back-end/Dockerfile.browser`) behind the `assistant`
compose profile, so a plain `docker compose up` skips its ~2.5 GB Chrome
image — add `--profile assistant` (or `COMPOSE_PROFILES=assistant`) to start
it. `FEATURE_ASSISTANT=1` and `SCAN_MODE=opencv` are already the dev-overlay
defaults for `api`/`worker`/`ai-browser` alike, but `DEEPSEEK_API_KEY` and
`TYPESAFE_API_KEY` default to empty, so `GET /api/v1/features` (signed in)
reports `assistant: false` until you export both. `GEMINI_API_KEY` is
optional.

Production runs the same compose files from `/opt/folio` on the host, but only
through `deploy-runner.sh` and `rollback.sh`: they pin `IMAGE_TAG` to one SHA
per service, pass `--env-file /opt/folio/.env`, run migrations first and hold
an Artifact Registry login. Don't run a bare
`docker compose -f docker-compose.yml -f docker-compose.prod.yml up -d` there.
Every app service has `pull_policy: always` and `${IMAGE_TAG:-latest}`, so that
command pulls `:latest` for api, worker and frontend alike (and `:latest` is
pushed by the last build even when that deploy failed), skips migrations, and
fails without a registry login.

---

## Deploys

Both backend and frontend deploy automatically when a PR merges to the
submodule's `master` and CI passes. The submodule's `release` job picks the
next version from its tag list and the PR label, tags the merge commit,
publishes a GitHub Release and sends `repository_dispatch` to this repo. A
hand-pushed tag deploys nothing, and a PR labelled `version:none` is neither
released nor deployed. No manual SSH needed.

### Production host

Hetzner CX33 `folio-prod-1` since 2026-07-15; the GCP VM it replaced was
deleted (#39). GCP still holds the Artifact Registry images, Secret Manager,
the backup bucket and the workflows' Workload Identity Federation login. The
host has no `gcloud`: registry logins happen in the workflows or from a
workstation, secrets are rendered on a workstation, and the backups reach GCS
through `mc` with an HMAC key. SSH is `root@<prod-host>` (see Rollback).

- `/opt/folio/` holds `.env` plus the compose files and `scripts/` that every
  deploy syncs. The app images (`api`, which `worker` shares, `frontend` and
  `ai-browser`) come from `europe-west1-docker.pkg.dev/flowitup-folio-prod/folio/`.
- HTTP comes in through a Cloudflare Tunnel (`cloudflared`, config
  `/etc/cloudflared/config.yml`). Every origin it targets listens on
  `127.0.0.1`:

  | Hostname | Origin on the host |
  |---|---|
  | `folio.flowitup.com` — `/health`, `/api/*` | `localhost:5000` (api) |
  | `folio.flowitup.com` — everything else | `localhost:3000` (frontend) |
  | `cdn.flowitup.com` | `localhost:9000` (MinIO, presigned URLs) |
  | `learn.flowitup.com` | `localhost:8080` (LearnFlow, served by Caddy — not part of this repo) |

  The host is shared with LearnFlow: restarting `cloudflared` or taking port
  8080 affects both sites.
- Backups run from host cron (`/etc/cron.d/folio-backups`): `pg-dump.sh` at
  03:00 and `minio-mirror.sh` at 03:30 UTC, into
  `gs://flowitup-folio-prod-backups`. No restore test is scheduled — see
  `scripts/README.md`.

### Trigger

```
folio-back-end (or folio-front-end): PR merged to master, CI green
  → release job: next version from tags + PR label → tag v1.2.3 → GitHub Release
  → repository_dispatch (deploy-api / deploy-frontend) to flowitup/folio
  → parent .github/workflows/deploy-{backend,frontend}.yml
  → build+push image to AR → SSH to the Hetzner prod host → deploy-runner.sh
  → (frontend: Cloudflare purge + 30 s) → smoke
  → commit submodule pointer bump on parent master
```

`deploy-backend.yml` builds and pushes two images from the same
`folio-back-end` SHA: `api` (also runs `worker`) and `ai-browser` (assistant
browser-automation container). `deploy-runner.sh api` always swaps and
health-waits `api`+`worker`. `ai-browser` only runs when `FEATURE_ASSISTANT=1`
is set in `/opt/folio/.env` on the host (off by default in prod today); when
it's off, deploy-runner stops and removes any running `ai-browser` instead of
pulling the image. When it's on, a missing/failed `ai-browser` pull or
health-wait only warns — it never aborts the api/worker deploy.

The pointer in parent `master` is bumped only after a deploy passes its smoke
test, so it normally matches prod. It is stale after a hard rollback (see
Rollback), when smoke or the Cloudflare purge fails after the containers were
already swapped, or when the pointer push itself fails. To see what is
actually running, check the host:
`docker inspect --format '{{index .Config.Labels "org.opencontainers.image.revision"}}' folio-api-1 folio-frontend-1`.

### Manual deploy (workflow_dispatch)

Use when a release didn't auto-dispatch (e.g. PAT expired, dispatch step
failed) or you need to redeploy a specific SHA.

```bash
gh workflow run deploy-backend.yml  -R flowitup/folio \
  -f version=1.2.3 -f sha=<7-40-hex-sha>

gh workflow run deploy-frontend.yml -R flowitup/folio \
  -f version=1.2.3 -f sha=<7-40-hex-sha>
```

`version` must be the release whose tag `v<version>` points at `sha`;
otherwise the run fails, so only released SHAs can be deployed. For the
backend, a SHA older than the database's migration head fails at
`flask db upgrade`; use `rollback.sh` instead (see Rollback).

### Status

- Live: https://folio.flowitup.com — `/health` (BE), `/` (FE).
- Workflow runs: https://github.com/flowitup/folio/actions
- Last deployed SHAs: the image revision labels on the host. `git submodule
  status` on parent master normally agrees (see the caveats above).

### Rollback

Forward-only is preferred — push a fix and let CI auto-deploy.

**Frontend:** redeploy the previous release through the workflow. It rebuilds
that SHA, purges the Cloudflare cache, smoke-tests and moves the submodule
pointer back:

```bash
gh workflow run deploy-frontend.yml -R flowitup/folio -f version=<previous> -f sha=<its sha>
```

**Backend:** the workflow runs `flask db upgrade`, which fails for a SHA older
than the database's migration head, so roll back on the host with
`rollback.sh` (it runs no migrations). The host keeps no Artifact Registry
login between deploys (the workflows log in with a one-hour token and log
out). Log it in from a workstation with gcloud access to
`flowitup-folio-prod`, and always pass the SHA:

```bash
gcloud artifacts docker tags list europe-west1-docker.pkg.dev/flowitup-folio-prod/folio/api \
  --sort-by='~UPDATE_TIME' --limit=10            # pick <sha>
gcloud auth print-access-token | ssh root@<prod-host> \
  'docker login -u oauth2accesstoken --password-stdin europe-west1-docker.pkg.dev'
ssh root@<prod-host> \
  '/opt/folio/scripts/rollback.sh api <sha>; rc=$?; docker logout europe-west1-docker.pkg.dev; exit $rc'
```

`<prod-host>` is `PROD_HOST` in `.github/workflows/deploy-backend.yml`; log in
as `root` (no sudo). `rollback.sh api` also swaps `worker` (same image) and,
while the assistant is on, `ai-browser`. Don't roll back `worker` on its own:
it would run a different SHA than `api`. Logs are host-only
(`docker logs <container>`); there is no centralized log aggregation.

After a hard rollback the parent submodule pointer is stale. Bump it back
from a clone of this repo (no submodule checkout needed):

```bash
git switch master && git pull --ff-only
git update-index --cacheinfo 160000,<sha>,folio-back-end   # or folio-front-end
git commit -m "chore(deploy): rollback folio-back-end → <sha> [skip ci]" && git push origin master
```

### Required secrets

Parent repo `flowitup/folio` (Settings → Secrets and variables → Actions):

- `GCP_WIF_PROVIDER` — Workload Identity Federation provider resource path,
  e.g. `projects/<num>/locations/global/workloadIdentityPools/github-actions/providers/github`.
- `GCP_SA_EMAIL` — service account the WIF binding impersonates,
  `deploy-sa@flowitup-folio-prod.iam.gserviceaccount.com`. Org policy
  `iam.disableServiceAccountKeyCreation` blocks JSON keys, so we use OIDC
  via WIF — no `GCP_SA_KEY` needed, no key rotation.
- `HETZNER_SSH_KEY` — private half of the dedicated CI deploy keypair; logs
  in as `root` on the Hetzner prod host. The host key is pinned inline in
  both workflows, so a MITM or rebuilt host fails the connection instead of
  prompting; after a rebuild, update the pinned `ssh-ed25519` line in both.
- `CF_API_TOKEN` — Cloudflare token, zone-scoped, `Cache Purge:Edit` only.
- `CF_ZONE_ID` — `flowitup.com` zone ID.
- `SUBMODULE_TOKEN` — fine-grained PAT, scoped to `flowitup/folio-back-end`
  + `flowitup/folio-front-end` with `Contents:read` + `Metadata:read`.
  Optional: both submodules are public, and the checkout and tag-verify steps
  use `GITHUB_TOKEN` when this secret doesn't exist. If it exists it is always
  used, so an expired or revoked PAT fails every deploy at checkout.

Each submodule (`folio-back-end`, `folio-front-end`):

- `PARENT_DISPATCH_TOKEN` — fine-grained PAT scoped to `flowitup/folio`
  with `Contents: Read and write` + `Metadata: Read-only` (the
  `repository_dispatch` API requires `Contents: write` for fine-grained
  PATs). Used to send `repository_dispatch` after release.

### Runtime secrets (Secret Manager → `/opt/folio/.env`)

Every `${VAR:?required}` in `docker-compose.prod.yml` comes from a
`folio-<name>` secret in the `flowitup-folio-prod` GCP project — Secret
Manager is still the rotation source of truth after the Hetzner move. Today
that's rendered on the workstation and copied to `/opt/folio/.env` on the
host. To apply new values, re-run the deploy workflow for the version already
live (`gh workflow run deploy-backend.yml -R flowitup/folio -f version=<live> -f sha=<live sha>`;
run the frontend one too if its variables changed); that recreates the
containers at that SHA with the new file.

The rendered file also carries the backup scripts' `GCS_HMAC_ACCESS_KEY` and
`GCS_HMAC_SECRET_KEY`, plus any optional flags. Write the assistant switch
exactly as `FEATURE_ASSISTANT=1`, with no quotes or comment: deploy-runner
greps for that line.

Sign-in codes (phone-only login since 2026-09-11) go out through the Android
SMS gateway:

- `folio-sms-gateway-url` → `SMS_GATEWAY_URL` — full message endpoint reachable
  from the prod host (`http://<phone-ip>:8080/message` local server, or
  `https://api.sms-gate.app/3rdparty/v1/messages` cloud relay).
- `folio-sms-gateway-username` / `folio-sms-gateway-password` →
  `SMS_GATEWAY_USERNAME` / `SMS_GATEWAY_PASSWORD` — Basic-auth credentials
  shown in the app for that mode (local and cloud credentials differ).

### Concurrency + safety

- `concurrency.group=deploy-prod-backend` / `deploy-prod-frontend` — two
  close pushes of the same submodule run one after the other. A backend and a
  frontend deploy can still overlap on the host, and they share one registry
  login.
- Smoke tries `/health` (backend, healthy JSON body) or `/` (frontend,
  Next.js asset marker after the locale redirect) up to 5 times, 5 s apart,
  and fails the workflow loud otherwise; the frontend purges the Cloudflare
  cache and waits 30 s for edge propagation first. The new containers are
  already live when smoke runs: a failure doesn't roll back, it only skips
  the pointer bump.
- Submodule pointer push fetches + rebases onto `origin/master` in up to 3
  attempts with backoff to avoid racing human pushes; a rebase conflict fails
  immediately.
- `[skip ci]` in commit message prevents recursive triggers (defensive;
  parent has no CI on master today).

---

## Docs

Architecture notes, code-standards docs and the older infra runbooks are kept
outside this repository (private ops notes, not published to GitHub — see
`.gitignore`); those infra runbooks (GCP bootstrap, Cloudflare setup) predate
the Hetzner move. For deploys, rollback and backups, this README and
`scripts/README.md` are the current reference.
