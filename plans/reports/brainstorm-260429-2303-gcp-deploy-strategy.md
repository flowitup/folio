---
type: brainstorm
date: 2026-04-29
slug: gcp-deploy-strategy
status: agreed
---

# Brainstorm — GCP Deploy Strategy for Folio

## 1. Problem statement

Folio = 6-service Docker stack (Flask API + RQ worker + Postgres 16 + Redis 7 + MinIO + Next.js SSR). Need production deploy.

**Constraints:**
- Provider: **GCP** (mandated — burn AI Ultra $100/mo credit).
- Domain at **Cloudflare**.
- Workload: commercial / paying customers (backups + uptime matter, no formal SLA).
- Prior experience: Coolify on Hetzner + SSH-based deploys.
- Region: **europe-west1** (Belgium, closest to Paris).

**Credit reality:** AI Ultra GCP credit = ~12 months from activation, then full price. Architect for both worlds.

## 2. Approaches evaluated

| # | Approach | Monthly cost (eu-west1) | Inside credit? | Verdict |
|---|---|---|---|---|
| A | Single GCE VM, all services in Docker | **~$80** | Yes | **CHOSEN** |
| B | GCE VM + Cloud SQL Postgres + GCS uploads | ~$135 | No (~$35 over) | Recommended for commercial — declined |
| C | Cloud Run + Cloud SQL + Memorystore | ~$240 | No (2.4× over) | Overkill for stage |

### Rejected approaches — why
- **B** offered managed Postgres (PITR, automatic backups, no patching) for ~$35/mo overage. User chose A — accepting self-managed-DB ops risk to stay inside credit. **Revisit at >50 paying users or first DB scare.**
- **C** rejected: ~3× cost; Cloud Run + RQ worker is a poor fit (request-driven runtime vs. long-running queue consumer); Memorystore Basic 1 GB ($35) overkill for current Redis usage.

## 3. Chosen solution — Option A

### Architecture

```
            Cloudflare (DNS + orange-cloud proxy + Tunnel)
                              │
                              ▼
        ┌─────────────────────────────────────────────┐
        │  GCE e2-standard-2 (eu-west1, Debian 12)    │
        │  ┌────────────┬────────────┬─────────────┐  │
        │  │  frontend  │     api    │   worker    │  │
        │  │  (Next.js) │   (Flask)  │   (RQ)      │  │
        │  └────────────┴────────────┴─────────────┘  │
        │  ┌────────────┬────────────┬─────────────┐  │
        │  │  postgres  │    redis   │    minio    │  │
        │  │   (vol)    │    (vol)   │    (vol)    │  │
        │  └────────────┴────────────┴─────────────┘  │
        │  cloudflared (tunnel daemon)                │
        └─────────────────────────────────────────────┘
                              │
                              ▼
            GCS bucket — nightly pg_dump + minio mirror
```

### Pricing breakdown (europe-west1, list price, no SUD)

| Item | Spec | $/mo |
|---|---|---|
| Compute Engine VM | `e2-standard-2` (2 vCPU, 8 GB RAM) | $52.50 |
| Boot+data disk | `pd-balanced` 50 GB | $5.50 |
| Static external IP | reserved (or skip if Tunnel) | $2.92 |
| Snapshots | weekly, ~50 GB retained | $1.40 |
| GCS bucket (offsite backups) | 5–10 GB Standard, eu-west1 | $0.20 |
| Egress to internet | ~200 GB/mo (CF caches static) | $17.00 |
| Artifact Registry | container images, ~5 GB | $0.50 |
| **Total** | | **~$80/mo** |
| Cloudflare DNS + proxy + Tunnel + SSL | | **$0** |

**Inside $100 credit with ~$20/mo headroom for traffic spikes.**

**Month-13 cost (no credit):** $80/mo out of pocket.

### Networking — Cloudflare in front

- DNS at Cloudflare → A record points at GCE static IP.
- **Orange-cloud proxy ON** → free SSL, DDoS protection, caches static Next.js assets, hides origin IP.
- **Cloudflare Tunnel** (optional, recommended): `cloudflared` daemon on the VM, no inbound ports open at all. Eliminates the static-IP $3/mo if used. Better security posture.
- VM firewall: allow SSH (preferably IAP-tunneled, not public 22), allow only Cloudflare egress IPs on 80/443 if not using Tunnel.

### Storage strategy on the VM

- Postgres data → named Docker volume on `pd-balanced`.
- Redis data → named Docker volume.
- MinIO buckets → named Docker volume.
- Daily `pg_dump` → cron container → upload to GCS (versioned bucket, 30-day lifecycle).
- Weekly disk snapshot of the boot+data disk (GCP-managed, retained 4 weeks).
- MinIO objects → nightly `mc mirror` to GCS (cold copy).

### Deploy workflow (GitHub Actions → SSH → docker compose pull)

1. Push to `main` on either submodule (`folio-back-end` or `folio-front-end`) or root monorepo.
2. GitHub Actions:
   - Build Docker image.
   - Tag with commit SHA + `latest`.
   - Push to **Artifact Registry** (`europe-west1-docker.pkg.dev/<project>/folio`).
3. Workflow SSHes into VM (key stored in GitHub Secrets, locked to deploy user with restricted shell).
4. On VM: `gcloud auth configure-docker` (one-time), `docker compose pull && docker compose up -d --no-deps <service>`.
5. Healthcheck poll on `/health` — rollback to previous tag if fail (5-min window).

**Why not Coolify on GCP:** user opted for GHA→SSH for tighter Git ↔ deploy coupling and simpler IAM. Coolify remains an option if UI-driven redeploys become useful later.

### Secrets

- `.env.production` lives on the VM at `/opt/folio/.env`, mode 600, owned by deploy user.
- Bootstrapped from **Google Secret Manager** at first boot via startup script (avoids checking secrets into anything).
- GitHub Actions does **not** carry production secrets — only an SSH key + Artifact Registry token.

### Backup & recovery

| What | How | Frequency | Retention | RPO | RTO |
|---|---|---|---|---|---|
| Postgres | `pg_dump` → GCS | Daily 03:00 UTC | 30 days | 24 h | ~10 min |
| Postgres (PITR-lite) | WAL archive → GCS | Continuous | 7 days | ~5 min | ~20 min |
| MinIO | `mc mirror` → GCS | Daily | 30 days | 24 h | ~30 min |
| Disk snapshot | GCP-managed | Weekly | 4 weeks | 7 d | ~15 min |
| Code | git + container images in AR | per push | 90 days | 0 | ~5 min |

### Monitoring

- **Cloud Logging** for VM serial + Docker logs (free tier covers small scale).
- **Cloud Monitoring** uptime check on `https://<domain>/health` every 60 s, alert → email + (optional) Discord webhook.
- **Cloudflare Analytics** (free) for edge-side traffic + cache hit rate.

## 4. Risks & mitigations

| Risk | Severity | Mitigation |
|---|---|---|
| Single VM = single failure domain | **HIGH** for commercial | Snapshots + scripted re-create from Terraform/gcloud snippets → RTO ~30 min |
| Self-managed Postgres corruption | HIGH | WAL archive + nightly dump + restore drill quarterly |
| MinIO data loss (single replica) | MEDIUM | Daily mirror to GCS |
| VM compromise (public SSH) | MEDIUM | Use IAP SSH or Cloudflare Tunnel, no public 22 |
| Egress overage | LOW | CF cache ratio + monitor; alarm at 300 GB/mo |
| Credit expiry surprise (month 13) | MEDIUM | Calendar reminder month 11 to evaluate Option B migration |
| Disk fills up (logs, MinIO) | LOW | Disk-usage alert at 80 %, log rotation + MinIO bucket lifecycle |

## 5. Success metrics

- p95 API latency < 400 ms (incl. Cloudflare hop).
- Uptime ≥ 99.5 % (allows ~3.5 h downtime/mo — single-VM realistic).
- Deploy time push → live < 5 min.
- Backup restore drill: full restore from GCS in < 30 min, validated quarterly.
- Monthly GCP spend ≤ $100 (credit-funded).

## 6. Implementation phases (for /ck:plan)

1. **GCP project + IAM bootstrap** — project, service accounts, Artifact Registry, Secret Manager seeded.
2. **VM provisioning** — Terraform or `gcloud` script for GCE + disk + IP + firewall + startup script.
3. **VM bootstrap** — Docker, docker-compose plugin, cloudflared, log rotation, deploy user, SSH lockdown.
4. **Cloudflare wiring** — DNS records, Tunnel config, page rules for caching.
5. **CI/CD** — GitHub Actions workflows for back-end and front-end (build → push AR → SSH deploy).
6. **Secrets management** — Secret Manager → startup-script template → `/opt/folio/.env`.
7. **Backups** — pg_dump cron, WAL archive, MinIO mirror, disk snapshot schedule.
8. **Observability** — uptime check, log-based alerts, Cloudflare analytics.
9. **First-deploy + smoke test** — DB migrations, seed admin user, full happy-path test.
10. **Restore drill** — wipe a test VM, restore from GCS, validate RTO.
11. **Runbook** — `docs/deployment-guide.md` updated with rollback, restore, scale-up steps.

## 7. Open questions

- GCP project name + billing account: new project or reuse existing?
- Domain registered at Cloudflare already, or still elsewhere?
- Will the API need outbound SMTP from the VM, and what provider (existing SMTP creds)? Affects firewall egress.
- Do we need staging? (Adds a second VM ≈ +$50/mo, or re-uses the prod VM with namespaced compose project + a `*.staging.<domain>` CF record.)
- Plan for the AI Ultra credit's month-13 cliff — automatic Option-B migration or accept $80/mo bill?

## 8. Decision log

- **2026-04-29:** Chose Option A over recommended Option B — willing to absorb self-managed-DB risk to stay inside credit. Revisit at first DB scare or 50+ paying users.
- **2026-04-29:** Region = europe-west1 (proximity, EU data residency).
- **2026-04-29:** Deploy = GitHub Actions → SSH → `docker compose pull`. Coolify deferred.
