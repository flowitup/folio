# Security Scan Report

**Project:** construction (back-end + front-end)
**Scanned:** 2026-04-06
**Stack:** Flask 3 (Python) + Next.js 16 (TypeScript)

---

## Summary

| Category | Critical | High | Medium | Low |
|----------|----------|------|--------|-----|
| Secrets  | 0 | 0 | 1 | 0 |
| Deps (FE)| 0 | 5 | 2 | 0 |
| Deps (BE)| 0 | 0 | 0 | 0 |
| Code patterns | 0 | 0 | 0 | 0 |
| .env exposure | 0 | 0 | 0 | 0 |

**Total: 8 findings (0 Critical, 5 High, 3 Medium)**

---

## Findings

### MEDIUM

#### 1. `ProductionConfig` falls back to insecure default secret
**File:** `construction-back-end/config/__init__.py:99`
```python
SECRET_KEY: str = get_env("SECRET_KEY", required=False) or "dev-secret-key"
```
If `SECRET_KEY` is unset in a production environment, the app silently uses `"dev-secret-key"`, making sessions trivially forgeable. `JWT_SECRET_KEY` has the same pattern in the base `Config` (line 66) but no production override — it will use `"dev-jwt-secret-change-in-production"` unless the env var is set.

**Fix:** Make both keys `required=True` in `ProductionConfig` so the app fails fast instead of running insecure.
```python
class ProductionConfig(Config):
    SECRET_KEY: str = get_env("SECRET_KEY", required=True)
    JWT_SECRET_KEY: str = get_env("JWT_SECRET_KEY", required=True)
```

#### 2. `JWT_COOKIE_CSRF_PROTECT` and `JWT_COOKIE_SECURE` disabled based on env var detection
**File:** `construction-back-end/config/__init__.py:73-75`
```python
_is_production: bool = get_env("FLASK_ENV", default="development") == "production"
JWT_COOKIE_SECURE: bool = _is_production
JWT_COOKIE_CSRF_PROTECT: bool = _is_production
```
If `FLASK_ENV` is not explicitly set to `"production"` in a deployed environment, both cookie security flags are off. Acceptable for local dev but risky if a staging/prod deploy omits the env var.

**Fix:** Acceptable pattern, but document it clearly and enforce `FLASK_ENV=production` in deployment configs/CI. Consider adding a startup assertion in `ProductionConfig.__post_init__`.

#### 3. CORS origins default to `localhost:3000`
**File:** `construction-back-end/app/__init__.py:50-51`
```python
cors_origins = os.environ.get("CORS_ORIGINS", "http://localhost:3000").split(",")
CORS(app, supports_credentials=True, origins=cors_origins)
```
If `CORS_ORIGINS` is not set in production, cross-origin requests from the real domain will be blocked — but more critically, `supports_credentials=True` with a wildcard or wrong origin can allow credential leakage. Risk is low since the default is `localhost`, but deployment docs should require `CORS_ORIGINS` to be set explicitly.

---

### HIGH — Frontend Dependencies (all transitive, none in application code)

| # | Package | Installed | Vulnerability | CVE/Advisory |
|---|---------|-----------|---------------|--------------|
| 1 | `next` | 16.1.3 | DoS via Image Optimizer `remotePatterns` bypass | GHSA-… |
| 2 | `rollup` | transitive | Arbitrary File Write via path traversal | GHSA-mw96-cpmx-2vgc |
| 3 | `picomatch` | transitive | ReDoS via extglob quantifiers + POSIX method injection | GHSA-3v7f-55p6-f55p |
| 4 | `flatted` | transitive | Unbounded recursion DoS in `parse()` revive phase | – |
| 5 | `minimatch` | transitive | ReDoS via repeated wildcards | – |

**Impact:** Rollup and picomatch are dev-build tools — not present in the production bundle. `flatted`/`minimatch` are also build-time deps. **`next` is production** and the DoS is exploitable if `images.remotePatterns` is misconfigured.

**Fix:** Run `npm audit fix` to patch rollup, picomatch, flatted, minimatch. For Next.js: `npm audit fix --force` upgrades to `16.2.2` (outside semver range — review changelog first).

### MODERATE — Frontend Dependencies

| # | Package | Vulnerability |
|---|---------|---------------|
| 1 | `ajv` | ReDoS when using `$data` option |
| 2 | `brace-expansion` | Zero-step sequence → process hang |

Both are build-time tools. `npm audit fix` resolves them.

---

## Positives (No Issues Found)

- **No hardcoded secrets** in application source (test files contain test-only passwords — acceptable)
- **No `.env` files tracked in git** — `.gitignore` correctly excludes `.env*`
- **No SQL injection patterns** — SQLAlchemy ORM used throughout, no raw string concatenation in queries
- **No XSS vectors** — no `dangerouslySetInnerHTML` or `innerHTML` assignments in frontend
- **No command injection** — no `subprocess` / `os.system` with user input
- **No `eval()`** in frontend source
- **CORS** uses explicit env-var-driven allowlist (not `*`)
- **Argon2** used for password hashing (strong choice)
- **JWT stored in HTTP-only cookies** (not `localStorage`)
- **Rate limiting** on auth endpoint (5/min)

---

## Recommended Actions

1. **[Medium / Quick]** Fix `ProductionConfig` to require `SECRET_KEY` and `JWT_SECRET_KEY`.
2. **[High / Quick]** Run `npm audit fix` in `construction-front-end/` to patch build-tool vulns.
3. **[High / Careful]** Run `npm audit fix --force` to upgrade `next` to `16.2.2` — review Next.js changelog for breaking changes first.
4. **[Medium / Doc]** Add `CORS_ORIGINS` and `FLASK_ENV=production` to deployment checklist / CI env requirements.
5. **[Low / Optional]** Install `pip-audit` as a dev dependency to enable backend dep scanning in CI: `uv add --dev pip-audit`.

---

## Unresolved Questions

- Are any Next.js `images.remotePatterns` configured in production? If so, the `next` DoS (finding #1 HIGH) becomes more urgent.
- Is `pip-audit` or another Python dependency scanner planned for CI?
