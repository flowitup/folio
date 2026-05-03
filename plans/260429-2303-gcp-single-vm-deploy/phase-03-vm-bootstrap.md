---
phase: 3
title: "VM Bootstrap"
status: pending
priority: P1
effort: "3h"
dependencies: [2]
---

# Phase 3: VM Bootstrap

> **[REVISED 2026-04-29]** Volume strategy reverted to named volumes (NOT bind mounts). Port-binding hardened to 127.0.0.1. Prod compose override added to strip `:-defaults`. **YAGNI cut Y1:** fail2ban dropped (no public SSH to brute-force on Tunnel-only deploy). **The `## Red Team Fixes` and `## Validation Decisions` sections at the end are authoritative**; supersede the named-volume → bind-mount migration, the `1000:1000` UID criterion, and the fail2ban install/jail steps.

## Overview

Install everything the VM needs to run the Docker stack: Docker Engine + compose plugin, `cloudflared`, log rotation, unattended security upgrades, deploy user with restricted shell, fail2ban, and the directory layout under `/opt/folio` and `/var/lib/folio`. Driven by a startup script (cloud-init) so the VM is reproducible.

## Requirements

- **Functional:** `docker compose version` works, `cloudflared --version` works, deploy user can SSH and run docker without sudo, all volumes mounted.
- **Non-functional:** No interactive prompts; script idempotent; security baseline (fail2ban, unattended-upgrades, SSH config hardened).

## Architecture

```
VM filesystem layout:
/opt/folio/
├── docker-compose.yml          (synced from monorepo)
├── .env                         (rendered from Secret Manager — phase 6)
└── deploy-key.json              (vm-runtime-sa, AR pull only — auto via metadata)

/var/lib/folio/                  (data disk mount)
├── postgres/                    (named volume)
├── redis/                       (named volume)
├── minio/                       (named volume)
└── logs/                        (json-file driver, rotated)

System packages:
├── docker-ce + docker-compose-plugin
├── cloudflared
├── fail2ban
├── unattended-upgrades
└── google-cloud-sdk (already on GCE images)

Users:
├── deploy (no sudo, docker group, ~/.ssh/authorized_keys from CI)
└── root (locked SSH, sudo via gcloud-managed user only)
```

## Related Code Files

- Create: `infra/gcp/cloud-init/startup.sh` — idempotent bootstrap.
- Create: `infra/gcp/cloud-init/sshd_config.d/99-folio.conf` — disable password auth, root login, etc.
- Create: `infra/gcp/cloud-init/fail2ban.local` — SSH jail.
- Create: `infra/gcp/cloud-init/logrotate.d/folio` — rotate Docker JSON logs.
- Modify: `docker-compose.yml` — pin volume paths to `/var/lib/folio/<service>` (was named volumes).

## Implementation Steps

1. Write `startup.sh` to:
   - `apt-get update && apt-get install -y ca-certificates curl gnupg lsb-release fail2ban unattended-upgrades`.
   - Install Docker Engine via official repo (Debian 12 path).
   - Add `deploy` user, add to `docker` group.
   - Install `cloudflared` via official `.deb` package.
   - Configure docker daemon (`/etc/docker/daemon.json`): `log-driver: json-file`, `max-size: 10m`, `max-file: 3`.
   - Render SSH hardening drop-in (no root, no password, AllowUsers deploy).
   - Enable `unattended-upgrades` (security only).
   - Configure `fail2ban` SSH jail.
   - `mkdir -p /var/lib/folio/{postgres,redis,minio,logs}` with correct ownership.
2. Wire the script as VM `startup-script` metadata in Terraform — re-runs idempotently on reboot.
3. SSH in, verify each piece (`docker info`, `cloudflared --version`, `fail2ban-client status sshd`).
4. Update `docker-compose.yml` so volume host paths are `/var/lib/folio/<svc>` (preserves data across compose recreate).
5. Pre-pull `gcr.io/cloud-builders/gke-deploy` and base images to warm cache (optional).
6. Configure Docker to authenticate to Artifact Registry: `gcloud auth configure-docker europe-west1-docker.pkg.dev` runs as `deploy` user; uses VM-attached SA, no keys.

## Success Criteria

- [ ] Reboot VM → `startup.sh` re-runs, no errors, no drift.
- [ ] `sudo -u deploy docker pull europe-west1-docker.pkg.dev/flowitup-folio-prod/folio/api:latest` works (after phase 5 pushes one).
- [ ] `cloudflared --version` works.
- [ ] `fail2ban-client status sshd` shows active.
- [ ] `cat /etc/ssh/sshd_config.d/99-folio.conf` confirms hardening.
- [ ] `df -h /var/lib/folio` shows data disk; service subdirs exist with `1000:1000` ownership (or appropriate UIDs).
- [ ] Docker logs rotate at 10 MB / 3 files.

## Risk Assessment

| Risk | Mitigation |
|---|---|
| Startup script fails mid-run → half-bootstrapped VM | All steps idempotent (`apt install -y` retries safely); test by running twice. |
| Wrong UIDs cause Postgres/MinIO to refuse to start on bind mounts | Document expected UIDs (Postgres=999 in alpine, MinIO=1000); set in startup. |
| Disk full from logs | logrotate + Docker `max-size` cap + monitoring alert at 80 %. |
| Unattended-upgrades reboots at peak | Configure to reboot at 04:00 UTC, only on kernel security upgrade. |
| `cloudflared` install path drift between Debian releases | Pin to specific `.deb` URL in script; bump in PR review. |

## Red Team Fixes (2026-04-29)

Findings 4, 10, 15 apply here. Override earlier sections as follows.

### Reverted: keep named volumes (don't migrate to bind paths)

Original plan said "modify docker-compose.yml so volume host paths are `/var/lib/folio/<svc>`." **Reversed.** Reasons:
1. Switching named volumes → bind paths does NOT preserve data automatically (different storage); the "preserves data across compose recreate" claim was wrong.
2. UIDs vary per image: postgres:16-alpine = UID 70, NOT 999; minio = UID 1000; redis = 999. A single `chown 1000:1000 /var/lib/folio/*` (as the original success criterion implied) breaks Postgres at boot.

Replacement: Docker named volumes (`postgres_data`, `redis_data`, `minio_data`) live under `/var/lib/docker/volumes/...`. Backups (phase 7) read from inside containers via `docker exec`, not from host paths. Disk pressure is monitored (phase 8); for backups we use logical dumps + `mc mirror`, not raw filesystem snapshots of these volumes.

The data disk (phase 2) is mounted at `/var/lib/docker` (or symlinked there), so all named volumes live on the dedicated 50 GB pd-balanced disk regardless. **New step 4:** add `/etc/docker/daemon.json` `"data-root": "/var/lib/docker"` and ensure the data disk is mounted there at boot, not at `/var/lib/folio`.

### Bind ports to localhost — close 0.0.0.0 exposure

Compose currently publishes `5432`, `6379`, `9000`, `9001` on `0.0.0.0`. Behind Cloudflare Tunnel none of those should be reachable, but a single firewall typo or test rule exposes all of them with default credentials.

Add a production compose override `docker-compose.prod.yml` (loaded via `COMPOSE_FILE=docker-compose.yml:docker-compose.prod.yml` or `-f` flag in CI):

```yaml
services:
  db:
    ports: !reset []
  redis:
    ports: !reset []
  minio:
    ports:
      - "127.0.0.1:9000:9000"     # S3 endpoint — only reachable via cloudflared/local
      - "127.0.0.1:9001:9001"     # console — admin via SSH port-forward only
```

### Strip `:-default` fallbacks for prod (Finding 4)

Same `docker-compose.prod.yml` adds explicit error-on-missing for credential env vars:

```yaml
services:
  db:
    environment:
      POSTGRES_USER: "${POSTGRES_USER:?required in prod}"
      POSTGRES_PASSWORD: "${POSTGRES_PASSWORD:?required in prod}"
      POSTGRES_DB: "${POSTGRES_DB:?required in prod}"
  api:
    environment:
      SECRET_KEY: "${SECRET_KEY:?required in prod}"
      JWT_SECRET_KEY: "${JWT_SECRET_KEY:?required in prod}"
      S3_ACCESS_KEY: "${S3_ACCESS_KEY:?required in prod}"
      S3_SECRET_KEY: "${S3_SECRET_KEY:?required in prod}"
  minio:
    environment:
      MINIO_ROOT_USER: "${S3_ACCESS_KEY:?required in prod}"
      MINIO_ROOT_PASSWORD: "${S3_SECRET_KEY:?required in prod}"
```

`${VAR:?msg}` aborts the compose run if `VAR` is unset. `:-default` fallback is impossible from this override.

### Image prune cron (capacity)

Add to startup script: install `/etc/cron.weekly/folio-image-prune`:
```bash
#!/bin/sh
docker image prune -af --filter 'until=168h'
```
Prevents AR-pulled image accumulation from filling the 50 GB disk.

### Updated Success Criteria (replacements / additions)

- [ ] Named volumes used; data disk mounted at `/var/lib/docker` so volumes inherit the 50 GB pd-balanced storage.
- [ ] `docker-compose.prod.yml` exists and `docker compose -f docker-compose.yml -f docker-compose.prod.yml config` aborts when `POSTGRES_PASSWORD` etc. are unset.
- [ ] `nmap` from outside the VM finds NO port 5432/6379/9000/9001 open (port-bound to 127.0.0.1 only).
- [ ] Image prune cron installed; `docker images | wc -l` stays bounded across deploys.
- [ ] **Removed:** UID-based ownership assertion under `/var/lib/folio/*` (no longer applicable — Docker manages volume perms).

## Validation Decisions (2026-04-29 Session 1)

**Y1 — Drop fail2ban entirely.**

Cloudflare Tunnel + IAP-only SSH means **no public SSH port exists**. fail2ban guards a closed door. Pure overhead.

**Action:**
- Remove `fail2ban` from the `apt-get install` list in `startup.sh`.
- Remove `fail2ban.local` from "Related Code Files."
- Remove `fail2ban` from systemd verification step.
- Drop the success criterion `fail2ban-client status sshd shows active`.

**Other security baseline (kept):**
- `unattended-upgrades` (security only) — kept, but **disable auto-reboot** (manual reboots in maintenance windows). Edit `/etc/apt/apt.conf.d/50unattended-upgrades` → `Unattended-Upgrade::Automatic-Reboot "false";`.
- SSH hardening drop-in (no root, no password, AllowUsers deploy) — kept.

**Effort reclaimed:** ~30 min. Less surface to debug.
