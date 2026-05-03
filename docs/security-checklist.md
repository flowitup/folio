# Folio Security Checklist

Last Updated: 2026-05-03 (production deploy applied)
Status: ✅ Production live at https://folio.flowitup.com — see [`deployment-guide.md`](./deployment-guide.md)

## Password Security

- [x] Passwords hashed with Argon2id (GPU-resistant, recommended by OWASP)
- [x] Minimum 8 character requirement enforced
- [x] Salt automatically handled by Argon2
- [ ] Password complexity rules (optional - consider for future)
- [x] No password in logs/error messages
- [x] Timing-attack prevention (dummy hash on user not found)

## Token Security

- [x] JWT signed with strong secret (HS256, 256-bit minimum)
- [x] Short-lived access tokens (30 minutes)
- [x] Long-lived refresh tokens (7 days)
- [x] httpOnly cookies (no JavaScript access)
- [x] Secure flag in production (`FLASK_ENV=production` triggers `JWT_COOKIE_SECURE=True`)
- [x] SameSite=Strict cookie attribute (production); SameSite=None for dev only
- [x] CSRF protection enabled in production (`csrf_access_token` cookie + `X-CSRF-TOKEN` header)
- [ ] Token blacklist for logout (Redis) - planned for future

## API Security

- [x] Rate limiting on login endpoint (5/minute)
- [x] CORS configured correctly
- [x] Input validation (Pydantic schemas)
- [x] Generic error messages (prevents user enumeration)
- [x] HTTPS enforced in production

## Authorization (RBAC)

- [x] Permission-based access control
- [x] Role hierarchy support
- [x] Wildcard permissions (*:*, resource:*)
- [x] Auth checked at multiple layers (middleware + route)
- [x] Server-side auth verification

## Session Security

- [x] Session tied to user identity via JWT claims
- [x] Logout clears cookies
- [ ] Session timeout on inactivity - planned
- [ ] Concurrent session limit - optional

## Frontend Security

- [x] httpOnly cookies (tokens not accessible via JS)
- [x] Server-side session validation
- [x] Protected routes with middleware
- [x] Auth state managed server-side
- [x] No sensitive data in localStorage

## OWASP Top 10 Coverage

| OWASP ID | Vulnerability | Status | Implementation |
|----------|--------------|--------|----------------|
| A01:2021 | Broken Access Control | ✅ Covered | RBAC, layered auth checks, permission-based routes |
| A02:2021 | Cryptographic Failures | ✅ Covered | Argon2id hashing, JWT signing, httpOnly cookies |
| A03:2021 | Injection | ✅ Covered | Pydantic validation, parameterized queries, SQLAlchemy ORM |
| A04:2021 | Insecure Design | ✅ Covered | Hexagonal architecture, separation of concerns |
| A05:2021 | Security Misconfiguration | ⚠️ Review | Environment-specific config review recommended |
| A07:2021 | Identification/Auth Failures | ✅ Covered | Proper token handling, rate limiting, secure password storage |

## Test Coverage

- [x] Unit tests for AuthService (authenticate, hash_password)
- [x] Unit tests for AuthorizationService (permissions, roles)
- [x] Unit tests for Argon2PasswordHasher
- [x] Integration tests for auth endpoints (login, logout, refresh, me)
- [x] Rate limiting tests
- [x] Cookie handling tests

## Production Deployment Checklist (✅ applied 2026-05-03)

- [x] JWT_SECRET cryptographically random (64 bytes hex from `openssl rand -hex 64`, stored in Secret Manager)
- [x] HTTPS enforced (Cloudflare proxy + Tunnel — all traffic terminates TLS at CF, no public 80/443 on origin)
- [x] Secure cookie flag enabled (`FLASK_ENV=production` triggers `JWT_COOKIE_SECURE=True`)
- [x] CORS allowed origins set to `https://folio.flowitup.com` only (via SM key `folio-cors-origins`)
- [x] Rate limiting enabled (Flask-Limiter, Redis-backed, per-user via JWT subject)
- [x] Monitoring set up (Cloud Monitoring uptime check + disk-usage alert, email channel `mt.bui.fr@gmail.com`)
- [x] Database connection on private Docker network only (no host-published port)

## Production Infrastructure Hardening

### Network
- [x] No public IP on VM (Cloudflare Tunnel outbound-only)
- [x] No public 80/443 listener on origin
- [x] SSH only via IAP TCP forwarding (no 0.0.0.0/0 SSH rule; default-allow-ssh deleted)
- [x] All container ports bound to `127.0.0.1` (cloudflared reaches via loopback)
- [x] Cloudflare WAF + DDoS in front of every request

### Secrets
- [x] 20 secrets in Google Secret Manager (label `env=prod`)
- [x] Per-secret IAM bindings (no project-level `secretAccessor`)
- [x] `/opt/folio/.env` rendered by systemd oneshot, mode 640 root:docker
- [x] No secrets in repo (`.env`, `*.env.*` blocked by parent + submodule `.gitignore`)
- [x] Compose enforces `${VAR:?required}` — fails fast on missing env, no silent dev defaults

### Identity (least-privilege)
- [x] 3 service accounts, distinct purposes (deploy / runtime / backup)
- [x] `vm-runtime-sa` cannot write backups (impersonates `backup-sa` via `serviceAccountTokenCreator`)
- [x] `backup-sa` cannot delete or modify objects (objectCreator + objectViewer; bucket retention lock prevents true delete)
- [x] `deploy-sa` JSON key in GitHub Secrets only — never on the VM
- [x] HMAC keys (1 pair, for `mc` mirror) in Secret Manager, rotation runbook documented

### Backups & recovery
- [x] Daily logical pg_dump → GCS (verified 2026-05-03, 38KB landed)
- [x] Daily MinIO mirror with 5% drop guard (no `--remove` flag — Red Team finding 5)
- [x] Weekly disk snapshots (boot + data, 28d retention)
- [x] Bucket retention lock (7d primary, 365d archive)
- [x] Bucket versioning ON
- [x] Weekly automated restore-test (sidecar Postgres container)
- [x] Quarterly tabletop restore drill scheduled (runbook §5.5)

### Front-end / browser
- [x] httpOnly cookies for tokens (no JS access)
- [x] CSRF token in separate cookie (JS-readable, sent via header)
- [x] No localStorage tokens
- [x] No public env vars containing secrets (only `NEXT_PUBLIC_API_BASE_URL`)
- [x] Browser-side bot detection respected (no CAPTCHA bypass attempts)

### Observability
- [x] Cloud Logging captures all container stdout
- [x] Uptime check pages within 60-300s of /health failure
- [x] Disk-usage alert at 85%
- [x] No PII in logs (api logs requests but not bodies)

## Future Improvements

1. **Token Blacklist**: Implement Redis-based token blacklist for immediate logout
2. **Password Reset**: Add forgot password flow with secure tokens
3. **Two-Factor Auth (2FA)**: TOTP or SMS-based 2FA
4. **Audit Logging**: Log all auth events for security monitoring
5. **Session Timeout**: Auto-logout after inactivity
6. **Brute Force Protection**: Progressive delays, account lockout
