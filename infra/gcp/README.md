# GCP Infrastructure

Idempotent provisioning of the `flowitup-folio-prod` GCP environment, phase by phase. All scripts are safe to re-run.

**Plan root:** [`plans/260429-2303-gcp-single-vm-deploy/`](../../plans/260429-2303-gcp-single-vm-deploy/)

| Phase | Script / file | What it does |
|---|---|---|
| 1 | `bootstrap.sh` | Project, billing, APIs, Artifact Registry, backup buckets, 3 service accounts |
| 2 | `provision-vm.sh` + `firewall.sh` | VM, persistent data disk, IAP-only firewall (no 80/443) |
| 3 | `cloud-init/startup.sh` + `../../docker-compose.prod.yml` | Format/mount data disk at `/var/lib/docker`, install Docker + cloudflared, harden SSH, prod compose override (127.0.0.1 binds, `:?required` env) |
| 4 | `../cloudflare/cloudflared-config.yml` + `../cloudflare/page-rules.md` | Cloudflare Tunnel ingress, proxied CNAME, page rules, WAF baseline, Resend DNS records |
| 5 | `../ci-templates/deploy-{api,frontend}.yml` + `../../scripts/deploy/*.sh` | GitHub Actions → AR push → IAP-tunneled deploy → migrations → health check + CF cache purge (frontend) |
| 6 | `secret-manager/seed.sh` + `scripts/render-env.sh` + `cloud-init/folio-render-env.service` | Seed 20 SM keys, render `/opt/folio/.env` on demand (no timer per Y2), per-secret IAM bindings |

---

## Phase 1 — Bootstrap

Project + billing + APIs + Artifact Registry + GCS backup buckets + 3 least-privilege service accounts.

**Phase doc:** [`phase-01-gcp-bootstrap.md`](../../plans/260429-2303-gcp-single-vm-deploy/phase-01-gcp-bootstrap.md)

## Prerequisites

- `gcloud` CLI installed (`gcloud --version` ≥ 470).
- Authenticated as a user with **Project Creator** + **Billing Account User** on the AI Ultra billing account: `gcloud auth login`.
- Application default creds for impersonation: `gcloud auth application-default login`.
- Billing account ID handy: `gcloud beta billing accounts list`.

## Inputs

| Var | Default | Required |
|---|---|---|
| `BILLING_ACCOUNT` | — | **yes** (format: `XXXXXX-XXXXXX-XXXXXX`) |
| `PROJECT_ID` | `flowitup-folio-prod` | no |
| `REGION` | `europe-west1` | no |
| `ADMIN_EMAIL` | `mt.bui.fr@gmail.com` | no |

## Run

```bash
BILLING_ACCOUNT=XXXXXX-XXXXXX-XXXXXX ./infra/gcp/bootstrap.sh
```

Re-running is safe — every step checks for existing resources before creating.

### One-time key minting

These flags create credentials and **must not** run on every invocation:

```bash
# After first run: mint deploy-sa JSON key. Script writes it to a tempdir (mode 700)
# and prints the path. Paste contents into GitHub secret GCP_SA_KEY, then shred.
./infra/gcp/bootstrap.sh --rotate-deploy-key

# Mint GCS HMAC keys for backup-sa (mc/MinIO carve-out). Use during phase 6 secret seeding.
./infra/gcp/bootstrap.sh --rotate-hmac
```

After pasting into GitHub secrets / Secret Manager, follow the `shred` command the
script prints (uses `mktemp` location, not the worktree).

## What it creates

| Resource | Detail |
|---|---|
| Project | `flowitup-folio-prod` |
| Billing link | AI Ultra billing account |
| APIs (8) | compute, artifactregistry, secretmanager, storage, logging, monitoring, iap, billingbudgets |
| Budget alert | `$100/mo` with 50/80/100/120% thresholds → billing admin email |
| Artifact Registry | `europe-west1-docker.pkg.dev/flowitup-folio-prod/folio` (docker format) |
| Bucket: primary | `gs://flowitup-folio-prod-backups` — versioned, 30-day lifecycle on noncurrent, 7-day retention lock, UBLA |
| Bucket: archive | `gs://flowitup-folio-prod-backups-archive` — 365-day retention lock, UBLA |
| `deploy-sa` | `artifactregistry.writer`, `iap.tunnelResourceAccessor`, `compute.osLogin` |
| `vm-runtime-sa` | `artifactregistry.reader`, `logging.logWriter`, `monitoring.metricWriter`, `iam.serviceAccountTokenCreator` on `backup-sa` |
| `backup-sa` | `storage.objectCreator` on backup buckets only — append-only |

`vm-runtime-sa` does **not** have GCS write to backup buckets. Backup scripts impersonate `backup-sa` from the VM. A VM compromise cannot wipe backups.

`vm-runtime-sa`'s `roles/secretmanager.secretAccessor` is bound **per-secret** during phase 6 secret seeding, not project-wide.

## Verify (success criteria)

```bash
# Project + billing
gcloud projects describe flowitup-folio-prod
gcloud beta billing projects describe flowitup-folio-prod

# APIs
gcloud services list --enabled --filter='config.name~(compute|artifactregistry|secretmanager|storage|logging|monitoring|iap|billingbudgets)\.googleapis\.com'

# Budget
gcloud billing budgets list --billing-account="$BILLING_ACCOUNT"

# Artifact Registry
gcloud artifacts repositories list --location=europe-west1

# Buckets — confirm retention + UBLA + versioning
gcloud storage buckets describe gs://flowitup-folio-prod-backups \
  --format='value(retentionPolicy.retentionPeriod,iamConfiguration.uniformBucketLevelAccess.enabled,versioning.enabled)'
gcloud storage buckets describe gs://flowitup-folio-prod-backups-archive \
  --format='value(retentionPolicy.retentionPeriod,iamConfiguration.uniformBucketLevelAccess.enabled)'

# Service accounts
gcloud iam service-accounts list --filter='email~(deploy|vm-runtime|backup)-sa@flowitup-folio-prod\.iam'

# Confirm vm-runtime-sa has NO write on backup buckets
gcloud storage buckets get-iam-policy gs://flowitup-folio-prod-backups --format=json | \
  jq '.bindings[] | select(.members[] | contains("vm-runtime-sa"))'
# ↑ should print nothing

# Confirm backup-sa is objectCreator only
gcloud storage buckets get-iam-policy gs://flowitup-folio-prod-backups --format=json | \
  jq '.bindings[] | select(.members[] | contains("backup-sa")) | .role'
# ↑ should print only "roles/storage.objectCreator"
```

## After phase 1

1. Run `--rotate-deploy-key`, paste JSON into GitHub repo secret `GCP_SA_KEY`, delete file.
2. Move on to phase 2 (VM provisioning). HMAC keys come later in phase 6.

## Service account map

See `iam-policies/*.yaml` for the canonical role list per SA. Those YAMLs are documentation/audit input — `bootstrap.sh` applies the same bindings imperatively.

| SA | Used by | Key |
|---|---|---|
| `deploy-sa` | GitHub Actions | JSON key in `GCP_SA_KEY` secret |
| `vm-runtime-sa` | prod VM | none (VM-attached) |
| `backup-sa` | nightly backup cron via impersonation | GCS HMAC (Secret Manager) |

## Common failures

| Symptom | Cause | Fix |
|---|---|---|
| `Project ID already in use` | Project name globally unique across GCP | Pick a unique `PROJECT_ID`; update plan and re-run. |
| `BILLING_ACCOUNT_NOT_FOUND` | Wrong billing ID format | `gcloud beta billing accounts list` to copy the ID exactly. |
| `retention policy is locked` warning | Re-running after retention is locked | Expected — script swallows the error and continues. |
| Budget create says "permission denied" | Caller lacks `Billing Account Costs Manager` | Add the role on the billing account, retry. |
| `services enable` hangs | Newly created project, propagation delay | Wait 30s and re-run; idempotent. |

---

## Phase 2 — VM Provisioning

Single `e2-standard-2` VM in `europe-west1-b`, 30 GB boot + 50 GB persistent data disk, IAP-only ingress (no public 22/80/443). Cloudflare Tunnel handles HTTP via outbound from `cloudflared` — phase 4 wires it.

**Phase doc:** [`phase-02-vm-provisioning.md`](../../plans/260429-2303-gcp-single-vm-deploy/phase-02-vm-provisioning.md)

### Prereqs

- Phase 1 complete (`vm-runtime-sa` exists). `provision-vm.sh` aborts otherwise.
- gcloud authenticated against `flowitup-folio-prod`.

### Run

```bash
./infra/gcp/provision-vm.sh    # VM + persistent data disk
./infra/gcp/firewall.sh        # IAP SSH rule + audit (fails if 0.0.0.0/0 ingress found)
```

Both safe to re-run. The data disk is **not** formatted/mounted by phase 2 — phase 3 cloud-init handles that. Inside the VM the disk appears as `/dev/disk/by-id/google-folio-data`.

### Defaults

| Var | Default |
|---|---|
| `VM_NAME` | `flowitup-folio-prod-1` |
| `ZONE` | `europe-west1-b` |
| `MACHINE_TYPE` | `e2-standard-2` (2 vCPU, 8 GB) |
| `IMAGE_FAMILY` / `IMAGE_PROJECT` | `ubuntu-2404-lts-amd64` / `ubuntu-os-cloud` |
| `BOOT_DISK_SIZE_GB` | `30` |
| `DATA_DISK_NAME` / `DATA_DISK_SIZE_GB` | `flowitup-folio-prod-data` / `50` |
| `DISK_TYPE` | `pd-balanced` |

### Verify (success criteria)

```bash
# VM running
gcloud compute instances list --filter='name=flowitup-folio-prod-1' \
  --format='table(name,zone.basename(),status,labels.folio_env)'

# Data disk attached, auto-delete=False (one row per disk)
gcloud compute instances describe flowitup-folio-prod-1 --zone=europe-west1-b \
  --flatten='disks[]' --format='table(disks.deviceName,disks.autoDelete,disks.boot)'
# expect: folio-data | False | False

# Deletion protection
gcloud compute instances describe flowitup-folio-prod-1 --zone=europe-west1-b \
  --format='value(deletionProtection)'   # → True

# IAP SSH works
gcloud compute ssh flowitup-folio-prod-1 --tunnel-through-iap --zone=europe-west1-b \
  --command='echo ok && uname -a'

# Firewall: only allow-iap-ssh, no world-open ingress
./infra/gcp/firewall.sh --audit-only
```

### Common failures

| Symptom | Cause | Fix |
|---|---|---|
| `Required permission compute.instances.create` | Caller lacks Compute Admin | `gcloud projects add-iam-policy-binding flowitup-folio-prod --member=user:YOU --role=roles/compute.admin` |
| OS Login SSH refuses with `Permission denied (publickey)` | First IAP SSH on new project | Run `gcloud compute os-login ssh-keys add --key-file=$HOME/.ssh/id_ed25519.pub` once. |
| `enable-oslogin` warning during create | Project metadata also needed | `gcloud compute project-info add-metadata --metadata enable-oslogin=TRUE` |
| `DATA_DISK_NAME exists, auto-delete=True` | Disk attached interactively previously | Script auto-corrects on re-run (set-disk-auto-delete --no-auto-delete). |
| `firewall.sh` exits 1 with "world-open ingress found" | Pre-existing rule allows 0.0.0.0/0 | Review listed rules; remove (`gcloud compute firewall-rules delete <name>`) if from a prior project. |

---

## Phase 3 — VM Bootstrap

OS-level setup on the running VM: format/mount the 50 GB data disk at `/var/lib/docker`, install Docker Engine + compose plugin, install `cloudflared` (configured in phase 4), harden SSH, enable security-only unattended-upgrades, weekly `docker image prune`. NO `fail2ban` (Y1: no public SSH on Tunnel-only deploy).

**Phase doc:** [`phase-03-vm-bootstrap.md`](../../plans/260429-2303-gcp-single-vm-deploy/phase-03-vm-bootstrap.md)

### Prereqs

- Phase 2 complete (VM running, IAP SSH works).
- The VM's data disk visible inside as `/dev/disk/by-id/google-folio-data` — verify via the smoke-test in Phase 2's verify section.

### Run

```bash
# 1. Copy the bootstrap script to the VM via IAP
gcloud compute scp infra/gcp/cloud-init/startup.sh \
  flowitup-folio-prod-1:/tmp/startup.sh \
  --tunnel-through-iap --zone=europe-west1-b \
  --ssh-key-file=$HOME/.ssh/gcp_ed25519

# 2. Execute as root
gcloud compute ssh flowitup-folio-prod-1 --tunnel-through-iap \
  --zone=europe-west1-b \
  --ssh-key-file=$HOME/.ssh/gcp_ed25519 \
  -- 'sudo bash /tmp/startup.sh'
```

The script is **idempotent** — re-run it any time to reconcile drift (re-applies daemon.json, sshd hardening, cron, etc.).

### One-time per OS Login user

After bootstrap, your OS-Login-derived user needs `docker` group membership to run `docker` without `sudo`:

```bash
gcloud compute ssh flowitup-folio-prod-1 --tunnel-through-iap \
  --zone=europe-west1-b --ssh-key-file=$HOME/.ssh/gcp_ed25519 \
  -- 'sudo usermod -aG docker $USER'

# Log out and back in to refresh group membership; verify with:
gcloud compute ssh flowitup-folio-prod-1 --tunnel-through-iap \
  --zone=europe-west1-b --ssh-key-file=$HOME/.ssh/gcp_ed25519 \
  -- 'docker info | grep "Docker Root Dir"'
# expect: Docker Root Dir: /var/lib/docker
```

Phase 5 (CI) repeats this for `deploy-sa`'s OS Login user.

### Stage the prod compose override

```bash
# Copy docker-compose.yml + docker-compose.prod.yml to /opt/folio on the VM
gcloud compute scp docker-compose.yml docker-compose.prod.yml \
  flowitup-folio-prod-1:/tmp/ \
  --tunnel-through-iap --zone=europe-west1-b \
  --ssh-key-file=$HOME/.ssh/gcp_ed25519
gcloud compute ssh flowitup-folio-prod-1 --tunnel-through-iap \
  --zone=europe-west1-b --ssh-key-file=$HOME/.ssh/gcp_ed25519 \
  -- 'sudo install -m 644 /tmp/docker-compose*.yml /opt/folio/'
```

`docker compose up` is **deferred to phase 9** (after secrets are seeded in phase 6 and CI is wired in phase 5).

### Verify (success criteria)

```bash
# Inside the VM (via IAP SSH):
docker info | grep -E 'Docker Root Dir|Live Restore'
# expect: /var/lib/docker, Live Restore Enabled: true

df -h /var/lib/docker            # ~49G total (50 GB pd-balanced minus fs overhead)
docker compose version --short   # ≥ 2.20

# SSH hardening drop-in active
sudo sshd -T | grep -E 'permitrootlogin|passwordauthentication'
# expect: permitrootlogin no, passwordauthentication no

# Compose prod override fails fast on missing creds
cd /opt/folio && docker compose -f docker-compose.yml -f docker-compose.prod.yml config 2>&1 | head -3
# expect: error mentioning POSTGRES_USER (or any required env var) is required

# No 0.0.0.0 ports — only loopback or none (after phase 9 brings stack up)
ss -tlnp 2>/dev/null | awk 'NR>1 && $4 !~ /^127\.0\.0\.1:/ && $4 !~ /^\[::1\]:/ {print}'
# expect: no rows (OS Login's sshd on 22 is filtered out by IAP firewall, not by ss)
```

### Common failures

| Symptom | Cause | Fix |
|---|---|---|
| `data disk /dev/disk/by-id/google-folio-data not present` | Disk attached after VM boot, or device-name typo | Re-run `provision-vm.sh`; reboot VM (`sudo reboot`) and re-run startup. |
| `mkfs.ext4` aborts with "appears to contain a filesystem" | Disk already formatted from a prior run | Expected — script's `blkid` check skips re-format. If you really want to wipe: `wipefs -a /dev/disk/by-id/google-folio-data` (DESTRUCTIVE). |
| `docker info` shows `/var/lib/docker` but disk usage tiny | Mount happened AFTER Docker created files | Stop docker, `mv /var/lib/docker /var/lib/docker.old`, mount disk, `cp -a /var/lib/docker.old/* /var/lib/docker/`, restart docker. (Shouldn't occur — script orders mount before docker install.) |
| `docker compose -f ... -f ... config` succeeds with empty values | `:?required` not failing | Compose < v2.20 — upgrade via `apt-get install --only-upgrade docker-compose-plugin`. |
| `cloudflared` install 404 | apt repo path drift | `cat /etc/apt/sources.list.d/cloudflared.list`; check codename matches `lsb_release -cs`. |

### Open verification — when `folio-back-end` submodule populates

Two assumptions in `docker-compose.prod.yml` need confirming against actual app code before Phase 9:

- **`JWT_SECRET_KEY` required** — Red Team #4 flagged a naming mismatch. If the back-end uses only `SECRET_KEY` and no `JWT_SECRET_KEY`, drop the latter from the override (it'd block compose-up unnecessarily).
- **`worker` S3 env vars** — base compose's `worker` defines no `S3_*`. If RQ jobs touch attachments (likely, given an `S3AttachmentStorage` reference in the plan), worker needs the same `S3_ACCESS_KEY` / `S3_SECRET_KEY` / `S3_ENDPOINT_URL` / `S3_BUCKET` block as `api`. Add to the override under `services.worker.environment` when verified.

---

## Phase 4 — Cloudflare Wiring

Tunnel-only ingress: `cloudflared` daemon on the VM connects OUTBOUND to Cloudflare; no inbound 80/443. DNS via proxied CNAME, page-rule cache for `_next/static/*`, WAF baseline, Resend SPF/DKIM/DMARC for outbound mail.

**Phase doc:** [`phase-04-cloudflare-wiring.md`](../../plans/260429-2303-gcp-single-vm-deploy/phase-04-cloudflare-wiring.md)
**Operator runbook:** [`../cloudflare/page-rules.md`](../cloudflare/page-rules.md) — full step-by-step (tunnel login, copy creds, systemd install, DNS, page rules, WAF, Resend records, ProxyFix TODO, verify, common failures).
**Daemon config:** [`../cloudflare/cloudflared-config.yml`](../cloudflare/cloudflared-config.yml) — installed at `/etc/cloudflared/config.yml`.

### Quick path

```bash
# laptop
brew install cloudflared
cloudflared tunnel login                                  # browser → authorize flowitup.com
cloudflared tunnel create flowitup-folio-prod             # captures UUID + creds JSON
cloudflared tunnel route dns flowitup-folio-prod folio.flowitup.com   # creates proxied CNAME

# copy creds + config to VM, install systemd unit
# → see infra/cloudflare/page-rules.md sections 1c–1d for the exact commands
```

After the tunnel is up: configure page rules, WAF, and Resend DNS via the Cloudflare dashboard per [`page-rules.md`](../cloudflare/page-rules.md) sections 2–4.

### Out-of-scope until back-end submodule populates

The Red Team `ProxyFix` + `CF-Connecting-IP`-aware rate-limiter code change in `folio-back-end` is documented in [`page-rules.md` § 5](../cloudflare/page-rules.md#5-proxyfix-code-change--todo--back-end-submodule). Cannot be applied here (submodule is empty in this checkout). Phase 9 smoke test verifies it.

---

## Phase 5 — CI/CD Pipeline

GitHub Actions in each submodule build → push → IAP-tunneled deploy. Worker shares the api image (Y5). Frontend deploy ends with a Cloudflare cache purge. No `DEPLOY_SSH_KEY` — `deploy-sa` authenticates via OS Login over IAP.

**Phase doc:** [`phase-05-ci-cd-pipeline.md`](../../plans/260429-2303-gcp-single-vm-deploy/phase-05-ci-cd-pipeline.md)
**Workflow templates:** [`../ci-templates/deploy-api.yml`](../ci-templates/deploy-api.yml) (→ `folio-back-end/.github/workflows/`), [`../ci-templates/deploy-frontend.yml`](../ci-templates/deploy-frontend.yml) (→ `folio-front-end/.github/workflows/`)
**VM-side scripts:** [`../../scripts/deploy/`](../../scripts/deploy/) — `deploy-runner.sh`, `wait-healthy.sh`, `rollback.sh`

### Architecture

```
push → folio-back-end (or folio-front-end) main
  └─ GitHub Actions (ubuntu-latest)
     ├─ google-github-actions/auth (GCP_SA_KEY)
     ├─ docker build + push → AR (tags: $SHA, latest)
     └─ gcloud compute ssh --tunnel-through-iap --command="/opt/folio/scripts/deploy-runner.sh $SHA $SVC"
                              │
                              ▼
                        VM (deploy-sa OS Login user, in docker group)
                          deploy-runner.sh:
                            1. compose pull $SVC (and worker if api)
                            2. flask db upgrade  (api only, before traffic swap)
                            3. compose up -d --no-deps $SVC
                            4. wait-healthy.sh $SVC
                          [frontend only, back in CI:]
                          5. POST api.cloudflare.com/.../purge_cache
```

### One-time wiring (operator)

```bash
# 1. Stage VM-side scripts (compose files were staged in phase 3)
gcloud compute scp scripts/deploy/deploy-runner.sh \
                   scripts/deploy/wait-healthy.sh \
                   scripts/deploy/rollback.sh \
  flowitup-folio-prod-1:/tmp/ \
  --tunnel-through-iap --zone=europe-west1-b \
  --ssh-key-file=$HOME/.ssh/gcp_ed25519
gcloud compute ssh flowitup-folio-prod-1 --tunnel-through-iap \
  --zone=europe-west1-b --ssh-key-file=$HOME/.ssh/gcp_ed25519 -- '
  sudo install -d -m 755 /opt/folio/scripts &&
  sudo install -m 755 /tmp/deploy-runner.sh  /opt/folio/scripts/ &&
  sudo install -m 755 /tmp/wait-healthy.sh   /opt/folio/scripts/ &&
  sudo install -m 755 /tmp/rollback.sh       /opt/folio/scripts/ &&
  rm /tmp/deploy-runner.sh /tmp/wait-healthy.sh /tmp/rollback.sh'

# 2. Trigger ONE deploy from CI to create the deploy-sa OS Login user on the VM,
#    then add it to the docker group. (User name is "sa_<numeric-id>".)
#    Find the user after the first deploy attempt (which will fail at docker pull):
gcloud compute ssh flowitup-folio-prod-1 --tunnel-through-iap \
  --zone=europe-west1-b --ssh-key-file=$HOME/.ssh/gcp_ed25519 -- '
  awk -F: "/^sa_[0-9]+/ {print \$1}" /etc/passwd'
# → expect output like: sa_106349873262834567890
# Add it to docker group:
gcloud compute ssh flowitup-folio-prod-1 --tunnel-through-iap \
  --zone=europe-west1-b --ssh-key-file=$HOME/.ssh/gcp_ed25519 -- \
  'sudo usermod -aG docker sa_106349873262834567890'   # ← substitute real ID

# 3. In each submodule's GitHub repo (folio-back-end, folio-front-end):
#    Settings → Secrets and variables → Actions → New repository secret
#       GCP_SA_KEY     → contents of deploy-sa-key.json (from `bootstrap.sh --rotate-deploy-key`)
#       CF_API_TOKEN   → CF dashboard → My Profile → API Tokens → Create (zone-scoped, Cache Purge:Edit only)
#       CF_ZONE_ID     → CF dashboard → flowitup.com → Overview → API → Zone ID
#    Then copy the workflow template into .github/workflows/:
#       cp infra/ci-templates/deploy-api.yml      → folio-back-end/.github/workflows/deploy-api.yml
#       cp infra/ci-templates/deploy-frontend.yml → folio-front-end/.github/workflows/deploy-frontend.yml
```

### Verify (after first successful deploy from CI)

```bash
# CI logs: build + push + IAP SSH all green; deploy-runner.sh logs end with "deploy ok"
# On the VM:
gcloud compute ssh flowitup-folio-prod-1 --tunnel-through-iap \
  --zone=europe-west1-b --ssh-key-file=$HOME/.ssh/gcp_ed25519 -- '
  docker ps --format "table {{.Names}}\t{{.Image}}\t{{.Status}}" &&
  docker images --format "table {{.Repository}}\t{{.Tag}}\t{{.Size}}" | head -10'
# expect: api + worker images point at AR with the github.sha tag, status "Up X / healthy"
```

### Manual rollback

```bash
gcloud compute ssh flowitup-folio-prod-1 --tunnel-through-iap \
  --zone=europe-west1-b --ssh-key-file=$HOME/.ssh/gcp_ed25519 -- \
  '/opt/folio/scripts/rollback.sh api <previous-sha>'
# Or omit SHA — script picks the previous tag from AR automatically.
```

### Open verification — when back-end submodule populates

- **Migration command** in `deploy-runner.sh` line 41: `docker compose run --rm -e FLASK_APP=wsgi:app api flask db upgrade`. Assumes Flask-Migrate is installed AND the WSGI factory is at `wsgi:app`. If the back-end uses raw alembic (`alembic upgrade head`) or a custom script (`python scripts/migrate.py`), edit deploy-runner line 41 accordingly. Red Team Finding 1 flagged this exact ambiguity — confirm against the back-end Dockerfile / requirements.txt before first prod deploy.
- **Workflow path filters** in both templates list common Python/Next.js project layouts; if the actual submodule structure differs (e.g. `lib/` instead of `src/`), update the `paths:` block so unrelated commits don't trigger deploys.

### Common failures

| Symptom | Cause | Fix |
|---|---|---|
| CI step "Deploy via IAP tunnel" times out | deploy-sa lacks `roles/iap.tunnelResourceAccessor` | Re-run `bootstrap.sh` (it's idempotent) — phase 1 fixes added the role. |
| `permission denied while trying to connect to the Docker daemon socket` in deploy-runner | `sa_<numeric>` user not in docker group | One-time `sudo usermod -aG docker sa_<numeric>` (see "wiring" step 2). |
| `flask db upgrade` errors with "Could not locate a Flask application" | `FLASK_APP` not set or wrong | Confirm `wsgi:app` matches back-end's WSGI module; otherwise edit `deploy-runner.sh` line 41. |
| Frontend deploy succeeds but users see 404 white screen | CF cache purge step failed silently | Re-check CF API token scope (must include "Cache Purge: Edit" for the zone), re-run workflow. |
| `cf-purge.json` returns `"success":false` | Token mis-scoped or zone ID wrong | CF dashboard → API Tokens → token diagnostics; verify zone ID matches the curl URL. |
| `concurrency: group: deploy-prod-backend` queues but never starts | Prior run stuck mid-deploy | Check the running workflow run; cancel manually if hung > 10 min. |

---

## Phase 6 — Secrets Management

20 canonical secrets in Google Secret Manager; `render-env.sh` fetches them at boot (and on-demand during rotation) and writes `/opt/folio/.env` (mode 640, root:docker). No daily timer (Y2 — rewriting `.env` without `compose up -d --force-recreate` doesn't propagate to running containers).

**Phase doc:** [`phase-06-secrets-management.md`](../../plans/260429-2303-gcp-single-vm-deploy/phase-06-secrets-management.md)
**Canonical reference:** [`../../.env.example`](../../.env.example) — all 18 SM-sourced + 6 constants + 2 CF-only-in-GitHub
**Files:** [`secret-manager/seed.sh`](secret-manager/seed.sh), [`scripts/render-env.sh`](scripts/render-env.sh), [`cloud-init/folio-render-env.service`](cloud-init/folio-render-env.service)

### Operator runbook

#### 1. Seed all 20 secrets (one-time, from operator laptop)

```bash
PROJECT_ID=flowitup-folio-prod ./infra/gcp/secret-manager/seed.sh
```

The script prompts for each missing secret, reads with `read -s` (no echo, no shell history), and pipes via stdin to `gcloud secrets create` (no temp file ever exists). Per-secret `vm-runtime-sa` accessor binding is applied automatically.

If a secret already exists, it's skipped. To rotate one:

```bash
./infra/gcp/secret-manager/seed.sh --rotate folio-jwt-secret-key
```

**Two of the 20 keys** (`folio-cf-api-token`, `folio-cf-zone-id`) are mirrored from GitHub Secrets — they exist in SM as a backup but are NOT consumed on the VM (only by Phase 5 frontend deploy workflow's CF purge step). Paste the same value you set in GitHub.

#### 2. Stage scripts on the VM + install systemd unit

```bash
# Copy render-env.sh + systemd unit
gcloud compute scp \
  infra/gcp/scripts/render-env.sh \
  infra/gcp/cloud-init/folio-render-env.service \
  flowitup-folio-prod-1:/tmp/ \
  --tunnel-through-iap --zone=europe-west1-b \
  --ssh-key-file=$HOME/.ssh/gcp_ed25519

# Install + enable
gcloud compute ssh flowitup-folio-prod-1 --tunnel-through-iap \
  --zone=europe-west1-b --ssh-key-file=$HOME/.ssh/gcp_ed25519 -- '
  sudo install -d -m 755 /opt/folio/scripts &&
  sudo install -m 755 /tmp/render-env.sh /opt/folio/scripts/ &&
  sudo install -m 644 /tmp/folio-render-env.service /etc/systemd/system/ &&
  sudo systemctl daemon-reload &&
  sudo systemctl enable folio-render-env.service &&
  sudo rm /tmp/render-env.sh /tmp/folio-render-env.service'
```

#### 3. Render `.env` for the first time

```bash
gcloud compute ssh flowitup-folio-prod-1 --tunnel-through-iap \
  --zone=europe-west1-b --ssh-key-file=$HOME/.ssh/gcp_ed25519 -- '
  sudo systemctl start folio-render-env.service &&
  sudo journalctl -u folio-render-env.service -n 5 --no-pager &&
  sudo ls -la /opt/folio/.env'
# expect: render-env logs "rendered ... keys=24 sha256=xxx…", file at -rw-r----- root:docker
```

### Rotation procedure

1. Update SM secret: `./infra/gcp/secret-manager/seed.sh --rotate <key>` (laptop).
2. Re-render on VM:
   ```bash
   gcloud compute ssh flowitup-folio-prod-1 --tunnel-through-iap \
     --zone=europe-west1-b --ssh-key-file=$HOME/.ssh/gcp_ed25519 \
     -- 'sudo systemctl start folio-render-env.service'
   ```
3. Recreate the consuming containers (NOT just pull):
   ```bash
   gcloud compute ssh flowitup-folio-prod-1 --tunnel-through-iap \
     --zone=europe-west1-b --ssh-key-file=$HOME/.ssh/gcp_ed25519 \
     -- 'cd /opt/folio && docker compose -f docker-compose.yml -f docker-compose.prod.yml up -d --force-recreate <svc>'
   ```

**DB password rotation needs dual-credential window** (add new role, repoint app, drop old) — naïve rotation breaks app↔DB auth. See Phase 11 runbook (when written).

**`NEXT_PUBLIC_*` rotation requires a frontend rebuild + redeploy** — Next.js bakes these into client bundles at build time.

### Verify (success criteria)

```bash
# Audit: all 20 keys present, labeled env=prod
gcloud secrets list --filter='labels.env=prod' --project=flowitup-folio-prod \
  --format='value(name)' | sort | wc -l
# expect: 20

# Per-secret IAM — vm-runtime-sa is the ONLY non-default binding
gcloud secrets get-iam-policy folio-postgres-password --project=flowitup-folio-prod \
  --format='value(bindings.members)' | tr ';' '\n'
# expect: serviceAccount:vm-runtime-sa@flowitup-folio-prod.iam.gserviceaccount.com

# deploy-sa cannot read prod secrets
gcloud secrets versions access latest --secret=folio-postgres-password \
  --project=flowitup-folio-prod --impersonate-service-account=deploy-sa@flowitup-folio-prod.iam.gserviceaccount.com 2>&1
# expect: PERMISSION_DENIED

# .env on VM has all expected keys, mode 640
gcloud compute ssh flowitup-folio-prod-1 --tunnel-through-iap \
  --zone=europe-west1-b --ssh-key-file=$HOME/.ssh/gcp_ed25519 \
  -- 'sudo stat -c "%a %U:%G %s" /opt/folio/.env && sudo grep -cE "^[A-Z_]+=" /opt/folio/.env'
# expect: 640 root:docker <bytes>, key count = 24 (18 SM + 6 constants)
```

### Common failures

| Symptom | Cause | Fix |
|---|---|---|
| `seed.sh` errors `INVALID_ARGUMENT` on `--labels=env=prod` | gcloud version drift | Drop `--labels=env=prod` from the create call; manually label later via `gcloud secrets update <key> --update-labels=env=prod`. |
| `render-env.sh` fails on first run with `PERMISSION_DENIED` | Per-secret IAM not applied (seed.sh hit a permissions error mid-loop) | Re-run `seed.sh` — IAM binding step is idempotent. Or manually: `gcloud secrets add-iam-policy-binding <key> --member=serviceAccount:vm-runtime-sa@... --role=roles/secretmanager.secretAccessor`. |
| `compose up` fails: `required variable POSTGRES_USER is missing a value` | render-env.sh never ran (or ran with empty env file) | `sudo systemctl status folio-render-env.service` and check journalctl. |
| `.env` mode is 600 not 640, containers can't read | render-env was run as user other than root | `sudo systemctl start folio-render-env.service` (the unit forces root + correct group). |
| Secret rotated but container still uses old value | Forgot step 3 (force-recreate) | `docker compose up -d --force-recreate <svc>`. Compose only re-reads `.env` on container creation, not restart. |
| `ADMIN_BOOTSTRAP_PASSWORD` accidentally committed | None — it's only in `/opt/folio/.env`, never in repo | Rotate immediately via `seed.sh --rotate folio-admin-bootstrap-password`. |
