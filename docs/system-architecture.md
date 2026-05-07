# System Architecture

**Last Updated:** 2026-01-18
**Version:** 1.0

## Architecture Pattern

**Primary:** Hexagonal Architecture (Ports & Adapters)
**Supporting:** Domain-Driven Design (DDD), CQRS principles

## Settings Page · Users & Roles Tab (FE relocation — no new BE endpoints)

The Settings page (`/[locale]/settings`) uses a 7-section anchor-navigation layout rendered by a server component (`settings/page.tsx`) that fetches `roles` and `projects` server-side and passes them into `<SettingsClient>` (extracted client component).

**Users section (7th tab) — permission gate:**
- `useAuth().user.permissions.includes("*:*")` evaluated client-side inside `<UsersSection>`
- Superadmin (`*:*`): renders the existing `BulkAddForm` (user search + project multi-select + role picker)
- Non-superadmin: renders an inline "you don't have authorization" panel **inside the section content area** — no redirect to `/unauthorized`

**Route changes:**
- `/(app)/admin/users` route deleted entirely; existing bookmarks → 404 after merge
- Sidebar ADMIN section removed (Users was the only item in that group)

**Reused BE endpoints (unchanged):**
- `GET /api/v1/admin/users?search=q&limit=20` — debounced user search
- `POST /api/v1/admin/users/<user_id>/memberships` — bulk-add memberships

---

## Superadmin Bulk Add (admin tool — direct membership)

A `*:*`-bearing admin (the existing `admin` role from `scripts/seed_auth.py`) can add an existing user to multiple projects in one operation. NO new role, no migration — this reuses the invitation-feature's `user_projects` table (incl. `role_id` + `invited_by_user_id`).

```
superadmin opens /[locale]/(app)/admin/users (server-side *:* gate)
  ├─ debounced user search → GET /api/v1/admin/users?search=q&limit=20
  ├─ select target user
  ├─ multi-select projects (cap 50) → uses existing /api/v1/projects
  ├─ pick role → existing /api/v1/roles (excludes superadmin)
  └─ Submit → POST /api/v1/admin/users/<user_id>/memberships
       └─ BulkAddExistingUserUseCase (~80 LoC)
            ├─ authz: requester *:*  (defense-in-depth at use-case + route)
            ├─ load target user (404 if missing)
            ├─ load role (404 if missing or name=='superadmin' → 403)
            ├─ dedup project_ids; reject empty (400) or > 50 (400)
            ├─ per project_id loop:
            │    ├─ load project; missing → status='project_not_found'
            │    ├─ existing_role = membership_repo.find_role_id(user_id, project_id)
            │    ├─ if None → add membership (invited_by=requester), status='added'
            │    ├─ elif existing_role == role_id → status='already_member_same_role'
            │    └─ else → status='already_member_different_role'
            ├─ if any 'added': enqueue ONE consolidated email (template added_to_projects.{en,fr,vi}.{html,txt})
            └─ return ResultsDto(results=[{project_id, project_name, status}])

UI: per-status grouped toasts ("Added to 3 · Skipped 1 already-member · 1 not found").
```

**Key properties:**
- **Partial success** — no all-or-nothing transaction. Each project is independent; failures don't roll back the rest.
- **Authz** — `*:*` permission required at BOTH route layer (JWT claims check) and use-case layer (defense-in-depth). The existing `admin` role is the de-facto superadmin tier — no new role added.
- **Consolidated email** — one email per bulk operation regardless of N projects. Always sent in `'en'` for v1 (Folio doesn't store user preferred locale yet). Lists only successfully-added projects.
- **Audit** — every new `user_projects` row stamps `invited_by_user_id` = the superadmin's UUID. Field name is slightly inaccurate for non-invitation paths; future migration could rename to `added_by_user_id`.
- **Rate limits** — 5/h per user + 10/h per IP on bulk-add; 30/min per user on user-search.
- **Pydantic guards** — `project_ids: Field(min_length=1, max_length=50)` rejects abuse before reaching the use-case.

### Notes + In-App Notifications

Per-project shared notes with date-anchored in-app reminders. Lazy notification computation — no background worker, no notifications table, no scheduled jobs.

```
┌─ Browser ────────────────────────────────────────────────────────┐
│  Bell icon (Topbar) ──poll @60s──→ GET /api/v1/notifications     │
│         ▲                              │                         │
│         │ items[]                      │                         │
│         │                              ▼                         │
│  Notes agenda /projects/:id/notes      Lazy SQL:                 │
│   • inline edit rows                   notes JOIN memberships    │
│   • optimistic save                    WHERE fire_at <= NOW()    │
│   • undo-toast delete                  AND NOT EXISTS dismissed  │
└──────────────────────────────────────────────────────────────────┘

fire_at = (due_date AT 09:00 UTC) - lead_time_minutes
                       └─ fixed anchor; no per-user TZ for v1

Dismissals:
   notes_dismissed(user_id, note_id, dismissed_at) — composite PK
   ON DELETE CASCADE: project deleted → notes deleted → dismissals deleted
```

**Tables**
- `notes` — id, project_id (cascade), created_by (restrict), title, description, due_date, lead_time_minutes ∈ {0,60,1440}, status ∈ {open,done}, timestamps. Indexes: project_id; due_date; (project_id, status, due_date).
- `notes_dismissed` — user_id (cascade), note_id (cascade), dismissed_at. Composite PK; user_id index.

**Endpoints** — see `docs/checklist/feature-checklist.md`.

**Critical invariant** — when a note's `due_date` or `lead_time_minutes` is updated, all existing dismissals for that note are deleted in the same transaction. This re-fires the reminder for all project members under the new schedule.

**Polling** — bell-icon polls every 60s ±10s (jitter). Pauses when `document.hidden`. `Cache-Control: no-cache, must-revalidate` on the polling endpoint.

### Labor · Export (Excel / PDF)

**Endpoint:** `GET /api/v1/projects/<id>/labor-export?from=YYYY-MM&to=YYYY-MM&format=xlsx|pdf`
**Auth:** `@jwt_required + @require_permission("project:read")`

**Pipeline:**
```
HTTP GET → Pydantic LaborExportRequest (regex + range validator: 1..24 months)
       → ExportLaborUseCase.execute(project_id, range, format, requester)
           ├─ for each month in range:
           │    GetLaborSummaryUseCase + entry_repo.list_by_project_in_range → MonthBucket
           ├─ build_xlsx(context, buckets) | build_pdf(context, buckets)
           └─ slugify_project_name → filename
       → Flask send_file(BytesIO(bytes), Content-Disposition: attachment, Cache-Control: no-store)
```

**Builders** (`app/domain/labor/export/`):
- `xlsx_builder.py` — per-month sheets + Summary sheet; daily detail + per-worker monthly summary
- `pdf_builder.py` — A4 portrait; KPI mini-table + per-worker monthly breakdown
- `format.py` — shared formatting helpers (`format_eur_fr()`)
- `models.py` — `MonthBucket`, `ExportContext` value objects

**Currency rule:**
- xlsx: cell `number_format = '[$€-fr-FR]'` (raw float values)
- pdf: `format_eur_fr()` helper — both match FE `Intl.NumberFormat('fr-FR', { style: 'currency', currency: 'EUR' })`

**Font assets:** `app/domain/labor/export/fonts/` — DejaVu Sans + DejaVu Sans Bold TTF (~1.4 MB total); required for Vietnamese diacritics in PDF output. License: Bitstream Vera + DejaVu open-font.

**"No aggregated Total" rule:** every cost breakdown uses explicit "Priced cost" + "Bonus cost" labels; any combined figure is labeled "Total (priced + bonus)" — no bare "Total" that could mislead readers.

#### Single-worker scope

**Endpoint:** `GET /api/v1/projects/<id>/workers/<worker_id>/labor-export?from=YYYY-MM&to=YYYY-MM&format=xlsx|pdf`
**Auth:** `@jwt_required + @require_permission("project:read") + @require_project_access()` (membership, not just claim)
**Rate limit:** `5 per minute, key_func=jwt_user_key` (per-user; same on the project-wide route)

`ExportLaborUseCase` accepts an optional `worker_id`. When set, the use-case validates `worker.project_id == project_id` AND `worker.is_active`, scopes summary + daily-entry queries to that worker, populates `ExportContext.worker_name` + `worker_daily_rate`, and renders a single-sheet xlsx (worker header + monthly summary + daily detail) or single-section pdf (no daily detail — parity with project-wide PDF).

**Filename:** `labor-{project-slug}-{worker-slug}-{from}-to-{to}.{ext}` — slugifier falls back to the first 8 chars of the project / worker UUID when the name is pure CJK / emoji.

**Security shipped with this endpoint** (also applied to the existing project-wide route, defense-in-depth):
- **Membership check** — `@require_project_access()` decorator added below `@require_permission("project:read")`. Prior behaviour: any seat with the `project:read` claim could export any project. Now the caller must be a member of the specific project.
- **Per-user rate-limit key** — was per-IP via `get_remote_address`; now `key_func=jwt_user_key` so NAT/proxy users no longer share buckets and IP rotation no longer bypasses the limit.
- **ReportLab Paragraph escaping** — `xml.sax.saxutils.escape` wraps all user-controlled strings (`project_name`, `worker_name`, `generated_by_email`) before Paragraph interpolation. Prior behaviour: `<` in a name crashed PDF build via SAX parser; `<b>...</b>` rendered formatted text.
- **Inactive worker block** — `WorkerInactiveError(WorkerNotFoundError)` raised in the use-case when `worker.is_active is False`; route maps to 404 with `error: "worker_inactive"`. The FE button is already gated on `is_active`; this is the defense-in-depth against direct API calls.

**Font registration** — moved from a lazy `_FONT_REGISTERED` flag to module-load time; eliminates the double-registration race on first concurrent PDF builds.

**Requester identity helper** — `app/api/_helpers/requester_identity.py:get_requester_email(user_repository)` deduplicated across both export routes (JWT carries no `email` claim, so DB lookup is mandatory but no longer copy-pasted).

**Frontend trigger** — Download icon on each `worker-list` row (gated on `worker.is_active`) opens the unified `LaborExportDialog` with an optional `worker?: Worker | null` prop. The same component handles project-wide and per-worker export; `fetchExportFile(url, range, format)` is the private helper both `fetchLaborExport` and `fetchWorkerLaborExport` delegate to.

**Error paths:** 422 (invalid params / range > 24 months), 403 (missing permission), 404 (project not found).

---

### Invoices · Monthly Export (Excel / PDF)

**Endpoint:** `GET /api/v1/projects/<id>/invoices-export?from=YYYY-MM&to=YYYY-MM&format=xlsx|pdf[&type=client|labor|supplier]`
**Auth:** `@jwt_required + @require_permission("project:read") + @require_project_access()` (membership, not just claim)
**Rate limit:** `5 per minute, key_func=jwt_user_key`

```
HTTP GET → Pydantic ExportInvoicesQuery (regex 1900-2199 + range validator: 1..24 months + optional type)
        → ExportInvoicesUseCase
            ├─ ProjectRepository.find_by_id              (404 ProjectNotFoundError if missing)
            └─ InvoiceRepository.find_by_project_in_range(project_id, date_from, date_to, type_filter)
                ├─ aggregate per-type subtotals + grand_total in Decimal (no float drift)
                ├─ sort (issue_date, type.value, invoice_number) for deterministic output
                ├─ build InvoiceBundle + InvoiceExportContext
                └─ dispatch:
                     xlsx → app.domain.invoice.export.xlsx_builder.build_xlsx
                          ├─ Summary sheet (header band, KPIs, per-type subtotals,
                          │  invoice list, GRAND TOTAL band)
                          └─ one sheet per type that EXISTS in range (skip empty)
                     pdf  → app.domain.invoice.export.pdf_builder.build_pdf
                          ├─ Page 1: summary (header, meta, KPIs, subtotals, invoice index)
                          └─ Pages 2..N+1: one polished invoice per page
                             (header band, INVOICE title, meta block, items table
                              with zebra rows, grand-total band, notes)
        → send_file(stream, attachment=True, mimetype, download_name)
            + Cache-Control: no-store, must-revalidate
            + X-Content-Type-Options: nosniff
```

**Filename:** `invoices-{project-slug}-{from}-to-{to}[-{type}].{ext}` — type suffix only when the filter is set; slugifier reused from labor (`slugify_project_name`).

**Cross-package font reuse** — pdf_builder computes `_FONTS_DIR = Path(__file__).resolve().parent.parent.parent / "labor" / "export" / "fonts"` to share the bundled DejaVu Sans + Bold TTFs (~1.4 MB) with labor instead of duplicating them. Documented at the top of `pdf_builder.py`; if labor moves, update that path.

**Empty range path** — both xlsx and pdf render a clean `No invoices in range YYYY-MM to YYYY-MM` message; per-type sheets are skipped when their type has zero invoices (so a `?type=labor` export never produces empty Client / Supplier sheets).

**Currency rule (LOCKED)** — every monetary value is aggregated in `Decimal` and only cast to `float` at the openpyxl-cell-write boundary. xlsx cells store raw float values with `EUR_FR_FORMAT` so Excel can sort and sum them; never write pre-formatted strings. PDF formats Decimals via `format_eur_fr` (`1 234,56 €`, fr-FR). `test_grand_total_decimal_precision` directly asserts `3 × Decimal("0.10") == Decimal("0.30")` exactly.

**XML-escape defense** — `xml.sax.saxutils.escape` wraps every user-supplied string before ReportLab `Paragraph` interpolation: project name, recipient name, recipient address, invoice number, item descriptions, notes. Covered by `test_special_chars_xml_escaped` (recipient = `<script>alert(1)</script>` produces a valid PDF with the tag rendered as escaped text).

**Frontend trigger** — `Export range` button on the project Invoices page header opens `InvoiceExportDialog` (date range + type filter + xlsx/pdf toggle). The active list-tab type carries through as `initialType`. Dialog calls `fetchInvoiceExport(projectId, range, format, typeFilter?)` which streams the binary blob → `triggerBrowserDownload(blob, filename)`.

**i18n** — `invoices.export.*` (20 keys × en / fr / vi at strict parity, real Vietnamese: "Khách hàng" / "Nhân công" / "Nhà cung cấp" for the type filter). Vietnamese `summaryLine` is non-pluralised by intent (no plural noun morphology); en + fr use ICU plural.

**Shipped this cycle, also back-ported to labor:**
- `${apiBaseUrl}/api/v1/...` double-prefix bug — `NEXT_PUBLIC_API_BASE_URL` already includes `/api/v1`, so the literal in `fetchInvoiceExport` / `fetchLaborExport` / `fetchWorkerLaborExport` was producing `/api/v1/api/v1/projects/...` → 404 against the Flask blueprint mounted at `/api/v1`. Dropped the literal in all three; added URL-pinning regex assertions (`toMatch(/\/api\/v1\/projects\/[^/]+\/.../) + not.toMatch(/api\/v1\/api\/v1/)`) in unit tests so future drift fails CI.
- YYYY-MM regex tightened to `^(19|20|21)\d{2}-(0[1-9]|1[0-2])$` on both `ExportInvoicesQuery` and `ExportLaborQuery` — closes a 500 path where `from=to=0000-01` survived validation and crashed `_parse_yyyy_mm` with `year 0 is out of range`.
- `format_validation_error(exc) -> tuple[Response, int]` extracted to `app/api/_helpers/pydantic_errors.py`; invoice + both labor export routes now share it (3 byte-identical copies dedup'd).
- `parseFilenameFromContentDisposition(header, fallback) -> string` extracted to `src/lib/api/_helpers/content-disposition.ts`; `fetchInvoiceExport` and the labor exporters import it (RFC 6266 `filename*=UTF-8''…` + plain `filename="…"` parser).
- Admin test fixtures (invoice + labor export API tests) no longer grant `*:*`, so the route's `@require_permission("project:read")` is actually exercised.

**Error paths:** 422 (invalid params / range > 24 months / unknown type / out-of-range year), 403 (missing permission), 404 (project not found / cross-project access).

---

### Labor · Supplement Hours

Per-day supplement hours (0–12) accumulate across the current calendar month per worker. At summary time the total is converted to bonus days using pure Python arithmetic — no phantom rows, no monthly close job.

**Conversion formula:**
```
bonus_full  = banked_hours // 8
bonus_half  = 1 if (banked_hours % 8) >= 4 else 0
```

**Thresholds:**

| Banked hours (month) | Bonus full days | Bonus half days |
|---|---|---|
| 0–3 | 0 | 0 |
| 4–7 | 0 | 1 |
| 8–11 | 1 | 0 |
| 12–15 | 1 | 1 |
| 16+ | banked // 8 | 1 if remainder ≥ 4 |

**Key properties:**
- Pure-derived: conversion computed at read time in `GetLaborSummaryUseCase`; no persisted phantom rows and no monthly close action.
- Standalone entries allowed: `shift_type` is nullable; a row with `shift_type IS NULL` and `supplement_hours > 0` is a supplement-only entry. Override-without-shift (shift_type present but `supplement_hours` = 0 override) is valid; the only rejected case is both fields absent.
- Validation: `supplement_hours ∈ [0, 12]` (CHECK constraint `chk_labor_supplement_hours_range`); `shift_type IS NOT NULL OR supplement_hours > 0` (CHECK constraint `chk_labor_entry_nonempty`).
- Month boundary reset: banked hours are summed over the queried date range; residual < 4h at end of month is discarded (no carry-over).
- Migration: `20a22df3582d` — adds `supplement_hours INT NOT NULL DEFAULT 0`, makes `shift_type` nullable, adds 2 CHECK constraints.

## Invitation Lifecycle (invite-only signup)

```
admin clicks "Invite member"
  └─> POST /api/v1/invitations  (auth + project:invite perm OR project.owner_id)
       └─> CreateInvitationUseCase
             ├─ if email belongs to existing user:
             │    └─ ProjectMembership.create() → repo.add()
             │       └─ enqueue tasks.send_email(added_to_project tmpl)
             │           └─ RQ worker → EmailPort.send() → Resend HTTP API
             │           returns {kind: 'direct_added'}
             └─ else (new email):
                  ├─ Invitation.create() → (entity, raw_token) [token hashed in DB]
                  ├─ repo.save(invitation)
                  ├─ build accept_url = APP_BASE_URL/{locale}/accept-invite/{raw_token}
                  └─ enqueue tasks.send_email(invite tmpl in admin's locale)
                      returns {kind: 'invitation_sent', invitation_id, expires_at}

invitee receives email, clicks link → /[locale]/accept-invite/{token}
  ├─> server-component calls GET /api/v1/invitations/verify/{token}
  │     └─ VerifyInvitationUseCase
  │         ├─ unknown → 404
  │         ├─ expired/revoked/accepted → 410 with reason
  │         └─ valid → returns safe metadata (no invitation_id)
  └─> renders form (or error / logged-in-other state)
       └─> on submit: POST /api/v1/invitations/accept {token, name, password}
             └─ AcceptInvitationUseCase (single DB transaction)
                 ├─ create User (display_name=name, Argon2 password hash)
                 ├─ create ProjectMembership (user_id, project_id, role_id, invited_by)
                 ├─ invitation.accept() → save
                 └─ TokenIssuer.issue_pair(user) → set httpOnly+CSRF cookies
                 redirects → /[locale]/dashboard (authenticated)
```

**Key properties:**
- **Token**: opaque `secrets.token_urlsafe(32)`, SHA-256 hashed in DB, single-use, 7-day expiry. Lookup in constant time via `hmac.compare_digest`.
- **No public signup**: there is NO `POST /auth/register`, NO `POST /signup`, NO `POST /users`. Invitation acceptance is the only account-creation path. A negative test guards this.
- **Permission**: new `project:invite` permission, granted to global `admin` role. `project.owner_id == inviter_id` is also accepted (no permission required for owners).
- **Per-project roles**: the `user_projects` membership table now carries `role_id` (NOT NULL) and `invited_by_user_id` (nullable). Existing rows backfilled to `member`.
- **Email dispatch**: `ResendEmailAdapter` implements an EmailPort contract; `wiring.py` switches between `resend | smtp | inmemory` based on `EMAIL_PROVIDER` env. Templates live at `app/infrastructure/email/templates/{invite,added_to_project}.{en,fr,vi}.{html,txt}`. RQ worker dispatches asynchronously so request handlers don't block on the Resend API.
- **Rate limits**: 10 invites/h per inviter (Flask-Limiter), 50/day per project (use-case level). Public `verify` 60/min/IP, `accept` 5/min/IP.
- **Edge cases**: revoke pending; resend = revoke + new token; pending duplicate enforced by partial unique index `(email, project_id) WHERE status='pending'`; logged-in-as-other shows sign-out gate; verify endpoint returns same 404 for nonexistent and 410 with reason for expired/revoked/accepted (no info-leak about whether token ever existed for nonexistent case).

## High-Level Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                     Frontend Layer                          │
│              Next.js 16 (App Router, RSC)                   │
│                                                             │
│  ┌─────────────────────────────────────────────────────┐   │
│  │  UI Components (Shadcn UI)                          │   │
│  │  - Radix UI primitives (accessible components)      │   │
│  │  - Tailwind CSS + CSS variables (theming)          │   │
│  │  - 9 core components (Button, Input, Card, etc.)   │   │
│  │  - cn() utility (class merging)                    │   │
│  └─────────────────────────────────────────────────────┘   │
│  ┌─────────────────────────────────────────────────────┐   │
│  │  Design System (Fintech Blue)                       │   │
│  │  - Blue accent (#3B82F6 / #60A5FA dark)            │   │
│  │  - CSS variables (light + dark mode)               │   │
│  │  - System preference dark mode                     │   │
│  └─────────────────────────────────────────────────────┘   │
│  ┌─────────────────────────────────────────────────────┐   │
│  │  Internationalization (next-intl)                   │   │
│  │  - Locale routing (/en/*, /vi/*)                   │   │
│  │  - Translation middleware                          │   │
│  │  - Message files (en.json, vi.json)                │   │
│  └─────────────────────────────────────────────────────┘   │
│  - Auth Middleware (cookie-based route protection)         │
│  - Server Actions (login/logout server-side)               │
│  - AuthContext + AuthProvider (client state)               │
│  - AuthErrorBoundary (error handling)                      │
│  - API Client (credentials: include for cookies)           │
└─────────────────────────────────────────────────────────────┘
                             │ HTTP/REST
                             ▼
┌─────────────────────────────────────────────────────────────┐
│                      API Layer                              │
│                   Flask 3.0 REST API                        │
│                                                             │
│  ┌──────────────────────────────────────────────────┐      │
│  │  Adapters (Primary - Driving)                    │      │
│  │  - /api/v1/auth/* (Auth endpoints)               │      │
│  │  - Rate Limiting (Flask-Limiter)                 │      │
│  │  - Request Validation (Pydantic)                 │      │
│  │  - JWT/Cookie handling (Flask-JWT-Extended)      │      │
│  └──────────────────────────────────────────────────┘      │
│                             │                               │
│                             ▼                               │
│  ┌──────────────────────────────────────────────────┐      │
│  │  Application Layer (Use Cases)                   │      │
│  │  - LoginUseCase                                  │      │
│  │  - Orchestrates domain logic                     │      │
│  │  - Enforces business rules                       │      │
│  └──────────────────────────────────────────────────┘      │
│                             │                               │
│                             ▼                               │
│  ┌──────────────────────────────────────────────────┐      │
│  │  Domain Layer (Core Business Logic)              │      │
│  │  - Entities: User, Role, Permission              │      │
│  │  - Value Objects: Email, HashedPassword          │      │
│  │  - Exceptions: InvalidCredentialsError, etc.     │      │
│  └──────────────────────────────────────────────────┘      │
│                             │                               │
│                             ▼                               │
│  ┌──────────────────────────────────────────────────┐      │
│  │  Adapters (Secondary - Driven)                   │      │
│  │  - UserRepository (Database)                     │      │
│  │  - TokenIssuer (JWT generation)                  │      │
│  │  - PasswordHasher (Argon2)                       │      │
│  │  - AuthorizationService (RBAC)                   │      │
│  └──────────────────────────────────────────────────┘      │
└─────────────────────────────────────────────────────────────┘
                             │
              ┌──────────────┴──────────────┐
              ▼                             ▼
    ┌──────────────────┐        ┌──────────────────┐
    │   PostgreSQL     │        │      Redis       │
    │                  │        │                  │
    │ - User tables    │        │ - Token blacklist│
    │ - Role/Perm RBAC │        │ - Rate limiting  │
    │ - Migrations     │        │ - Sessions       │
    └──────────────────┘        └──────────────────┘
```

## Layer Responsibilities

### 1. API Layer (Adapters - Primary)

**Location:** `app/api/v1/`

**Responsibilities:**
- HTTP request/response handling
- Input validation (Pydantic schemas)
- Authentication/authorization (JWT middleware)
- Rate limiting
- Error serialization

**Key Components:**
- `routes.py` - Endpoint definitions
- `schemas.py` - Request/response models
- `middleware.py` - JWT verification

**Technology:**
- Flask 3.0
- Flask-JWT-Extended
- Pydantic
- Flask-Limiter

### 2. Application Layer (Use Cases)

**Location:** `app/application/`

**Responsibilities:**
- Orchestrate domain logic
- Implement business workflows
- Coordinate between domain and infrastructure
- Transaction management

**Key Components:**
- `LoginUseCase` - Authenticate user, issue tokens
- `ports.py` - Interface definitions (IUserRepository, ITokenIssuer, etc.)

**Dependencies:** Domain entities, ports (interfaces)

### 3. Domain Layer (Core Business Logic)

**Location:** `app/domain/`

**Responsibilities:**
- Business entities and rules
- Domain events
- Pure business logic (no framework dependencies)

**Structure:**
```
domain/
├── entities/
│   ├── user.py         # User aggregate root
│   ├── role.py         # Role entity
│   └── permission.py   # Permission entity
├── value_objects/
│   ├── email.py        # Email validation
│   └── hashed_password.py
└── exceptions/
    ├── auth_exceptions.py
    └── validation_exceptions.py
```

**Principles:**
- Framework-agnostic
- Rich domain models
- Encapsulated business logic

### 4. Infrastructure Layer (Adapters - Secondary)

**Location:** `app/infrastructure/`

**Responsibilities:**
- External service integration
- Database access
- Authentication mechanisms
- Authorization services

**Structure:**
```
infrastructure/
├── database/
│   ├── models/         # SQLAlchemy models
│   └── repositories/   # Repository implementations
├── auth/
│   ├── jwt_token_issuer.py
│   └── password_hasher.py
├── authorization/
│   └── rbac_service.py
└── rate_limiter.py
```

**Technology:**
- SQLAlchemy 2.0
- Alembic (migrations)
- Redis (token blacklist, rate limiting)
- Argon2 (password hashing)

## Dependency Injection

**Location:** `wiring.py`

**Pattern:** Simple DI container
**Purpose:** Decouple layers, enable testing

**Container Components:**
```python
@dataclass
class Container:
    user_repository: IUserRepository
    token_issuer: ITokenIssuer
    password_hasher: IPasswordHasher
    authorization_service: IAuthorizationService
    login_usecase: LoginUseCase
```

**Initialization:** App startup via `create_app()`

## Authentication & Authorization

### JWT Token Flow

```
1. User submits credentials
   ↓
2. LoginUseCase validates
   ↓
3. TokenIssuer creates JWT (access + refresh)
   ↓
4. Response includes:
   - JSON body: tokens + user info
   - HTTP-only cookies: tokens
   ↓
5. Client sends subsequent requests with:
   - Header: Authorization: Bearer <token>
   - OR cookies (automatic)
   ↓
6. JWT middleware verifies token
   ↓
7. Check if token revoked (Redis lookup)
   ↓
8. Extract user_id and permissions
   ↓
9. Proceed to endpoint
```

### Token Revocation

**Storage:** Redis
**Format:** `SET revoked_token:{jti} "1" EX {ttl}`
**TTL:** Matches token expiry (30 min for access, 7 days for refresh)

**Revocation Points:**
- Logout
- Password change (future)
- Admin force-logout (future)

### RBAC Architecture

**Model:** Resource-Action permissions
**Format:** `resource:action`

**Hierarchy:**
```
Role (e.g., "manager")
  ├── Permission: project:create
  ├── Permission: project:read
  ├── Permission: project:update
  └── Permission: user:read
```

**Enforcement:**
1. User logs in → permissions loaded into JWT claims
2. Protected endpoint checks required permission
3. AuthorizationService validates `user_permissions ∩ required_permissions`

## Database Design

### Schema Overview

```sql
users
  - id: UUID (PK)
  - email: VARCHAR(255) UNIQUE
  - password_hash: VARCHAR(255)
  - is_active: BOOLEAN
  - created_at: TIMESTAMP
  - updated_at: TIMESTAMP

roles
  - id: UUID (PK)
  - name: VARCHAR(100) UNIQUE
  - description: TEXT

permissions
  - id: UUID (PK)
  - resource: VARCHAR(100)
  - action: VARCHAR(100)
  - UNIQUE(resource, action)

user_roles
  - user_id: UUID (FK → users.id)
  - role_id: UUID (FK → roles.id)
  - PK(user_id, role_id)

role_permissions
  - role_id: UUID (FK → roles.id)
  - permission_id: UUID (FK → permissions.id)
  - PK(role_id, permission_id)
```

### Migrations

**Tool:** Alembic
**Location:** `migrations/versions/`
**Commands:**
- Generate: `flask db migrate -m "description"`
- Apply: `flask db upgrade`
- Rollback: `flask db downgrade`

## API Design

### Versioning

**Strategy:** URI versioning
**Format:** `/api/v1/*`
**Rationale:** Clear, client-friendly, supports parallel versions

### Response Format

**Success (200-299):**
```json
{
  "access_token": "...",
  "user": { ... }
}
```

**Error (400-599):**
```json
{
  "error": "InvalidCredentials",
  "message": "Invalid email or password",
  "status_code": 401
}
```

### Rate Limiting

**Strategy:** Token bucket (Redis-backed)
**Limits:**
- Default: 100 req/min per IP
- Login: 5 req/min per IP

**Headers:**
- `X-RateLimit-Limit` - Max requests
- `X-RateLimit-Remaining` - Remaining requests
- `X-RateLimit-Reset` - Reset timestamp

## Security Architecture

### Defense Layers

1. **Input Validation:** Pydantic schemas
2. **Rate Limiting:** Flask-Limiter
3. **Authentication:** JWT with short expiry
4. **Authorization:** RBAC checks
5. **Token Revocation:** Redis blacklist
6. **Password Security:** Argon2id hashing
7. **CSRF Protection:** Cookie `SameSite=Lax`
8. **HTTPS Enforcement:** Production cookies `Secure=True`

### Secrets Management

**Development:** `.env` file (gitignored)
**Production:** Environment variables (Docker, K8s secrets)

**Required Secrets:**
- `DATABASE_URL`
- `REDIS_URL`
- `JWT_SECRET_KEY`
- `SECRET_KEY`

## Configuration Management

**Pattern:** 12-factor app methodology
**Files:**
- `config/__init__.py` - Config classes
- `.env` - Local environment variables (not committed)

**Environments:**
- `DevelopmentConfig` - Debug enabled, SQLite fallback
- `ProductionConfig` - Strict validation, required secrets
- `TestingConfig` - In-memory SQLite

## Testing Strategy

### Frontend Testing (Next.js 16)

**Framework:** Vitest (fast, native ESM support)
**Libraries:** React Testing Library (React 19 compatible)
**Environment:** jsdom (DOM simulation)

**Test Levels:**
- **Unit Tests:** Components, hooks, utility functions
- **Integration Tests:** Component interactions, server actions
- **E2E Tests:** Full user workflows (future)

**Configuration:**
- Path aliases: `@/*` → `./src/*`
- Environment: jsdom for DOM testing
- Globals enabled (describe, it, expect available globally)
- Watch mode for development

**Test Scripts:**
```bash
npm run test          # Run all tests once
npm run test:watch    # Watch mode (development)
npm run type-check    # TypeScript validation
```

### Backend Testing (Flask)

**Levels:**
- **Unit Tests:** Domain logic, use cases
- **Integration Tests:** API endpoints, database
- **E2E Tests:** Full workflows (future)

**Coverage Target:** >80%

**Tools:**
- pytest
- pytest-flask
- pytest-cov

## CI/CD Architecture (Frontend)

### GitHub Actions Workflow

**File:** `.github/workflows/ci.yml`

**Triggers:**
- Push to `main` branch
- Pull requests to `main` branch

**Pipeline Stages:**

```
┌─────────────────────────────────────────────────────────────┐
│                    GitHub Actions CI                        │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  ┌──────────┐  ┌──────────────┐                            │
│  │   Lint   │  │  Type Check  │  ← Run in parallel         │
│  └────┬─────┘  └──────┬───────┘                            │
│       │               │                                     │
│       └───────┬───────┘                                     │
│               ▼                                             │
│        ┌──────────┐                                         │
│        │  Tests   │                                         │
│        └────┬─────┘                                         │
│             ▼                                               │
│        ┌──────────┐                                         │
│        │  Build   │                                         │
│        └──────────┘                                         │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

**Job Details:**

| Job | Depends On | Command | Purpose |
|-----|------------|---------|---------|
| Lint | None | `npm run lint` | ESLint code quality check |
| Type Check | None | `npm run type-check` | TypeScript type validation |
| Tests | Lint, Type Check | `npm run test` | Vitest test suite |
| Build | Tests | `npm run build` | Production bundle creation |

**Features:**
- Node.js 20 LTS
- npm dependency caching for faster builds
- Concurrency control (cancel outdated builds)
- Fail-fast on any job failure
- Parallel execution of independent jobs (lint + type-check)

## Deployment Architecture (Future)

### Containerization

```
docker-compose.yml
  ├── backend (Flask)
  ├── frontend (Next.js)
  ├── postgres
  └── redis
```

### Production Stack

**Option 1: Cloud-native**
- Frontend: Vercel / Netlify
- Backend: AWS ECS / Google Cloud Run
- Database: AWS RDS PostgreSQL
- Cache: AWS ElastiCache Redis

**Option 2: Self-hosted**
- Docker Swarm / Kubernetes
- PostgreSQL with replication
- Redis Sentinel for HA

## Scalability Considerations

### Horizontal Scaling

- **Stateless API:** Multiple Flask instances behind load balancer
- **Session Storage:** Redis (shared across instances)
- **Token Blacklist:** Redis (centralized)

### Performance Optimization

- **Database:** Connection pooling, read replicas
- **Caching:** Redis for frequently accessed data
- **CDN:** Static assets (frontend)

## Monitoring & Observability (Future)

**Logging:** Structured JSON logs
**Metrics:** Prometheus
**Tracing:** OpenTelemetry
**Alerting:** PagerDuty / Opsgenie

## Frontend Authentication Architecture

### UI Component Architecture

**Framework:** Shadcn UI (copy-paste components)
**Primitive Library:** Radix UI (accessible, unstyled components)
**Styling:** Tailwind CSS 4 with CSS variables
**Icons:** Lucide React

#### Component Catalog

| Component | Primitives | Variants | Purpose |
|-----------|-----------|----------|---------|
| Button | @radix-ui/react-slot | default, secondary, destructive, outline, ghost, link | Action triggers |
| Input | Native HTML | default | Text input fields |
| Label | @radix-ui/react-label | default | Form labels |
| Select | @radix-ui/react-select | default | Dropdown selects |
| Card | Native divs | default | Content containers |
| Badge | Native span | default, secondary, destructive, outline | Status indicators |
| Alert | Native divs | default, destructive | Alert messages |
| DropdownMenu | @radix-ui/react-dropdown-menu | default | Context menus |
| Separator | @radix-ui/react-separator | horizontal, vertical | Visual dividers |

#### Class Composition Pattern

**Utility:** `cn()` function in `src/lib/utils.ts`
**Purpose:** Merge Tailwind classes with intelligent conflict resolution

```typescript
import { clsx } from "clsx"
import { twMerge } from "tailwind-merge"

export function cn(...inputs: ClassValue[]) {
  return twMerge(clsx(inputs))
}
```

**Usage in components:**
```typescript
<Button className={cn("custom-class", isActive && "active-class")} />
```

#### Design System Variables

**Location:** `src/app/globals.css`

**Shadcn Theme Variables:**
```css
:root {
  --background: #FFFFFF;
  --foreground: #0F172A;
  --primary: #3B82F6;
  --primary-foreground: #FFFFFF;
  --secondary: #F1F5F9;
  --muted: #F1F5F9;
  --accent: #EFF6FF;
  --destructive: #EF4444;
  --border: #E2E8F0;
  --input: #E2E8F0;
  --ring: #3B82F6;
  --radius: 0.5rem;
}
```

**Fintech Custom Variables:**
```css
:root {
  --accent-primary: #3B82F6;
  --bg-elevated: #FFFFFF;
  --bg-muted: #F1F5F9;
  --text-primary: #0F172A;
  --text-secondary: #64748B;
  --border-default: #E2E8F0;
  --status-positive: #22C55E;
  --status-negative: #EF4444;
  --shadow-md: 0 4px 6px -1px rgb(0 0 0 / 0.1);
}
```

**Dark Mode Strategy:**
- System preference detection: `@media (prefers-color-scheme: dark)`
- Manual toggle support: `.dark` class
- CSS variable overrides in dark mode context

#### Internationalization Architecture

**Framework:** next-intl v4.7.0
**Pattern:** Locale-prefixed routing

**Routing Structure:**
```
/{locale}/path
├── /en/dashboard
├── /en/settings
├── /vi/dashboard
└── /vi/settings
```

**Middleware Flow:**
```
1. Request arrives
   ↓
2. Locale detection (cookie, header, path)
   ↓
3. Middleware intercepts (src/middleware.ts)
   ↓
4. Locale validation (en or vi)
   ↓
5. Load translations (src/i18n/request.ts)
   ↓
6. Inject into page context
   ↓
7. Render localized content
```

**Translation Files:**
- `messages/en.json` - English translations
- `messages/vi.json` - Vietnamese translations

**Usage Pattern:**
```typescript
import { useTranslations } from 'next-intl'

export default function Page() {
  const t = useTranslations('namespace')
  return <h1>{t('key')}</h1>
}
```

## Frontend Authentication Architecture

### Server-Side Session Handling

**Pattern:** Hybrid cookie + server action approach

**Components:**
1. **Server Actions** (`src/lib/auth/actions.ts`)
   - `login()` - Calls backend, extracts cookies, validates session
   - `logout()` - Clears cookies, revokes token, redirects
   - `getSession()` - Server-side session retrieval from cookies

2. **Middleware** (`src/middleware.ts`)
   - Cookie-based authentication check (access_token cookie)
   - Route protection (protected vs. auth routes)
   - Auto-redirect logic (login → dashboard, dashboard → login)

3. **Client Context** (`src/context/AuthContext.tsx`)
   - React Context for client-side auth state
   - `useAuth()` hook for components
   - Syncs with server session via `initialUser` prop

4. **Error Boundary** (`src/context/AuthErrorBoundary.tsx`)
   - Catches auth-related errors
   - Auto-logout on 401 errors
   - Graceful error display

### Authentication Flow

```
1. User visits protected route
   ↓
2. Middleware checks access_token cookie
   ↓
3. No token → redirect to /login?callbackUrl=/original-path
   ↓
4. User submits login form
   ↓
5. Server action calls POST /api/v1/auth/login
   ↓
6. Backend sets HTTP-only cookies + returns JSON
   ↓
7. Server action extracts cookies from response headers
   ↓
8. Server action validates session via GET /api/v1/auth/me
   ↓
9. AuthProvider updates client state
   ↓
10. Redirect to /dashboard (or callbackUrl)
```

### Cookie Configuration

**Production:**
- `httpOnly: true`
- `secure: true` (HTTPS only)
- `sameSite: 'lax'`
- `path: /`

**Development:**
- `secure: false` (allow HTTP)

### Route Protection

**Protected Routes:**
- `/dashboard/*`
- `/projects/*`
- `/settings/*`
- All routes under `/(app)/*` group

**Auth Routes (redirect if authenticated):**
- `/login`
- `/register`

**Public Routes:**
- `/` (landing page)
- `/about`
- API routes

## Development Tools

### Setup Verification Script

**Location:** `/scripts/verify-setup.sh`

**Purpose:** Full E2E verification of construction project setup

**Capabilities:**
- Starts Docker services (api, worker, db, redis)
- Runs database migrations and seeds admin user
- Starts frontend Next.js dev server
- Executes E2E auth tests (login, /me endpoint)

**Usage:**
```bash
./scripts/verify-setup.sh [OPTIONS]
```

**Options:**
- `--cleanup` - Stop all services after verification
- `--timeout N` - Set timeout in seconds (default: 120)
- `--help` - Show help message

**Environment Variables:**
- `ADMIN_EMAIL` - Admin email for seeding (default: admin@example.com)
- `ADMIN_PASSWORD` - Admin password for seeding (default: password123)

**Verification Steps:**
1. Prerequisites check (Docker, Docker Compose, Node.js, npm, curl)
2. Docker services startup and health checks (DB, Redis, API)
3. Database migrations and auth data seeding
4. Frontend dev server startup
5. E2E integration tests (login endpoint, /me endpoint validation, frontend connectivity)

**Exit Codes:**
- `0` - All verifications passed
- `1` - Verification failed at any step

## Domain Modules

### Billing BC

**Status:** Completed (Phase 260505-1357)

**Purpose:** Outgoing client-facing documents (devis = quotes, factures = client invoices) with per-document PDF export, status lifecycle enforcement, atomic numbering, and user-managed template skeletons. Distinct from the internal `invoices` expense-tracking table.

```
┌──────────────────── FE ────────────────────┐               ┌─────────────────── BE ──────────────────┐
│ Sidebar: Billing group                       │               │ Blueprints:                              │
│  ├─ Devis        → /billing/devis            │               │  /api/v1/billing-documents               │
│  ├─ Factures     → /billing/factures         │               │  /api/v1/billing-document-templates      │
│  └─ Templates    → /billing/templates        │               │  /api/v1/company-profile                 │
│                                              │               │                                          │
│ Pages:                                       │  REST + JWT   │ Use-cases (app/application/billing/):    │
│  list.tsx (kind-filtered)                    ◄──────────────►│  CreateBillingDocumentUseCase            │
│  new.tsx (mode: blank | from-existing | tpl) │               │  CloneBillingDocumentUseCase             │
│  [id]/page.tsx (edit + status + actions)     │               │  ConvertDevisToFactureUseCase            │
│  [id]/pdf  → fetch BE PDF, download          │               │  UpdateBillingDocumentUseCase            │
│  templates/list + edit                       │               │  UpdateBillingDocumentStatusUseCase      │
│                                              │               │  ListBillingDocumentsUseCase             │
│ Settings → CompanyProfile section            │               │  GetBillingDocumentUseCase               │
│                                              │               │  DeleteBillingDocumentUseCase            │
│ Components:                                  │               │  RenderBillingDocumentPdfUseCase         │
│  - BillingDocumentForm (items + totals)      │               │  CreateTemplateUseCase / Update / etc.   │
│  - StatusBadge + StatusTransitionMenu        │               │  GetCompanyProfileUseCase / Upsert       │
│  - "Create from existing" picker dialog      │               │                                          │
│  - "Apply template" picker dialog            │               │ Domain (app/domain/billing/):            │
│  - "Convert to facture" button               │               │  BillingDocument (immutable dataclass)   │
│                                              │               │  BillingDocumentItem (frozen)            │
│                                              │               │  BillingDocumentTemplate                 │
│                                              │               │  CompanyProfile                          │
│                                              │               │  BillingDocumentKind enum                │
│                                              │               │  BillingDocumentStatus enum              │
│                                              │               │                                          │
│                                              │               │ Infrastructure:                          │
│                                              │               │  SqlAlchemyBillingDocumentRepository     │
│                                              │               │  SqlAlchemyBillingTemplateRepository     │
│                                              │               │  SqlAlchemyCompanyProfileRepository      │
│                                              │               │  SqlAlchemyBillingNumberCounterRepository│
│                                              │               │  PdfBillingDocumentRenderer (ReportLab)  │
└──────────────────────────────────────────────┘               └──────────────────────────────────────────┘
```

**Tables introduced:**

- `billing_documents` — polymorphic on `kind` (devis | facture); stores issuer snapshot at create time, recipient freetext fields, JSONB `items[]`, status, document number, optional `project_id`, `source_devis_id` (set on convert).
- `billing_document_templates` — skeleton rows (kind, items, notes, terms, default_vat_rate); no number, no status, no recipient.
- `company_profile` — one row per user; snapshotted onto each doc at create. Fields: `legal_name`, `address`, `siret`, `tva_number`, `iban`, `bic`, `logo_url`, `default_payment_terms`, `prefix_override`.
- `billing_number_counters` — `PRIMARY KEY (user_id, kind, year)`, `next_value INT`; locked with `SELECT FOR UPDATE` on generation. Produces `DEV-YYYY-NNN` / `FAC-YYYY-NNN`.

**Status transition matrix:**

| Kind | Allowed transitions |
|---|---|
| **devis** | `draft → sent`, `sent → accepted`, `sent → rejected`, `sent → expired`, `accepted ↔ sent` (revert), `rejected → draft` |
| **facture** | `draft → sent`, `sent → paid`, `sent → overdue`, `sent → cancelled`, `overdue → paid`, `paid → cancelled` (refund) |

Invalid transitions raise `InvalidStatusTransitionError` → HTTP 409.

**Numbering scheme:** Auto-generated, atomic per `(user_id, kind, year)`. Generation acquires a `SELECT … FOR UPDATE` lock on the `billing_number_counters` row inside the create-document transaction, increments `next_value`, and formats `DEV-YYYY-NNN` / `FAC-YYYY-NNN` (3-digit zero-padded). Optional `prefix_override` on `company_profile` prepends a custom token (e.g. `FLW-DEV-2026-001`). Number is read-only after creation.

**Issuer-snapshot pattern:** At create time, all fields from `company_profile` (legal_name, address, siret, tva_number, iban, bic, logo_url) are deep-copied onto `billing_documents.issuer_*` columns. Historical documents are immutable with respect to company settings; if the user later changes their address, existing docs reflect the address at time of creation. Missing `company_profile` → 409 with `reason: "company_profile_missing"`.

**Convert-devis-to-facture race protection:** The convert use-case issues `SELECT FOR UPDATE` on the source devis row before inserting the new facture. A `UNIQUE (source_devis_id)` constraint on `billing_documents` ensures each accepted devis converts at most once; a second concurrent request collides on the constraint → `DevisAlreadyConvertedError` → HTTP 409.

**Endpoints:** 17 — see `docs/checklist/feature-checklist.md` → Billing section.

---

### Companies BC

**Status:** Completed (Phase 260506-0048, BE PR #30, FE PR #43)

**Purpose:** Admin-managed shared legal entities (`companies`) that users attach via single-use invite tokens. Replaces the former 1:1 `company_profile`. Each user can hold many attached companies; the billing-document create form gains a mandatory company picker. Sensitive fields are masked in API responses for non-admins; PDFs always render full values (legal requirement).

```
┌────────────────── FE ──────────────────┐        ┌──────────────────── BE ──────────────────┐
│ Settings / My companies (all users)     │        │ /api/v1/companies                         │
│  ├─ masked company cards               │        │  ├─ GET (list: my attached OR all if admin)│
│  ├─ "Add company" → token redeem dialog│        │  ├─ POST (admin create)       10/min       │
│  ├─ "Set primary" toggle               │        │  ├─ GET <id> (full if admin, masked else)  │
│  └─ "Detach" button                    │        │  ├─ PUT <id> (admin edit)     30/min       │
│                                        │        │  └─ DELETE <id> (admin)                   │
│ Settings / All companies (admin only)  │        │                                            │
│  ├─ full-value company list            │        │ /api/v1/companies/<id>/invite-tokens       │
│  ├─ "New company" form                 │        │  ├─ POST (generate, returns plaintext once)│
│  └─ per-company manage page           │        │  └─ DELETE active (revoke)                │
│      ├─ Edit fields                    │        │                                            │
│      ├─ "Generate invite token" modal  │        │ /api/v1/companies/attach-by-token          │
│      │  (one-shot copy, shows expiry) │        │  └─ POST (user redeems)       5/min        │
│      ├─ Attached users list            │        │                                            │
│      └─ "Boot user" / "Delete company" │        │ /api/v1/companies/<id>/access              │
│                                        │        │  ├─ DELETE (self-detach)                   │
│ Billing doc create form                │        │  └─ DELETE /<user_id> (admin boot) 30/min  │
│  └─ CompanyPickerSelect at top         │        │                                            │
│     ├─ 0 attached → redirect Settings  │        │ /api/v1/companies/<id>/attached-users      │
│     ├─ 1 attached → auto-use           │        │  └─ GET (admin list)                       │
│     └─ 2+ → dropdown, default primary  │        │                                            │
│        or localStorage last-used       │        │ /api/v1/users/me/primary-company           │
│                                        │        │  └─ PUT <company_id>          30/min       │
└────────────────────────────────────────┘        └──────────────────────────────────────────┘
```

**Tables introduced:**

- `companies` — `id UUID PK`, `legal_name`, `address`, `siret`, `tva_number`, `iban`, `bic`, `logo_url`, `default_payment_terms`, `prefix_override` (pattern `^[A-Z0-9]{1,8}$`), `created_by UUID FK(users)`, timestamps. Indexes: `legal_name`, `created_by`.
- `user_company_access` — `(user_id, company_id) PK` (both FK cascade), `is_primary BOOL NOT NULL DEFAULT FALSE`, `attached_at`. Partial unique `(user_id) WHERE is_primary=TRUE` enforces at-most-one primary per user.
- `company_invite_tokens` — `id UUID PK`, `company_id FK(companies) ON DELETE CASCADE`, `token_hash TEXT` (argon2), `created_by FK(users)`, `created_at`, `expires_at` (created_at + 7 days), `redeemed_at TIMESTAMPTZ NULL`, `redeemed_by UUID NULL`. Partial unique `(company_id) WHERE redeemed_at IS NULL` — only one active token per company at a time.

**Tables modified:**

- `billing_documents` — gains `company_id UUID FK(companies) ON DELETE SET NULL`. After migration backfill this is `NOT NULL` for all post-migration documents (legacy pre-migration rows remain NULL-safe via `ON DELETE SET NULL`).
- `billing_number_counters` — PK re-keyed from `(user_id, kind, year)` to `(company_id, kind, year)`; `user_id` column dropped. Each company keeps its own continuous numbering sequence per kind per year.

**Table dropped:** `company_profile` — retired after migration backfill.

**Token lifecycle:**

```
admin → POST /companies/<id>/invite-tokens
          └─ generate 32-byte random token
          └─ argon2-hash → store in company_invite_tokens
          └─ return plaintext token ONCE (never stored, never loggable)
             dialog shows: token + expires_at (ISO)

user copies plaintext → pastes into "Add company" dialog
  → POST /companies/attach-by-token { token: "<plaintext>" }
       └─ argon2-verify against unredeemed tokens for all companies
       └─ SELECT FOR UPDATE on matching row
       └─ assert redeemed_at IS NULL && expires_at > now()
       └─ mark redeemed_at = now(), redeemed_by = user_id
       └─ INSERT user_company_access (is_primary=true if first attachment)
```

**Masking helper pattern:**

`mask_company_for_user(company, requester_role_set)` in `app/domain/billing/company_masking.py` (adjacent to the billing issuer-snapshot pattern). Admin (`*:*` in role set) receives full fields; all others receive last-4 masked values (`····5678`; `····` when field has fewer than 4 chars). Applied in `ListMyCompaniesUseCase` and `GetCompanyUseCase` before the entity reaches the API layer. PDF renderer reads `billing_documents.issuer_*` snapshot columns — never re-fetches from `companies` — so masking is never applied to PDF output.

**Migration summary (single Alembic revision, reversible):**

One revision creates `companies`, `user_company_access`, `company_invite_tokens`, adds `billing_documents.company_id`, then: (1) INSERTs one row into `companies` for each existing `company_profile` row (`created_by = user_id`); (2) INSERTs one `user_company_access` row per user (`is_primary=true`); (3) re-keys `billing_number_counters` — for each old `(user_id, kind, year)` row, finds the user's migrated primary company and inserts `(company_id, kind, year, next_value)`, then drops the `user_id` column; (4) backfills `billing_documents.company_id` for every existing row using the doc owner's primary company at migration time; (5) `DROP TABLE company_profile`. Round-trip verified (`flask db upgrade && flask db downgrade -1 && flask db upgrade head`) on real Postgres before merge.

---

### Invoices (Factures) Module

**Status:** Completed (Phase 260422-0022)

**Purpose:** Per-project invoice management for client, labor, and supplier invoices with RBAC enforcement and browser print-to-PDF.

**Domain Entities:**
- `Invoice` - Aggregate root (id, project_id, type, issue_date, due_date, recipient_name, items, total_amount, invoice_number, created_by, created_at, updated_at)
- `InvoiceItem` - Value object (description, quantity, unit_price; total computed)
- `InvoiceType` - Enum (CLIENT, LABOR, SUPPLIER)

**API Endpoints:**
- `POST /api/v1/invoices` - Create invoice (requires `project:manage_invoices` permission)
- `GET /api/v1/invoices?project_id=<uuid>&type=<CLIENT|LABOR|SUPPLIER>` - List invoices
- `GET /api/v1/invoices/<id>` - Get invoice details
- `PUT /api/v1/invoices/<id>` - Update invoice
- `DELETE /api/v1/invoices/<id>` - Delete invoice

**Frontend Features:**
- Invoice list view (filterable by type)
- Invoice form with dynamic line items
- Browser print-to-PDF (no external libs, pure CSS `@media print`)
- Auto-generated invoice numbers (INV-YYYY-NNNN per project)

**Database:**
- `invoices` table - stores metadata + JSONB items column
- No separate `invoice_items` table (YAGNI)

**Test Coverage:**
- 68 new tests (domain entities, use cases, API endpoints, components)
- All passing

## Unresolved Architectural Decisions

- Session persistence strategy for multi-region deployment
- Message queue for async tasks (Celery vs RabbitMQ)
- Event sourcing for audit trail
- Frontend token refresh strategy (currently relies on backend cookie renewal)
