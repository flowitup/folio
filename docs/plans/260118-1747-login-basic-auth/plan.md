---
title: "Login Feature with Basic Authentication"
description: "Implement login/logout with JWT + session auth, custom RBAC for construction management system"
status: complete
priority: P1
effort: 12h
branch: main
tags: [authentication, security, rbac, flask, nextjs]
created: 2026-01-18
completed: 2026-01-18
---

# Login Feature Implementation Plan

## Overview

Implement basic authentication (login/logout) with dual auth support (JWT + session-based), custom RBAC with flexible permissions, for Flask backend and Next.js 15 frontend.

## Requirements Summary

| Requirement | Decision |
|-------------|----------|
| Auth Type | Both JWT (API) + Session (web) |
| Storage | PostgreSQL |
| Features | Login/logout only |
| RBAC | Custom roles with permissions |

## Architecture

```
Backend (Flask 3.0+)          Frontend (Next.js 15)
┌─────────────────┐           ┌─────────────────┐
│ Auth Blueprint  │◄──────────│ Login Page      │
│ /api/v1/auth/*  │  HTTP     │ Auth Context    │
├─────────────────┤           ├─────────────────┤
│ Ports/Adapters  │           │ Middleware      │
│ (Hexagonal)     │           │ Protected Route │
├─────────────────┤           └─────────────────┘
│ User/Role/Perm  │
│ (PostgreSQL)    │
└─────────────────┘
```

## Implementation Phases

| Phase | Name | Status | Effort | Description |
|-------|------|--------|--------|-------------|
| 01 | [Database Schema](phase-01-database-schema.md) | complete | 2h | User, Role, Permission tables with migrations (completed 2026-01-18) |
| 02 | [Backend Auth Core](phase-02-backend-auth-core.md) | complete | 3h | Domain entities, ports, adapters (hexagonal) (completed 2026-01-18) |
| 03 | [Backend Auth Endpoints](phase-03-backend-auth-endpoints.md) | complete | 2h | Login/logout API routes, JWT/session handling (completed 2026-01-18, 58 tests, reviewed 9/10) |
| 04 | [Frontend Auth Infrastructure](phase-04-frontend-auth-infra.md) | complete | 2h | Auth context, API client updates, middleware (completed 2026-01-18, reviewed 9/10) |
| 05 | [Frontend Login UI](phase-05-frontend-login-ui.md) | complete | 2h | Login page, protected routes, logout (completed 2026-01-18, reviewed 9/10) |
| 06 | [Testing & Security](phase-06-testing-security.md) | complete | 1h | Unit tests, security validation (completed 2026-01-18, 99 tests, 86% coverage) |

## Key Dependencies

- PostgreSQL database (existing docker-compose)
- Redis for session/token management (existing)
- Flask-JWT-Extended, Argon2, Pydantic (to install)

## Research Reports

- [Flask Auth Report](research/researcher-01-flask-auth-report.md)
- [Next.js Auth Report](research/researcher-02-nextjs-auth-report.md)

## Success Criteria

- [x] User can login with email/password
- [x] JWT token issued for API clients
- [x] Session cookie issued for web browsers
- [x] Protected routes require authentication
- [x] RBAC enforces role-based access
- [x] Logout clears session/token
- [x] All tests pass (99 tests, 86% coverage)

---

## Validation Summary

**Validated:** 2026-01-18
**Questions asked:** 4

### Confirmed Decisions

| Decision | User Choice | Notes |
|----------|-------------|-------|
| Token Revocation | Redis blacklist | Store revoked JTIs in Redis with TTL |
| Admin Setup | Seed script | CLI command to create initial admin |
| Token Expiry | 30 minutes | Standard balance of security/UX |
| Default Roles | Admin + Manager + User | Three-tier permission system |

### Action Items

- [x] **Phase 01**: Add token blacklist table OR Redis key structure
- [ ] **Phase 01**: Create seed script for admin user + roles/permissions
- [x] **Phase 01**: Define Manager role with project CRUD permissions
- [x] **Phase 03**: Implement Redis token blacklist in `revoke_token()`

### Role/Permission Matrix (Confirmed)

| Role | Permissions |
|------|-------------|
| admin | `*:*` (all resources, all actions) |
| manager | `project:*`, `user:read` |
| user | `project:read`, `user:read` (self only)
