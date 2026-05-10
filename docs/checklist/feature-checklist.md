# Feature Implementation Checklist

**Last Updated:** 2026-05-07
**Project:** Construction Management System

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

---

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

## Projects · Edit + Delete UI

FE-only; uses the existing `PUT /api/v1/projects/<id>` and `DELETE /api/v1/projects/<id>` endpoints (already listed under Backend → Projects).

| Surface | What it does |
|---|---|
| Project card kebab (`MoreHorizontal`) on `/{locale}/projects` | Opens shadcn `DropdownMenu`. Items: **Edit**, **Delete** (both gated by `canMutateProject` mirroring BE `can_mutate_project`), **Show / Hide team**. |
| `EditProjectDialog` | Dialog mirroring `CreateProjectDialog`: pre-fills name + address; no-op close when unchanged; awaits caller's `onUpdated` (refetch) before close so failures surface. |
| `DeleteProjectDialog` | `AlertDialog` with cascade copy + irreversible warning + billing note. Action button stays disabled until typed text matches `project.name` exactly. Awaits caller's `onDeleted` (refetch) before close. |

**Permission gating (FE mirror of BE rule):** `project.owner_id === user.id || user.permissions.includes("project:create" | "project:*" | "*:*")`.

**Cascade copy (matches FK behavior):**
- Permanently deleted: workers, labor entries, tasks, expenses (legacy `invoices` table), notes, invitations, project memberships.
- Unlinked but kept: billing documents (`billing_documents.project_id` → SET NULL).

**i18n:** 19 new keys under `projects.*` for en / fr / vi (parity).

**Tests:** 28 Vitest tests — `EditProjectDialog` (10) + `DeleteProjectDialog` (12) + `updateProject` / `deleteProject` API wrappers (6).

---

## Invoices · Monthly Export (Excel / PDF)

| Method | Path | Auth | Notes |
|---|---|---|---|
| GET | `/api/v1/projects/<id>/invoices-export?from=YYYY-MM&to=YYYY-MM&format=xlsx\|pdf[&type=client\|labor\|supplier]` | jwt + project:read + project membership | 24-month cap, optional type filter, per-user rate limit (5/min), 422/403/404 paths |

**Output:** xlsx — Summary sheet + one sheet per type that has invoices in range; pdf — Page 1 summary + one polished invoice page per invoice.
**Filename:** `invoices-{project-slug}-{from}-to-{to}[-{type}].{ext}`
**Font reuse:** shares DejaVu TTFs from `app/domain/labor/export/fonts/` (no duplication).

---

## Billing

Auth for all routes: `@jwt_required()` + row-level ownership check (`billing_documents.user_id == jwt_user_id`; superadmin `*:*` bypasses). Rate limits as noted.

| Method | Path | Use-case | Rate-limit |
|---|---|---|---|
| GET | `/api/v1/billing-documents` | List documents (owner-filtered; optional `?kind=devis\|facture&status=...`) | — |
| POST | `/api/v1/billing-documents` | Create document (snapshots company_profile; 409 if profile missing) | 10/min |
| GET | `/api/v1/billing-documents/<id>` | Get document | — |
| PUT | `/api/v1/billing-documents/<id>` | Update document (draft only for immutable fields) | 30/min |
| DELETE | `/api/v1/billing-documents/<id>` | Delete document | — |
| POST | `/api/v1/billing-documents/<id>/clone` | Clone document (new number, status=draft, items/recipient copied) | 10/min |
| POST | `/api/v1/billing-documents/<id>/convert-to-facture` | Convert accepted devis → new facture; sets `source_devis_id`; race-safe | 10/min |
| PATCH | `/api/v1/billing-documents/<id>/status` | Transition status; validates per-kind matrix; 409 on invalid transition | 30/min |
| GET | `/api/v1/billing-documents/<id>/pdf` | Render + stream PDF via ReportLab (DejaVu fonts) | 5/min |
| POST | `/api/v1/billing-documents/from-template/<template_id>` | Apply template → new document (recipient + dates supplied in body) | 10/min |
| POST | `/api/v1/billing-documents/import` | Import legacy doc with verbatim `document_number` + explicit `status` + optional `created_at`; bumps counter to `MAX(existing, parsed_seq)`; 409 on duplicate `(company_id, kind, document_number)` | 30/min |
| GET | `/api/v1/billing-documents/activity-suggestions?category=&q=&limit=` | Distinct line-item descriptions ranked by frequency, scoped to current user; `Cache-Control: no-cache, must-revalidate`; returns `{categories, suggestions[]}` with `last_unit/last_unit_price/last_vat_rate` hints | 60/min |
| GET | `/api/v1/billing-document-templates` | List templates (owner-filtered; optional `?kind=...`) | — |
| POST | `/api/v1/billing-document-templates` | Create template | 10/min |
| GET | `/api/v1/billing-document-templates/<id>` | Get template | — |
| PUT | `/api/v1/billing-document-templates/<id>` | Update template | 30/min |
| DELETE | `/api/v1/billing-document-templates/<id>` | Delete template | — |
| GET | `/api/v1/company-profile` | Get current user's company profile | — |
| PUT | `/api/v1/company-profile` | Upsert company profile (creates on first call) | 30/min |

**Total: 17 endpoints** across 3 blueprints (`billing_documents_bp`, `billing_templates_bp`, `company_profile_bp`).

> **Note:** `company_profile_bp` is retired by the Companies module below. Billing doc endpoints now require `company_id` in the request body.

**Error → HTTP mapping:**
- 400 — Pydantic validation
- 403 — `ForbiddenBillingDocumentError`
- 404 — `BillingDocumentNotFoundError`, `BillingTemplateNotFoundError`
- 409 — `InvalidStatusTransitionError`, `BillingNumberCollisionError`, `DevisAlreadyConvertedError`, `MissingCompanyProfileError` (body: `{"reason": "company_profile_missing"}`)
- 422 — Pydantic body errors
- 429 — rate limited

**New tables:** `billing_documents`, `billing_document_templates`, `company_profile`, `billing_number_counters`
**New BE dependencies:** none beyond existing `reportlab`, `python-slugify` (already in requirements from labor export)
**New FE dependencies:** none (reuses shadcn/ui Dialog, Table, Form, existing `formatEUR`, `triggerBrowserDownload`)
**i18n namespaces added:** `billing.*`, `companyProfile.*` (en / fr / vi parity)

---

## Companies

Auth for all routes: `@jwt_required()`. Admin-only endpoints require `*:*` permission. Rate limits as noted.

| Method | Path | Use-case | Permission | Rate-limit |
|---|---|---|---|---|
| GET | `/api/v1/companies` | List user's attached companies; `?scope=all` returns all companies (admin) | jwt | — |
| POST | `/api/v1/companies` | Create company | jwt + `*:*` | 10/min |
| GET | `/api/v1/companies/<id>` | Get company (full if admin, sensitive-field masked otherwise) | jwt + (admin OR attached) | — |
| PUT | `/api/v1/companies/<id>` | Update company | jwt + `*:*` | 30/min |
| DELETE | `/api/v1/companies/<id>` | Delete company (hard-delete; cascades access + tokens) | jwt + `*:*` | — |
| POST | `/api/v1/companies/<id>/invite-tokens` | Generate invite token; returns plaintext ONCE; `?regenerate=true` invalidates existing | jwt + `*:*` | 10/min |
| DELETE | `/api/v1/companies/<id>/invite-tokens/active` | Revoke active invite token | jwt + `*:*` | — |
| POST | `/api/v1/companies/attach-by-token` | Redeem invite token; attaches company to caller | jwt | 5/min |
| DELETE | `/api/v1/companies/<id>/access` | Self-detach from company | jwt + attached | — |
| DELETE | `/api/v1/companies/<id>/access/<user_id>` | Admin boot a user from a company | jwt + `*:*` | 30/min |
| GET | `/api/v1/companies/<id>/attached-users` | List users attached to company | jwt + `*:*` | — |
| PUT | `/api/v1/users/me/primary-company` | Set caller's primary company | jwt | 30/min |

**Total: 12 endpoints** across 2 blueprints (`companies_bp`, `users_me_bp`).

**Error → HTTP mapping:**
- 403 — `ForbiddenCompanyError` (non-admin on admin-only endpoint)
- 404 — `CompanyNotFoundError`, `UserCompanyAccessNotFoundError`, `InviteTokenNotFoundError`
- 409 — `ActiveInviteTokenAlreadyExistsError`, `CompanyAlreadyAttachedError`
- 410 — `InviteTokenExpiredError` (`reason: "expired"`), `InviteTokenAlreadyRedeemedError` (`reason: "already_redeemed"`)
- 422 — Pydantic body / missing `company_id` on billing doc create
- 429 — rate limited

**New tables:** `companies`, `user_company_access`, `company_invite_tokens`
**Modified tables:** `billing_documents` (+ `company_id` FK), `billing_number_counters` (PK re-keyed to `company_id`)
**Dropped table:** `company_profile`
**New BE dependencies:** `argon2-cffi` (already a dep from invitation hashing)
**New FE dependencies:** none (reuses shadcn/ui Select, Dialog, existing company-picker primitives)
**i18n namespaces added:** `companies.*` (en / fr / vi parity)
