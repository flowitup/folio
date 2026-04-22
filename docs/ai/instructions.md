# Construction Flow App (Frontend + Backend)

## 1) Project overview

Construction Flow is a web app to manage construction projects with a construction company and clients.

### MVP features
1) **Workspace by Project**
- A user can belong to multiple projects (separated workspaces).
- User can switch between projects.

2) **Labor charges**
- Track daily labor costs.
- Fields: labor name, quantity of charge (0.5 / 1 day), amount. Then we can put quantity of charge by hours supplement (e.g. 2 hours = 0.25 day or 1 hour = 0.125 day).
- Filter by day / date range.
- Display grouped by date (date headers + list items).

3) **Transactions history**
- Track purchases/payments (materials, etc.)
- Fields: date, item/material name, quantity, amount, payment method (cash / personal card / company card), person who paid.
- Filter by day / date range (+ later more filters).
- Display grouped by date.

### Later features
- Dashboard analytics (KPIs + charts)
- Email notifications to client (and possibly team)
- Optional: vendors/suppliers, categories, attachments/files, audit log

---

## 2) Final choices (conclusion)

### Frontend
- **Next.js 16** (App Router) + **TypeScript 5**
- **React 19**
- **Node.js**: 20 LTS
- **Package manager**: npm
- **Current version**: 0.1.0
- **Tailwind CSS v4**
- **UI Library**: Shadcn UI (Radix primitives + Tailwind)
- **Icons**: Lucide React
- **i18n**: next-intl v4.7.0 (en, fr, vi locales)
- **Testing**: Vitest 4 + React Testing Library
- **Linting**: ESLint 9 (flat config)

### Backend
- **Python Flask API** (v3.0+)
- **Python**: 3.12
- **Package manager**: `uv`
- **Current version**: 0.2.0
- **Hexagonal Architecture** (Ports & Adapters)
- Libraries/infra:
    - **SQLAlchemy 2.0** + **Alembic** (migrations)
    - **Gunicorn** (production WSGI server)
    - **Background jobs**: RQ + Redis
    - **Auth**: Flask-JWT-Extended + Argon2
    - **Validation**: Pydantic v2
    - **Rate limiting**: Flask-Limiter
    - **Transactional outbox pattern** for reliable notifications

### Deployment
- **Domain**: construction.flowitup.com
- **Hosting**: Hetzner VPS
- **Deployment platform**: Coolify (self-hosted) with Docker
- **Services**:
    - **frontend** (Next.js 16)
    - **api** (Flask + Gunicorn)
    - **worker** (RQ)
    - **db** (PostgreSQL)
    - **redis** (queue/cache)

### 3) Core architecture rules
#### 3.1 Workspace / multi-project separation
- Every business table is scoped by project_id.
- Every request to project data must validate membership (ProjectMember).
- Frontend routing is project-scoped: /projects/[projectId]/...

#### 3.2 Hexagonal boundaries (must follow)
- core/** (domain + use-cases) must NOT import:
    - Flask
    - SQLAlchemy
    - Celery/RQ
    - provider SDKs (SendGrid/Mailgun/etc.)
- adapters/** (HTTP layer) depends on core/**.
- infrastructure/** (DB/email/queue implementations) depends on core/**.
- app/** is the composition root (dependency injection wiring).

#### 3.3 Email/notifications (later)
- Email integration is done via a port interface: EmailSenderPort.
- Core emits domain events; handlers write to outbox / enqueue jobs.
- Emails are sent asynchronously by the worker.
- Recommended reliability: Transactional outbox.

### 4) Data model list
#### MVP models
- User
- Project
- ProjectMember (user ↔ project, includes role)
- LaborCharge
- Transaction

#### Likely soon
- Laborer (optional, replaces free-text labor_name)
- Vendor (optional)
- Category (optional)

#### Notifications / Email
- NotificationPreference
- OutboxEvent (recommended)
- EmailLog (optional)

#### Analytics
- DailyProjectStats (optional precomputed totals)

#### Files & Audit
- FileAttachment (later)
- AuditLog (later)

### 5) Notifications / Email
- NotificationPreference
- OutboxEvent (recommended)
- EmailLog (optional)

### 6) Analytics
- DailyProjectStats (optional precomputed totals)

### 7) Files & Audit
- FileAttachment (later)
- AuditLog (later)

### 8) Frontend UI style guide (selected style)
#### Selected style
Fintech minimalist (TaxPal/Stripe-like): clean, professional, blue accent, dark mode support.

#### Design System
- **Component Library**: Shadcn UI (9 components)
- **Icons**: Lucide React
- **CSS Variables**: Shadcn + custom fintech tokens
- **Class Utility**: `cn()` from clsx + tailwind-merge

#### Style rules (baseline)
- Typography: Inter (primary), JetBrains Mono (code)
- Layout: Left sidebar (w-64) + top bar (h-16)
- Visual language: light backgrounds, subtle borders, minimal shadows
- Radius: use a consistent radius (--radius: 0.5rem)
- Colors:
  - Light: #3B82F6 (Blue 500) accent, #FFFFFF background
  - Dark: #60A5FA (Blue 400) accent, #0F172A background
- Dark mode: Manual toggle (light/dark/system) + localStorage persistence
- Lists: group by date; date headers may be sticky
- Use badges/chips for payment method and status
- Always show currency formatting + daily totals

#### i18n Support
- Locales: en (English), fr (French), vi (Vietnamese)
- URL pattern: `/[locale]/dashboard`, `/[locale]/projects`
- Library: next-intl v4.7.0
- Messages: `src/messages/{locale}.json`

### 9) Deployment notes (Coolify + Hetzner)
#### Recommended domains
- construction.flowitup.com → frontend
- optional: api.construction.flowitup.com → backend API

#### Operational checklist
- API health endpoint: GET /health
- DB migrations with Alembic on deploy
- Backups: nightly Postgres dump to offsite storage
- Secrets managed in Coolify
- Persistent volume for Postgres
- Health checks for api/frontend containers

### 10) Development Environment

#### Backend (Python)
- **Package manager**: `uv` (fast Python package installer)
- **Python version**: 3.12
- **Working directory**: `construction-back-end/`
- **Command execution**: Always use `uv run python` or `uv run <tool>`
  - Example: `uv run python -m pytest`
  - Example: `uv run ruff check .`
  - Example: `uv run black .`
  - Example: `uv run mypy .`
- **Install dependencies**: `uv sync --frozen`

#### Frontend (Node.js)
- **Package manager**: npm
- **Node version**: 20 LTS
- **Working directory**: `construction-front-end/`
- **Routes**: All under `/[locale]/` (i18n)
- **Command execution**:
  - Example: `npm run dev` - Start dev server
  - Example: `npm run build` - Production build
  - Example: `npm run lint` - ESLint
  - Example: `npm run test` - Vitest (63 tests)
  - Example: `npm run type-check` - TypeScript check
- **Install dependencies**: `npm ci`

#### UI Components (Shadcn)
- **Config**: `components.json` (New York style, RSC)
- **Components**: `src/components/ui/` (button, input, select, card, badge, alert, dropdown-menu, label, separator)
- **Utility**: `src/lib/utils.ts` - `cn()` function
- **Add new**: `npx shadcn@latest add <component>`

### 11) CI/CD Pipeline (Backend)
#### GitHub Actions workflow
- **File**: `construction-back-end/.github/workflows/ci.yml`
- **Runner**: self-hosted
- **Python**: 3.12

#### Jobs
1. **version-bump** (on PR)
   - Detects PR labels: `version:major`, `version:minor`, `version:patch`
   - Computes new semver based on main branch version
   - Updates `pyproject.toml` and commits to PR branch
   - Skips if version already bumped (PR version > main version)

2. **lint-test** (on PR, after version-bump)
   - **ruff check** - fast Python linter
   - **black --check** - code formatting
   - **mypy** - static type checking (strict mode)
   - **pytest** - test suite

3. **release** (on push to main)
   - Creates git tag `v{version}` if not exists
   - Creates GitHub Release with changelog link
   - Idempotent (skips if tag already exists)

#### Security features
- Uses `GITHUB_TOKEN` (built-in, limited scope)
- Concurrency control to prevent race conditions
- Step timeouts to prevent hung runners
- `contents: write` + `pull-requests: read` permissions only

---

### 12) CI/CD Pipeline (Frontend)
#### GitHub Actions workflow
- **File**: `construction-front-end/.github/workflows/ci.yml`
- **Runner**: ubuntu-latest
- **Node.js**: 20 LTS

#### Jobs (on PR)
1. **version-bump**
   - Detects PR labels: `version:major`, `version:minor`, `version:patch`
   - Computes new semver based on main branch version
   - Updates `package.json` using `npm version --no-git-tag-version`
   - Commits to PR branch

2. **lint** (parallel with type-check, after version-bump)
   - ESLint 9 with flat config

3. **type-check** (parallel with lint, after version-bump)
   - `tsc --noEmit`

4. **test** (after lint + type-check)
   - Vitest with jsdom environment

5. **build** (after test)
   - Next.js production build

#### Jobs (on push to main)
6. **release**
   - Creates git tag `v{version}` if not exists
   - Creates GitHub Release with changelog link

#### Pipeline flow
```
On PR: version-bump → lint/type-check (parallel) → test → build
On push to main: release
```

---

### 13) Version Labels (Both Projects)
| Label | Action | Example |
|-------|--------|---------|
| `version:major` | X.0.0 | 0.1.0 → 1.0.0 |
| `version:minor` | 0.X.0 | 0.1.0 → 0.2.0 |
| `version:patch` | 0.0.X | 0.1.0 → 0.1.1 |

Create these labels in both GitHub repositories with colors:
- `version:major`: `#B60205` (red)
- `version:minor`: `#0E8A16` (green)
- `version:patch`: `#1D76DB` (blue)

---

### 14) Authentication System

#### Overview
JWT-based authentication with HTTP-only cookies for secure browser sessions.

#### Backend (Flask)
- **Library**: Flask-JWT-Extended
- **Password hashing**: Argon2
- **Token storage**: HTTP-only cookies (access + refresh)
- **Rate limiting**: 5 login attempts per minute (Flask-Limiter)

#### API Endpoints
| Endpoint | Method | Description | Auth |
|----------|--------|-------------|------|
| `/auth/login` | POST | Authenticate and get tokens | No |
| `/auth/logout` | POST | Revoke tokens, clear cookies | Optional |
| `/auth/refresh` | POST | Get new access token | Refresh token |
| `/auth/me` | GET | Get current user info | Access token |

#### Request/Response Schemas
```python
# Login Request
{ "email": "user@example.com", "password": "********" }

# Login Response
{
  "access_token": "...",
  "refresh_token": "...",
  "token_type": "Bearer",
  "expires_in": 1800,  # 30 minutes
  "user": {
    "id": "uuid",
    "email": "user@example.com",
    "permissions": ["project:read", "labor:write"],
    "roles": ["admin"]
  }
}
```

#### Frontend (Next.js)
- **Session management**: Server-side via cookies
- **Server Actions**: `login()`, `logout()`, `refreshToken()`
- **Session helpers**: `getSession()`, `getCurrentUser()`, `hasPermission()`, `hasRole()`
- **Protected routes**: `ProtectedRoute` component + middleware

#### Files Structure
```
# Backend
app/api/v1/auth/
├── __init__.py          # Blueprint setup
├── routes.py            # API endpoints
├── schemas.py           # Pydantic models
└── middleware.py        # JWT decorators

# Frontend
src/lib/auth/
├── index.ts             # Re-exports
├── types.ts             # TypeScript types
├── actions.ts           # Server Actions (login, logout, refresh)
├── session.ts           # Session helpers (getSession, getCurrentUser)
└── middleware.ts        # Route protection

src/components/auth/
├── LoginForm.tsx        # Login form component (Shadcn Input/Label/Button)
└── ProtectedRoute.tsx   # Protected route wrapper

src/components/layout/
├── Sidebar.tsx          # Navigation sidebar (Lucide icons)
└── Topbar.tsx           # Header (project selector, language switcher)

src/components/ui/       # Shadcn UI components
├── button.tsx
├── input.tsx
├── label.tsx
├── select.tsx
├── card.tsx
├── badge.tsx
├── alert.tsx
├── dropdown-menu.tsx
└── separator.tsx

src/i18n/                # Internationalization
├── config.ts            # Locale definitions
├── routing.ts           # Centralized locale routing config
├── navigation.ts        # Localized Link/useRouter (uses routing.ts)
└── request.ts           # next-intl config

src/messages/            # Translation files
├── en.json
├── fr.json
└── vi.json

src/lib/
├── utils.ts             # cn() utility
└── ...

src/app/[locale]/        # All routes under locale prefix
├── login/
├── dashboard/
├── projects/
└── settings/
```

#### Security Features
- HTTP-only cookies (prevent XSS token theft)
- CSRF tokens for cookie-based auth
- Rate limiting on login endpoint
- Token revocation on logout
- Secure cookie settings in production