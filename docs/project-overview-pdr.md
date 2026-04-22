# Construction Management System - Project Overview & PDR

**Last Updated:** 2026-01-28
**Status:** Phase 04 Complete (Auth Infrastructure)
**Version:** 1.0

## Executive Summary

The Construction Management System (CMS) is a full-stack web application designed to streamline project management, team collaboration, and resource planning for construction firms. The system employs hexagonal architecture with domain-driven design principles for long-term maintainability and scalability.

**Target Users:** Construction project managers, site supervisors, team leads, administrators
**Deployment:** Cloud-native (Vercel + AWS) or self-hosted (Docker)
**Time Horizon:** 12-month MVP → feature-complete system

## Business Objectives

| Objective | Success Metric | Status |
|-----------|---|---|
| Secure authentication & authorization | Zero security vulnerabilities, 100% password hashing | ✅ Done |
| Intuitive project management UI | <3s page load, responsive design | 🔄 In Progress |
| Multi-language support | en, vi, fr locales fully translated | ⚠️ Partial |
| Team collaboration features | Real-time updates, activity feeds | 📋 Planned |
| Mobile-friendly interface | 90+ Lighthouse score | ⚠️ Partial |
| Production-ready deployment | <10ms p99 latency, 99.5% uptime | 📋 Planned |

## Project Scope

### In Scope (MVP Phase 1)
✅ User authentication (login/logout/refresh)
✅ Role-based access control (admin/manager/user)
✅ Project CRUD operations
✅ Team member management
✅ Basic dashboard
✅ Multi-language UI (en, vi)
⚠️ Security hardening & testing

### Out of Scope (Future Phases)
- Real-time collaboration (WebSockets)
- Advanced analytics & reporting
- Mobile native apps
- Payment integration
- Social features (comments, mentions)
- Project timeline/Gantt charts
- Resource allocation optimization

## Technical Requirements

### Functional Requirements

**FR-01: Authentication**
- Users can log in with email + password
- Passwords hashed with Argon2id (OWASP compliant)
- Tokens expire (30min access, 7day refresh)
- Users can log out and revoke tokens
- Rate limiting on login (5 attempts/min)

**FR-02: Authorization**
- Three default roles: admin, manager, user
- Resource-action permission model (project:read, user:create)
- Wildcard permissions (*:* for admin)
- Multi-layer auth checks (middleware + route)

**FR-03: Project Management**
- Create, read, update, delete projects
- Filter & search projects
- Assign team members to projects
- Track project status (active, completed, archived)

**FR-04: Internationalization**
- Support en, vi, fr locales
- Locale-prefixed routing (/{locale}/dashboard)
- User can switch language
- Database-agnostic translation system

**FR-05: API Design**
- REST v1 endpoints with URI versioning
- Pydantic validation on all inputs
- Standardized error responses
- Swagger/OpenAPI documentation

### Non-Functional Requirements

| Category | Requirement | Target |
|----------|---|---|
| Performance | API response time | <200ms p95 |
| Availability | Uptime SLA | 99.5% |
| Security | OWASP Top 10 coverage | 100% (critical) |
| Scalability | Concurrent users | 10,000+ |
| Code Quality | Test coverage | >80% |
| Documentation | API docs | 100% endpoints |

### Technical Constraints

1. **Frontend:**
   - Next.js 16+ with App Router (RSC support)
   - React 19 with TypeScript strict mode
   - Tailwind CSS v4 (no CSS-in-JS)
   - Max bundle size: 150KB (gzipped)

2. **Backend:**
   - Python 3.12+ with type hints
   - SQLAlchemy 2.0 with async support (future)
   - PostgreSQL 15+ (no MongoDB)
   - Flask 3.0 (no FastAPI/Django initially)

3. **Infrastructure:**
   - Redis for caching & sessions
   - Docker containerization
   - Environment-based configuration
   - No global dependencies (use venv)

4. **Code Standards:**
   - Max 200 LOC per file (soft limit)
   - Ruff linting, mypy type checking
   - ESLint + Prettier on frontend
   - Conventional commits

## Architecture Overview

### Hexagonal Architecture

**Design Pattern:** Ports & Adapters with DDD principles

**Layers (Backend):**
```
API Layer (Primary Adapters)
  ↓
Application Layer (Use Cases)
  ↓
Domain Layer (Pure Business Logic)
  ↓
Infrastructure Layer (Secondary Adapters)
  ↓
External Services (DB, Redis, Auth)
```

**Benefits:**
- Business logic independent of frameworks
- Easy to test (mock external services)
- Technology agnostic (swap implementations)
- Clear separation of concerns

### Technology Stack Decision

**Why Flask (not FastAPI)?**
- Mature ecosystem & community
- Excellent documentation
- Perfect for MVP scope
- Easy to integrate with RQ (task queue)

**Why Next.js (not SPA)?**
- Server-side rendering for SEO
- Built-in API routes (no separate backend needed for auth)
- App Router with RSC support
- Excellent i18n support (next-intl)

**Why PostgreSQL (not MongoDB)?**
- Strong ACID compliance
- Excellent for relational data (projects ← users, teams)
- Full-text search support
- JSON fields for flexibility

## Security Architecture

### Defense Layers

1. **Input Validation:** Pydantic schemas enforce type & range checks
2. **Rate Limiting:** Redis-backed token bucket (5 login/min)
3. **Authentication:** JWT with short expiry + refresh tokens
4. **Authorization:** RBAC checks at middleware + route level
5. **Token Revocation:** Redis blacklist (immediate logout)
6. **Password Security:** Argon2id (GPU-resistant, OWASP approved)
7. **CSRF Protection:** SameSite=Lax cookies
8. **HTTPS Enforcement:** Secure flag in production

### OWASP Coverage

| OWASP | Vulnerability | Implementation |
|-------|---|---|
| A01 | Broken Access Control | RBAC, layered auth checks |
| A02 | Cryptographic Failures | Argon2id, JWT signing, httpOnly cookies |
| A03 | Injection | Pydantic validation, SQLAlchemy ORM |
| A04 | Insecure Design | Hexagonal arch, DDD principles |
| A05 | Misconfiguration | Env-based config, secrets mgmt |
| A07 | Auth Failures | Rate limiting, secure token handling |

### Future Security Enhancements

- [ ] Two-factor authentication (TOTP/SMS)
- [ ] Audit logging for all auth events
- [ ] Session timeout on inactivity
- [ ] Brute force protection (progressive delays)
- [ ] Password reset flow with secure tokens
- [ ] API key authentication for integrations

## Database Design

### Core Schema

**users**
- id (UUID, PK)
- email (VARCHAR 255, UNIQUE)
- password_hash (VARCHAR 255)
- is_active (BOOLEAN)
- created_at, updated_at (TIMESTAMP)

**roles**
- id (UUID, PK)
- name (VARCHAR 100, UNIQUE)
- description (TEXT)

**permissions**
- id (UUID, PK)
- resource (VARCHAR 100)
- action (VARCHAR 100)
- UNIQUE(resource, action)

**projects**
- id (UUID, PK)
- name (VARCHAR 255)
- description (TEXT)
- status (ENUM: active, completed, archived)
- owner_id (UUID, FK → users)
- created_at, updated_at (TIMESTAMP)

**Relationships:**
- user_roles (many-to-many)
- role_permissions (many-to-many)
- project_members (many-to-many, with role)

## Implementation Roadmap

### Phase 01-04: Foundation (COMPLETED)
✅ Project setup, Docker, database
✅ Backend auth infrastructure (JWT, passwords)
✅ Frontend auth infrastructure (cookies, middleware)
✅ API endpoints (login, logout, refresh, /me)

### Phase 05-06: MVP Features
🔄 Frontend login UI & session management
🔄 Project CRUD endpoints & UI
- Team member management UI
- Dashboard with project list

### Phase 07-09: Polish & Testing
- Comprehensive test suite (>80% coverage)
- Security audit & penetration testing
- Performance optimization
- Documentation completion

### Phase 10-12: Deployment & Release
- Production deployment (Vercel + AWS)
- Monitoring & alerting setup
- CI/CD pipeline completion
- Launch & post-launch support

## Success Criteria

### MVP Acceptance

**Functional:**
- ✅ Login/logout works with secure tokens
- 🔄 Project CRUD fully functional
- 🔄 User can switch roles & languages
- 🔄 API documentation complete

**Non-Functional:**
- ✅ Zero OWASP Top 10 critical issues
- 🔄 All endpoints <200ms p95 response time
- 🔄 >80% code coverage (backend + frontend)
- 🔄 Responsive design (mobile + desktop)

**Quality:**
- ✅ All commits follow conventional format
- ✅ No type errors in TypeScript/mypy
- ✅ All tests passing in CI/CD
- 🔄 Zero security vulnerabilities (per audit)

## Risk Assessment

| Risk | Probability | Impact | Mitigation |
|------|---|---|---|
| Database migration issues | Medium | High | Automated migrations, rollback testing |
| Auth token compromise | Low | Critical | Redis blacklist, short expiry, logging |
| Performance bottlenecks | Medium | Medium | Caching strategy, connection pooling, CDN |
| Team knowledge gaps | Low | Medium | Documentation, code review, pair programming |
| Feature scope creep | High | High | Strict backlog prioritization, sprint reviews |

## Dependencies & Integrations

### External Services
- **PostgreSQL:** Database (managed RDS in prod)
- **Redis:** Session store, rate limiting, token blacklist
- **SMTP:** Email delivery (future: password reset)
- **S3/GCS:** File storage (future: project documents)

### Third-Party Libraries

**Backend:**
- Flask 3.0, SQLAlchemy 2.0, Pydantic
- Flask-JWT-Extended, Argon2-cffi
- Flask-Limiter, RQ (task queue)
- pytest, pytest-flask (testing)

**Frontend:**
- Next.js 16, React 19, TypeScript 5
- Tailwind CSS 4, shadcn/ui, Lucide icons
- next-intl (i18n), Vitest (testing)
- TanStack Query (future), Zustand (future)

## Stakeholders & Roles

| Role | Responsibility | Decision Authority |
|------|---|---|
| Product Manager | Requirements, roadmap, UX | Scope & timeline |
| Tech Lead | Architecture, code standards | Technical decisions |
| Backend Dev | API endpoints, database | Implementation details |
| Frontend Dev | UI/UX, client logic | Component design |
| DevOps | Infrastructure, deployment | Production env |
| QA Lead | Testing strategy, bug triage | Release readiness |

## Communication Plan

- **Daily:** Standup (15min, async Slack updates)
- **Weekly:** Retrospectives, backlog refinement
- **Bi-weekly:** Demo to stakeholders
- **Monthly:** Executive summary, metrics review

## Metrics & KPIs

### Development Metrics
- Code coverage: >80%
- Test pass rate: 100%
- Build time: <5 minutes
- Deployment frequency: Weekly

### Product Metrics
- User registration growth: 50+/week (target)
- Login success rate: 99.9%+
- Feature adoption: 70%+
- User satisfaction: 4.5/5 stars

### Performance Metrics
- API response time p95: <200ms
- Frontend page load: <3s
- Lighthouse score: 90+
- Error rate: <0.1%

## Next Steps

1. **Immediate (Week 1-2):**
   - Complete frontend login UI
   - Update security checklist with deployment items
   - Set up deployment guide

2. **Short-term (Week 3-4):**
   - Implement project CRUD endpoints
   - Build project list & detail UI
   - Integration testing

3. **Medium-term (Month 2):**
   - Team member management
   - Dashboard implementation
   - Performance optimization

## Questions & Decisions Pending

- Real-time collaboration approach (WebSockets vs. polling)?
- Message queue strategy (RQ vs. Celery vs. Cloud Tasks)?
- Multi-region deployment strategy?
- API rate limiting per user vs. per IP?
- Caching strategy for permissions (TTL)?
