# Codebase Summary

**Last Updated:** 2026-05-07
**Total Files:** ~350 (includes .git)
**Repos:** [`flowitup/folio`](https://github.com/flowitup/folio) (umbrella, this) · [`flowitup/folio-back-end`](https://github.com/flowitup/folio-back-end) · [`flowitup/folio-front-end`](https://github.com/flowitup/folio-front-end)

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

### Repository layout (umbrella `flowitup/folio`)

```
folio/                                        # umbrella repo (this)
├── docker-compose.yml                        # base compose (dev defaults)
├── docker-compose.prod.yml                   # prod override (127.0.0.1, ${VAR:?required})
├── folio-back-end/                           # git submodule → flowitup/folio-back-end
├── folio-front-end/                          # git submodule → flowitup/folio-front-end
├── infra/                                    # Infrastructure as Code (GCP)
├── scripts/                                  # VM-side orchestration + backup cron
└── docs/                                     # Documentation (this dir)
```

### Backend Domain Modules

- **Auth** — JWT login/logout/refresh, Argon2 password hashing, RBAC (`resource:action` permissions), Redis token blacklist.
- **Projects** — CRUD + membership; `project:read / project:manage_*` permission gates. FE exposes Edit + Delete via the project card kebab (typed-name confirmation on delete; cascade copy mirrors FK behavior).
- **Labor** — daily attendance entries, supplement hours (0–12/day), per-project summary (priced + bonus cost), Excel/PDF export.
- **Invoices** — internal expense tracking: `client | labor | supplier` invoice types, JSONB items column, per-project monthly Excel/PDF export. *(Note: naming is internal only — distinct from outgoing billing below.)*
- **Invitations** — invite-only signup; single-use token, 7-day expiry, RQ email dispatch.
- **Notes** — per-project shared notes with date-anchored in-app reminders; lazy SQL computation, no background job.
- **Project Documents** — per-project file storage (plans, contracts, photos, invoices receipts, etc.) on the existing MinIO bucket via a distinct `project-documents/` key prefix. Upload (multipart, single-file per request — FE fires N parallel for multi-file), list with type/uploader filters + sort + pagination, inline preview for PDF + images (authenticated `<embed>`/`<img>` via blob-fetch), download, soft-delete (`deleted_at TIMESTAMPTZ`; MinIO object retained). Allowlist: PDF, PNG/JPG/JPEG/WebP, DOCX, XLSX, DWG, TXT — 25 MB cap (`PROJECT_DOCUMENT_MAX_SIZE_BYTES`). Rate-limited at 30/min/user. New `IDocumentStorage` Protocol port reuses the existing `S3AttachmentStorage` singleton instance.
- **Billing module** — outgoing client-facing devis + facture documents, polymorphic on `kind`, with user-managed templates and per-document PDF export. Distinct from internal expense tracking (`invoices` table, retained under that name pending a future rename to `expenses`).
- **Companies module** — admin-managed shared `companies` (legal entities) attached to users via single-use invite tokens; replaces the old 1:1 `company_profile`; sensitive fields (SIRET/TVA/IBAN/BIC) masked in UI for non-admins, full on PDF; numbering counters re-keyed per `(company_id, kind, year)`; documents enforce `(company_id, kind, document_number)` uniqueness so each company keeps an independent sequence.
- **Payment methods module** — per-company CRUD list of invoice payment methods (`Cash` + `legal_name` seeded as builtins; user-added entries supported). Soft-delete via `is_active`. Invoices snapshot the label at write time (`payment_method_label`), so historical invoices survive method rename and soft-delete. Membership-checked read; `*:*` admin write. Single-query list with usage counts via `LEFT JOIN GROUP BY`.

### Frontend Route Groups

- `(app)/dashboard` — KPI overview.
- `(app)/projects/[id]/labor` — attendance + export.
- `(app)/projects/[id]/invoices` — internal invoice list + export.
- `(app)/projects/[id]/notes` — agenda + reminder dismiss.
- `(app)/projects/[id]/documents` — file list + drag-drop upload (XHR per file) + inline preview + soft-delete.
- `(app)/projects/[id]/members` — invite + bulk-add.
- `(app)/billing/devis` — outgoing quote list + CRUD + PDF.
- `(app)/billing/factures` — outgoing invoice list + CRUD + PDF.
- `(app)/billing/templates` — reusable billing skeletons.
- `(app)/settings` — companies section (my companies + admin all-companies), user/roles section.

## Tech Stack

| Layer | Technology |
|---|---|
| Backend | Flask 3.0, SQLAlchemy 2.0, Alembic, Pydantic v2, Flask-JWT-Extended, Flask-Limiter, RQ |
| Frontend | Next.js 16 App Router, React 19, TypeScript 5, Tailwind CSS v4, shadcn/ui, next-intl |
| Database | PostgreSQL 15+, Redis 7+ |
| PDF | ReportLab + DejaVu Sans fonts (Vietnamese-safe) |
| CI/CD | GitHub Actions → GCP VM (Workload Identity Federation) |

## Key Patterns

- **Hexagonal Architecture** — Domain → Application → Infrastructure; no framework imports in domain.
- **Issuer snapshot** — billing docs copy company fields at create time; historical docs never change when settings update.
- **Atomic document numbering** — `SELECT … FOR UPDATE` on `billing_number_counters` per `(company_id, kind, year)`; each legal entity has its own continuous sequence.
- **Sensitive-field masking** — `mask_company_for_user(company, role_set)` applied on every read path; admin (`*:*`) sees full values; non-admin sees last-4 masked (`····5678`). PDF renders full values from the issuer snapshot (legal requirement).
- **Decimal-as-string in JSONB** — `BillingDocument.items` stored as JSONB; monetary `Decimal` values serialized as strings to avoid float drift.
- **Lazy notification computation** — `notes_dismissed` dismissal table; no background job; SQL fires at read time.
- **Soft-delete (project_documents)** — first soft-delete in the BE. `deleted_at TIMESTAMPTZ NULL` + partial indexes (`WHERE deleted_at IS NULL`). All list/read paths filter; `repository.soft_delete` uses `UPDATE ... WHERE deleted_at IS NULL` for concurrency safety. MinIO object retained on soft-delete (out-of-scope janitor follow-up).
- **Bearer-via-blob preview/download** — native `<embed src>`, `<img src>`, and `<a download>` can't send the `Authorization: Bearer` header the BE requires. The `lib/api/project-document-blob.ts` helper fetches with Bearer + CSRF, `URL.createObjectURL(blob)`, and feeds THAT as the resource src. Cleanup via `URL.revokeObjectURL`. Same pattern in upload XHR with `refreshAccessTokenViaCookie` bootstrap. Shared helper at `lib/api/refresh.ts`.
- **JSONB items** — both `invoices` and `billing_documents` store line items as JSONB (no separate items table). Items optionally carry a `category` (section header — Toiture, Menuiserie, Plomberie…) used for grouped activity suggestions.
- **Activity suggestions** — `GET /billing-documents/activity-suggestions?category=&q=` aggregates the requester's past line items grouped by `(category, description)`, ranked by frequency, with `last_unit/last_unit_price/last_vat_rate` pre-fill hints. Backs the items-editor Combobox.
- **Historical import** — `POST /billing-documents/import` accepts a verbatim `document_number` + explicit `status` + optional `created_at`, and bumps the per-`(company, kind, year)` counter to `MAX(existing, parsed_seq)`. Used to ingest legacy invoices without breaking the auto-numbering of new docs.
