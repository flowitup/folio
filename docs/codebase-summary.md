# Codebase Summary

**Last Updated:** 2026-01-28
**Total Files:** 304 (includes .git)
**Total Tokens:** ~280,170 (Repomix)
**Actual Source:** ~2,800 LOC (backend) + ~1,200 LOC (frontend)

## Project Overview

Construction Management System with Flask backend and Next.js frontend implementing hexagonal architecture with domain-driven design principles.

## Architecture

**Pattern:** Hexagonal Architecture (Ports & Adapters)
**Backend:** Flask 3.0+ with SQLAlchemy, PostgreSQL
**Frontend:** Next.js 16 with App Router, React 19, React Server Components
**Database:** PostgreSQL with Alembic migrations
**Cache/Sessions:** Redis
**Auth:** JWT + Cookie-based (hybrid)

## Core Components

### Backend Structure

```
construction-back-end/
├── app/
│   ├── api/v1/              # API endpoints (adapters)
│   │   └── auth/            # Auth endpoints
│   │       ├── routes.py    # Login, logout, refresh, /me
│   │       ├── schemas.py   # Pydantic request/response models
│   │       ├── middleware.py # Auth middleware
│   │       └── __init__.py
│   ├── application/         # Use cases (application layer)
│   │   └── auth/
│   │       ├── login_usecase.py
│   │       └── ports.py     # Interfaces (IUserRepository, etc.)
│   ├── domain/              # Core business logic
│   │   ├── entities/        # User, Role, Permission
│   │   ├── value_objects/   # Email, HashedPassword
│   │   └── exceptions/      # Domain-specific exceptions
│   ├── infrastructure/      # External adapters
│   │   ├── database/        # SQLAlchemy models & repositories
│   │   ├── auth/            # JWT token issuer, password hasher
│   │   ├── authorization/   # RBAC service
│   │   └── rate_limiter.py  # Flask-Limiter config
│   └── __init__.py          # App factory
├── config/                  # Environment configuration
├── migrations/              # Alembic database migrations
├── tests/                   # Test suite
├── wiring.py                # Dependency injection container
└── run.py                   # Application entry point
```

## Implementation Status

### Completed (Phases 01-08)
- ✅ Project structure & Docker setup
- ✅ Backend auth infrastructure (JWT, RBAC, password hashing)
- ✅ API endpoints (login, logout, refresh, /me)
- ✅ Frontend auth infrastructure (cookies, middleware, Context)
- ✅ Dependency injection container
- ✅ Database schema with migrations
- ✅ Rate limiting & token blacklist
- ✅ Labor charge calculator module (CRUD + RBAC)
- ✅ Invoices (Factures) module — per-project client/labor/supplier invoices with browser print-to-PDF
- ✅ Invitation module — invite-only account creation: admins invite users to projects with per-project roles via tokenized email links (Resend, 7-day expiry, single-use); `app/application/invitations/`, `app/infrastructure/email/`, `app/api/v1/invitations/`; frontend `accept-invite/[token]` (public) + `(app)/projects/[id]/members` (admin)
- ✅ Superadmin bulk-add — `*:*` admins add an existing user to multiple projects with one role applied across all; partial-success per-project results + consolidated email; `app/application/admin/`, `app/api/v1/admin/`; frontend `(app)/admin/users` page (superadmin-only) with debounced user search
- ✅ Notes + in-app notifications — per-project shared notes with due-date reminders; lazy SQL computation (no worker/no notifications table); BE: `app/application/notes/` (8 use-cases) + `app/api/v1/notes/` + `app/api/v1/notifications/`; FE: `src/app/[locale]/(app)/projects/[id]/notes/` (agenda + inline-editable rows) + `src/components/notifications/` (bell + 60s polling)
- ✅ Settings: Users tab (7th, moved from /admin/users) — superadmin (`*:*`) sees the bulk-add form for assigning roles to existing users across projects; non-superadmin sees an inline permission-denied panel. /admin/users route deleted.
- ✅ Labor supplement hours — per-day banked hours (0–12) accumulate across the month; every 8h auto-converts to 1 bonus full-day, 4h remainder to 1 bonus half-day. Standalone supplement-only entries supported (no shift required). Migration `20a22df3582d`; `app/application/labor/`; conversion is pure-derived (no persisted phantom rows).
- ✅ Labor export — per-project Excel/PDF export over a 1..24-month range; includes daily detail (xlsx) + per-worker monthly summary with priced/bonus split (no aggregated total); real Vietnamese/French i18n; `app/domain/labor/export/`; bundled DejaVu fonts for Vietnamese diacritics.
- ✅ Labor export — single-worker scope — `GET /api/v1/projects/<id>/workers/<worker_id>/labor-export`; one-sheet xlsx (worker header + monthly summary + daily detail) and matching pdf header; per-worker Download trigger on the labor page worker list; ships with cross-project membership enforcement (`@require_project_access`), per-user rate-limit (`key_func=jwt_user_key`), `xml.sax.saxutils.escape` defense for ReportLab Paragraph, and a 404 `worker_inactive` block on inactive workers.
- ✅ Invoice export — monthly batch — `GET /api/v1/projects/<id>/invoices-export?from=YYYY-MM&to=YYYY-MM&format=xlsx|pdf[&type=client|labor|supplier]`; xlsx is `Summary` + one sheet per type that exists in the range (per-type sheets skipped when empty); pdf is summary page first then one polished invoice per page (header band, meta, items table, grand-total band, notes); empty range renders a clean "No invoices in range" message in both formats; same security envelope as labor (jwt + project:read + project membership + 5/min/user); reuses `format_eur_fr` and the DejaVu fonts from `app/domain/labor/export/`; FE dialog `InvoiceExportDialog` + i18n parity en/fr/vi at `invoices.export.*`. Same release back-ported a HIGH-1 fix to labor: `${apiBaseUrl}/api/v1/...` was double-prefixing because `apiBaseUrl` already includes `/api/v1` — labor + invoice export URLs were broken end-to-end; fix dropped the literal and added URL-pinning regex assertions in unit tests so future drift fails CI. Shared helpers extracted in this cycle: `app/api/_helpers/pydantic_errors.py::format_validation_error` (BE, used by 3 export routes) and `src/lib/api/_helpers/content-disposition.ts::parseFilenameFromContentDisposition` (FE, used by 2 export clients).

### In Progress (Phase 09)
- 🔄 Frontend login UI & form components
- 🔄 Session timeout handling
- 🔄 E2E auth flow testing

### Planned (Phases 10+)
- 📋 Project CRUD endpoints & UI
- 📋 Team member management
- 📋 Dashboard implementation
- 📋 Comprehensive testing (>80% coverage)
- 📋 Production deployment
- 📋 Advanced features (real-time, analytics)

---

## Frontend Structure

### UI Component Library (Shadcn UI)

**Location:** `construction-front-end/src/components/ui/`

**Installed Components:**
- `button.tsx` - Variant-based button (default/secondary/destructive/outline/ghost/link)
- `input.tsx` - Form input fields with focus states
- `label.tsx` - Accessible form labels
- `select.tsx` - Dropdown select with Radix UI primitives
- `card.tsx` - Content containers (Card/CardHeader/CardTitle/CardContent/CardDescription/CardFooter)
- `badge.tsx` - Status badges (default/secondary/destructive/outline)
- `alert.tsx` - Alert messages (default/destructive)
- `dropdown-menu.tsx` - Context menus with keyboard navigation
- `separator.tsx` - Visual dividers (horizontal/vertical)

**Configuration:**
- `components.json` - Shadcn CLI configuration (New York style, RSC enabled, Lucide icons)
- `src/lib/utils.ts` - cn() utility for Tailwind class merging

**Dependencies:**
- `@radix-ui/react-*` - Accessible primitives (dropdown-menu, label, select, separator, slot)
- `class-variance-authority` - Component variant management
- `clsx` + `tailwind-merge` - Class composition utilities
- `lucide-react` - Icon library

### Design System

**Theme:** Fintech minimalist (blue accent, white backgrounds, soft shadows)
**Style guide:** `src/app/globals.css`

**Color Palette:**
- **Accent:** Blue (#3B82F6 light, #60A5FA dark)
- **Background:** White (#FFFFFF light, Slate 900 #0F172A dark)
- **Borders:** Subtle slate tones
- **Status:** Green (positive), Red (negative), Amber (warning), Blue (info)

**Dark Mode:** System preference via `@media (prefers-color-scheme: dark)` + `.dark` class

**CSS Variables:**
```css
/* Shadcn theme */
--background, --foreground, --primary, --secondary
--muted, --accent, --destructive, --border, --input, --ring

/* Fintech custom */
--accent-primary, --bg-elevated, --text-primary
--border-default, --status-positive, --shadow-md
```

### Internationalization (i18n)

**Framework:** next-intl v4.7.0
**Supported Locales:** en (English), vi (Vietnamese)

**Files:**
- `src/middleware.ts` - Locale detection and routing
- `src/i18n/request.ts` - Translation message loader
- `messages/en.json` - English translations
- `messages/vi.json` - Vietnamese translations

**Routing:** `/{locale}/path` (e.g., `/en/dashboard`, `/vi/dashboard`)

## Recent Changes

### Shadcn UI Extended Integration (COMPLETED - 2026-01-27)

**New Components:**
- DropdownMenu - Replaced custom language switcher
- Alert - Error/warning messages
- Separator - Visual dividers in navigation

**Refactored:**
- Language switcher → Shadcn DropdownMenu
- Dashboard/settings/projects cards → Shadcn Card
- Button variants → Shadcn Button
- Inline hover styles removed (replaced with Tailwind utilities)

### Shadcn UI Integration (COMPLETED - 2026-01-27)

**Configuration:**
- Initialized Shadcn CLI (`components.json`)
- Mapped fintech CSS variables to Shadcn theme system
- Installed core components: Button, Input, Label, Select, Card, Badge

**Design System:**
- Preserved fintech blue palette (#3B82F6)
- CSS variables for light/dark mode
- Tailwind CSS 4 compatibility

### Fintech UI Redesign (COMPLETED - 2026-01-26)

**Design Tokens Updated:**
- Accent color: Forest green (#4A6B5D) → Blue (#3B82F6)
- Background: Warm off-white (#FDFCFA) → Pure white (#FFFFFF)
- Shadows: Diffused → Soft elevated
- Borders: Visible subtle → Minimal light dividers
- Corner radius: 10-14px → 8-12px

**Typography:** Inter (body), Outfit (headings), JetBrains Mono (code)

### Frontend Unit Tests (COMPLETED - 2026-01-19)

**New Files:**
1. `construction-front-end/src/__tests__/api-error.test.ts` - ApiError class tests (5 tests)
2. `construction-front-end/src/__tests__/env-config.test.ts` - Environment config tests (6 tests)
3. `construction-front-end/src/__tests__/formatters.test.ts` - Utility formatter tests (21 tests)
4. `construction-front-end/src/lib/utils/formatters.ts` - Formatter utilities
5. `construction-front-end/vitest.setup.ts` - Test environment defaults

**Test Coverage:**
- **Total Tests:** 34 (all passing in 396ms)
- **ApiError Tests:** Constructor, data handling, instanceof, stack traces
- **Environment Tests:** NODE_ENV flags, env var validation
- **Formatters:** formatCurrency, formatDate, truncate, slugify, isValidEmail

**Formatter Utilities:**
- `formatCurrency(amount)` - USD currency formatting with Intl API
- `formatDate(date)` - Human-readable date strings
- `truncate(str, maxLength)` - String truncation with ellipsis
- `slugify(str)` - URL-safe slug generation
- `isValidEmail(email)` - Email validation regex

### Frontend Testing Setup (COMPLETED - 2026-01-18)

**New Files:**
1. `construction-front-end/vitest.config.ts` - Vitest configuration with React plugin, jsdom environment, path aliases
2. `construction-front-end/src/__tests__/setup.test.ts` - Setup verification tests

**Modified Files:**
1. `construction-front-end/package.json` - Added test scripts (`test`, `test:watch`, `type-check`)

**Dependencies Added:**
- vitest: ^4.0.17
- @vitejs/plugin-react: ^5.1.2
- jsdom: ^27.4.0
- @testing-library/react: ^16.3.1
- @testing-library/dom: ^10.4.1

**Key Features:**
- Vitest as test runner (fast, ESM support)
- React Testing Library for component testing
- jsdom environment for DOM testing
- Path aliases (@/*) working in tests
- TypeScript support out of box
- Watch mode for development (`npm run test:watch`)

**Test Scripts:**
- `npm run test` - Run all tests once
- `npm run test:watch` - Run tests in watch mode
- `npm run type-check` - Run TypeScript compiler

## Recent Changes

### Phase 04: Frontend Auth Infrastructure (COMPLETED)

**New Files:**
1. `src/lib/auth/types.ts` - TypeScript types (User, AuthSession, LoginResponse)
2. `src/lib/auth/session.ts` - Server-side session utils (getSession, requireAuth)
3. `src/lib/auth/actions.ts` - Server actions (login, logout)
4. `src/lib/auth/middleware.ts` - Middleware helpers (isProtectedRoute, isAuthRoute)
5. `src/middleware.ts` - Next.js middleware (route protection)
6. `src/context/AuthContext.tsx` - Client-side auth context + provider
7. `src/context/AuthErrorBoundary.tsx` - Error boundary for auth errors

**Modified Files:**
1. `src/lib/api/http.ts` - Added `credentials: 'include'` for cookie support
2. `src/app/layout.tsx` - Wrapped with AuthProvider + ErrorBoundary

**Key Features:**
- Cookie-based authentication (HTTP-only, secure in prod)
- Server actions for login/logout
- Next.js middleware for route protection
- Client-side auth context synced with server session
- Error boundary with auto-logout on 401

### Phase 03: Auth Endpoints (Backend)

### New Files

1. **app/api/v1/auth/routes.py**
   - `POST /api/v1/auth/login` - Authenticate, return JWT + set cookies
   - `POST /api/v1/auth/logout` - Clear cookies, revoke token
   - `POST /api/v1/auth/refresh` - Get new access token
   - `GET /api/v1/auth/me` - Current user info

2. **app/api/v1/auth/schemas.py**
   - `LoginRequest` - Email + password (min 8 chars)
   - `LoginResponse` - Tokens + user info
   - `UserResponse` - User ID, email, permissions, roles
   - `RefreshResponse` - New access token
   - `LogoutResponse` - Success message
   - `ErrorResponse` - Standardized errors

3. **app/api/v1/auth/middleware.py**
   - JWT verification middleware (not yet used)

4. **app/infrastructure/rate_limiter.py**
   - Flask-Limiter instance
   - Default: 100 req/min
   - Login endpoint: 5 req/min

5. **tests/test_auth_endpoints.py**
   - Integration tests for all auth endpoints
   - Test cases: login success, invalid credentials, logout, refresh, /me

### Modified Files

1. **config/__init__.py**
   - Added JWT configuration (secret, expiry, cookie settings)
   - Added rate limiting config

2. **app/__init__.py**
   - Initialized `JWTManager` and `limiter`
   - Registered JWT error handlers
   - Registered token revocation checker
   - Registered `/api/v1/auth` blueprint

3. **wiring.py**
   - Added `LoginUseCase` to DI container
   - Wired `TokenIssuer`, `PasswordHasher`, `AuthorizationService`

4. **pyproject.toml**
   - Added dependencies: `flask-jwt-extended`, `pydantic`, `flask-limiter`, `argon2-cffi`

## Key Technologies

| Layer | Technologies |
|-------|-------------|
| API | Flask 3.0, Flask-RESTful, Pydantic |
| Auth | Flask-JWT-Extended, Argon2, Redis |
| Database | SQLAlchemy 2.0, PostgreSQL, Alembic |
| Testing | pytest, pytest-flask |
| Code Quality | mypy, ruff |

## Authentication Flow

1. **Login:** `POST /api/v1/auth/login`
   - Validates credentials via `LoginUseCase`
   - Issues access + refresh tokens
   - Sets HTTP-only cookies (browser) + returns JSON (API clients)

2. **Protected Routes:** Require `@jwt_required()` decorator
   - Token from `Authorization: Bearer <token>` header OR cookies
   - Checks token revocation via Redis

3. **Refresh:** `POST /api/v1/auth/refresh`
   - Uses refresh token to get new access token
   - Fetches fresh permissions from database

4. **Logout:** `POST /api/v1/auth/logout`
   - Clears cookies
   - Adds JTI to Redis blacklist (TTL = token expiry)

## Database Schema (Relevant Tables)

- **users** - User accounts (id, email, password_hash, is_active)
- **roles** - Role definitions (id, name, description)
- **permissions** - Granular permissions (id, resource, action)
- **user_roles** - Many-to-many join table
- **role_permissions** - Many-to-many join table

## Security Features

- **Password Hashing:** Argon2id
- **Rate Limiting:** 5 login attempts/min per IP
- **Token Revocation:** Redis blacklist with TTL
- **CSRF Protection:** Enabled for cookie-based auth
- **Secure Cookies:** `Secure` flag in production, `SameSite=Lax`
- **Token Expiry:** Access 30min, Refresh 7 days

## RBAC System

**Model:** Resource-Action permissions
**Format:** `resource:action` (e.g., `project:create`, `user:read`)
**Wildcard:** `*:*` for admin role

**Default Roles:**
- **admin** - `*:*` (all permissions)
- **manager** - `project:*`, `user:read`
- **user** - `project:read`, `user:read` (self only)

## Configuration

**Environment Variables:**
- `DATABASE_URL` - PostgreSQL connection string
- `REDIS_URL` - Redis connection string
- `JWT_SECRET_KEY` - JWT signing secret
- `SECRET_KEY` - Flask secret key
- `FLASK_ENV` - Environment (development/production)

## Development Workflow

1. **Migrations:** `flask db migrate -m "message"` → `flask db upgrade`
2. **Tests:** `pytest tests/`
3. **Linting:** `ruff check .`
4. **Type Checking:** `mypy app/`
5. **Run Dev Server:** `python run.py` or `flask run`

## API Documentation

Base URL: `http://localhost:5000/api/v1`

### Auth Endpoints

| Method | Endpoint | Auth | Description |
|--------|----------|------|-------------|
| POST | `/auth/login` | None | Login with email/password |
| POST | `/auth/logout` | Optional | Logout and revoke token |
| POST | `/auth/refresh` | Refresh Token | Get new access token |
| GET | `/auth/me` | Required | Get current user info |

### Request/Response Examples

**Login:**
```json
POST /api/v1/auth/login
{
  "email": "user@example.com",
  "password": "password123"
}

Response 200:
{
  "access_token": "eyJ...",
  "refresh_token": "eyJ...",
  "token_type": "Bearer",
  "expires_in": 1800,
  "user": {
    "id": "uuid",
    "email": "user@example.com",
    "permissions": ["project:read", "user:read"],
    "roles": ["user"]
  }
}
```

## Testing

**Test Coverage:** Auth endpoints fully covered
**Test Files:**
- `tests/test_auth_endpoints.py` - Integration tests for login/logout/refresh/me

**Run Tests:** `pytest tests/`
**Coverage:** `pytest --cov=app tests/`

## Next Steps (Pending Phases)

- **Phase 04:** Frontend auth infrastructure (Next.js)
- **Phase 05:** Frontend login UI
- **Phase 06:** Security audit and additional tests

## Key Implementation Details

### Backend Architecture
- **Language:** Python 3.12
- **Framework:** Flask 3.0
- **ORM:** SQLAlchemy 2.0
- **Database:** PostgreSQL 15+
- **Auth:** Flask-JWT-Extended + Argon2-cffi
- **Validation:** Pydantic v2
- **Testing:** pytest + pytest-flask

**Key Files:**
- `app/api/v1/auth/routes.py` - Auth endpoints
- `app/application/auth/login_usecase.py` - Login business logic
- `app/domain/entities/user.py` - User aggregate root
- `app/infrastructure/database/repositories/user_repository.py` - DB access
- `wiring.py` - Dependency injection container

### Frontend Architecture
- **Version:** Next.js 16, React 19, TypeScript 5
- **Styling:** Tailwind CSS v4, shadcn/ui components
- **Testing:** Vitest + React Testing Library
- **i18n:** next-intl (en, vi, fr)

**Key Files:**
- `src/lib/auth/session.ts` - Server-side session
- `src/lib/auth/actions.ts` - Server actions (login/logout)
- `src/context/AuthContext.tsx` - Client auth state
- `src/middleware.ts` - Route protection middleware
- `src/components/ui/*` - Shadcn UI components

## Code Statistics

| Component | Files | LOC | Tests |
|-----------|-------|-----|-------|
| Backend Auth | 15 | ~800 | 20+ |
| Backend DB/Infra | 12 | ~600 | 10+ |
| Frontend Auth | 8 | ~400 | 34 |
| Frontend UI | 20+ | ~800 | 5+ |
| **Total** | **55+** | **~2,600** | **69+** |

## Unresolved Questions

- Token refresh strategy in frontend (currently relies on backend cookie renewal)
- Session timeout handling (auto-refresh vs. force re-login)
- Redis token blacklist cleanup TTL strategy
- Async/await support for Flask endpoints (future optimization)
