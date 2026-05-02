# Cloudflare runbook — `folio.flowitup.com`

Operator runbook for Phase 4 wiring. Tunnel-only ingress: no inbound 80/443 to GCP, no static IP. Domain `flowitup.com` is already on Cloudflare (V6).

**Plan:** [`phase-04-cloudflare-wiring.md`](../../plans/260429-2303-gcp-single-vm-deploy/phase-04-cloudflare-wiring.md)
**Daemon config:** [`cloudflared-config.yml`](./cloudflared-config.yml) → installed at `/etc/cloudflared/config.yml`

---

## 1. Tunnel — one-time setup (operator laptop + VM)

### 1a. Authorize cloudflared against your Cloudflare account (laptop)

```bash
brew install cloudflared
cloudflared tunnel login
# → opens browser, pick the flowitup.com zone, authorize.
# → writes ~/.cloudflared/cert.pem (zone origin cert)
```

### 1b. Create the named tunnel (laptop)

```bash
cloudflared tunnel create flowitup-folio-prod
# → prints tunnel UUID + writes ~/.cloudflared/<UUID>.json
```

Note the UUID. Verify:

```bash
cloudflared tunnel list   # should show flowitup-folio-prod
```

### 1c. Copy creds + config to the VM

```bash
# Stage in /tmp first (IAP scp, requires sudo to install into /etc on VM)
gcloud compute scp \
  ~/.cloudflared/cert.pem \
  ~/.cloudflared/<UUID>.json \
  infra/cloudflare/cloudflared-config.yml \
  flowitup-folio-prod-1:/tmp/ \
  --tunnel-through-iap --zone=europe-west1-b \
  --ssh-key-file=$HOME/.ssh/gcp_ed25519

# Install with correct perms
gcloud compute ssh flowitup-folio-prod-1 --tunnel-through-iap \
  --zone=europe-west1-b --ssh-key-file=$HOME/.ssh/gcp_ed25519 -- '
  sudo install -d -m 750 /etc/cloudflared &&
  sudo install -m 600 /tmp/cert.pem        /etc/cloudflared/cert.pem &&
  sudo install -m 600 /tmp/*.json          /etc/cloudflared/credentials.json &&
  sudo install -m 644 /tmp/cloudflared-config.yml /etc/cloudflared/config.yml &&
  sudo rm /tmp/cert.pem /tmp/*.json /tmp/cloudflared-config.yml &&
  ls -la /etc/cloudflared/'
```

### 1d. Install + start the systemd unit (VM)

`service install` writes a systemd unit. Default behavior of the unit's `ExecStart` and origincert/config search paths is **version-dependent** — pin both explicitly to avoid "tunnel started but config never loaded" silent failures.

```bash
gcloud compute ssh flowitup-folio-prod-1 --tunnel-through-iap \
  --zone=europe-west1-b --ssh-key-file=$HOME/.ssh/gcp_ed25519 -- '
  sudo cloudflared --config /etc/cloudflared/config.yml service install &&
  sudo systemctl enable --now cloudflared &&
  sudo systemctl status cloudflared --no-pager | head -15'
```

Verify the unit's `ExecStart` references `/etc/cloudflared/config.yml`:

```bash
gcloud compute ssh flowitup-folio-prod-1 --tunnel-through-iap \
  --zone=europe-west1-b --ssh-key-file=$HOME/.ssh/gcp_ed25519 -- \
  'systemctl cat cloudflared | grep ExecStart'
```

### 1e. Wire DNS (laptop or via Cloudflare dashboard)

```bash
cloudflared tunnel route dns flowitup-folio-prod folio.flowitup.com
```

This creates a **proxied CNAME** `folio.flowitup.com` → `<UUID>.cfargotunnel.com` in the Cloudflare zone automatically. Verify in the Cloudflare dashboard → DNS → Records.

---

## 2. Resend SMTP DNS records (V3)

Add via Cloudflare dashboard → DNS → Records. **All proxied: OFF (DNS-only / grey cloud)** — proxying breaks SPF/DKIM lookups.

| Type | Name | Value | TTL |
|---|---|---|---|
| TXT | `flowitup.com` (or merge with existing SPF) | `v=spf1 include:_spf.resend.com ~all` | Auto |
| CNAME | `resend._domainkey.flowitup.com` | (token from Resend dashboard → Domains → flowitup.com) | Auto |
| TXT | `_dmarc.flowitup.com` (recommended) | `v=DMARC1; p=none; rua=mailto:postmaster@flowitup.com` | Auto |

After adding, click **Verify** in Resend's domain UI. Verification can take a few minutes due to DNS propagation.

**SPF gotcha:** if `flowitup.com` already has an SPF TXT record, do NOT add a second one. Merge the include into the existing string. Two SPF records = mailbox rejection.

---

## 3. Page Rules — cache + bypass

Cloudflare dashboard → Rules → Page Rules. (Or use Cache Rules if your zone has Cache Rules UI; same effect, newer surface.)

### 3a. Aggressive cache for static assets

| Setting | Value |
|---|---|
| URL match | `folio.flowitup.com/_next/static/*` |
| Cache Level | Cache Everything |
| Edge TTL | 1 month |
| Browser TTL | 1 month |

### 3b. Bypass cache for API

| Setting | Value |
|---|---|
| URL match | `folio.flowitup.com/api/*` |
| Cache Level | Bypass |

Order: **3a first, 3b second** (page rules apply in order).

---

## 4. Security baseline

Cloudflare dashboard → Security tab.

| Setting | Where | Value |
|---|---|---|
| Bot Fight Mode | Bots → Configure | ON |
| Security Level | Settings | Medium |
| Always Use HTTPS | SSL/TLS → Edge Certificates | ON |
| Min TLS Version | SSL/TLS → Edge Certificates | 1.2 |
| TLS 1.3 | SSL/TLS → Edge Certificates | ON |
| Automatic HTTPS Rewrites | SSL/TLS → Edge Certificates | ON |
| Browser Integrity Check | Security → Settings | ON |

WAF: leave the **Cloudflare Managed Ruleset** ON (free plan default). Add a **skip rule** for `folio.flowitup.com/api/v1/uploads*` if upload flow trips the OWASP body-size or filename rules during phase 9 smoke. Don't pre-emptively disable rules.

---

## 5. ProxyFix code change (TODO — back-end submodule)

Red Team #8 requires a code change in `folio-back-end` so Flask sees the real client IP via `CF-Connecting-IP` instead of the cloudflared loopback. **This worktree's submodule is empty**, so the change is documented here for whoever opens the back-end PR.

### 5a. Wrap WSGI with ProxyFix

```python
# folio-back-end/app/__init__.py
from werkzeug.middleware.proxy_fix import ProxyFix

def create_app() -> Flask:
    app = Flask(__name__)
    # ...existing config...
    if app.config.get("BEHIND_PROXY", False):
        app.wsgi_app = ProxyFix(app.wsgi_app, x_for=1, x_proto=1, x_host=1)
    return app
```

### 5b. Rate limiter `key_func` prefers `CF-Connecting-IP`

```python
# folio-back-end/app/infrastructure/rate_limiter.py
from flask import request

def cf_aware_remote_address() -> str:
    return request.headers.get("CF-Connecting-IP") or request.remote_addr or "0.0.0.0"

limiter = Limiter(key_func=cf_aware_remote_address, ...)
```

### 5c. Env var

Phase 6 (secrets) seeds `BEHIND_PROXY=true` in the prod env. Already a known phase-6 deliverable.

### 5d. Smoke test (Phase 9)

Issue ≥10 requests from two distinct source IPs (`curl --resolve` against two CF datacenter IPs, or run from two different runners). Inspect `/var/log/folio/api.log` and confirm `CF-Connecting-IP` in access logs holds the client IPs, not cloudflared's `127.0.0.1`.

---

## 6. Verify (success criteria)

After all of the above, from any external network:

```bash
# TLS + 200 from frontend (after compose stack is up in phase 9)
curl -I https://folio.flowitup.com/

# Cloudflare in path
curl -sI https://folio.flowitup.com/ | grep -E '^(cf-ray|server|cf-cache-status):'

# Origin IP not leaking
dig +short folio.flowitup.com    # → only Cloudflare IPs (104.16.* / 172.64.* range)

# Static asset HIT after warm
curl -sI https://folio.flowitup.com/_next/static/<hash>.js | grep cf-cache-status
curl -sI https://folio.flowitup.com/_next/static/<hash>.js | grep cf-cache-status
# 1st: MISS or DYNAMIC, 2nd: HIT

# API never cached
curl -sI https://folio.flowitup.com/api/v1/health | grep cf-cache-status   # → BYPASS
```

These rely on the compose stack being up — Phase 4 alone won't make `/` return 200, only the tunnel + DNS path. Phase 9 first deploy is when the verify block fully passes.

---

## 7. Common failures

| Symptom | Cause | Fix |
|---|---|---|
| `cloudflared tunnel create` errors with "missing zone" | `cert.pem` not present or wrong account | Re-run `cloudflared tunnel login` and pick `flowitup.com`. |
| systemd unit fails: `Failed to read /etc/cloudflared/config.yml` | Wrong perms or path mismatch | Check `ls -la /etc/cloudflared/`; cred file must be `credentials.json` per config, not `<UUID>.json`. |
| Tunnel up but DNS doesn't resolve | CNAME not created or proxy disabled | Cloudflare dashboard → DNS — confirm orange cloud (proxied) on the `folio` CNAME. |
| `502 Bad Gateway` from edge | Origin (frontend/api) not running yet | Expected until Phase 9. |
| 5 SPF TXT records visible | Multiple includes — only 1 SPF record allowed | Merge into one: `v=spf1 include:_spf.resend.com include:other.com ~all`. |
| Resend DKIM stays "Pending" | DNS propagation OR proxied CNAME (DKIM must be DNS-only) | Cloudflare DNS → toggle `resend._domainkey` proxy to OFF (grey). |

---

## 8. Useful commands (cheat sheet)

```bash
# On the VM
sudo systemctl status cloudflared
sudo journalctl -u cloudflared -f       # live logs
cloudflared tunnel info flowitup-folio-prod
cloudflared tunnel list

# From laptop
cloudflared tunnel ingress validate /etc/cloudflared/config.yml   # only locally; copy from VM first
cloudflared tunnel route dns --help
```
