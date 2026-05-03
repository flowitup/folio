---
phase: 4
title: "Cloudflare Wiring"
status: pending
priority: P1
effort: "2h"
dependencies: [3]
---

# Phase 4: Cloudflare Wiring

> **[REVISED 2026-04-29]** ProxyFix wiring + CF-Connecting-IP-aware rate-limiter key_func now an explicit code change in this phase, not a runbook note. **Tunnel-only locked (YAGNI Y5)**: A-record + Caddy/Traefik path is DELETED from scope. Resend SMTP DNS records (SPF, DKIM CNAME) added. **The `## Red Team Fixes` and `## Validation Decisions` sections at the end are authoritative**; supersede the original Tunnel/A-record dual-branch architecture.

## Overview

Connect the domain to the VM via Cloudflare. Two viable approaches: (a) **DNS A-record + orange-cloud proxy** to the VM's static IP, or (b) **Cloudflare Tunnel** with `cloudflared` daemon on the VM (no inbound ports). Pick Tunnel for stronger security posture; A-record if Tunnel adds complexity.

## Requirements

- **Functional:** `https://<domain>` reaches the Next.js frontend; `https://<domain>/api/v1/...` reaches Flask API; TLS via Cloudflare Universal SSL; CF cache hits on `/_next/static/*`.
- **Non-functional:** Origin IP not exposed (Tunnel) or only-CF traffic (proxy). Real client IP preserved through `CF-Connecting-IP` header. WAF baseline rules on.

## Architecture

```
Browser → Cloudflare edge (TLS terminate, WAF, cache)
       ↓
       ├─ if Tunnel:  cloudflared on VM ──→ docker network ──→ frontend:3000 / api:5000
       └─ if A-record: VM:80/443 (caddy or traefik in compose) ──→ frontend:3000 / api:5000
```

Routing:
- `domain.tld` → frontend (Next.js, all paths except `/api/*`)
- `domain.tld/api/*` → api (Flask, port 5000)

## Related Code Files

- Create (Tunnel option): `infra/cloudflare/cloudflared-config.yml` — ingress rules.
- Create (A-record option): `caddy/Caddyfile` or `traefik/dynamic.yml` — reverse proxy in compose.
- Modify: `docker-compose.yml` — add reverse proxy service if going A-record.
- Create: `infra/cloudflare/page-rules.md` — cache config, security level, bot fight mode.

## Implementation Steps

### Decision step (5 min)
1. Pick **Tunnel** unless user has reason against it. (Recommended.)

### If Tunnel (recommended)
2. `cloudflared tunnel login` (from local machine), authorize the zone.
3. `cloudflared tunnel create flowitup-folio-prod` → captures tunnel UUID.
4. Write `cloudflared-config.yml`:
   ```yaml
   tunnel: <UUID>
   credentials-file: /etc/cloudflared/<UUID>.json
   ingress:
     - hostname: domain.tld
       path: ^/api/.*
       service: http://localhost:5000
     - hostname: domain.tld
       service: http://localhost:3000
     - service: http_status:404
   ```
5. Copy credentials JSON to `/etc/cloudflared/` on VM.
6. `cloudflared service install` → runs as systemd unit, auto-restart.
7. Cloudflare DNS: CNAME `domain.tld` → `<UUID>.cfargotunnel.com` (proxied).
8. Remove the static external IP + the `allow-cf-http*` firewall rules (no longer needed).

### If A-record
2. Add Caddy to `docker-compose.yml`, ports 80:80, 443:443, auto-TLS via CF DNS challenge.
3. Caddyfile routes `/api/*` → api, else → frontend.
4. Cloudflare DNS: A `domain.tld` → VM static IP, **proxied** (orange cloud).
5. Set CF SSL mode to **Full (strict)**.

### Both paths
6. Page rules:
   - `domain.tld/_next/static/*` → cache everything, Edge TTL 1 month.
   - `domain.tld/api/*` → bypass cache.
7. Security: enable Bot Fight Mode, set Security Level "Medium", enable `CF-Connecting-IP` rewrite.
8. Test from external network: TLS valid, hits app, `CF-Connecting-IP` reaches Flask logs.

## Success Criteria

- [ ] `curl -I https://domain.tld/` returns 200 with `cf-ray` header.
- [ ] `curl https://domain.tld/api/v1/health` returns Flask `/health` body.
- [ ] Origin IP not resolvable via DNS (`dig domain.tld` returns CF IPs).
- [ ] Static asset hits show `cf-cache-status: HIT` after 2nd request.
- [ ] API responses always show `cf-cache-status: BYPASS` or `DYNAMIC`.
- [ ] Flask access log shows real client IP via `CF-Connecting-IP`, not Cloudflare's edge IP.

## Risk Assessment

| Risk | Mitigation |
|---|---|
| Tunnel daemon dies → site down with no obvious cause | systemd `Restart=always`; uptime check (phase 8) covers it. |
| Cloudflare account locked / billing issue | Domain still on CF registrar, can transfer DNS in 24h; document escape hatch in runbook. |
| WAF blocks legitimate API traffic (uploads, large bodies) | Whitelist `/api/*` from challenge rules; raise body limit if needed. |
| Mixed-content / CORS regression | `NEXT_PUBLIC_API_BASE_URL=https://domain.tld/api/v1`; CORS_ORIGINS env updated to include prod domain. |
| Real-IP not propagated → rate limiting broken | Test with `X-Forwarded-For` + `CF-Connecting-IP`; document Flask `ProxyFix` config. |

## Red Team Fixes (2026-04-29)

Finding 8 applies here. Implementation step (was only in risk table):

### Wire ProxyFix in Flask app — net new code change

`folio-back-end/app/__init__.py` MUST wrap the WSGI app with `werkzeug.middleware.proxy_fix.ProxyFix` AND replace the rate limiter `key_func` with one that prefers `CF-Connecting-IP`. Without this, `request.remote_addr` is the cloudflared loopback or a Cloudflare edge IP — every user looks like the same client, rate limiter is defeated.

```python
# folio-back-end/app/__init__.py
from werkzeug.middleware.proxy_fix import ProxyFix

def create_app() -> Flask:
    app = Flask(__name__)
    # ... existing config ...
    if app.config.get("BEHIND_PROXY", False):
        app.wsgi_app = ProxyFix(app.wsgi_app, x_for=1, x_proto=1, x_host=1)
    # ...
```

```python
# folio-back-end/app/infrastructure/rate_limiter.py
from flask import request

def cf_aware_remote_address() -> str:
    return request.headers.get("CF-Connecting-IP") or request.remote_addr or "0.0.0.0"

limiter = Limiter(key_func=cf_aware_remote_address, ...)
```

Add `BEHIND_PROXY=true` to the prod env (Secret Manager seed).

### Smoke-test verifies real-IP propagation

Add to phase 9 smoke-test: issue 10 logins, half from one source IP, half from another (simulate via `curl --resolve` or two runners). Assert Flask access logs show DISTINCT client IPs in `CF-Connecting-IP` field — not all the same edge IP.

### Updated Success Criteria (addition)

- [ ] `app.wsgi_app` is `ProxyFix`-wrapped in prod (verify by sending request with crafted `X-Forwarded-For: 1.2.3.4` from cloudflared and confirming `request.remote_addr == "1.2.3.4"`).
- [ ] Rate limiter `key_func` reads `CF-Connecting-IP` first.
- [ ] Smoke-test multi-IP probe passes.

## Validation Decisions (2026-04-29 Session 1)

**V4 / Y5 — Tunnel-only, A-record path deleted.**

Original phase had a "Decision step" between Tunnel and A-record + two parallel implementation paths. **Locked to Tunnel.** All of the "If A-record" section (Caddy/Traefik in compose, static IP, CF SSL Full strict, etc.) is **deleted from scope**. No parallel paths in the plan.

**Action:**
- Implementation steps reduce to: Tunnel install + ingress config + DNS CNAME + page rules + WAF baseline.
- Delete: `caddy/Caddyfile`, `traefik/dynamic.yml` from "Related Code Files."
- Delete: SSL mode "Full (strict)" config step (Tunnel handles TLS inside CF).

**V3 — Resend SMTP: add SPF + DKIM DNS records.**

Resend requires DNS records for deliverability:
- SPF: TXT `domain.tld` → `v=spf1 include:_spf.resend.com ~all` (or merge with existing SPF if any).
- DKIM: CNAME `resend._domainkey.domain.tld` → `<resend-provided-target>` (token issued from Resend dashboard, dropped in via Cloudflare DNS).
- DMARC (optional but recommended): TXT `_dmarc.domain.tld` → `v=DMARC1; p=none; rua=mailto:postmaster@domain.tld`.

**Action:** Add to Implementation Steps a "Configure Resend domain" task. The Resend API key is added to Secret Manager in phase 6 (V3 propagation).

**Tunnel ingress final config** (locked):
```yaml
tunnel: <UUID>
credentials-file: /etc/cloudflared/<UUID>.json
ingress:
  - hostname: domain.tld
    path: ^/api/.*
    service: http://localhost:5000
  - hostname: domain.tld
    service: http://localhost:3000
  - service: http_status:404
```

**Effort reclaimed:** ~1h (delete A-record branch + remove static IP wiring elsewhere).
