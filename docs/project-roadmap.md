# Construction Management System - Project Roadmap

**Last Updated:** 2026-05-03
**Current Phase:** Production deploy live (Option A, GCP)
**Overall Progress:** 65% (Frontend), 85% (Backend), Infra: 100%

## Milestones

- ✅ 2026-05-03: **Production deploy live** at https://folio.flowitup.com
  (Option A — single GCE VM in europe-west1, fronted by Cloudflare Tunnel,
  fully documented in `docs/deployment-guide.md`).

## Roadmap Overview

```
Phase 01-04: Foundation (COMPLETED) ████████████████░░░░░
Phase 05-07: MVP Features (IN PROGRESS) ████░░░░░░░░░░░░░░░░
Phase 08: Domain Modules (COMPLETED) ████████████████░░░░░
Phase 09-10: Production Ready (PLANNED) ░░░░░░░░░░░░░░░░░░░░
Phase 11-12: Advanced Features (FUTURE) ░░░░░░░░░░░░░░░░░░░░
```

## Phase 01: Project Setup & Infrastructure

**Duration:** Week 1-2
**Status:** ✅ COMPLETED (2026-01-18)
**Progress:** 100%

### Deliverables
- ✅ Repository structure (hexagonal architecture)
- ✅ Docker & Docker Compose setup
- ✅ PostgreSQL + Redis + Flask + Next.js containers
- ✅ Database migrations framework (Alembic)
- ✅ Dependency management (requirements.txt, package.json)
- ✅ Environment configuration (12-factor app)

### Achievements
- Project structure aligned with DDD principles
- Full Docker containerization ready
- Database schema with auth tables
- Initial seed data (admin user)

### Notes
- Skip K8s initially, use Docker Compose for simplicity
- Redis used for sessions + rate limiting (future: more uses)

---

## Phase 02: Backend Authentication & Authorization

**Duration:** Week 3-4
**Status:** ✅ COMPLETED (2026-01-25)
**Progress:** 100%

### Deliverables
- ✅ JWT token generation & validation
- ✅ Password hashing (Argon2id)
- ✅ RBAC system (roles & permissions)
- ✅ Token revocation (Redis blacklist)
- ✅ Rate limiting on auth endpoints
- ✅ Dependency injection container (wiring.py)

### Achievements
- Secure password handling (no plaintext storage)
- Stateless authentication (JWT)
- Role-based authorization (admin/manager/user)
- Comprehensive error handling & validation

### Technical Details
- **Algorithm:** Argon2id with auto-generated salt
- **Token Expiry:** 30min access, 7day refresh
- **Rate Limiting:** 5 login attempts per IP per minute
- **Cookie Security:** httpOnly, Secure (prod), SameSite=Lax

---

## Phase 03: Backend API Endpoints

**Duration:** Week 5-6
**Status:** ✅ COMPLETED (2026-01-25)
**Progress:** 100%

### Deliverables
- ✅ `/api/v1/auth/login` - Authenticate user
- ✅ `/api/v1/auth/logout` - Revoke token
- ✅ `/api/v1/auth/refresh` - Get new access token
- ✅ `/api/v1/auth/me` - Get current user
- ✅ Pydantic validation schemas
- ✅ Swagger/OpenAPI documentation
- ✅ Integration tests (100% coverage)

### Achievements
- Clean REST API design (URI versioning)
- Standardized request/response format
- Comprehensive endpoint testing
- Error response standardization

### API Endpoints Summary
| Endpoint | Method | Auth | Purpose |
|----------|--------|------|---------|
| /auth/login | POST | None | Login with credentials |
| /auth/logout | POST | Optional | Revoke token |
| /auth/refresh | POST | Refresh | Get new access token |
| /auth/me | GET | Required | Current user info |

---

## Phase 04: Frontend Auth Infrastructure

**Duration:** Week 7-8
**Status:** ✅ COMPLETED (2026-01-27)
**Progress:** 100%

### Deliverables
- ✅ Server-side session management (getSession, requireAuth)
- ✅ Server actions (login, logout)
- ✅ Next.js middleware (route protection)
- ✅ React Context (AuthContext + AuthProvider)
- ✅ Auth error boundary
- ✅ Cookie-based authentication flow
- ✅ Frontend unit tests (34 tests, all passing)

### Achievements
- Secure cookie-based authentication
- Server-side session validation
- Client-side auth state management
- Route protection (protected vs. auth vs. public)
- Type-safe auth patterns

### Architecture
- **Cookie Transport:** HTTP-only, Secure (prod)
- **Client State:** React Context (AuthContext)
- **Middleware:** Route protection at Next.js level
- **Error Handling:** AuthErrorBoundary with auto-logout

### Test Coverage
- ApiError class tests
- Environment config validation
- Utility formatters (currency, date, slug)
- Setup verification tests
- Total: 34 tests (100% passing)

---

## Phase 05: Frontend Login UI & Session Management

**Duration:** Week 9-10
**Status:** 🔄 IN PROGRESS (Started 2026-01-28)
**Progress:** 0%

### Objectives
- Build polished login form UI
- Implement password reset flow (optional for MVP)
- Session timeout handling
- Error state management
- Multi-language login page

### Tasks

#### 05.1: Login Form Component
- [ ] Create LoginForm component (email + password inputs)
- [ ] Form validation (email format, password strength)
- [ ] Error message display
- [ ] Loading state while authenticating
- [ ] Remember me checkbox (optional)
- **Files:** src/components/auth/login-form.tsx

#### 05.2: Login Page Layout
- [ ] Create /login page with form
- [ ] Redirect authenticated users → /dashboard
- [ ] Callback URL support (?callbackUrl=/original-path)
- [ ] Fintech-minimalist design (blue accent, white bg)
- [ ] Responsive mobile layout
- **Files:** src/app/[locale]/(auth)/login/page.tsx

#### 05.3: Session Management
- [ ] Auto-logout on token expiry
- [ ] Token refresh strategy
- [ ] Session timeout indicator (optional)
- [ ] Graceful error handling (401 → login)
- **Files:** src/lib/auth/session-handler.ts

#### 05.4: Internationalization
- [ ] Translate login page (en, vi, fr)
- [ ] Error message translations
- [ ] Language switcher on login page
- **Files:** messages/{en,vi,fr}.json

#### 05.5: Testing
- [ ] Unit tests for LoginForm component
- [ ] E2E tests for login flow (Playwright)
- [ ] Error scenario testing
- [ ] Target: >80% coverage
- **Files:** src/__tests__/auth/login-form.test.tsx

### Success Criteria
- [ ] Login form renders without errors
- [ ] Valid credentials authenticate successfully
- [ ] Invalid credentials show error message
- [ ] Authenticated users redirect to /dashboard
- [ ] Session persists across page reloads
- [ ] Logout clears session
- [ ] Tests pass (>80% coverage)
- [ ] Mobile responsive (320px+)
- [ ] Lighthouse score 90+

### Estimated Effort
- Design & Component: 2 days
- Integration & Testing: 2 days
- i18n & Polish: 1 day
- **Total:** 5 days

### Dependencies
- ✅ Phase 04 (Auth Infrastructure)
- React & Next.js setup
- shadcn/ui form components

---

## Phase 06: Project Management - Backend

**Duration:** Week 11-12
**Status:** 📋 PLANNED
**Progress:** 0%

### Objectives
- Implement project CRUD endpoints
- Project filtering & search
- Team member assignment
- Status tracking (active/completed/archived)

### Endpoints to Create

#### 06.1: Project CRUD
- [ ] `POST /api/v1/projects` - Create project
- [ ] `GET /api/v1/projects` - List projects (paginated)
- [ ] `GET /api/v1/projects/{id}` - Get project details
- [ ] `PUT /api/v1/projects/{id}` - Update project
- [ ] `DELETE /api/v1/projects/{id}` - Delete project

#### 06.2: Team Management
- [ ] `POST /api/v1/projects/{id}/members` - Add team member
- [ ] `GET /api/v1/projects/{id}/members` - List members
- [ ] `DELETE /api/v1/projects/{id}/members/{memberId}` - Remove member

#### 06.3: Database Models
- [ ] Project entity & repository
- [ ] ProjectMember join table
- [ ] Migration for projects table

### Success Criteria
- [ ] All endpoints return correct status codes
- [ ] Pagination working (limit, offset)
- [ ] Authorization checks (owner/manager can edit)
- [ ] Input validation comprehensive
- [ ] Integration tests >90% coverage

### Estimated Effort
- Endpoints: 3 days
- Database & Migrations: 1 day
- Testing: 1 day
- **Total:** 5 days

---

## Phase 07: Project Management - Frontend

**Duration:** Week 13-14
**Status:** 📋 PLANNED
**Progress:** 0%

### Objectives
- Project list UI with filtering
- Project detail page
- Create/edit project forms
- Team member management UI

### Components to Build

#### 07.1: Project List Page
- [ ] Table/card view of projects
- [ ] Filter by status (active/completed/archived)
- [ ] Search by project name
- [ ] Sort by created date
- [ ] Create project button
- **File:** src/app/[locale]/(app)/projects/page.tsx

#### 07.2: Project Detail Page
- [ ] Display project info
- [ ] Edit project button
- [ ] Team members section
- [ ] Activity timeline (future)
- **File:** src/app/[locale]/(app)/projects/[id]/page.tsx

#### 07.3: Create/Edit Project Form
- [ ] Project name, description inputs
- [ ] Status dropdown (active/completed/archived)
- [ ] Due date picker (optional for MVP)
- [ ] Validation & error messages
- **File:** src/components/projects/project-form.tsx

#### 07.4: Team Members Component
- [ ] Add member button (modal/form)
- [ ] List team members with roles
- [ ] Remove member button
- [ ] Permission checks (owner only)
- **File:** src/components/projects/team-members.tsx

### Success Criteria
- [ ] Projects list renders correctly
- [ ] CRUD operations work end-to-end
- [ ] Filtering & search functional
- [ ] Responsive design (mobile+)
- [ ] Tests >80% coverage
- [ ] Lighthouse 90+

### Estimated Effort
- List & Detail Pages: 2 days
- Forms & Components: 2 days
- Testing & Polish: 1 day
- **Total:** 5 days

---

## Phase 08: Domain Modules (Labor & Invoices)

**Duration:** Week 13-14
**Status:** ✅ COMPLETED (2026-04-22)
**Progress:** 100%

### Completed Modules

#### Labor Charge Calculator
- Domain entities (Labor, LaborItem)
- Use cases (CRUD operations)
- SQLAlchemy repository
- API endpoints (POST, GET, PUT, DELETE)
- RBAC permission `project:manage_labor`
- Frontend form & list components
- 34 new tests (all passing)

#### Invoices (Factures)
- Domain entities (Invoice, InvoiceItem with JSONB storage)
- Three invoice types (CLIENT, LABOR, SUPPLIER)
- Use cases (CRUD operations)
- SQLAlchemy repository with auto-generated invoice numbers
- API endpoints (POST, GET, PUT, DELETE, list with filtering)
- RBAC permission `project:manage_invoices`
- Frontend form with dynamic line items, list view, print-to-PDF
- 68 new tests (all passing)

### Achievements
- ✅ Hexagonal architecture fully proven across two domain modules
- ✅ Consistent patterns for repository layer, use cases, API endpoints
- ✅ RBAC enforcement on all invoice operations
- ✅ Browser-native print-to-PDF (no external libs)
- ✅ Auto-generated sequential invoice numbers (INV-YYYY-NNNN per project)
- ✅ JSONB items storage (avoids unnecessary joins)

### Test Coverage
- 68 new tests across both modules
- All passing (domain, use cases, API endpoints, components)
- Target >80% coverage maintained

---

## Phase 10: Dashboard & Home Page

**Duration:** Week 15
**Status:** 📋 PLANNED
**Progress:** 0%

### Objectives
- Landing page (non-authenticated)
- Dashboard with project overview
- Quick stats & widgets

### Deliverables
- [ ] Landing page with CTA
- [ ] Dashboard with user's projects
- [ ] Project stats (total, active, completed)
- [ ] Quick action buttons
- [ ] Responsive design

### Estimated Effort: 3 days

---

## Phase 11: Testing & Quality Assurance

**Duration:** Week 16-17
**Status:** 📋 PLANNED
**Progress:** 0%

### Objectives
- Achieve >80% code coverage
- End-to-end testing
- Security audit
- Performance testing

### Tasks
- [ ] Unit test coverage audit
- [ ] Integration test suite
- [ ] E2E tests (Playwright)
- [ ] Security penetration testing
- [ ] Performance benchmark (Lighthouse, Core Web Vitals)
- [ ] Accessibility audit (WCAG 2.1)

### Estimated Effort: 2 weeks

---

## Phase 12: Documentation & Deployment Setup

**Duration:** Week 18
**Status:** 📋 PLANNED
**Progress:** 5% (docs partially done)

### Deliverables
- ✅ README.md (main project doc)
- ✅ System Architecture doc
- ✅ Code Standards doc
- ✅ Codebase Summary
- ✅ Project Overview & PDR
- [ ] Deployment Guide (AWS, Vercel)
- [ ] Contributing Guide
- [ ] API Documentation (Swagger)
- [ ] Troubleshooting Guide

### Estimated Effort: 1 week

---

## Phase 13: Production Deployment

**Duration:** Week 19-20
**Status:** 📋 PLANNED
**Progress:** 0%

### Deliverables
- [ ] Frontend deployment (Vercel)
- [ ] Backend deployment (AWS ECS or Cloud Run)
- [ ] Database setup (AWS RDS)
- [ ] Redis setup (AWS ElastiCache or similar)
- [ ] CI/CD pipeline (GitHub Actions)
- [ ] Monitoring & alerting setup
- [ ] SSL/TLS certificates
- [ ] Domain setup & DNS

### Estimated Effort: 2 weeks

---

## Phase 14: Launch & Post-Launch

**Duration:** Week 21+
**Status:** 📋 FUTURE
**Progress:** 0%

### Activities
- [ ] Beta testing with stakeholders
- [ ] Bug fixes & optimization

---

## Phase 15-16: Advanced Features

### Phase 15: Advanced Invoicing & Reporting
- Invoice templates & customization
- Multi-currency support
- Recurring invoices
- Payment tracking
- Financial reports & analytics

### Phase 16: Real-Time Features & Notifications
- WebSocket support for live updates
- In-app notifications
- Email notifications
- Slack integration
- Activity feeds
- [ ] Performance tuning
- [ ] Official launch announcement
- [ ] Post-launch monitoring

---

## Timeline Summary

| Phase | Duration | Status | Completion Date |
|-------|----------|--------|-----------------|
| 01: Foundation | 2 weeks | ✅ Complete | 2026-01-18 |
| 02: Backend Auth | 2 weeks | ✅ Complete | 2026-01-25 |
| 03: API Endpoints | 2 weeks | ✅ Complete | 2026-01-25 |
| 04: Frontend Auth | 2 weeks | ✅ Complete | 2026-01-27 |
| 05: Login UI | 1 week | 🔄 In Progress | 2026-02-04 |
| 06: Projects Backend | 1 week | 📋 Planned | 2026-02-11 |
| 07: Projects Frontend | 1 week | 📋 Planned | 2026-02-18 |
| 08: Dashboard | 1 week | 📋 Planned | 2026-02-25 |
| 09: QA & Testing | 2 weeks | 📋 Planned | 2026-03-11 |
| 10: Documentation | 1 week | 📋 Planned | 2026-03-18 |
| 11: Production | 2 weeks | 📋 Planned | 2026-04-01 |

**MVP Release Target:** April 2026 (12 weeks from start)

---

## Progress Metrics

### Backend Progress: 75%
- ✅ Auth infrastructure (100%)
- ✅ API endpoints (100%)
- ✅ Database schema (100%)
- 🔄 Projects endpoints (0%)
- 📋 Advanced features (0%)

### Frontend Progress: 55%
- ✅ Project setup (100%)
- ✅ Auth infrastructure (100%)
- 🔄 Login UI (0%)
- 🔄 Projects UI (0%)
- 📋 Dashboard (0%)

### Testing Progress: 50%
- ✅ Backend unit tests (100%)
- ✅ Backend integration tests (100%)
- ✅ Frontend unit tests (100%)
- 🔄 E2E tests (0%)
- 📋 Security audit (0%)

### Documentation Progress: 50%
- ✅ System Architecture (100%)
- ✅ Code Standards (100%)
- ✅ Codebase Summary (100%)
- ✅ Project Overview (100%)
- 🔄 Deployment Guide (0%)

---

## Risk Tracking

| Risk | Likelihood | Impact | Mitigation | Status |
|------|-----------|--------|-----------|--------|
| Schedule delays | Medium | High | Weekly standups, sprint tracking | Monitoring |
| Scope creep | High | High | Strict backlog, phase gates | Mitigating |
| Performance issues | Medium | Medium | Early load testing, caching strategy | Planning |
| Security vulnerabilities | Low | Critical | Code review, security audit | Planned |

---

## Milestones

🎯 **Milestone 1:** Authentication Complete (2026-01-27) ✅
🎯 **Milestone 2:** MVP Features Complete (2026-02-25)
🎯 **Milestone 3:** QA & Documentation (2026-03-18)
🎯 **Milestone 4:** Production Ready (2026-04-01)
🎯 **Milestone 5:** Official Launch (2026-04-15)

---

## Future Enhancements (Post-MVP)

### Phase 13: Advanced Features
- Real-time collaboration (WebSockets)
- Project timeline/Gantt charts
- Resource allocation & optimization
- Budget tracking & reporting
- Mobile-native apps (React Native)

### Phase 14: Integrations
- Slack notifications
- Google Calendar sync
- GitHub integration
- Email notifications
- Third-party tools (Stripe, SendGrid)

### Phase 15: Analytics & Intelligence
- Advanced project analytics
- Team productivity metrics
- Predictive scheduling
- AI-powered recommendations
- Custom reporting

---

## Key Dependencies

- **PostgreSQL 15+** - Data persistence
- **Redis 7+** - Caching & sessions
- **Docker** - Containerization
- **GitHub Actions** - CI/CD
- **Vercel** - Frontend hosting
- **AWS** - Backend & infrastructure

---

## Contact & Support

For roadmap questions or updates, contact the product team.
For technical implementation details, see [System Architecture](./system-architecture.md).
