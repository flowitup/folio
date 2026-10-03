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

What it does: starts folio-back-end's own `docker-compose.yml` (api, worker,
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

`<service>` is `api` or `frontend`. `api` also restarts `worker` (shares the
same image) and, only when `/opt/folio/.env` has `FEATURE_ASSISTANT=1`,
`ai-browser` (own image, same SHA); when the flag is off, any running
`ai-browser` is stopped and removed instead. `ai-browser` is stopped before
migrations, which run with `lock_timeout=120s`: an earlier poller kept a
`SELECT … FOR UPDATE` open on `assistant_jobs` and hung the v0.4.0 migration,
and any lock that remains now fails the migration after two minutes instead
of hanging the deploy. A failed/missing `ai-browser` pull or health-wait only
warns — it never fails the `api`/`worker` deploy.

Exit codes: `2` invalid service or malformed SHA; any other failed step
aborts the script non-zero (`set -euo pipefail`); `0` on success.

## deploy/wait-healthy.sh

Polls a compose service's container until Docker reports it `healthy`, or
just `running` for services with no healthcheck (e.g. `worker`). Called by
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

`<service>` is one of `api`, `frontend`, `worker`, `ai-browser`. Always pass
`<sha>`. Without it, the script lists the image's Artifact Registry tags
(newest first, skipping `latest`/`stable`/`prod`) and takes the newest one
that isn't the running container's OCI revision label. That is the previous
release only when the running image is the newest build: after a deploy that
failed before its swap, or after an earlier rollback, it returns the newer,
broken build. The lookup needs `gcloud` with Artifact Registry read access on
the host (the prod host has no `gcloud`, so there it always fails), and it
fails for `worker` (there is no `worker` image; worker runs the `api` image).

`api` also swaps `worker`, and `ai-browser` while `FEATURE_ASSISTANT=1`. With
the assistant off, `ai-browser` is left as it is (deploy-runner removes it
instead).

Env vars: `PROJECT_ID` (default `flowitup-folio-prod`), `REGION` (default
`europe-west1`), `AR_REPO` (default `folio`) — used to build the Artifact
Registry image path.

Exit codes: `2` invalid service or malformed SHA; `1` missing argument, no
previous tag found, or any failed step (`gcloud`, pull, `up`, health-wait);
`0` on success.

## backup/install-backup-cron.sh

Installs the two nightly backup jobs the way the prod host runs them: copies
`pg-dump.sh` and `minio-mirror.sh` to `/usr/local/bin/` and writes
`/etc/cron.d/folio-backups` (`pg-dump.sh` daily 03:00, `minio-mirror.sh`
daily 03:30 — host time, which is UTC on the prod host). Run it as root on the
host from a copy of `scripts/backup/` (once, or again to update). Unlike the
deploy scripts, nothing here is synced by the GitHub Actions workflows, so the
host only changes when someone re-runs it:

```bash
scp scripts/backup/{install-backup-cron,pg-dump,minio-mirror}.sh root@<prod-host>:/root/
ssh root@<prod-host> bash /root/install-backup-cron.sh
```

No log files or logrotate config: both jobs log through `logger`, so their
status lines are in journald (`journalctl -t pg-dump -t minio-mirror`). It
does not install `verify-latest-dump.sh` (see below).

The repo copies of `pg-dump.sh` and `minio-mirror.sh` are the ones on the host,
and the installer's cron text matches the host's cron file (checked
2026-09-26). To spot drift, compare
`ssh root@<prod-host> sha256sum /usr/local/bin/pg-dump.sh /usr/local/bin/minio-mirror.sh`
with `sha256sum scripts/backup/pg-dump.sh scripts/backup/minio-mirror.sh`, and
`ssh root@<prod-host> cat /etc/cron.d/folio-backups` with the heredoc in
`install-backup-cron.sh`.

Exit codes: `1` not run as root, `2` `pg-dump.sh` or `minio-mirror.sh` is
missing next to the installer (checked before anything is installed), `0` on
success; any other failed step aborts non-zero (`set -euo pipefail`).

## backup/pg-dump.sh

Nightly Postgres logical dump (`pg_dump -Fc`, custom format) streamed
straight to GCS, with no temp file on disk: `docker exec` runs `pg_dump` in
the Postgres container and pipes it into a throwaway `quay.io/minio/mc`
container (`mc pipe`) that writes `pg-dumps/<UTC date>.dump` to the bucket.
The host has no `gcloud`; the upload authenticates with `backup-sa`'s GCS HMAC
key pair (`GCS_HMAC_ACCESS_KEY` / `GCS_HMAC_SECRET_KEY` in `/opt/folio/.env`).
`backup-sa` can create, list and read objects in this bucket but not delete
them, and the bucket has a 7-day retention period plus versioning:
earlier dumps can't be removed or replaced, so a same-day re-run fails (exit
`3`) instead of overwriting that day's dump.

This does not protect backups from a compromised host: root there can read the
HMAC pair from `/opt/folio/.env` (`minio-mirror.sh` uses the same pair) and
with it list and download every dump and mirrored file in the bucket. It
still can't delete them.

Runs on the prod host as `/usr/local/bin/pg-dump.sh` from
`/etc/cron.d/folio-backups` (in place since the 2026-07-15 move;
`install-backup-cron.sh` reproduces it). A successful run logs
`ok: uploaded pg-dumps/<date>.dump` to journald (tag `pg-dump`); the handled
failures below log an `ERROR:` line first.

Env vars: `ENV_FILE` (default `/opt/folio/.env`, source of `POSTGRES_USER`,
`POSTGRES_DB` and the HMAC pair), `BACKUP_BUCKET` (default
`flowitup-folio-prod-backups`).

Exit codes: `1` env file unreadable or one of those four values missing, `2`
no running Postgres container found, `3` dump or upload failed, `0` success.
Any other failing command (for example `docker ps` itself) aborts with its own
status before a log line is written (`set -euo pipefail`).

## backup/minio-mirror.sh

Nightly MinIO → GCS mirror via a throwaway `minio/mc` container (S3-to-S3
directly, no disk staging). Refuses to mirror if the source object count
drops by more than 5 % (100 − `DROP_THRESHOLD_PCT`) versus the last
successful run, to stop a wiped or corrupted MinIO from propagating into the
backup. It never passes `--remove`, so nothing is deleted from the
destination. It does pass `--overwrite`, but `backup-sa` can't delete or
replace objects (see `pg-dump.sh`), so an object that changes in MinIO under
the same key would fail the run (exit `4`) every night rather than be
overwritten; new objects are simply added. Runs on the prod host as
`/usr/local/bin/minio-mirror.sh` from the same cron file. A successful run logs
`ok: mirrored <N> objects` to journald (tag `minio-mirror`). The script's
comment about `folio-render-env.service` is stale: no such unit exists on the
host (see the root README, "Runtime secrets").

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

**Not installed on the prod host, so no restore test runs today.** It was
written for the GCP VM: it lists and downloads the dumps with `gsutil` as that
VM's own service account (`vm-runtime-sa`). The Hetzner host has neither
`gsutil` nor that identity, so the script can't run there as is. Nothing has
scheduled it since the 2026-07-15 move.

What it does: downloads the latest `pg-dump.sh` output, restores it into a
throwaway `postgres:16-alpine` sidecar on `127.0.0.1:55432` (the port is
fixed; the container name has a random suffix), then runs `SELECT 1`. That
proves the dump restores and the database answers, not that any particular
table is intact. The sidecar and the local copy are removed whatever the
outcome.

Env vars: `PROJECT_ID`, `ENV_FILE` (default `/opt/folio/.env`, source of
`POSTGRES_USER`/`POSTGRES_DB`), `BACKUP_BUCKET`, `WORK_DIR` (default
`/var/lib/folio/restore-test`).

Exit codes: `1` required vars missing, no dump in the bucket or bucket
unreadable (silent: `gsutil`'s stderr is discarded), or download failed;
`2` env file unreadable; `3` `pg_restore` failed; `4` post-restore
`SELECT 1` failed; `125` sidecar container failed to start; `0` success.
