# Folio Deployment Guide

**Last Updated:** 2026-05-03
**Status:** ✅ Production live at https://folio.flowitup.com
**Deploy Plan:** [plans/260429-2303-gcp-single-vm-deploy/plan.md](../plans/260429-2303-gcp-single-vm-deploy/plan.md)

This is the single source of operational truth for production. Read **Common
Operations** before any deploy. Read **Incidents** before any 3 AM page.

---

## Table of Contents

1. [Architecture](#1-architecture)
2. [Stack Inventory](#2-stack-inventory)
3. [Common Operations](#3-common-operations)
4. [Incidents](#4-incidents)
5. [Maintenance](#5-maintenance)
6. [Escalation](#6-escalation)

---

## 1. Architecture

### Topology

```
                          ┌──────────────────┐
                  HTTPS   │   Cloudflare     │   DNS + WAF + CDN + DDoS
   user ────────────────► │  flowitup.com    │   (no public IP exposed)
                          └────────┬─────────┘
                                   │ Cloudflare Tunnel
                                   │ (cloudflared daemon, persistent
                                   │  outbound-only TLS connection)
                                   ▼
   ┌───────────────────────────────────────────────────────────────────┐
   │  GCE VM: flowitup-folio-prod-1 (e2-standard-2, europe-west1-b)    │
   │  ┌──────────────────────────────────────────────────────────────┐ │
   │  │ Docker Compose project: folio                                │ │
   │  │                                                              │ │
   │  │ ┌──────────┐ ┌──────────┐ ┌────────────┐                    │ │
   │  │ │ frontend │ │   api    │ │   worker   │                    │ │
   │  │ │ (Next.js)│ │ (Flask)  │ │   (RQ)     │                    │ │
   │  │ │  :3000   │ │  :5000   │ │  no port   │                    │ │
   │  │ └────┬─────┘ └─────┬────┘ └─────┬──────┘                    │ │
   │  │      │             │            │                            │ │
   │  │      └─────────────┴────────────┴────┐                       │ │
   │  │                                      ▼                       │ │
   │  │  ┌────────┐  ┌────────┐  ┌──────────────────┐               │ │
   │  │  │   db   │  │ redis  │  │      minio       │               │ │
   │  │  │ (PG16) │  │  (7)   │  │ (S3-compatible)  │               │ │
   │  │  │ :5432  │  │ :6379  │  │  :9000 / :9001   │               │ │
   │  │  └────────┘  └────────┘  └──────────────────┘               │ │
   │  │                                                              │ │
   │  │  Data dir: /var/lib/docker (mounted on 50 GB pd-balanced     │ │
   │  │  data disk, weekly snapshot policy attached)                 │ │
   │  └──────────────────────────────────────────────────────────────┘ │
   │                                                                   │
   │  systemd units:                                                   │
   │   - docker.service                                                │
   │   - cloudflared.service        (outbound tunnel daemon)           │
   │   - google-cloud-ops-agent     (logs + metrics → GCP)             │
   │   - folio-render-env.service   (oneshot: rerender .env from SM)   │
   │  cron (UTC):                                                      │
   │   - 03:00  pg-dump.sh                                             │
   │   - 03:30  minio-mirror.sh                                        │
   │   - Sun 04:00  verify-latest-dump.sh                              │
   └───────────────────────────────────────────────────────────────────┘
                                   │
                                   ├─► Secret Manager   (20 secrets, runtime SA)
                                   ├─► Artifact Registry (api + frontend images)
                                   ├─► Cloud Storage    (gs://...-backups, -archive)
                                   ├─► Cloud Logging    (container stdout via Ops Agent)
                                   └─► Cloud Monitoring (uptime check + 1 alert)
```

### Why this shape

- **Single VM** (Option A) — simplicity over HA. ~$80/mo at e2-standard-2. No
  Cloud SQL, no GKE, no managed Redis. Acknowledged tradeoff: operator owns
  DB recovery.
- **Cloudflare Tunnel** — no public IP on the VM, no port 80/443 open in
  firewall. Cloudflare WAF + DDoS sit in front; the only inbound to the VM
  is IAP-tunneled SSH for ops.
- **Compose v2** with prod override — base file describes services; prod
  override binds ports to 127.0.0.1, sets `${VAR:?required}` enforcement,
  points to AR images instead of local builds.
- **Service-account-per-purpose** — `deploy-sa` (push images, IAP SSH from
  CI), `vm-runtime-sa` (read images + secrets, default ADC on VM),
  `backup-sa` (write backups via impersonation; never authenticated
  directly).

---

## 2. Stack Inventory

### Cloud (GCP project: `flowitup-folio-prod`, org: `mtbui-creative-org`)

| Component | Resource | Purpose |
|---|---|---|
| Compute | `flowitup-folio-prod-1` (e2-standard-2, europe-west1-b) | All 6 containers |
| Boot disk | 30 GB pd-balanced | OS, Docker engine, configs |
| Data disk | 50 GB pd-balanced (`flowitup-folio-prod-data`) | Mounted at `/var/lib/docker` |
| Snapshot policy | `folio-snapshot-weekly` | Sun 02:00 UTC, 28d retention, both disks |
| Artifact Registry | `folio` (europe-west1) | Docker images: `api`, `frontend` |
| Cloud Storage | `gs://flowitup-folio-prod-backups` | pg-dumps, minio-mirror; 7d retention lock + versioning |
| Cloud Storage | `gs://flowitup-folio-prod-backups-archive` | Long-term archive; 365d retention lock |
| Secret Manager | 20 secrets (label `env=prod`) | DB creds, JWTs, API keys, HMAC pair |
| Cloud Logging | Implicit | Container logs via Ops Agent + journald |
| Cloud Monitoring | 1 uptime check + 2 alert policies | Uptime `/health` + disk >85% (email) |
| IAP | TCP forwarding | SSH access (no public IP, no 0.0.0.0/0 SSH rule) |
| Billing budget | $100/mo with 50/80/100/120% alerts | Cost guardrail |

### Identity & access

| SA | Project roles | Bucket / SA roles | Keys | Notes |
|---|---|---|---|---|
| `deploy-sa@…` | `artifactregistry.writer`, `iap.tunnelResourceAccessor`, `compute.osLogin` | — | 1 JSON key in GitHub `GCP_SA_KEY` | CI only |
| `vm-runtime-sa@…` | `artifactregistry.reader`, `logging.logWriter`, `monitoring.metricWriter` | per-secret `secretmanager.secretAccessor` (×20), `iam.serviceAccountTokenCreator` on backup-sa, `storage.objectViewer` on primary backup bucket | None — VM-attached metadata server | Default ADC on VM |
| `backup-sa@…` | — | `storage.objectCreator` + `storage.objectViewer` (primary), `storage.objectCreator` (archive) | 1 GCS HMAC pair in SM | Append-only writer; impersonated by vm-runtime-sa |

### VM operating system

| Component | Version | Role |
|---|---|---|
| OS | Ubuntu 24.04 LTS amd64 | base |
| Docker Engine | latest stable (apt repo) | container runtime |
| Compose | v2 plugin (compose-plugin) | orchestration |
| cloudflared | latest stable (CF apt repo) | tunnel daemon (systemd) |
| google-cloud-ops-agent | latest stable | logs + metrics, capped 256 MB RAM |
| google-cloud-cli | apt-installed (NOT snap) | gcloud CLI for SA impersonation |
| unattended-upgrades | enabled, no auto-reboot | security patches; manual reboot windows |

### Containers

| Service | Image | Host port | Healthcheck | Restart |
|---|---|---|---|---|
| `frontend` | `…/folio/frontend:latest` (Node 22 alpine, Next.js standalone) | `127.0.0.1:3000` | HTTP `/` 200 | unless-stopped |
| `api` | `…/folio/api:latest` (Python 3.12, gunicorn) | `127.0.0.1:5000` | HTTP `/health` 200 | unless-stopped |
| `worker` | `…/folio/api:latest` (same image, RQ command) | none | DISABLED (RQ worker) | unless-stopped |
| `db` | `postgres:16-alpine` | none | `pg_isready` | unless-stopped |
| `redis` | `redis:7-alpine` | none | `redis-cli ping` | unless-stopped |
| `minio` | `minio/minio:latest` | `127.0.0.1:9000-9001` | `/minio/health/live` | unless-stopped |

### Cloudflare ingress (`infra/cloudflare/cloudflared-config.yml`)

| Path | Routes to | Notes |
|---|---|---|
| `folio.flowitup.com /health` | `localhost:5000` | Used by Cloud Monitoring uptime check |
| `folio.flowitup.com /api/*` | `localhost:5000` | Flask API |
| `folio.flowitup.com *` | `localhost:3000` | Next.js frontend (catch-all on host) |
| `cdn.flowitup.com *` | `localhost:9000` | MinIO presigned URL host (S3-compatible) |
| (catch-all) | `http_status:404` | Required terminator |

### Configuration files (critical)

| File | Source | Mode | Renders via |
|---|---|---|---|
| `/opt/folio/.env` | Secret Manager (24 keys) | 640 root:docker | `folio-render-env.service` |
| `/opt/folio/docker-compose.yml` | Repo root | 644 root:root | scp on deploy |
| `/opt/folio/docker-compose.prod.yml` | Repo root | 644 root:root | scp on deploy |
| `/etc/cloudflared/config.yml` | Repo `infra/cloudflare/` | 644 root:root | scp on deploy |
| `/etc/cloudflared/cert.pem` | Cloudflare login | 600 root:root | One-time at provisioning |
| `/etc/cloudflared/credentials.json` | Cloudflare tunnel create | 600 root:root | One-time at provisioning |
| `/etc/cron.d/folio-backups` | Generated by `install-backup-cron.sh` | 644 root:root | Operator |

### Constants in code (NOT in Secret Manager)

```
S3_ENDPOINT_URL=http://minio:9000          # docker network internal
S3_REGION=us-east-1
EMAIL_PROVIDER=resend
API_INTERNAL_BASE_URL=http://api:5000/api/v1
FLASK_DEBUG=false
NODE_ENV=production
```

### Secret Manager keys consumed by VM

```
folio-postgres-user / -password / -db                 → DB creds
folio-secret-key                                      → Flask SECRET_KEY
folio-jwt-secret-key                                  → JWT signing
folio-s3-access-key / -secret-key / -bucket           → MinIO root + bucket
folio-s3-public-endpoint-url                          → cdn.flowitup.com
folio-cors-origins                                    → folio.flowitup.com
folio-next-public-api-base-url                        → baked into FE at build time
folio-resend-api-key / -from-email                    → email
folio-ratelimit-storage-uri                           → redis://redis:6379/2
folio-behind-proxy                                    → "true" (ProxyFix)
folio-gcs-hmac-access-key / -secret-key               → mc → GCS for backup
folio-admin-bootstrap-password                        → first-login seed
```

Two further SM keys are mirrored from GitHub Secrets but **not** consumed
on the VM: `folio-cf-api-token`, `folio-cf-zone-id` (used by GitHub Actions
for CF cache purge after frontend deploys).

---

## 3. Common Operations

### 3.1 Deploy a code change

**Path A — manual (current; no GitHub remote yet):**

```bash
cd ~/workspaces/folio
API_SHA=$(cd folio-back-end && git rev-parse --short HEAD)
FE_SHA=$(cd folio-front-end  && git rev-parse --short HEAD)

# 1. Build + push images (laptop, ~5–10 min)
docker buildx build --platform=linux/amd64 \
  -t europe-west1-docker.pkg.dev/flowitup-folio-prod/folio/api:${API_SHA} \
  -t europe-west1-docker.pkg.dev/flowitup-folio-prod/folio/api:latest \
  --push ./folio-back-end

docker buildx build --platform=linux/amd64 \
  --build-arg NEXT_PUBLIC_API_BASE_URL=https://folio.flowitup.com/api/v1 \
  -t europe-west1-docker.pkg.dev/flowitup-folio-prod/folio/frontend:${FE_SHA} \
  -t europe-west1-docker.pkg.dev/flowitup-folio-prod/folio/frontend:latest \
  --push ./folio-front-end

# 2. Migrate (only if schema changed)
gcloud compute ssh flowitup-folio-prod-1 --tunnel-through-iap --zone=europe-west1-b -- '
PG_USER=$(sudo grep ^POSTGRES_USER= /opt/folio/.env | cut -d= -f2-)
PG_PASS=$(sudo grep ^POSTGRES_PASSWORD= /opt/folio/.env | cut -d= -f2-)
PG_DB=$(sudo grep ^POSTGRES_DB= /opt/folio/.env | cut -d= -f2-)
sudo docker run --rm \
  --network folio_default --env-file /opt/folio/.env \
  -e DATABASE_URL="postgresql://${PG_USER}:${PG_PASS}@db:5432/${PG_DB}" \
  -e REDIS_URL=redis://redis:6379/0 \
  -e FLASK_APP=app:create_app \
  -e FROM_EMAIL=$(sudo grep ^RESEND_FROM_EMAIL= /opt/folio/.env | cut -d= -f2-) \
  europe-west1-docker.pkg.dev/flowitup-folio-prod/folio/api:latest \
  flask db upgrade
'

# 3. Pull + restart
gcloud compute ssh flowitup-folio-prod-1 --tunnel-through-iap --zone=europe-west1-b -- '
cd /opt/folio
sudo IMAGE_TAG=latest docker compose -f docker-compose.yml -f docker-compose.prod.yml \
  --env-file=.env pull api worker frontend
sudo IMAGE_TAG=latest docker compose -f docker-compose.yml -f docker-compose.prod.yml \
  --env-file=.env up -d --no-build api worker frontend
'

# 4. Smoke
curl -sI https://folio.flowitup.com/health | head -1   # expect HTTP/2 200
```

**Path B — CI-driven (after GitHub remote is wired):** `git push origin main`
on the back-end or front-end submodule triggers GitHub Actions
(`.github/workflows/deploy-{api,frontend}.yml`, templates in
`infra/ci-templates/`). CI builds + pushes, then SSHes via IAP and runs the
pull + restart sequence. Templates also call CF cache-purge after frontend
deploys.

### 3.2 Rollback

Roll the image tag back to the previous SHA:

```bash
# 1. Find recent SHAs in AR
gcloud artifacts docker images list \
  europe-west1-docker.pkg.dev/flowitup-folio-prod/folio \
  --include-tags --sort-by=~UPDATE_TIME --limit=10

# 2. Pin the previous SHA on the VM
gcloud compute ssh flowitup-folio-prod-1 --tunnel-through-iap --zone=europe-west1-b -- '
cd /opt/folio
sudo IMAGE_TAG=<previous-sha> docker compose \
  -f docker-compose.yml -f docker-compose.prod.yml --env-file=.env \
  pull api frontend
sudo IMAGE_TAG=<previous-sha> docker compose \
  -f docker-compose.yml -f docker-compose.prod.yml --env-file=.env \
  up -d --no-build api worker frontend
'
```

If migrations need rollback too, see §4.2.

### 3.3 SSH to VM (via IAP)

```bash
gcloud compute ssh flowitup-folio-prod-1 \
  --tunnel-through-iap --zone=europe-west1-b
```

No public SSH. Requires `roles/iap.tunnelResourceAccessor` on your user account
or the calling SA. CI uses `deploy-sa` with that role.

### 3.4 Read logs

```bash
# All containers, last 50, follow
gcloud compute ssh flowitup-folio-prod-1 --tunnel-through-iap --zone=europe-west1-b -- \
  'sudo docker compose -f /opt/folio/docker-compose.yml -f /opt/folio/docker-compose.prod.yml logs -f --tail=50'

# Single service
gcloud compute ssh flowitup-folio-prod-1 --tunnel-through-iap --zone=europe-west1-b -- \
  'sudo docker logs -f --tail=100 folio-api-1'
```

Cloud Logging filters (paste into the console):

```
# API errors only
resource.type="gce_instance" jsonPayload.container.image=~"/folio/api" severity>=ERROR

# Worker job failures
resource.type="gce_instance" jsonPayload.container.image=~"/folio/api" textPayload=~"job .* failed"

# Postgres slow queries
resource.type="gce_instance" jsonPayload.container.image=~"postgres" textPayload=~"duration: [0-9]{3,}"
```

Console: https://console.cloud.google.com/logs/query?project=flowitup-folio-prod

### 3.5 Re-render `.env` after rotating a secret

```bash
gcloud compute ssh flowitup-folio-prod-1 --tunnel-through-iap --zone=europe-west1-b -- '
sudo systemctl start folio-render-env.service
sudo journalctl -u folio-render-env.service -n 5 --no-pager
cd /opt/folio
sudo IMAGE_TAG=latest docker compose -f docker-compose.yml -f docker-compose.prod.yml \
  --env-file=.env up -d --force-recreate
'
```

### 3.6 Scale VM up

`e2-standard-2` (2 vCPU / 8 GB) → `e2-standard-4` (4 vCPU / 16 GB):

```bash
gcloud compute instances stop flowitup-folio-prod-1 --zone=europe-west1-b
gcloud compute instances set-machine-type flowitup-folio-prod-1 \
  --machine-type=e2-standard-4 --zone=europe-west1-b
gcloud compute instances start flowitup-folio-prod-1 --zone=europe-west1-b
sleep 60
curl -sI https://folio.flowitup.com/health | head -1
```

Cost change: ~$50/mo → ~$100/mo. Disk + tunnel + logs unaffected.

---

## 4. Incidents

### 4.1 Site down — first 5 minutes

```
1. Cloudflare down?              → https://www.cloudflarestatus.com/
2. Tunnel disconnected?          → §4.5
3. VM running?                   → §4.6
4. Containers up + healthy?      → §3.4 logs / docker ps
5. DB issue?                     → §4.2
6. Disk full?                    → §5.4 (df -h)
```

Quick triage one-liner:

```bash
gcloud compute ssh flowitup-folio-prod-1 --tunnel-through-iap --zone=europe-west1-b -- '
echo "=== docker ps ==="; sudo docker ps
echo "=== disk ==="; df -h | grep -E "/$|/var/lib/docker"
echo "=== cloudflared ==="; sudo systemctl is-active cloudflared
echo "=== api errors (last 20) ==="; sudo docker logs folio-api-1 --tail=20 2>&1 | grep -i error | tail -10
'
```

### 4.2 Database recovery (point-in-time)

⚠️ **RPO target = 24 h** (last successful `pg_dump`). WAL archiving was
explicitly dropped in Phase 7 — cannot recover to a sub-day point.

**Restore latest dump:**

```bash
gcloud compute ssh flowitup-folio-prod-1 --tunnel-through-iap --zone=europe-west1-b -- '
# 1. Pick a dump
sudo gcloud storage ls gs://flowitup-folio-prod-backups/pg-dumps/

# 2. Download
sudo gcloud storage cp gs://flowitup-folio-prod-backups/pg-dumps/2026-05-03.dump /tmp/restore.dump

# 3. Stop writers
cd /opt/folio
sudo docker compose -f docker-compose.yml -f docker-compose.prod.yml stop api worker

# 4. Drop + recreate DB
PG_USER=$(sudo grep ^POSTGRES_USER= /opt/folio/.env | cut -d= -f2-)
PG_DB=$(sudo grep ^POSTGRES_DB= /opt/folio/.env | cut -d= -f2-)
sudo docker exec folio-db-1 psql -U "$PG_USER" -d postgres -c "DROP DATABASE IF EXISTS $PG_DB;"
sudo docker exec folio-db-1 psql -U "$PG_USER" -d postgres -c "CREATE DATABASE $PG_DB;"

# 5. Restore (schema is part of -Fc dump; no separate migration step)
sudo docker exec -i folio-db-1 pg_restore -U "$PG_USER" -d "$PG_DB" \
  --no-owner --no-privileges < /tmp/restore.dump

# 6. Restart writers
sudo docker compose -f docker-compose.yml -f docker-compose.prod.yml start api worker
sudo rm -f /tmp/restore.dump

# 7. Verify
curl -s https://folio.flowitup.com/health
'
```

### 4.3 MinIO data recovery

Backup mirror lives at `gs://flowitup-folio-prod-backups/minio-mirror/<bucket>/`.
For a single-object restore:

```bash
gcloud storage cp \
  gs://flowitup-folio-prod-backups/minio-mirror/folio-prod-uploads/path/to/file.png \
  /tmp/recovered.png

gcloud compute ssh flowitup-folio-prod-1 --tunnel-through-iap --zone=europe-west1-b -- '
sudo gcloud storage cp /tmp/recovered.png /tmp/recovered.png
S3_KEY=$(sudo grep ^S3_ACCESS_KEY= /opt/folio/.env | cut -d= -f2-)
S3_SEC=$(sudo grep ^S3_SECRET_KEY= /opt/folio/.env | cut -d= -f2-)
sudo docker run --rm --network host \
  -v /tmp:/host \
  -e MC_HOST_minio="http://${S3_KEY}:${S3_SEC}@127.0.0.1:9000" \
  minio/mc:latest cp /host/recovered.png minio/folio-prod-uploads/path/to/file.png
'
```

For a full bucket restore: `mc mirror` from `gcs/` alias to `minio/` alias
(reverse of the daily backup direction).

### 4.4 VM lost — full rebuild

```bash
# 1. Find latest snapshots
gcloud compute snapshots list --filter='sourceDiskName ~ flowitup-folio-prod' \
  --format='table(name,sourceDiskName,creationTimestamp)' --sort-by=~creationTimestamp

# 2. Recreate disks from snapshots
gcloud compute disks create flowitup-folio-prod-1-restore \
  --source-snapshot=<boot-snapshot-name> --zone=europe-west1-b
gcloud compute disks create flowitup-folio-prod-data-restore \
  --source-snapshot=<data-snapshot-name> --zone=europe-west1-b

# 3. Re-provision the VM (edit provision-vm.sh disk attachment first)
./infra/gcp/provision-vm.sh

# 4. Re-run startup.sh (idempotent — installs cloudflared, ops-agent, etc.)
gcloud compute scp infra/gcp/cloud-init/startup.sh <new-vm>:/tmp/ \
  --tunnel-through-iap --zone=europe-west1-b
gcloud compute ssh <new-vm> --tunnel-through-iap --zone=europe-west1-b -- 'sudo bash /tmp/startup.sh'

# 5. Restore /etc/cloudflared/{credentials.json,cert.pem} from password manager

# 6. Re-render .env
gcloud compute ssh <new-vm> --tunnel-through-iap --zone=europe-west1-b -- \
  'sudo systemctl start folio-render-env.service'

# 7. Pull + up
gcloud compute ssh <new-vm> --tunnel-through-iap --zone=europe-west1-b -- '
cd /opt/folio
sudo IMAGE_TAG=latest docker compose -f docker-compose.yml -f docker-compose.prod.yml \
  --env-file=.env pull
sudo IMAGE_TAG=latest docker compose -f docker-compose.yml -f docker-compose.prod.yml \
  --env-file=.env up -d --no-build
'
```

RTO target: ~30–45 min including DNS / CF propagation. Drill quarterly
(Phase 10).

### 4.5 Cloudflare tunnel disconnected

Symptoms: site returns Cloudflare 502 (origin unreachable) but VM is up.

```bash
gcloud compute ssh flowitup-folio-prod-1 --tunnel-through-iap --zone=europe-west1-b -- '
sudo systemctl status cloudflared --no-pager | head -10
sudo journalctl -u cloudflared -n 20 --no-pager
sudo systemctl restart cloudflared
sleep 3
sudo cloudflared tunnel info flowitup-folio-prod
'
```

If creds are missing on disk: copy `cert.pem` + `credentials.json` from
password manager → `/etc/cloudflared/` → restart.

### 4.6 VM not responding

```bash
gcloud compute instances describe flowitup-folio-prod-1 --zone=europe-west1-b \
  --format='value(status)'   # expect: RUNNING

gcloud compute instances reset flowitup-folio-prod-1 --zone=europe-west1-b
sleep 90
gcloud compute ssh flowitup-folio-prod-1 --tunnel-through-iap --zone=europe-west1-b
```

Containers come back automatically (`restart: unless-stopped`).

---

## 5. Maintenance

### 5.1 Rotate a secret

```bash
./infra/gcp/secret-manager/seed.sh --rotate folio-<key-name>

gcloud compute ssh flowitup-folio-prod-1 --tunnel-through-iap --zone=europe-west1-b -- '
sudo systemctl start folio-render-env.service
cd /opt/folio
sudo IMAGE_TAG=latest docker compose -f docker-compose.yml -f docker-compose.prod.yml \
  --env-file=.env up -d --force-recreate
'
```

⚠️ Rotating `folio-postgres-password` or `folio-s3-{access,secret}-key`
requires updating the existing volume's stored credentials FIRST (e.g.
`ALTER USER folio PASSWORD '…';` inside Postgres). For database creds:
update in DB, THEN push the new SM value, THEN re-render.

### 5.2 Rotate GCS HMAC keys (for backup-sa)

```bash
# 1. Mint new pair
gcloud storage hmac create backup-sa@flowitup-folio-prod.iam.gserviceaccount.com \
  --project=flowitup-folio-prod
# Copy the access ID + secret from output

# 2. Push to SM
./infra/gcp/secret-manager/seed.sh --rotate folio-gcs-hmac-access-key
./infra/gcp/secret-manager/seed.sh --rotate folio-gcs-hmac-secret-key

# 3. Re-render env (mc-mirror reads /opt/folio/.env each cron tick — no restart needed)
gcloud compute ssh flowitup-folio-prod-1 --tunnel-through-iap --zone=europe-west1-b -- \
  'sudo systemctl start folio-render-env.service'

# 4. Disable the OLD pair, verify backups still work, then delete
gcloud storage hmac update <old-access-id> --deactivate --project=flowitup-folio-prod
# wait 24h, verify pg-dump + minio-mirror cron success in journalctl, then:
gcloud storage hmac delete <old-access-id> --project=flowitup-folio-prod
```

### 5.3 Verify backups are working

```bash
# Today's pg-dump (should exist by 03:05 UTC)
gcloud storage ls -l gs://flowitup-folio-prod-backups/pg-dumps/$(date -u +%F).dump

# Cron history
gcloud compute ssh flowitup-folio-prod-1 --tunnel-through-iap --zone=europe-west1-b -- '
sudo journalctl -t pg-dump -t minio-mirror --since "today" --no-pager
sudo journalctl -t backup-verify --since "last week" --no-pager | tail -20
'
```

### 5.4 Disk space check

The disk-usage alert fires at 85%. Investigate:

```bash
gcloud compute ssh flowitup-folio-prod-1 --tunnel-through-iap --zone=europe-west1-b -- '
df -h | grep -E "/$|/var/lib/docker"
sudo du -sh /var/lib/docker/* 2>/dev/null | sort -h | tail -10
sudo du -sh /var/log/* 2>/dev/null | sort -h | tail -5
sudo docker system df
'
```

Common bloat: old Docker images (auto-pruned weekly via
`/etc/cron.weekly/folio-image-prune`), Postgres WAL (autovacuum), MinIO
uploads.

### 5.5 Quarterly restore drill

See [Phase 10 plan](../plans/260429-2303-gcp-single-vm-deploy/phase-10-restore-drill.md).
Every quarter, ~30 min:

1. Pick a random pg-dump from the last 30 days
2. Restore into a sidecar container (steps mirror §4.2 1-5)
3. Sanity query (e.g. `SELECT count(*) FROM users WHERE email='admin@flowitup.com'` → 1)
4. Tear down sidecar
5. Log result in `docs/journals/` with date + outcome

If the drill ever fails: investigate immediately — backup is the only
safety net for a single-VM Postgres.

### 5.6 Cost review

Monthly check (~5 min):

```bash
open "https://console.cloud.google.com/billing?project=flowitup-folio-prod"
```

Expected line items (~$80/mo, with $100 AI Ultra credit ≈ $0):

| Item | $/mo |
|---|---|
| e2-standard-2 (730 h) | ~50 |
| pd-balanced 80 GB total | ~10 |
| Snapshots (4 weekly × ~80 GB compressed) | ~5 |
| Egress | ~2 |
| Logging + monitoring | free tier |
| Storage (backups, < 1 GB initially) | <1 |
| Artifact Registry | <1 |

If anything > 2× expected: investigate Logs ingest (>10 GB/mo = config
bug) or egress (>10 GB/mo = something odd).

---

## 6. Escalation

### Self-serve

| Symptom | Resource |
|---|---|
| GCP service issue | https://status.cloud.google.com/ |
| Cloudflare issue | https://www.cloudflarestatus.com/ |
| Resend delivery issue | https://resend.com/status |
| Gunicorn / Flask app errors | Cloud Logging filter §3.4 |
| RQ worker stalled | Restart worker container; check Redis connectivity |

### Contacts

| Role | Contact |
|---|---|
| Project owner | mt.bui.fr@gmail.com |
| GCP billing admin | mtbui.creative@gmail.com |
| Domain (Cloudflare) | mtbui.creative@gmail.com |
| Resend account | mtbui.creative@gmail.com |

### Vendors

| Vendor | Reason | Plan |
|---|---|---|
| GCP | All infra | Pay-as-you-go (currently inside $100 AI Ultra credit) |
| Cloudflare | DNS, WAF, Tunnel, CDN | Free tier |
| Resend | Transactional email | Free tier (~100/day, 1 verified domain) |

### Out-of-scope (deferred)

- Multi-region / HA failover — would require Option B/C re-architecture
- Cloud SQL / managed Postgres — when DB scare or paying-customer count
  justifies $30/mo
- Datadog / Honeycomb APM — out of budget; current Cloud Monitoring + Cloud
  Logging is the v1 ceiling
- WAL archiving / sub-24h RPO — explicitly dropped in Phase 7. Revisit when
  data loss tolerance changes

---

## Appendix A — Phase → file map

| Phase | What it set up | Plan file |
|---|---|---|
| 1 | GCP project, APIs, AR, buckets, SAs, IAM | `phase-01-gcp-bootstrap.md` |
| 2 | VM + data disk + IAP-only firewall | `phase-02-vm-provisioning.md` |
| 3 | VM bootstrap (Docker, cloudflared, hardening) | `phase-03-vm-bootstrap.md` |
| 4 | Cloudflare DNS + Tunnel + page rules | `phase-04-cloudflare-wiring.md` |
| 5 | CI/CD workflow templates | `phase-05-ci-cd-pipeline.md` |
| 6 | Secret Manager seed + render-env unit | `phase-06-secrets-management.md` |
| 7 | Backup scripts + cron + snapshot policy | `phase-07-backup-strategy.md` |
| 8 | Ops Agent + uptime check + 2 alerts | `phase-08-observability.md` |
| 9 | First production deploy + smoke tests | `phase-09-first-deploy.md` |
| 10 | Restore drill (quarterly cadence) | `phase-10-restore-drill.md` |
| 11 | This runbook | `phase-11-runbook.md` |

## Appendix B — Anti-patterns we explicitly avoided

- ❌ **Public SSH on the VM** — IAP-only. Default-allow-ssh VPC rule was
  deleted in Phase 2.
- ❌ **0.0.0.0 port bindings on api/db/redis/minio** — Phase 3 prod compose
  binds all to `127.0.0.1` only.
- ❌ **Default credentials with `:-default` fallbacks** — prod compose uses
  `${VAR:?required}` to fail-fast on missing env.
- ❌ **vm-runtime-sa writing to backups** — write goes through `backup-sa`
  via impersonation. Compromised app cannot wipe backups.
- ❌ **`mc mirror --remove`** — would propagate source corruption into
  backups within 24 h.
- ❌ **Snap-installed gcloud on a server** — replaced with apt build (snap
  + hardened systemd is fragile).
- ❌ **Static IP / public 80/443** — Cloudflare Tunnel is outbound-only.
- ❌ **Commit-time secrets in repo** — all 20 prod secrets live in Secret
  Manager only; `.env` is rendered on the VM by a systemd unit.

---

*This document is the single source of operational truth. PRs that change
deployment, networking, or backups MUST update this guide as part of the
same change. Tabletop walk-throughs are recommended quarterly.*
