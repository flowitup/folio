# Scripts

Three groups: a local E2E smoke test, the host-side deploy/rollback scripts
(installed in `/opt/folio/scripts/` by the owner, never by CI: see
[Installing the host files](#installing-the-host-files)), and the host cron
backup jobs.

## smoke-test.sh

**Broken today — kept for reference.** It predates the Folio rename and
phone-only sign-in:

1. `BACKEND_DIR`/`FRONTEND_DIR` are hard-coded to `construction-back-end` /
   `construction-front-end` (not env-overridable). The script stops at
   "Directory not found" unless you edit them or symlink the submodules to
   those names.
2. The seed step runs `scripts/seed.py --with-admin`, which now needs
   `ADMIN_EMAIL` and a French `ADMIN_PHONE`. This script never passes the
   phone, so seeding fails, is reported as a warning, and the run carries on
   as if it had seeded.
3. The login test POSTs email+password to `/api/v1/auth/login`, which no
   longer exists (sign-in is `otp/request` + `otp/verify` in
   `folio-back-end/app/api/v1/auth/routes.py`).

What it does: starts folio-back-end's own `docker-compose.yml` (api,
db, redis — not this repo's compose files), runs `flask db upgrade` and the
seed, starts the frontend with `npm run dev` (installing `node_modules` and
copying `.env.example` to `.env.local` if they're missing; on a remote
`--context` it uses folio-front-end's compose instead), then calls a few API
routes and checks the frontend responds. Runs on a developer machine; not
invoked by CI — the deploy workflows smoke-test prod with their own inline
curl checks.

```bash
./smoke-test.sh [OPTIONS]
```

| Option | Description |
|--------|-------------|
| `--cleanup` | Stop all services after verification |
| `--cleanall` | Stop backend containers, drop backend volumes/images, then `docker builder/image/volume prune -f` **host-wide** (not scoped to this project) |
| `--quick SVC` | Skip the full setup; rebuild + restart only `api`, `frontend`, or `all` |
| `--context NAME` | Docker context to use (default: `default`) |
| `--host IP` | Remote host IP (required with `--context`) |
| `--timeout N` | Health-check timeout in seconds (default: `120`) |
| `--help, -h` | Show help |

Side effects: `--context` runs `docker context use` and never switches back;
`--quick frontend|all` runs `pkill -f "next dev"`, which stops every Next.js
dev server on the machine, including other checkouts'.

Env vars: `ADMIN_EMAIL` (default `admin@example.com`), `ADMIN_PASSWORD`
(default `password123`) — sent to the seed step and to the removed
email/password login. The seed script ignores the password and needs
`ADMIN_PHONE`, which this script does not pass.

Exit codes: `0` all steps passed, `1` a step failed (or an unknown/invalid
option), `0` for `--help`.

## deploy/ci-deploy.sh

The forced command of the CI deploy key (`folio-ci-deploy`, the
`HETZNER_SSH_KEY` secret). Root's `authorized_keys` holds that key as

```
restrict,command="/opt/folio/scripts/ci-deploy.sh" ssh-ed25519 <key> folio-ci-deploy
```

so whatever a client asks for, sshd runs this script instead. The one request
it accepts, as the whole command string, is

```
deploy <api|frontend> <sha: 7-40 lowercase hex> <host-files sha256: 64 lowercase hex>
```

with a short-lived Artifact Registry access token as the first line of stdin.
It logs Docker in to Artifact Registry with a throwaway config, runs
`deploy-runner.sh <sha> <service>` with a clean environment (nothing from the
SSH session) and no stdin, deletes the config, and exits with
`deploy-runner.sh`'s status. Anything else (a shell, any other command, sftp
or scp, a request in any other shape) is refused before anything runs, and
`restrict` rules out a PTY and port, agent and X11 forwarding. Both deploy
workflows send a shell request first and stop unless it is refused.

The last field is the sha256 of the host files concatenated in this order:
`ci-deploy.sh`, `deploy-runner.sh`, `wait-healthy.sh`, `rollback.sh`,
`docker-compose.yml`, `docker-compose.prod.yml`. The workflow computes it
over its checkout, and the host refuses to deploy while its own copies hash
differently. A change to any of them therefore waits for the owner to install
it (next section) instead of deploying a new image against old compose files.

Every decision is logged to the journal: `journalctl -t folio-ci-deploy`.

Exit codes: `2` refused, with one of `rejected: unexpected command`,
`rejected: host files differ from the workflow's checkout (host …, workflow …)`,
`rejected: host files are missing` or `rejected: no registry token on stdin`
on stderr; `1` registry login failed; otherwise `deploy-runner.sh`'s status,
or 128+n when a signal ends it (a dropped SSH connection kills a running
deploy, as it always has).

Tests: `uvx pytest scripts/deploy/tests` (hermetic: stub `docker`, `logger`,
`ssh` and `gcloud` on `PATH`, a temporary host layout, no daemon or network).
They also run the two workflows' guard and deploy steps against the stubs. They
check that the dispatch payload and the manual inputs reach the workflows'
scripts only through `env:`, and that hostile values are rejected without being
run. They run on every pull request that touches these scripts or workflows
(`.github/workflows/test-deploy-scripts.yml`).

## Installing the host files

CI can't write to the host, so the owner installs the host files with the
owner's own admin SSH key (the `folio-prod` alias below), once the change
that touches them has merged to `master` and while no deploy is running
(`gh run list -R flowitup/folio`). Run it from the root of a clone of this
repository. The files all come from one `master` commit, and each one is
replaced by an atomic rename, so a script that is already running keeps
reading its old copy. The two digests printed at the end, the host's and the
local one, must be the same:

```bash
git fetch origin && ref=$(git rev-parse origin/master)
files=(scripts/deploy/ci-deploy.sh scripts/deploy/deploy-runner.sh scripts/deploy/wait-healthy.sh
       scripts/deploy/rollback.sh docker-compose.yml docker-compose.prod.yml)
git archive "$ref" "${files[@]}" | ssh folio-prod 'set -e
  s=$(mktemp -d); trap "rm -rf $s" EXIT; tar -x -C "$s"
  for f in ci-deploy deploy-runner wait-healthy rollback; do
    install -o root -g root -m 755 "$s/scripts/deploy/$f.sh" "/opt/folio/scripts/.$f.sh.new"
    mv -f "/opt/folio/scripts/.$f.sh.new" "/opt/folio/scripts/$f.sh"
  done
  for f in docker-compose.yml docker-compose.prod.yml; do
    install -o root -g root -m 644 "$s/$f" "/opt/folio/.$f.new"
    mv -f "/opt/folio/.$f.new" "/opt/folio/$f"
  done
  cd /opt/folio && cat scripts/ci-deploy.sh scripts/deploy-runner.sh scripts/wait-healthy.sh \
    scripts/rollback.sh docker-compose.yml docker-compose.prod.yml | sha256sum'
for f in "${files[@]}"; do git show "$ref:$f"; done | sha256sum
```

A deploy refused with `host files differ` names both digests. Install the
files, then re-run the failed job if it started after the change merged; a
run that started earlier hashed the old files, so dispatch a new one from
`master` instead.

## deploy/deploy-runner.sh

Host-side deploy: pulls the new image from Artifact Registry, runs backend DB
migrations, swaps the container(s) with `--no-deps`, then waits for health.
Run by `ci-deploy.sh` (above) for the parent's `deploy-backend.yml` /
`deploy-frontend.yml` workflows, with a throwaway Docker config that holds
the Artifact Registry login for that deploy only.

```bash
/opt/folio/scripts/deploy-runner.sh <git-sha> <service>
```

`<service>` is `api` or `frontend`. Migrations run with `lock_timeout=120s`, so a lock held by another
session fails the migration after two minutes instead of hanging the deploy.

Exit codes: `2` invalid service or malformed SHA; any other failed step
aborts the script non-zero (`set -euo pipefail`); `0` on success.

## deploy/wait-healthy.sh

Polls a compose service's container until Docker reports it `healthy`, or
just `running` for services with no healthcheck (e.g. `redis`). Called by
`deploy-runner.sh` and `rollback.sh`; not invoked directly by CI.

```bash
/opt/folio/scripts/wait-healthy.sh <service>
```

Env vars: `COMPOSE_PROJECT_NAME` (default `folio`) builds the container name
`<project>-<service>-1`; `RETRIES` (default `30`) and `SLEEP_SEC` (default
`5`) control the poll loop (~150s timeout by default).

Exit codes: `0` healthy, `1` timeout (dumps the container's last 50 log
lines to stderr) or missing argument.

## deploy/rollback.sh

Manual rollback to a prior image tag, run over SSH by an operator (see root
`README.md` "Rollback" for the full procedure, including the registry login
the host needs first). It doesn't run or reverse migrations: the old code runs
against the newer schema, so only roll back across releases without breaking
schema changes; prefer rolling forward with a fix.

```bash
/opt/folio/scripts/rollback.sh <service> [<sha>]
```

`<service>` is one of `api`, `frontend`. Always pass
`<sha>`. Without it, the script lists the image's Artifact Registry tags
(newest first, skipping `latest`/`stable`/`prod`) and takes the newest one
that isn't the running container's OCI revision label. That is the previous
release only when the running image is the newest build: after a deploy that
failed before its swap, or after an earlier rollback, it returns the newer,
broken build. The lookup needs `gcloud` with Artifact Registry read access on
the host.

Env vars: `PROJECT_ID` (default `flowitup-folio-prod`), `REGION` (default
`europe-west1`), `AR_REPO` (default `folio`) — used to build the Artifact
Registry image path.

Exit codes: `2` invalid service or malformed SHA; `1` missing argument, no
previous tag found, or any failed step (`gcloud`, pull, `up`, health-wait);
`0` on success.

## backup/install-backup-cron.sh

Installs the cron schedule and logrotate config for the three backup
scripts below. Run manually as root on the prod host (once, or again to
update) — unlike the deploy scripts, this is **not** synced automatically
by the GitHub Actions workflows, so `scripts/backup/*.sh` must be copied to
`/opt/folio/scripts/backup/` on the host by hand first.

```bash
/opt/folio/scripts/backup/install-backup-cron.sh   # as root
```

Writes `/etc/cron.d/folio-backups` (`pg-dump.sh` daily 03:00,
`minio-mirror.sh` daily 03:30, `verify-latest-dump.sh` Sundays 04:00 — host
time, which is UTC on the prod host) and a matching
`/etc/logrotate.d/folio-backups` for `/var/log/folio/*.log`.

Exit codes: `1` not run as root, `2` one of the three backup scripts is
missing or not executable at `/opt/folio/scripts/backup/`, `0` on success.

## backup/pg-dump.sh

Nightly Postgres logical dump (`pg_dump -Fc`, custom format) streamed
straight to GCS, with no temp file on disk. The upload impersonates
`backup-sa` (`CLOUDSDK_AUTH_IMPERSONATE_SERVICE_ACCOUNT`), which is meant to
hold only object-create on the bucket: the upload identity can't list, read
or delete earlier dumps, and a same-day re-run can't overwrite that day's key
either.

This does not protect backups from a compromised host: the host's credential
can mint `backup-sa` tokens, `verify-latest-dump.sh` reads the bucket from the
host, and `minio-mirror.sh` uses `backup-sa` HMAC keys stored in
`/opt/folio/.env`.

Runs on the prod host from cron (installed by `install-backup-cron.sh`).

Env vars: `PROJECT_ID` (default `flowitup-folio-prod`), `ENV_FILE` (default
`/opt/folio/.env`, source of `POSTGRES_USER`/`POSTGRES_DB`), `BACKUP_BUCKET`
(default `<PROJECT_ID>-backups`).

Exit codes: `1` env file unreadable or DB vars missing, `2` no running
Postgres container found, `3` dump or upload failed, `0` success.

## backup/minio-mirror.sh

Nightly MinIO → GCS mirror via a throwaway `minio/mc` container (S3-to-S3
directly, no disk staging). Refuses to mirror if the source object count
drops by more than 5 % (100 − `DROP_THRESHOLD_PCT`) versus the last
successful run, to stop a wiped or corrupted MinIO from propagating into the
backup. It never passes `--remove`, so nothing is deleted from the
destination; changed objects are overwritten (`--overwrite`), and older
versions survive only through bucket versioning. Runs on the prod host via
cron, installed by `install-backup-cron.sh`.

Env vars: `PROJECT_ID`, `ENV_FILE` (default `/opt/folio/.env`, source of the
S3/GCS HMAC credentials), `BACKUP_BUCKET`, `LAST_COUNT_FILE` (default
`/var/lib/folio/last-mc-count`), `DROP_THRESHOLD_PCT` (default `95` — abort
if the source count falls below `last * 95 / 100`).

Exit codes: `1` env file or required vars missing; `3` drift guard aborted
the run; `4` mirror failed mid-run; `0` success. If the source listing fails
(MinIO down, wrong keys, `minio/mc` image pull fails), the script exits with
`mc`'s or docker's own status (usually `1`, or `125` from docker) before
writing any log line.

## backup/verify-latest-dump.sh

Weekly restore test: downloads the latest `pg-dump.sh` output, restores it
into a throwaway `postgres:16-alpine` sidecar on `127.0.0.1:55432` (the port
is fixed; the container name has a random suffix), then runs `SELECT 1`. That
proves the dump restores and the database answers, not that any particular
table is intact. The sidecar and the local copy are removed whatever the
outcome. Runs on the prod host via cron, installed by
`install-backup-cron.sh`.

Env vars: `PROJECT_ID`, `ENV_FILE` (default `/opt/folio/.env`, source of
`POSTGRES_USER`/`POSTGRES_DB`), `BACKUP_BUCKET`, `WORK_DIR` (default
`/var/lib/folio/restore-test`).

Exit codes: `1` required vars missing, no dump in the bucket or bucket
unreadable (silent: `gsutil`'s stderr is discarded), or download failed;
`2` env file unreadable; `3` `pg_restore` failed; `4` post-restore
`SELECT 1` failed; `125` sidecar container failed to start; `0` success.
