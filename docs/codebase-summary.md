# Codebase Summary

**Last Updated:** 2026-05-05
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
- **Projects** — CRUD + membership; `project:read / project:manage_*` permission gates.
- **Labor** — daily attendance entries, supplement hours (0–12/day), per-project summary (priced + bonus cost), Excel/PDF export.
- **Invoices** — internal expense tracking: `client | labor | supplier` invoice types, JSONB items column, per-project monthly Excel/PDF export. *(Note: naming is internal only — distinct from outgoing billing below.)*
- **Invitations** — invite-only signup; single-use token, 7-day expiry, RQ email dispatch.
- **Notes** — per-project shared notes with date-anchored in-app reminders; lazy SQL computation, no background job.
- **Billing module** — outgoing client-facing devis + facture documents, polymorphic on `kind`, with user-managed templates and per-document PDF export. Distinct from internal expense tracking (`invoices` table, retained under that name pending a future rename to `expenses`).

### Frontend Route Groups

- `(app)/dashboard` — KPI overview.
- `(app)/projects/[id]/labor` — attendance + export.
- `(app)/projects/[id]/invoices` — internal invoice list + export.
- `(app)/projects/[id]/notes` — agenda + reminder dismiss.
- `(app)/projects/[id]/members` — invite + bulk-add.
- `(app)/billing/devis` — outgoing quote list + CRUD + PDF.
- `(app)/billing/factures` — outgoing invoice list + CRUD + PDF.
- `(app)/billing/templates` — reusable billing skeletons.
- `(app)/settings` — company profile + user/roles section.

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
- **Issuer snapshot** — billing docs copy `company_profile` fields at create time; historical docs never change when settings update.
- **Atomic document numbering** — `SELECT … FOR UPDATE` on `billing_number_counters` per `(user_id, kind, year)`.
- **Decimal-as-string in JSONB** — `BillingDocument.items` stored as JSONB; monetary `Decimal` values serialized as strings to avoid float drift.
- **Lazy notification computation** — `notes_dismissed` dismissal table; no background job; SQL fires at read time.
- **JSONB items** — both `invoices` and `billing_documents` store line items as JSONB (no separate items table).
