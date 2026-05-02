---
phase: 8
title: "Observability"
status: pending
priority: P2
effort: "3h"
dependencies: [4]
---

# Phase 8: Observability

> **[REVISED 2026-04-29]** **YAGNI Y3:** alert policies trimmed 5 → 2 (kept: uptime check + disk >85%; dropped: CPU/RAM/5xx-rate alerts + weekly canary). Reason: alert fatigue on 2-vCPU VM. Add the rest after first incident teaches what's actually noisy. **The `## Validation Decisions` section at the end is authoritative**; supersedes the Architecture alert list.

## Overview

Minimum-viable observability for a single-VM deploy: container logs to Cloud Logging, uptime check on `/health`, alerts on disk/CPU/RAM, Cloudflare analytics for edge metrics. No APM (Datadog/Honeycomb) — out of budget. Aggressive but cheap.

## Requirements

- **Functional:** Operator can grep last 24 h logs across services, gets paged within 2 min of `/health` 5xx, sees disk/CPU/RAM trend.
- **Non-functional:** Free-tier Cloud Logging + Monitoring (50 GB/mo log ingest free); no agent install gymnastics; alerts route to email + (optional) Discord.

## Architecture

```
VM
├── docker (json-file logs at /var/lib/folio/logs/)
└── Ops Agent (Cloud Logging + Cloud Monitoring)
        ├── stream container stdout → Cloud Logging
        └── system metrics → Cloud Monitoring (CPU, mem, disk, net)

Cloud Monitoring
├── Uptime check: GET https://domain.tld/health every 60s, 3 regions
├── Alert policies:
│   ├── Uptime check failed (2 of 3 regions)  → email + Discord
│   ├── Disk usage > 85 %                     → email
│   ├── CPU > 80 % for 10 min                 → email
│   ├── RAM > 90 % for 5 min                  → email
│   └── Log-based: API 5xx rate > 1 % for 5 min → email + Discord
└── Dashboard: VM health + service health + traffic

Cloudflare Analytics (free)
├── Edge requests, cache hit ratio, 4xx/5xx breakdown
└── Threat events (WAF blocks)
```

## Related Code Files

- Create: `infra/gcp/cloud-init/install-ops-agent.sh` — appended to phase 3 startup.
- Create: `infra/gcp/monitoring/uptime-check.tf` — uptime check resource.
- Create: `infra/gcp/monitoring/alert-policies.tf` — 5 policies.
- Create: `infra/gcp/monitoring/dashboard.json` — exported dashboard config.
- Create: `infra/gcp/monitoring/log-metric-api-5xx.tf` — log-based metric.
- Modify: `folio-back-end` Flask app to ensure `/health` is cheap (no DB hit) and `/health/deep` runs DB+Redis check (NOT used for uptime — separate).

## Implementation Steps

1. Append Ops Agent install to phase 3 startup script (single curl + bash — Google's official installer).
2. Configure Ops Agent (`/etc/google-cloud-ops-agent/config.yaml`) to scrape Docker JSON logs.
3. Tag logs with service name (api, worker, frontend, postgres, redis, minio) via `extract_logs_from_files` directives.
4. Define uptime check on `https://domain.tld/health` (200, body contains "ok"), 60 s interval, multi-region.
5. Define alert policies in Terraform (5 listed above) with notification channels (email + Discord webhook via incoming webhook URL).
6. Create log-based metric `api_5xx_rate` (filter: `severity>=ERROR resource.type=gce_instance`).
7. Build dashboard with: uptime panel, CPU/RAM/disk gauges, request rate, error rate, Cloudflare cache-hit (manual import).
8. Test alerts: `kill -STOP` the api container → uptime fires within 2 min → alert reaches inbox.
9. Document log queries in `docs/deployment-guide.md`:
   - "show all api errors last 1 h"
   - "show worker job failures"
   - "show postgres slow queries"

## Success Criteria

- [ ] Cloud Logging shows logs from all 6 services with correct labels.
- [ ] Uptime check reports green on dashboard.
- [ ] Alert simulation (stop a container) triggers email within 2 min.
- [ ] Disk usage alert fires correctly when filling test data > 85 %.
- [ ] Dashboard usable on phone screen for on-the-go check.
- [ ] Cloud Logging ingest < 10 GB/mo (well inside free tier).

## Risk Assessment

| Risk | Mitigation |
|---|---|
| Log volume blows free tier | `max-size=10m max-file=3` in Docker daemon caps it; exclude `/health` request logs (high-frequency noise). |
| Alerts spam inbox / fatigue | Group by alert policy; set 30-min cooldown; severity tiers (paging vs email). |
| `/health` checked uses DB → false alarms during DB hiccups | `/health` returns 200 if Flask alive (no deps); `/health/deep` for ops, not uptime. |
| Discord webhook URL leaked | Store in Secret Manager; never in repo. |
| Ops Agent eats VM RAM | Constrain via systemd (`MemoryMax=256M`); confirmed safe per docs. |
| No alert channel = silent failure | Send a test alert weekly via cron (canary); if no email arrives, page. |

## Validation Decisions (2026-04-29 Session 1)

**Y3 — Alert policies trimmed 5 → 2.**

Original plan: 5 alert policies + a log-based 5xx-rate metric + a weekly canary cron. **Trimmed.** Reason: on a 2-vCPU VM, CPU/RAM alerts fire constantly during legitimate work (migrations, build pulls, single-user load tests) → alert fatigue → operator silences them → real outage missed via the silenced channel.

**Kept (2 policies):**
- ✅ **Uptime check** on `https://domain.tld/health` (60 s, multi-region) → email + Discord. Cloudflare can't see this alone — the only thing genuinely outside-the-stack-monitoring.
- ✅ **Disk usage > 85 %** → email. Real, immediate failure mode for a single VM with logs + uploads + Postgres + Docker images.

**Dropped (3 policies + canary):**
- ❌ CPU > 80 % for 10 min — fires during legit migrations.
- ❌ RAM > 90 % for 5 min — fires during build pulls.
- ❌ Log-based metric `api_5xx_rate > 1 %` for 5 min — premature without baseline; uptime check + manual log review covers v1.
- ❌ Weekly canary email — over-engineering; uptime check failure already pages.

**Add later if needed.** After first incident teaches what's actually noisy vs signal, add the missing alert. Cheaper than starting silenced-by-default.

**Effort reclaimed:** ~1h (3 fewer Terraform/config blocks, simpler runbook).
