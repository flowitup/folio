---
title: "Setup Verification Script"
description: "Bash script to verify full E2E setup of construction project"
status: completed
priority: P2
effort: 2h
branch: main
tags: [devops, automation, testing]
created: 2026-01-19
---

# Setup Verification Script

## Overview

Create `scripts/verify-setup.sh` at project root to perform full E2E verification of the construction project setup including Docker services, database seeding, frontend, and integration tests.

## Current State

- **Backend:** Flask API with docker-compose (api:5000, db:5432, redis:6379, worker)
- **Frontend:** Next.js 16 at port 3000
- **Health endpoint:** `GET /health` returns `{"status": "ok"}`
- **Auth endpoints:** login, logout, refresh, /me all functional
- **Seed script:** `construction-back-end/scripts/seed_auth.py`

## Phases

| Phase | Description | Status | Effort |
|-------|-------------|--------|--------|
| [Phase 01](./phase-01-implement-verify-setup-script.md) | Implement verify-setup.sh | completed | 2h |

## Key Dependencies

- Docker & Docker Compose installed
- Node.js and npm installed
- Python 3.12+ with uv (for backend)
- Available ports: 5000, 5432, 6379, 3000

## Success Criteria

1. ✅ Script starts all Docker services and waits for health
2. ✅ Database migrations and seeding complete
3. ✅ Frontend dev server starts and responds
4. ✅ E2E auth flow (login, /me) verified
5. ✅ Cleanup on exit (optional --cleanup flag)
6. ✅ Full cleanup with --cleanall flag (removes volumes, images, cache)
7. ✅ Clear color-coded status output
8. ✅ Proper exit codes for CI/CD

## Implementation Notes

### Fixes Applied During Implementation

| Issue | Root Cause | Fix |
|-------|-----------|-----|
| Migrations missing in Docker | Dockerfile didn't copy migrations/ | Added `COPY migrations/` to Dockerfile |
| Scripts missing in Docker | Dockerfile didn't copy scripts/ | Added `COPY scripts/` to Dockerfile |
| RQ worker import error | RQ 2.x removed `Connection` context manager | Updated to pass connection directly to Queue/Worker |
| Seed script ModuleNotFoundError | PYTHONPATH not set in docker exec | Added `PYTHONPATH=/app` to exec command |
| "Auth services not configured" | DI container not wired in create_app | Added container wiring in app factory |
| Missing repository adapter | SQLAlchemy implementation didn't exist | Created SQLAlchemyUserRepository adapter |
| JWT_TOKEN_LOCATION error | Mutable list default in dataclass | Changed to immutable tuple |

### Script Features

- `--cleanup` - Stop all services after verification
- `--cleanall` - Remove all Docker volumes, caches, images
- `--timeout N` - Set custom timeout (default: 120s)
- `--help` - Show usage information
- Docker Compose v1/v2 compatibility
- Color-coded output with ✓/✗ status indicators
- Proper exit codes for CI/CD integration

## Related Files

### Created/Modified Files

| File | Action | Purpose |
|------|--------|---------|
| `scripts/verify-setup.sh` | Created | Main verification script |
| `construction-back-end/Dockerfile` | Modified | Added COPY for migrations/ and scripts/ |
| `construction-back-end/infrastructure/queue/rq_worker.py` | Modified | Fixed RQ 2.x API |
| `construction-back-end/app/__init__.py` | Modified | Added DI container wiring |
| `construction-back-end/app/infrastructure/adapters/sqlalchemy_user_repository.py` | Created | SQLAlchemy user repository |
| `construction-back-end/config/__init__.py` | Modified | Fixed JWT_TOKEN_LOCATION config |

### Reference Files

- `construction-back-end/docker-compose.yml`
- `construction-back-end/scripts/seed_auth.py`
- `construction-front-end/package.json`
- `docs/system-architecture.md`

## Completion

Implementation completed 2026-01-20. All E2E tests passing.
