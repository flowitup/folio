# Feature Implementation Checklist

**Last Updated:** 2026-01-24
**Project:** Construction Management System
**Overall Completion:** ~65%

---

## Legend

- [x] Implemented & Working
- [~] Partially Implemented
- [ ] Not Implemented

---

## Backend Features

### API Endpoints

#### Health & Documentation
- [x] GET `/health` - Health check endpoint
- [x] GET `/v1/documentation` - Swagger UI

#### Authentication
- [x] POST `/api/v1/auth/login` - User login (5/min rate limit)
- [x] POST `/api/v1/auth/logout` - User logout
- [x] POST `/api/v1/auth/refresh` - Refresh access token
- [x] GET `/api/v1/auth/me` - Get current user info

#### Projects
- [x] GET `/api/v1/projects` - List projects (requires `project:read`)
- [x] POST `/api/v1/projects` - Create project (requires `project:create`)
- [x] GET `/api/v1/projects/:id` - Get project (requires `project:read`)
- [x] PUT `/api/v1/projects/:id` - Update project (requires `project:update`)
- [x] DELETE `/api/v1/projects/:id` - Delete project (requires `project:delete`)

#### Users (Stub - 501)
- [ ] GET `/api/v1/users` - List users
- [ ] GET `/api/v1/users/:id` - Get user by ID
- [ ] POST `/api/v1/users` - Create user
- [ ] PUT `/api/v1/users/:id` - Update user
- [ ] DELETE `/api/v1/users/:id` - Delete user

#### Invitations (invite-only signup)
- [x] POST `/api/v1/invitations` - Create invitation (auth + `project:invite` perm OR project owner; 10/h)
- [x] GET `/api/v1/projects/:id/invitations?status=pending` - List pending (auth + member; 60/min)
- [x] POST `/api/v1/invitations/:id/revoke` - Revoke pending (auth + perm/owner; 30/min)
- [x] GET `/api/v1/invitations/verify/:token` - Public verify (60/min/IP)
- [x] POST `/api/v1/invitations/accept` - Public accept; sets auth cookies (5/min/IP)
- [x] GET `/api/v1/roles` - List roles (excludes superadmin)
- [x] GET `/api/v1/projects/:id/members` - List project members

#### Admin (superadmin · bulk membership)
- [x] POST `/api/v1/admin/users/:id/memberships` - Bulk-add existing user to projects (`*:*` only; 5/h/user, 10/h/IP)
- [x] GET `/api/v1/admin/users?search=q&limit=20` - Search users by email or name (`*:*` only; 30/min)

## Notes (per-project)

| Endpoint | Method | Auth | Purpose |
|---|---|---|---|
| `/api/v1/projects/:id/notes` | POST | JWT + member | Create note |
| `/api/v1/projects/:id/notes` | GET | JWT + member | List project notes |
| `/api/v1/projects/:id/notes/:note_id` | PATCH | JWT + member | Update note (cascades dismissals on schedule change) |
| `/api/v1/projects/:id/notes/:note_id` | DELETE | JWT + member | Delete note |
| `/api/v1/notifications` | GET | JWT | List due reminders for current user across all projects |
| `/api/v1/notifications/:note_id/dismiss` | POST | JWT + member | Dismiss a reminder for current user |

### Settings: Users & Roles tab

- FE relocation only — no new BE endpoints
- Existing endpoints reused: `GET /api/v1/admin/users?search=q&limit=20`, `POST /api/v1/admin/users/<id>/memberships`
- Permission gate: client-side `*:*` check; BE remains authoritative
- Old `/{locale}/admin/users` route → 404 after merge

---

## Labor · Export (Excel / PDF)

| Method | Path | Auth | Notes |
|---|---|---|---|
| GET | `/api/v1/projects/<id>/labor-export?from=YYYY-MM&to=YYYY-MM&format=xlsx\|pdf` | jwt + project:read + project membership | sync streaming, 24-month cap, per-user rate limit (5/min, `key_func=jwt_user_key`), 422/403/404 paths |
| GET | `/api/v1/projects/<id>/workers/<worker_id>/labor-export?from=YYYY-MM&to=YYYY-MM&format=xlsx\|pdf` | jwt + project:read + project membership | single-worker scope; one-sheet xlsx, PDF parity (no daily detail); 404 `worker_not_found` (cross-project) / `worker_inactive` (deactivated); 422 `invalid_worker_id` (bad UUID); same per-user rate limit as project-wide |

**New BE dependencies (prod):** `openpyxl`, `reportlab`, `python-slugify`
**New BE dependencies (dev/test):** `pypdf`
**New FE dependencies:** none (uses existing shadcn primitives)
**Bundled assets:** DejaVu Sans + Bold TTF (~1.4 MB) at `app/domain/labor/export/fonts/` — Bitstream Vera + DejaVu open-font license

**Security hardening shipped with single-worker scope (also applied to project-wide route):**
- `@require_project_access()` membership check — `project:read` claim alone is no longer sufficient
- Per-user rate-limit key (`jwt_user_key`) — was per-IP
- `xml.sax.saxutils.escape` for `project_name` / `worker_name` / `generated_by_email` before ReportLab Paragraph interpolation

---

## Invoices · Monthly Export (Excel / PDF)

| Method | Path | Auth | Notes |
|---|---|---|---|
| GET | `/api/v1/projects/<id>/invoices-export?from=YYYY-MM&to=YYYY-MM&format=xlsx\|pdf[&type=client\|labor\|supplier]` | jwt + project:read + project membership | sync streaming, 24-month cap, per-user rate limit (5/min, `key_func=jwt_user_key`); xlsx = Summary + per-type sheets (skips empty types); pdf = summary page + ONE polished invoice per page; empty range renders clean "No invoices in range" message; 422 (invalid YYYY-MM / range > 24 / unknown type / year out of 1900-2199), 403, 404 paths |

**New BE dependencies:** none (reuses `openpyxl`, `reportlab`, `python-slugify` from labor)
**New FE dependencies:** none (reuses `triggerBrowserDownload`, shadcn primitives, `formatEUR`)
**Bundled assets:** none (cross-package font reuse from `app/domain/labor/export/fonts/`)

**Cross-cutting fixes shipped with this feature (also applied to labor):**
- `${apiBaseUrl}/api/v1/...` → `${apiBaseUrl}/...` — `NEXT_PUBLIC_API_BASE_URL` already includes `/api/v1`; the literal was producing `/api/v1/api/v1/projects/...` → 404. Fixed in `fetchInvoiceExport`, `fetchLaborExport`, `fetchWorkerLaborExport`. URL-pinning regex assertions added in 3 unit-test files so future drift fails CI.
- YYYY-MM regex tightened to `^(19|20|21)\d{2}-(0[1-9]|1[0-2])$` on both `ExportInvoicesQuery` and `ExportLaborQuery`. Previously `from=to=0000-01` → 500 via `date(0, 1, 1)`.
- `format_validation_error(exc)` extracted to `app/api/_helpers/pydantic_errors.py`; invoice + both labor export routes share it.
- `parseFilenameFromContentDisposition` extracted to `src/lib/api/_helpers/content-disposition.ts`; invoice + labor exporters share it.
- Admin test fixtures no longer grant `*:*`, so `@require_permission("project:read")` is actually exercised by tests.

---

## Labor · Supplement Hours

| Endpoint | Method | Change | Notes |
|---|---|---|---|
| `/api/v1/projects/<project_id>/labor-entries` | POST | gains `supplement_hours: int (0..12)`; `shift_type` now optional | `chk_labor_entry_nonempty` rejects both fields absent; `chk_labor_supplement_hours_range` enforces 0–12 |
| `/api/v1/projects/<project_id>/labor-entries/<entry_id>` | PUT | gains `supplement_hours` | same validators |
| `/api/v1/projects/<project_id>/labor-summary` | GET | response gains per-worker `banked_hours`, `bonus_full_days`, `bonus_half_days`, `bonus_cost`; top-level `total_banked_hours`, `total_bonus_days`, `total_bonus_cost` | additive, backward-compatible |

**Schema delta (migration `20a22df3582d`):**
- `supplement_hours INT NOT NULL DEFAULT 0` added to `labor_entries`
- `shift_type` made nullable (was NOT NULL)
- CHECK `chk_labor_supplement_hours_range`: `supplement_hours >= 0 AND supplement_hours <= 12`
- CHECK `chk_labor_entry_nonempty`: `shift_type IS NOT NULL OR supplement_hours > 0`

---

### Domain Entities

#### User Entity
- [x] UUID primary key
- [x] Email (unique, normalized)
- [x] Password hash (Argon2)
- [x] is_active flag
- [x] created_at / updated_at timestamps
- [x] Many-to-many roles relationship
- [x] `create()` factory method
- [x] `add_role()` / `remove_role()` methods
- [x] `has_permission()` / `has_role()` methods

#### Role Entity
- [x] UUID primary key
- [x] Name (unique, lowercase)
- [x] Description (optional)
- [x] Many-to-many permissions relationship
- [x] `create()` factory method
- [x] `add_permission()` / `has_permission()` methods

#### Permission Entity
- [x] UUID primary key
- [x] Name (format: `resource:action`)
- [x] Resource/action extraction
- [x] Wildcard support (`*:*`, `resource:*`)
- [x] `create()` factory method
- [x] `matches()` wildcard-aware matching

#### Project Entity
- [x] UUID primary key
- [x] Name (required, max 200 chars)
- [x] Address (optional, max 500 chars)
- [x] Owner ID (foreign key to User)
- [x] created_at / updated_at timestamps
- [x] Many-to-many users relationship (project members)
- [x] `create()` factory method

#### Value Objects
- [x] Email - Validated, normalized
- [x] Password - Min 8 chars validation

---

### Domain Services

#### AuthenticationService
- [x] `authenticate(email, password)` - Credential validation
- [x] `hash_password(password)` - Password hashing
- [x] Timing attack prevention
- [x] Generic error messages (prevents enumeration)

#### AuthorizationService
- [x] `get_user_permissions(user_id)` - Aggregate permissions
- [x] `has_permission(user_id, permission)` - Single permission check
- [x] `has_any_permission(user_id, permissions)` - Any permission check
- [x] `has_all_permissions(user_id, permissions)` - All permissions check
- [x] `has_role(user_id, role_name)` - Role check
- [x] Wildcard permission support

---

### Use Cases

#### LoginUseCase
- [x] Email/password validation (Pydantic)
- [x] User lookup (case-insensitive)
- [x] Active status verification
- [x] Password verification (Argon2)
- [x] Permission aggregation
- [x] Access + refresh token generation
- [x] Returns LoginResult with tokens + user

#### LogoutUseCase
- [x] JWT ID extraction
- [x] Token blacklist (Redis/memory)
- [x] Token invalidation

#### Project Use Cases
- [x] CreateProjectUseCase - Create new project with owner
- [x] GetProjectUseCase - Retrieve project by ID
- [x] ListProjectsUseCase - List projects (admin: all, user: own/member)
- [x] UpdateProjectUseCase - Update project details
- [x] DeleteProjectUseCase - Delete project

---

### Infrastructure Adapters

#### Database
- [x] SQLAlchemy ORM integration
- [x] PostgreSQL support (production)
- [x] SQLite support (development/testing)
- [x] Case-insensitive email index
- [x] Composite permission index

#### Security
- [x] Argon2PasswordHasher (64MB memory, 2 iterations)
- [x] JWTTokenIssuer (access: 30min, refresh: 7d)
- [x] Token blacklist with Redis backing
- [x] In-memory fallback for testing
- [x] Rate limiting (Flask-Limiter)
- [x] CSRF protection for cookie auth

#### Session
- [~] FlaskSessionManager (in-memory only, not production-ready)
- [ ] Redis-based session storage

---

### Middleware & Decorators
- [x] `@jwt_required()` - Valid access token
- [x] `@require_permission(*perms)` - All permissions required
- [x] `@require_any_permission(*perms)` - Any permission required
- [x] `@require_role(*roles)` - Role check
- [x] CORS enabled (all origins)
- [x] Rate limiting (5/min login, 100/min default)

---

### Background Jobs (RQ)
- [x] Queue infrastructure (default, emails, outbox)
- [x] Worker configuration
- [~] `send_email` task (STUB - logs only)
- [~] `process_notification` task (STUB - not implemented)
- [ ] Outbox pattern processor

---

### Database Migrations
- [x] Users table
- [x] Roles table
- [x] Permissions table
- [x] user_roles junction table
- [x] role_permissions junction table
- [x] Projects table
- [x] user_projects junction table
- [x] All indexes created

---

### Testing
- [x] Auth endpoint tests (15+ tests)
- [x] Auth model tests (10+ tests)
- [x] Domain entity tests (15+ tests)
- [x] Auth service tests (8+ tests)
- [x] Authorization service tests (12+ tests)
- [x] Password hasher tests (17+ tests)
- [x] Project repository tests (15+ tests)
- [x] Project use case tests (12+ tests)
- [x] pytest configuration
- [x] In-memory SQLite for tests
- [x] **Total: 126 backend tests**

---

### Docker & Infrastructure
- [x] Flask API container (port 5000)
- [x] PostgreSQL container (port 5432)
- [x] Redis container (port 6379)
- [x] RQ Worker container
- [x] Health checks configured
- [x] Volume persistence

---

## Frontend Features

### Pages & Routes

#### Public Pages
- [~] `/` - Landing page (placeholder template)
- [x] `/login` - Authentication page
- [x] `/unauthorized` - 403 error page

#### Protected Pages (App Shell)
- [~] `/(app)/dashboard` - Dashboard (placeholder metrics)
- [~] `/(app)/projects` - Projects list (scaffold only)
- [~] `/(app)/settings` - Settings (scaffold only)

---

### Authentication UI

#### Login Feature
- [x] LoginForm component
- [x] Email/password inputs
- [x] Client-side validation
- [x] Error handling with alert display
- [x] Loading state with spinner
- [x] Disabled inputs during submission
- [x] Accessibility (aria-describedby, role=alert)

#### Session Management
- [x] Cookie-based auth (HttpOnly, Secure)
- [x] CSRF token support
- [x] JWT payload decoding
- [x] Token refresh mechanism

#### Route Protection
- [x] Middleware (cookie presence check)
- [x] ProtectedRoute component
- [x] Required permissions validation
- [x] Required roles validation
- [x] Redirect to /unauthorized on failure
- [x] Redirect authenticated users from /login

---

### Layout Components

#### Sidebar
- [x] 264px fixed width
- [x] Navigation menu (Dashboard, Projects, Settings)
- [x] Active route highlighting
- [x] Emoji icons
- [ ] Mobile collapse/hamburger

#### Topbar
- [x] User email display
- [x] User avatar
- [x] Sign out button
- [~] Notification bell (non-functional)

---

### State Management

#### AuthContext
- [x] AuthProvider component
- [x] useAuth() hook
- [x] User state
- [x] isAuthenticated flag
- [x] isLoading state
- [x] login(credentials) method
- [x] logout() method
- [x] Server-side session initialization

#### AuthErrorBoundary
- [x] Error boundary component
- [x] Fallback UI
- [x] Recovery redirect to login

---

### API Integration

#### HTTP Client
- [x] Generic `http<TResponse, TBody>()` wrapper
- [x] ApiError class with status + data
- [x] Automatic JSON serialization
- [x] Automatic credential handling
- [x] Convenience methods (get, post, put, patch, delete)

#### Endpoints Called
- [x] POST `/auth/login`
- [x] POST `/auth/logout`
- [x] POST `/auth/refresh`
- [x] GET `/auth/me`

---

### Server Actions
- [x] `login(credentials)` - Authenticate user
- [x] `logout()` - Clear session + redirect
- [x] `refreshToken()` - Refresh access token

---

### Utility Functions

#### Formatters
- [x] `formatCurrency(amount)` - USD formatting
- [x] `formatDate(date)` - Readable date
- [x] `truncate(str, maxLength)` - String truncation
- [x] `slugify(str)` - URL-safe conversion
- [x] `isValidEmail(email)` - Email validation

#### Auth Utilities
- [x] `getSession()` - Server-side session retrieval
- [x] `getCurrentUser()` - Get user from session
- [x] `hasPermission(permission)` - Check permission
- [x] `hasRole(role)` - Check role

---

### Testing
- [x] Vitest configuration
- [x] @testing-library/react setup
- [x] API error tests (5 tests)
- [x] Environment config tests (6 tests)
- [x] Formatter tests (21 tests)
- [x] Total: 34 unit tests

---

### Environment & Config
- [x] NEXT_PUBLIC_API_BASE_URL support
- [x] .env.example template
- [x] TypeScript strict mode
- [x] ESLint configuration
- [x] PostCSS + Tailwind CSS v4

---

## Not Implemented (Planned)

### Backend
- [x] ~~Project CRUD operations~~ **COMPLETED**
- [ ] User management endpoints
- [ ] Email service implementation
- [ ] Password reset functionality
- [ ] Account lockout after failed attempts
- [ ] Multi-factor authentication (MFA)
- [ ] OAuth/SSO integration
- [ ] Audit logging
- [ ] Production session storage (Redis)

### Frontend
- [ ] Dashboard metrics with real data
- [ ] Projects list/grid view
- [ ] Create/Edit/Delete project UI
- [ ] Settings forms (Profile, Notifications, Organization)
- [ ] User registration page
- [ ] Forgot password flow
- [ ] Notification dropdown (real-time)
- [ ] Dark mode toggle
- [ ] Mobile responsive sidebar
- [ ] Pagination/virtualization for lists
- [ ] Token auto-refresh on 401

---

## Security Checklist

### Implemented
- [x] Argon2id password hashing (memory-hard)
- [x] Timing attack prevention
- [x] User enumeration prevention
- [x] JWT token revocation
- [x] CSRF protection (cookie auth)
- [x] Rate limiting
- [x] Input validation (Pydantic)
- [x] SQL injection protection (SQLAlchemy)
- [x] HttpOnly/Secure cookies

### Not Implemented
- [ ] Email verification
- [ ] Account lockout
- [ ] MFA/2FA
- [ ] Audit logging
- [ ] OAuth/SSO

---

## Summary

| Category | Backend | Frontend |
|----------|---------|----------|
| Authentication | 100% | 100% |
| Authorization (RBAC) | 100% | 100% |
| Database/Schema | 100% | N/A |
| API Integration | 100% | 100% |
| Project Management | 100% | 5% |
| User Management | 0% | N/A |
| Dashboard | N/A | 10% |
| Settings | N/A | 5% |
| Background Jobs | 20% | N/A |
| Testing | 100% | 100% |
| Docker/Infrastructure | 100% | N/A |

**Overall:** Backend ~75% | Frontend ~40%

---

*Generated from codebase analysis on 2026-01-24*
